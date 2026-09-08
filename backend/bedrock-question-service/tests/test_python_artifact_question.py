"""Synthetic protocol tests; none execute source or invoke a service."""

import copy
import json
import unittest
from unittest.mock import patch

from evals.python_artifact_question import (
    ArtifactQuestionError,
    bind_python_artifact_question,
    prepare_python_artifact_question,
)
from execution_evidence import PROTOCOL, _json, _sha


RUNTIME = {"implementation": "cpython", "version": "3.12.13"}


def returned(kind, value, reason="Proposed teaching reason."):
    return {"kind": "return", "value": {"type": kind, "value": value}, "reason": reason}


def raised(name):
    return {"kind": "exception", "type": name, "reason": "Proposed error reason."}


def spec(source="True", *, mode="eval", inputs=None, options=None):
    return {
        "artifact": {"source": source, "mode": mode, "inputs": inputs},
        "options": options
        or [
            returned("bool", True),
            returned("int", "1"),
            returned("float", "0x1.0000000000000p+0"),
            returned("str", "1"),
        ],
        "explanation": "Authored teaching explanation remains unassessed.",
        "topic": "Python values",
        "difficulty": 2,
    }


def prepare(value=None, **kwargs):
    return prepare_python_artifact_question(
        spec() if value is None else value,
        case_id="synthetic",
        runtime=RUNTIME,
        **kwargs,
    )


def service(prepared, *, value=None, exception=None, syntax=None):
    """A fabricated harness envelope, explicitly not native execution evidence."""
    job = prepared["job"]
    runtime = {**RUNTIME, "version": RUNTIME["version"] + " (synthetic test metadata)"}
    record = {
        "protocol": PROTOCOL,
        **{
            key: copy.deepcopy(job[key])
            for key in ("job_id", "artifact_sha256", "input_sha256", "mode", "limits")
        },
        "runtime": runtime,
        "status": "observed",
        "compile": {"valid": True},
        "child": {
            "status": "observed",
            "stdout": "",
            "stdout_base64": "",
            "return_value": value if exception is None else None,
            "exception": exception,
            "truncated": False,
            "reason": None,
            "runtime": {
                **runtime,
                "isolated": 1,
                "optimize": 0,
                "hash_randomization": 1,
            },
        },
        "child_exit_code": 0,
        "timed_out": False,
        "transport_truncated": False,
        "child_reaped": True,
        "reason": None,
        "child_stderr": "",
    }
    if syntax:
        record.update(
            compile={
                "valid": False,
                "exception": syntax,
                "line": 1,
                "offset": 1,
                "message": "Synthetic syntax observation",
            },
            child=None,
            child_exit_code=None,
        )
    return {"isError": False, "exitCode": 0, "stdOut": json.dumps(record), "stdErr": ""}


def bind(prepared, observed, **kwargs):
    return bind_python_artifact_question(
        prepared, observed, cleanup_confirmed=kwargs.get("cleanup_confirmed", True)
    )


