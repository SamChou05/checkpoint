"""Bounded, application-authored fixtures for the eval-only execution adapter.

Darwin rejects this machine's RLIMIT_AS configuration. Trusted local child
fixtures omit ONLY that line on Darwin; they do not qualify memory isolation.
An independent test exercises the real unmodified failure path. The eventual
managed Linux experiment must qualify the actual memory-limit setup.
"""

import base64
import copy
import hashlib
import json
import os
import subprocess
import sys
import time
import unittest
from unittest.mock import patch

import execution_evidence as evidence


MEMORY_LIMIT_LINE = (
    "resource.setrlimit(resource.RLIMIT_AS, "
    '(limits["memory_bytes"], limits["memory_bytes"]))'
)


def local_child_code():
    code = evidence.CHILD_CODE
    if sys.platform == "darwin":
        assert code.count(MEMORY_LIMIT_LINE) == 1
        code = code.replace(MEMORY_LIMIT_LINE, "# Darwin fixture: AS limit unqualified")
    return code


def run_synthetic(source, *, mode="exec", inputs=None, limits=None, child_code=None):
    """Run only the fixed, benign source literals authored in this test module."""
    with patch.object(evidence, "CHILD_CODE", child_code or local_child_code()):
        job = evidence.prepare_execution_job(
            "synthetic-test", source, mode=mode, inputs=inputs, limits=limits
        )
    assert job["eligible"], job["unsupported_reason"]
    return run_prepared_synthetic(job)


def run_prepared_synthetic(job):
    """Execute a trusted harness carrying only fixed source literals from here."""
    started = time.monotonic()
    completed = subprocess.run(
        [sys.executable, "-I", "-S", "-c", job["harness_code"]],
        capture_output=True,
        timeout=6,
        env={"PATH": os.defpath, "LANG": "C.UTF-8"},
        check=False,
    )
    service = {
        "isError": False,
        "exitCode": completed.returncode,
        "stdOut": completed.stdout.decode("utf-8"),
        "stdErr": completed.stderr.decode("utf-8"),
    }
    return (
        job,
        service,
        evidence.parse_execution_observation(job, service),
        time.monotonic() - started,
    )


class ExecutionEvidencePreparationTests(unittest.TestCase):
    def test_exact_source_inputs_and_harness_are_hashed_without_normalization(self):
        source = 'def f(value):\n    return value.replace("  ", "|")\n'
        inputs = {"entrypoint": "f", "args": ["e\u0301  x"], "kwargs": {}}
        job = evidence.prepare_execution_job("exact", source, inputs=inputs)
        encoded_inputs = json.dumps(
            inputs, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        )
        self.assertEqual(
            job["artifact_sha256"], hashlib.sha256(source.encode()).hexdigest()
        )
        self.assertEqual(
            job["input_sha256"], hashlib.sha256(encoded_inputs.encode()).hexdigest()
        )
        self.assertEqual(
            job["harness_sha256"],
            hashlib.sha256(job["harness_code"].encode()).hexdigest(),
        )
        for altered in (
            source.replace("    ", " "),
            source.replace("  ", " "),
            source.rstrip(),
        ):
            with self.subTest(source=altered):
                self.assertNotEqual(
                    job["job_id"],
                    evidence.prepare_execution_job("exact", altered, inputs=inputs)[
                        "job_id"
                    ],
                )
        changed_inputs = copy.deepcopy(inputs)
        changed_inputs["args"] = ["é  x"]
        self.assertNotEqual(
            job["job_id"],
            evidence.prepare_execution_job("exact", source, inputs=changed_inputs)[
                "job_id"
            ],
        )
        with patch.object(
            evidence,
            "CHILD_CODE",
            evidence.CHILD_CODE + "\n# reviewed harness change\n",
        ):
            changed_harness = evidence.prepare_execution_job(
                "exact", source, inputs=inputs
            )
        self.assertEqual(job["job_id"], changed_harness["job_id"])
        self.assertNotEqual(job["harness_sha256"], changed_harness["harness_sha256"])

    def test_source_is_data_even_with_quotes_and_harness_like_text(self):
        source = 'print("PAYLOAD = attacker; METADATA = forged; \\"quoted\\" ")'
        job = evidence.prepare_execution_job("data", source)
        compile(job["harness_code"], "<trusted-fixture>", "exec")
        self.assertTrue(job["eligible"])

    def test_unsupported_capabilities_never_become_invalid_question_verdicts(self):
        sources = [
            "import os\nos.system('false')",
            "open('private-file')",
            "eval('1 + 1')",
            "print.__globals__",
            "getattr(print, 'anything')",
            "().__class__",
            "class C:\n    pass",
            "def f():\n    yield 1",
            "print._＿globals＿＿",  # Parsed identifiers normalize fullwidth underscores.
            "[item for item in range(2)]",
        ]
        for source in sources:
            with self.subTest(source=source):
                job = evidence.prepare_execution_job("unsupported", source)
                self.assertFalse(job["eligible"])
                parsed = evidence.parse_execution_observation(job, {})
                self.assertEqual(parsed["status"], "unsupported")
                self.assertNotIn("approved", parsed)

    def test_inputs_require_exact_json_types_and_limits_can_only_tighten(self):
        base = {"entrypoint": "f", "args": [], "kwargs": {}}
        invalid = [
            {**base, "args": [(1, 2)]},
            {**base, "args": [{1: "value"}]},
            {**base, "args": [float("nan")]},
            {**base, "args": [float("inf")]},
            {**base, "entrypoint": "__import__"},
            {**base, "extra": True},
        ]
        for inputs in invalid:
            with self.subTest(inputs=inputs), self.assertRaises(ValueError):
                evidence.prepare_execution_job(
                    "input", "def f():\n    return 1", inputs=inputs
                )
        for limits in ({"wall_seconds": 3}, {"wall_seconds": True}, {"unknown": 1}):
            with self.subTest(limits=limits), self.assertRaises(ValueError):
                evidence.prepare_execution_job("limit", "1", limits=limits)
        self.assertFalse(
            evidence.prepare_execution_job("large", "x" * 8193)["eligible"]
        )