class PythonArtifactQuestionTests(unittest.TestCase):
    def test_display_and_job_preserve_exact_source_and_show_actual_json_inputs(self):
        source = "def f(data):\n    data['x'].append('e\u0301  y')\n    return data\n"
        inputs = {"entrypoint": "f", "args": [{"z": 0, "x": []}], "kwargs": {}}
        prepared = prepare(spec(source, mode="exec", inputs=inputs))
        start, end = prepared["source_span"]
        self.assertEqual(prepared["draft"]["prompt"][start:end], source)
        self.assertEqual(prepared["job"]["artifact_sha256"], _sha(source))
        self.assertEqual(prepared["invocation"], "f(*[{'x': [], 'z': 0}], **{})")
        self.assertEqual(prepared["job"]["input_sha256"], _sha(_json(inputs)))
        self.assertIn("CPython 3.12.13", prepared["draft"]["prompt"])
        self.assertNotIn("stdout", prepared["draft"]["prompt"])
        self.assertNotIn("expectedAnswer", prepared["draft"])

    def test_bool_int_float_and_string_are_four_distinct_typed_answers(self):
        prepared = prepare()
        for i, option in enumerate(prepared["spec"]["options"]):
            result = bind(prepared, service(prepared, value=option["value"]))
            self.assertEqual(result["status"], "bound")
            self.assertEqual(
                result["question"]["expectedAnswer"], prepared["draft"]["choices"][i]
            )
            self.assertEqual(result["binding"]["matched_option_index"], i)
            self.assertEqual(
                result["binding"]["question_sha256"], _sha(_json(result["question"]))
            )

    def test_structural_types_order_unicode_and_exact_float_encoding_are_preserved(
        self,
    ):
        collections = [
            returned("list", [{"type": "int", "value": "1"}]),
            returned("tuple", [{"type": "int", "value": "1"}]),
            returned(
                "dict",
                [
                    ["a", {"type": "int", "value": "1"}],
                    ["b", {"type": "bool", "value": True}],
                ],
            ),
            returned(
                "dict",
                [
                    ["b", {"type": "bool", "value": True}],
                    ["a", {"type": "int", "value": "1"}],
                ],
            ),
        ]
        prepared = prepare(spec(options=collections))
        for i, option in enumerate(collections):
            result = bind(prepared, service(prepared, value=option["value"]))
            self.assertEqual(result["binding"]["matched_option_index"], i)
        options = [
            returned("float", "-0x0.0p+0"),
            returned("float", "0x1.0000000000000p+0"),
            returned("str", "e\u0301  x"),
            returned("str", "é  x"),
        ]
        prepared = prepare(spec(options=options))
        self.assertEqual(len(set(prepared["draft"]["choices"])), 4)
        self.assertIn("e\\u0301  x", prepared["draft"]["choices"][2])
        for i, option in enumerate(options):
            self.assertEqual(
                bind(prepared, service(prepared, value=option["value"]))["binding"][
                    "matched_option_index"
                ],
                i,
            )

    def test_competing_signed_zero_answers_are_rejected_recursively(self):
        positive = {"type": "float", "value": "0x0.0p+0"}
        negative = {"type": "float", "value": "-0x0.0p+0"}
        for wrap in (
            lambda item: item,
            lambda item: {"type": "list", "value": [item]},
            lambda item: {"type": "tuple", "value": [item]},
            lambda item: {"type": "dict", "value": [["x", item]]},
            lambda item: {
                "type": "list",
                "value": [{"type": "dict", "value": [["x", item]]}],
            },
        ):
            options = [
                {
                    "kind": "return",
                    "value": wrap(item),
                    "reason": "Synthetic proposed reason.",
                }
                for item in (positive, negative)
            ] + [raised("TypeError"), raised("ValueError")]
            original = copy.deepcopy(options)
            with self.assertRaisesRegex(ArtifactQuestionError, "duplicate_options"):
                prepare(spec(options=options))
            self.assertEqual(options, original)
        # The ambiguity check never rewrites a native observation or key.
        prepared = prepare(
            spec(
                options=[
                    returned("float", negative["value"]),
                    returned("int", "0"),
                    raised("TypeError"),
                    raised("ValueError"),
                ]
            )
        )
        self.assertEqual(
            bind(prepared, service(prepared, value=positive))["status"], "unmatched"
        )

    def test_aliasing_in_source_is_allowed_without_certifying_alias_identity(self):
        source = "def f():\n    a = [[]] * 2\n    a[0].append(1)\n    return a"
        options = [
            returned(
                "list", [{"type": "list", "value": [{"type": "int", "value": "1"}]}] * 2
            ),
            returned("none", None),
            raised("IndexError"),
            raised("TypeError"),
        ]
        prepared = prepare(
            spec(
                source,
                mode="exec",
                inputs={"entrypoint": "f", "args": [], "kwargs": {}},
                options=options,
            )
        )
        self.assertTrue(prepared["job"]["eligible"])
        result = bind(prepared, service(prepared, value=options[0]["value"]))
        self.assertEqual(result["status"], "bound")
        self.assertIn("alias identity", result["scope"])

    def test_syntax_and_runtime_errors_can_supply_the_key_without_repair(self):
        for source, kwargs in (
            ("def f(): if True: return 1", {"syntax": "SyntaxError"}),
            (
                "1 / 0",
                {
                    "exception": {
                        "type": "ZeroDivisionError",
                        "message": "division by zero",
                    }
                },
            ),
        ):
            with self.subTest(source=source):
                options = [
                    returned("int", "1"),
                    raised("SyntaxError"),
                    raised("ZeroDivisionError"),
                    raised("IndentationError"),
                ]
                if source.startswith("def "):
                    value = spec(
                        source,
                        mode="exec",
                        inputs={"entrypoint": "f", "args": [], "kwargs": {}},
                        options=options,
                    )
                else:
                    value = spec(source, options=options)
                prepared = prepare(value)
                result = bind(prepared, service(prepared, **kwargs))
                expected = kwargs.get("syntax") or kwargs["exception"]["type"]
                self.assertEqual(
                    result["question"]["expectedAnswer"], f"Raises exactly {expected}"
                )
                self.assertIn(source, result["question"]["prompt"])

    def test_none_is_not_missing_evidence_and_exception_subclasses_do_not_overlap(self):
        options = [
            returned("none", None),
            raised("SyntaxError"),
            raised("IndentationError"),
            raised("TabError"),
        ]
        prepared = prepare(spec("None", options=options))
        self.assertEqual(
            bind(prepared, service(prepared, value=options[0]["value"]))["question"][
                "expectedAnswer"
            ],
            "Returns None (NoneType)",
        )
        for exception in ("SyntaxError", "IndentationError", "TabError"):
            self.assertEqual(
                bind(prepared, service(prepared, syntax=exception))["question"][
                    "expectedAnswer"
                ],
                f"Raises exactly {exception}",
            )

    def test_authored_key_stem_and_unexpected_fields_are_rejected(self):
        for key in (
            "expectedAnswer",
            "prompt",
            "sourceDocuments",
            "verificationVersion",
        ):
            value = spec()
            value[key] = "do not trust"
            with self.assertRaises(ArtifactQuestionError):
                prepare(value)

    def test_duplicate_typed_choices_and_exception_aliases_are_rejected(self):
        value = spec()
        value["options"][1] = copy.deepcopy(value["options"][0])
        with self.assertRaisesRegex(ArtifactQuestionError, "duplicate_options"):
            prepare(value)
        for alias in ("IOError", "EnvironmentError"):
            value = spec()
            value["options"][0] = raised(alias)
            with self.assertRaisesRegex(
                ArtifactQuestionError, "noncanonical_exception"
            ):
                prepare(value)

    def test_malformed_typed_values_and_lossy_json_inputs_are_rejected(self):
        for bad in (
            {"type": "bool", "value": 1},
            {"type": "int", "value": "01"},
            {"type": "float", "value": "nan"},
            {"type": "set", "value": []},
        ):
            value = spec()
            value["options"][0]["value"] = bad
            with self.assertRaises(ArtifactQuestionError):
                prepare(value)
        for inputs in (
            {"entrypoint": "f", "args": [(1, 2)], "kwargs": {}},
            {"entrypoint": "f", "args": [{1: "x"}], "kwargs": {}},
        ):
            with self.assertRaises(ArtifactQuestionError):
                prepare(spec("def f(x):\n    return x", mode="exec", inputs=inputs))

    def test_all_four_content_limits_reject_without_clipping(self):
        mutations = [
            lambda v: v["artifact"].update(source="'" + "a" * 320 + "'"),
            lambda v: v["options"][0].update(value={"type": "str", "value": "a" * 140}),
            lambda v: v.update(explanation="a" * 421),
            lambda v: v["options"][0].update(reason="a" * 281),
        ]
        for change in mutations:
            value = spec()
            change(value)
            with self.assertRaisesRegex(ArtifactQuestionError, "overlong"):
                prepare(value)

    def test_valid_feedback_is_kept_exactly_but_never_certified(self):
        value = spec()
        value["explanation"] = "  Incorrect explanation is not fixed here.\n"
        value["options"][0]["reason"] = "  Untested reason with  two spaces.\n"
        prepared = prepare(value)
        result = bind(prepared, service(prepared, value=value["options"][0]["value"]))
        self.assertEqual(result["question"]["explanation"], value["explanation"])
        self.assertEqual(
            result["question"]["choiceExplanations"],
            {
                choice: option["reason"]
                for choice, option in zip(
                    result["question"]["choices"], value["options"], strict=True
                )
            },
        )
        self.assertEqual(result["feedback_assessment"], "unassessed")
        self.assertNotIn("verificationVersion", result["question"])

    def test_feedback_requires_twelve_nonpadding_characters(self):
        for field in ("explanation", "reason"):
            for text in ("", "a" * 11, "  " + "a" * 11 + "\n"):
                value = spec()
                if field == "explanation":
                    value[field] = text
                else:
                    value["options"][0][field] = text
                with self.assertRaisesRegex(ArtifactQuestionError, "feedback"):
                    prepare(value)
        value = spec()
        value["explanation"] = "a" * 12
        for option in value["options"]:
            option["reason"] = "b" * 12
        prepared = prepare(value)
        self.assertEqual(prepared["draft"]["explanation"], "a" * 12)
        self.assertEqual(
            set(prepared["draft"]["choiceExplanations"].values()), {"b" * 12}
        )

    def test_prepared_source_choices_feedback_or_harness_mutation_cannot_reuse_binding(
        self,
    ):
        original = prepare()
        result = service(original, value=original["spec"]["options"][0]["value"])
        for mutate in (
            lambda p: p["spec"]["artifact"].update(source="False"),
            lambda p: p["draft"]["choices"].reverse(),
            lambda p: p["draft"].update(explanation="Rewritten after observation"),
            lambda p: p["job"].update(harness_code="forged"),
        ):
            changed = copy.deepcopy(original)
            mutate(changed)
            with self.assertRaises(ArtifactQuestionError):
                bind(changed, result)

    def test_native_result_missing_from_choices_produces_no_key(self):
        prepared = prepare()
        result = bind(prepared, service(prepared, value={"type": "int", "value": "8"}))
        self.assertEqual(result["status"], "unmatched")
        self.assertIsNone(result["question"])

    def test_native_runtime_mismatch_or_empty_token_produces_no_key(self):
        prepared = prepare()
        for version in ("3.11.9", " "):
            result = service(prepared, value=prepared["spec"]["options"][0]["value"])
            raw = json.loads(result["stdOut"])
            raw["runtime"]["version"] = version
            result["stdOut"] = json.dumps(raw)
            bound = bind(prepared, result)
            self.assertEqual(bound["reason"], "runtime_mismatch")
            self.assertEqual(bound["status"], "unsupported")
            self.assertIsNone(bound["question"])

    def test_changed_invocation_cannot_use_another_inputs_observation(self):
        value = spec(
            "def f(x):\n    return x",
            mode="exec",
            inputs={"entrypoint": "f", "args": [True], "kwargs": {}},
        )
        original = prepare(value)
        recorded = service(original, value={"type": "bool", "value": True})
        value["artifact"]["inputs"]["args"] = [1]
        changed = prepare(value)
        result = bind(changed, recorded)
        self.assertEqual(result["reason"], "artifact_mismatch")
        self.assertIsNone(result["question"])

    def test_valid_resource_limited_observation_remains_inconclusive(self):
        prepared = prepare()
        recorded = service(prepared, value={"type": "bool", "value": True})
        raw = json.loads(recorded["stdOut"])
        raw["status"] = "inconclusive"
        raw["child"].update(
            status="inconclusive", reason="memory_limit", return_value=None
        )
        recorded["stdOut"] = json.dumps(raw)
        result = bind(prepared, recorded)
        self.assertEqual(result["status"], "inconclusive")
        self.assertTrue(result["observation"]["envelope_valid"])
        self.assertFalse(result["observation"]["operational_failure"])
        self.assertIsNone(result["question"])

    def test_uncorrelated_truncated_failed_or_unreaped_observations_produce_no_key(
        self,
    ):
        prepared = prepare()
        changes = [
            lambda r: r.update(artifact_sha256="wrong"),
            lambda r: r.update(timed_out=True),
            lambda r: r.update(transport_truncated=True),
            lambda r: r.update(child_reaped=False),
            lambda r: r["child"].update(truncated=True),
        ]
        for change in changes:
            result = service(prepared, value=prepared["spec"]["options"][0]["value"])
            raw = json.loads(result["stdOut"])
            change(raw)
            result["stdOut"] = json.dumps(raw)
            self.assertIsNone(bind(prepared, result)["question"])
        for result in (
            {},
            {"isError": True},
            {"isError": False, "exitCode": 1, "stdErr": "", "stdOut": ""},
        ):
            self.assertIsNone(bind(prepared, result)["question"])

    def test_unsupported_source_and_unconfirmed_cleanup_produce_no_key(self):
        prepared = prepare(spec("open('anything')"))
        self.assertFalse(prepared["job"]["eligible"])
        self.assertEqual(bind(prepared, {})["status"], "unsupported")
        prepared = prepare()
        for confirmation in (False, None, 1):
            self.assertIsNone(
                bind(prepared, {}, cleanup_confirmed=confirmation)["question"]
            )

    def test_preparation_and_binding_do_not_execute_or_contact_services(self):
        with (
            patch("builtins.exec", side_effect=AssertionError("source executed")),
            patch("subprocess.Popen", side_effect=AssertionError("process spawned")),
        ):
            prepared = prepare()
            self.assertEqual(
                bind(
                    prepared,
                    service(prepared, value=prepared["spec"]["options"][0]["value"]),
                )["status"],
                "bound",
            )


if __name__ == "__main__":
    unittest.main()