class ExecutionEvidenceSyntheticRuntimeTests(unittest.TestCase):
    def test_remote_parent_rehashes_actual_payload_before_compilation(self):
        job = evidence.prepare_execution_job("tamper", "1 + 2", mode="eval")
        original = '"source":"1 + 2"'
        self.assertEqual(job["harness_code"].count(original), 1)
        job["harness_code"] = job["harness_code"].replace(original, '"source":"1 + 3"')
        # The request really contains this altered reviewed harness: its local
        # hash is consistent, but the embedded prepared metadata is now stale.
        job["harness_sha256"] = hashlib.sha256(job["harness_code"].encode()).hexdigest()
        _, service, result, _ = run_prepared_synthetic(job)
        raw = json.loads(service["stdOut"])
        self.assertEqual(raw["reason"], "prepared_metadata_mismatch")
        self.assertIsNone(raw["compile"])
        self.assertIsNone(raw["child"])
        self.assertEqual(result["status"], "inconclusive")

    def test_exact_multiline_code_keeps_unicode_and_quoted_double_spaces(self):
        source = (
            "def f(value):\n"
            '    if "  " in value:\n'
            '        return (value.replace("  ", "|", 1), len(value))\n'
            "    return (value, len(value))\n"
        )
        _, _, observed, _ = run_synthetic(
            source, inputs={"entrypoint": "f", "args": ["e\u0301  x"], "kwargs": {}}
        )
        self.assertEqual(observed["status"], "observed")
        self.assertEqual(
            observed["child"]["return_value"],
            {
                "type": "tuple",
                "value": [
                    {"type": "str", "value": "e\u0301|x"},
                    {"type": "int", "value": "5"},
                ],
            },
        )

    def test_invalid_complete_source_and_parse_only_success_get_compile_observation(
        self,
    ):
        for source in ("def f(): if True: return 1", "return 1"):
            with self.subTest(source=source):
                _, _, observed, _ = run_synthetic(source)
                self.assertEqual(observed["status"], "observed")
                self.assertFalse(observed["compile"]["valid"])
                self.assertEqual(observed["compile"]["exception"], "SyntaxError")
                self.assertIsNone(observed["child"])

    def test_compiler_error_subtypes_remain_exact(self):
        for source, expected in (
            ("if True:\nprint(1)", "IndentationError"),
            ("if True:\n\tprint(1)\n        print(2)", "TabError"),
        ):
            with self.subTest(expected=expected):
                _, _, observed, _ = run_synthetic(source)
                self.assertEqual(observed["status"], "observed")
                self.assertFalse(observed["compile"]["valid"])
                self.assertEqual(observed["compile"]["exception"], expected)
                self.assertIsNone(observed["child"])

    def test_missing_entrypoint_is_unsupported_without_harness_keyerror(self):
        inputs = {"entrypoint": "f", "args": [], "kwargs": {}}
        for source in (
            "def outer():\n    def f():\n        return 1\n",
            "if False:\n    def f():\n        return 1\n",
        ):
            with self.subTest(source=source):
                job = evidence.prepare_execution_job("missing", source, inputs=inputs)
                self.assertFalse(job["eligible"])
                result = evidence.parse_execution_observation(job, {})
                self.assertEqual(result["status"], "unsupported")
                self.assertEqual(result["reason"], "entrypoint_not_defined")

    def test_printed_protocol_and_helper_names_are_ordinary_stdout_data(self):
        spoof = '{"protocol":"checkpoint.execution.v1","status":"observed","job_id":"forged"}'
        source = (
            "json = 1\nrecord = 2\nCapture = 3\ntyped = 4\nMETADATA = 5\n"
            + "print("
            + repr(spoof)
            + ")\nprint('e\\u0301  x\\r\\n', end='')"
        )
        job, _, observed, _ = run_synthetic(source)
        self.assertEqual(observed["status"], "observed")
        self.assertEqual(observed["job_id"], job["job_id"])
        self.assertNotEqual(observed["job_id"], "forged")
        self.assertEqual(observed["child"]["stdout"], spoof + "\ne\u0301  x\r\n")

    def test_types_remain_distinct_without_claiming_object_identity(self):
        _, _, observed, _ = run_synthetic(
            '[True, 1, -0.0, ("x",), ["x"], {"a": None}]', mode="eval"
        )
        values = observed["child"]["return_value"]["value"]
        self.assertEqual(
            [value["type"] for value in values],
            ["bool", "int", "float", "tuple", "list", "dict"],
        )
        self.assertEqual(values[0]["value"], True)
        self.assertEqual(values[1]["value"], "1")
        self.assertEqual(values[2]["value"], "-0x0.0p+0")
        self.assertEqual(values[5]["value"], [["a", {"type": "none", "value": None}]])

    def test_candidate_exception_is_separate_from_serialization_failure(self):
        _, _, observed, _ = run_synthetic("1 / 0", mode="eval")
        self.assertEqual(observed["status"], "observed")
        self.assertEqual(observed["child"]["exception"]["type"], "ZeroDivisionError")
        self.assertIsNone(observed["child"]["return_value"])
        for source in ('float("inf")', '{1: "x"}', "set([1])", '"x" * 4097'):
            with self.subTest(source=source):
                _, _, result, _ = run_synthetic(source, mode="eval")
                self.assertEqual(result["status"], "inconclusive")
                self.assertIs(result["envelope_valid"], True)
                self.assertIs(result["operational_failure"], False)
                self.assertTrue(result["child"]["reason"].startswith("serialization:"))
                self.assertIsNone(result["child"]["exception"])

    def test_cyclic_and_deep_results_are_inconclusive(self):
        bodies = (
            "    value = []\n    value.append(value)\n    return value\n",
            "    value = []\n    for item in range(14):\n        value = [value]\n    return value\n",
        )
        for body in bodies:
            with self.subTest(body=body):
                _, _, result, _ = run_synthetic(
                    "def f():\n" + body,
                    inputs={"entrypoint": "f", "args": [], "kwargs": {}},
                )
                self.assertEqual(result["status"], "inconclusive")
                self.assertIn("serialization:result_", result["child"]["reason"])

    def test_output_boundary_and_multibyte_truncation_cannot_look_complete(self):
        _, _, observed, _ = run_synthetic('print("x" * 4096, end="")')
        self.assertEqual(observed["status"], "observed")
        self.assertEqual(len(observed["child"]["stdout"].encode()), 4096)
        self.assertEqual(
            base64.b64decode(observed["child"]["stdout_base64"]), b"x" * 4096
        )
        for source in ('print("x" * 4097, end="")', 'print("€" * 1366, end="")'):
            with self.subTest(source=source):
                _, _, result, _ = run_synthetic(source)
                self.assertEqual(result["status"], "inconclusive")
                self.assertTrue(result["child"]["truncated"])
                self.assertEqual(result["child"]["reason"], "output_limit")
                exact_prefix = base64.b64decode(
                    result["child"]["stdout_base64"], validate=True
                )
                self.assertEqual(len(exact_prefix), 4096)
                if "€" in source:
                    self.assertEqual(exact_prefix, ("€" * 1366).encode()[:4096])
                    self.assertEqual(exact_prefix[-1:], b"\xe2")
                    self.assertNotEqual(
                        result["child"]["stdout"].encode(), exact_prefix
                    )

    def test_nontermination_is_killed_and_reaped_with_bounded_local_wait(self):
        _, _, result, elapsed = run_synthetic(
            "while True:\n    pass", limits={"wall_seconds": 1}
        )
        self.assertEqual(result["status"], "inconclusive")
        self.assertTrue(result["timed_out"])
        self.assertTrue(result["child_reaped"])
        self.assertEqual(result["reason"], "child_deadline")
        self.assertLess(elapsed, 5)

    def test_trusted_child_stderr_and_transport_flood_fail_closed(self):
        for addition, expected in (
            ('sys.stderr.write("unexpected")\n', "unexpected_child_stderr"),
            ('sys.stderr.write("x" * 70000)\n', "child_transport_limit"),
        ):
            with self.subTest(reason=expected):
                # Test the trusted transport wrapper, never grant stderr access
                # or imports to candidate code.
                child = local_child_code().replace(
                    "capture = Capture()", addition + "capture = Capture()"
                )
                _, service, result, _ = run_synthetic("1", child_code=child)
                self.assertEqual(result["status"], "inconclusive")
                self.assertEqual(json.loads(service["stdOut"])["reason"], expected)

    @unittest.skipUnless(
        sys.platform == "darwin",
        "This is the observed Darwin resource-limit limitation.",
    )
    def test_unmodified_darwin_memory_setup_failure_is_inconclusive(self):
        _, _, result, _ = run_synthetic("print(1)", child_code=evidence.CHILD_CODE)
        self.assertEqual(result["status"], "inconclusive")
        self.assertIs(result["operational_failure"], True)
        self.assertEqual(result["reason"], "child_nonzero_exit")
        self.assertIn("current limit exceeds maximum limit", result["child_stderr"])


class ExecutionEvidenceEnvelopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.job, cls.service, cls.observed, _ = run_synthetic("1", mode="eval")

    def check_record_failure(self, change):
        record = copy.deepcopy(self.observed)
        change(record)
        service = {**self.service, "stdOut": json.dumps(record)}
        result = evidence.parse_execution_observation(self.job, service)
        self.assertEqual(result["status"], "inconclusive")
        self.assertIs(result["envelope_valid"], False)
        self.assertIs(result["operational_failure"], True)

    def test_valid_observation_signal_is_added_by_parser(self):
        self.assertIs(self.observed["envelope_valid"], True)
        self.assertIs(self.observed["operational_failure"], False)
        # A response cannot supply its own trust marker to bypass validation.
        self.check_record_failure(
            lambda row: row.update(
                envelope_valid=True, operational_failure=False, artifact_sha256="forged"
            )
        )

    def test_inconclusive_status_cannot_launder_malformed_or_operational_failure(self):
        changes = (
            lambda row: row.update(reason=None),
            lambda row: row.update(reason="unknown_limit"),
            lambda row: row.update(reason="harness_failure:ValueError"),
            lambda row: row.update(reason="child_cleanup_timeout", child_reaped=False),
            lambda row: row.update(reason="child_deadline", timed_out=True),
            lambda row: row.update(
                reason="child_transport_limit", transport_truncated=True
            ),
        )
        for index, change in enumerate(changes):
            with self.subTest(index=index):

                def malformed(row):
                    row.update(
                        status="inconclusive",
                        envelope_valid=True,
                        operational_failure=False,
                    )
                    change(row)

                self.check_record_failure(malformed)

    def test_limit_record_requires_exact_flags_reaped_child_and_consistent_phase(self):
        # This record belongs to its timeout job, so mutations below preserve
        # that job's source/input/limit correlation until the targeted mutation.
        timeout_job, _, timeout_record, _ = run_synthetic(
            "while True:\n    pass", limits={"wall_seconds": 1}
        )
        self.assertIs(timeout_record["envelope_valid"], True)
        self.assertIs(timeout_record["operational_failure"], False)
        changes = (
            lambda row: row.update(child_reaped=False),
            lambda row: row.update(child_reaped=1),
            lambda row: row.update(timed_out=1),
            lambda row: row.update(timed_out=False),
            lambda row: row.update(transport_truncated=True),
            lambda row: row.update(child_exit_code=False),
            lambda row: row.update(child_exit_code=None),
            lambda row: row.update(
                compile={"valid": False, "exception": "SyntaxError"}
            ),
            lambda row: row.update(child=copy.deepcopy(self.observed["child"])),
            lambda row: row.update(runtime={}),
        )
        for index, change in enumerate(changes):
            with self.subTest(index=index):
                record = copy.deepcopy(timeout_record)
                record["envelope_valid"] = True
                record["operational_failure"] = False
                change(record)
                service = {**self.service, "stdOut": json.dumps(record)}
                parsed = evidence.parse_execution_observation(timeout_job, service)
                self.assertEqual(parsed["status"], "inconclusive")
                self.assertIs(parsed["envelope_valid"], False)
                self.assertIs(parsed["operational_failure"], True)

    def test_child_output_limit_still_requires_runtime_bytes_and_result_consistency(
        self,
    ):
        job, service, record, _ = run_synthetic('print("€" * 1366, end="")')
        self.assertIs(record["envelope_valid"], True)
        self.assertIs(record["operational_failure"], False)
        self.assertEqual(record["status"], "inconclusive")
        changes = (
            lambda row: row["child"].update(truncated=False),
            lambda row: row["child"].update(truncated=1),
            lambda row: row["child"].update(stdout_base64="eA=="),
            lambda row: row["child"].update(stdout="forged display"),
            lambda row: row["child"].update(runtime={}),
            lambda row: row["child"].update(status="observed"),
            lambda row: row["child"].update(return_value={"type": "int", "value": "1"}),
            lambda row: row["child"].update(
                exception={"type": "RuntimeError", "message": "x"}
            ),
        )
        for index, change in enumerate(changes):
            with self.subTest(index=index):
                malformed = copy.deepcopy(record)
                malformed["envelope_valid"] = True
                malformed["operational_failure"] = False
                change(malformed)
                parsed = evidence.parse_execution_observation(
                    job, {**service, "stdOut": json.dumps(malformed)}
                )
                self.assertIs(parsed["envelope_valid"], False)
                self.assertIs(parsed["operational_failure"], True)

    def test_well_formed_operational_failure_is_not_silenced_by_response_flags(self):
        for reason in (
            "harness_failure:ValueError",
            "child_nonzero_exit",
            "unexpected_child_stderr",
            "invalid_child_envelope",
        ):
            with self.subTest(reason=reason):
                row = copy.deepcopy(self.observed)
                row.update(
                    status="inconclusive",
                    child=None,
                    child_exit_code=1,
                    reason=reason,
                    envelope_valid=True,
                    operational_failure=False,
                )
                parsed = evidence.parse_execution_observation(
                    self.job, {**self.service, "stdOut": json.dumps(row)}
                )
                self.assertEqual(parsed["status"], "inconclusive")
                self.assertIs(parsed["operational_failure"], True)

    def test_invalid_utf8_cannot_hide_behind_a_child_limit_reason(self):
        for reason, truncated, raw_bytes in (
            ("memory_limit", False, b"\xff"),
            ("serialization:result_type", False, b"\xff"),
            ("output_limit", True, b"\xff" + b"x" * 4095),
        ):
            with self.subTest(reason=reason):
                row = copy.deepcopy(self.observed)
                row.update(status="inconclusive", operational_failure=False)
                row["child"].update(
                    status="inconclusive",
                    reason=reason,
                    truncated=truncated,
                    return_value=None,
                    exception=None,
                    stdout=raw_bytes.decode("utf-8", errors="replace"),
                    stdout_base64=base64.b64encode(raw_bytes).decode("ascii"),
                )
                parsed = evidence.parse_execution_observation(
                    self.job, {**self.service, "stdOut": json.dumps(row)}
                )
                self.assertIs(parsed["envelope_valid"], False)
                self.assertIs(parsed["operational_failure"], True)

    def test_parent_stderr_cannot_hide_in_normal_or_limit_observations(self):
        for stderr in (None, 123, "unexpected wrapper diagnostic"):
            with self.subTest(stderr=stderr):
                self.check_record_failure(lambda row: row.update(child_stderr=stderr))
        row = copy.deepcopy(self.observed)
        row.update(
            status="inconclusive",
            reason="child_deadline",
            timed_out=True,
            child=None,
            child_exit_code=-9,
            child_stderr="setup diagnostic",
            envelope_valid=True,
            operational_failure=False,
        )
        parsed = evidence.parse_execution_observation(
            self.job, {**self.service, "stdOut": json.dumps(row)}
        )
        self.assertIs(parsed["operational_failure"], True)

    def test_mismatched_artifact_input_mode_and_limits_cannot_inherit_observation(self):
        for field, value in (
            ("job_id", "other"),
            ("artifact_sha256", "0" * 64),
            ("input_sha256", "1" * 64),
            ("mode", "exec"),
            ("limits", {**self.job["limits"], "wall_seconds": True}),
        ):
            with self.subTest(field=field):
                self.check_record_failure(lambda record: record.update({field: value}))

    def test_service_errors_and_noninteger_exit_code_never_approve(self):
        for field, value in (
            ("isError", True),
            ("exitCode", False),
            ("exitCode", 1),
            ("stdErr", "unexpected"),
        ):
            with self.subTest(field=field):
                result = evidence.parse_execution_observation(
                    self.job, {**self.service, field: value}
                )
                self.assertEqual(result["status"], "inconclusive")

    def test_modified_harness_cannot_reuse_recorded_harness_hash(self):
        job = {
            **self.job,
            "harness_code": self.job["harness_code"] + "\nprint('changed')\n",
        }
        self.assertEqual(
            evidence.parse_execution_observation(job, self.service)["status"],
            "inconclusive",
        )

    def test_malformed_json_duplicate_keys_and_nonfinite_constants_fail_closed(self):
        for raw in ('{"status":', '{"protocol":"x","protocol":"x"}', '{"number":NaN}'):
            with self.subTest(raw=raw):
                result = evidence.parse_execution_observation(
                    self.job, {**self.service, "stdOut": raw}
                )
                self.assertEqual(result["status"], "inconclusive")

    def test_forged_completion_and_malformed_typed_results_fail_closed(self):
        changes = (
            lambda row: row.update(timed_out=True),
            lambda row: row.update(child_reaped=False),
            lambda row: row.update(transport_truncated=True),
            lambda row: row.update(child_exit_code=False),
            lambda row: row.update(runtime={}),
            lambda row: row["child"].update(stdout="x" * 4097),
            lambda row: row["child"].update(stdout_base64="A==="),
            lambda row: row["child"].update(stdout_base64="eA=="),
            lambda row: row["child"].update(
                return_value={"type": "int", "value": True}
            ),
            lambda row: row["child"].update(
                return_value={"type": "float", "value": "0x1p+999999999"}
            ),
            lambda row: row["child"].update(
                return_value={
                    "type": "dict",
                    "value": [
                        ["a", {"type": "none", "value": None}],
                        ["a", {"type": "none", "value": None}],
                    ],
                }
            ),
            lambda row: row["child"].update(
                exception={"type": "ZeroDivisionError", "message": "x"}
            ),
        )
        for index, change in enumerate(changes):
            with self.subTest(index=index):
                self.check_record_failure(change)


if __name__ == "__main__":
    unittest.main()
