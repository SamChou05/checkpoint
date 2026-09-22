"""Bounded author-only fake-client checks; no credential or network operations."""

import copy
import importlib.util
import json
from pathlib import Path
import socket
import tempfile
import unittest
from unittest.mock import patch

from botocore.exceptions import ClientError
from botocore.session import get_session
from botocore.validate import validate_parameters

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("sonnet_author_tested", HERE / "author_probe.py")
probe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(probe)
_spec = importlib.util.spec_from_file_location("sonnet_author_fake_source", probe.BASELINE / "test_mixed_probe.py")
fixtures = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fixtures)


class AuthorProbeTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(socket.socket, "connect", side_effect=AssertionError("No network")))
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "capture.json"
        self.plan = probe.build_plan()
        self.capture = {"calls": [], "jobs": []}

    def run_fake(self, network=None, pin_check=lambda: None, **kwargs):
        network = network or fixtures.FakeNetwork()
        probe.run_jobs(self.plan, self.capture, self.path, network.client, pin_check, **kwargs)
        return network

    def test_exact_original_requests_and_native_adaptive_supported_config(self):
        prior = probe.original_plan()
        shape = get_session().get_service_model("bedrock-runtime").operation_model("Converse").input_shape
        for index, call in enumerate(self.plan["calls"]):
            self.assertEqual(call["normalized_request_sha256"], probe.digest(prior["jobs"][index]["request"]))
            request = call["request"]
            self.assertEqual(request["modelId"], "us.anthropic.claude-sonnet-4-6")
            self.assertEqual(request["inferenceConfig"], {"maxTokens": 16000})
            self.assertEqual(request["system"][0]["text"], prior["initial_author_prompts"][index]["system"])
            self.assertEqual(request["messages"][0]["content"][0]["text"], prior["initial_author_prompts"][index]["user"])
            self.assertEqual(request["outputConfig"], prior["contracts"][probe.base.MIXED_AUTHOR_CONTRACT])
            probe.native.ensure_supported_model(request["modelId"])
            validate_parameters(request, shape)
        self.assertEqual(self.plan["state"], "draft")
        dry_plan = Path(self.directory.name) / "dry-plan.json"
        dry_capture = Path(self.directory.name) / "dry-capture.json"
        with patch.object(probe, "PLAN", dry_plan), patch.object(probe, "CAPTURE", dry_capture), \
                patch.object(probe.safe, "credential_session", side_effect=AssertionError("No credentials in draft")), \
                patch.object(probe.base.boto3, "client", side_effect=AssertionError("No SDK factory in draft")):
            self.assertEqual(probe.build_plan(), self.plan)
        self.assertFalse(dry_plan.exists())
        self.assertFalse(dry_capture.exists())

    def test_three_author_dispatches_no_solver_reviewer_or_stamps(self):
        network = self.run_fake()
        self.assertEqual(len(network.calls), 3)
        self.assertEqual(self.capture["summary"]["requested_slots"], 15)
        self.assertEqual(self.capture["summary"]["raw_rows_observed"], 15)
        self.assertEqual(self.capture["summary"]["normal_bounded_exact_count_jobs"], 3)
        self.assertFalse(self.capture["summary"]["qualified"])
        for job in self.capture["jobs"]:
            self.assertEqual(job["provider_calls"], 1)
            self.assertEqual([row["source"] for row in job["assessment"]["rows"]], [[job["id"], i] for i in range(5)])
            self.assertNotIn('verificationPolicyRevision', json.dumps(job))
            for row in job["assessment"]["rows"]:
                if row["compiler_status"] == "valid":
                    from quantitative_task_compiler import compile_question
                    self.assertEqual(row["learner"], compile_question(row["compiler_spec"]))
        self.assertTrue(all(call["sdk_attempts"] == 1 and call["read_timeout"] == 100 and call["connect_timeout"] == 3
                            for call in self.capture["calls"]))

    def test_bad_typed_rows_preserve_all_sources_and_never_become_prose(self):
        def modify(index, request, payload, response):
            if index == 0:
                payload["questions"][0]["task"]["choices"] = dict(zip("abcd", ("100", "101", "102", "103")))
                payload["questions"][1]["task"]["choices"] = dict(zip("abcd", ("14", "0.8", "4/5", "99")))
                response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        self.run_fake(fixtures.FakeNetwork(modify))
        rows = self.capture["jobs"][0]["assessment"]["rows"]
        self.assertEqual([row["compiler_failure"] for row in rows[:2]], ["no_answer", "equivalent_choices"])
        self.assertEqual(len(rows), 5)
        self.assertFalse(any("learner" in row or "prose_draft" in row for row in rows[:2]))
        self.assertEqual(len(self.capture["calls"]), 3)

    def test_raw_lengths_and_allocation_are_observed_without_clipping_or_approval(self):
        def modify(index, request, payload, response):
            if index == 2:
                payload["questions"][3]["question"]["explanation"] = "X" * 321
                payload["questions"][4]["question"]["skillID"] = "00000000-0000-4000-8000-000000000000"
                response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        self.run_fake(fixtures.FakeNetwork(modify))
        assessment = self.capture["jobs"][2]["assessment"]
        self.assertEqual(assessment["kind_counts"], {"quantitative": 3, "prose": 2})
        self.assertEqual(assessment["length_failure_rows"], 0)
        self.assertEqual(assessment["prose_instruction_length_deviation_rows"], 1)
        self.assertTrue(assessment["rows"][3]["length_diagnostic"]["all_within_bounds"])
        self.assertFalse(assessment["allocation_diagnostic"]["matches_requested_counts"])
        self.assertEqual(assessment["rows"][3]["prose_draft"]["explanation"], "X" * 321)
        self.assertEqual(assessment["rows"][3]["length_diagnostic"]["fields"]["explanation"]["characters"], 321)
        self.assertFalse(assessment["rows"][4]["assignment_diagnostic"]["metadata_matches_known_assignment"])
        self.assertIsNone(assessment["independently_usable"])
        self.assertEqual(len(self.capture["calls"]), 3)

    def test_prose_main_instruction_and_runtime_limits_are_separate_at_boundaries(self):
        for count, runtime_valid, instruction_valid in ((320, True, True), (321, True, False),
                                                        (420, True, False), (421, False, False)):
            with self.subTest(characters=count):
                content = {"prompt": "A complete prompt.", "choices": ["one", "two", "three", "four"],
                           "explanation": "X" * count}
                result = probe.content_lengths(content, "prose")
                self.assertEqual(result["all_within_bounds"], runtime_valid)
                self.assertEqual(result["prose_author_instruction"]["explanation_within_maximum"], instruction_valid)
                self.assertEqual(result["fields"]["explanation"]["maximum"], 420)
                self.assertEqual(content["explanation"], "X" * count)
        self.assertEqual(self.plan["criteria"]["main_explanation_runtime_maximum"], 420)
        self.assertFalse(self.plan["criteria"]["instruction_deviation_alone_fails_usability"])

    def test_timeout_continues_next_fixed_jobs_once_and_usage_unknown(self):
        def modify(index, *args):
            if index == 0:
                raise TimeoutError("synthetic no-output timeout")
            return args[-1]
        self.run_fake(fixtures.FakeNetwork(modify))
        self.assertEqual(len(self.capture["calls"]), 3)
        self.assertEqual(self.capture["jobs"][0]["status"], "failed")
        self.assertEqual(self.capture["summary"]["normal_bounded_exact_count_jobs"], 2)
        self.assertEqual(self.capture["summary"]["reported_usage"]["calls_without_usage"], 1)
        self.assertEqual(self.capture["summary"]["requested_slots"], 15)

    def test_invalid_model_output_no_repair_and_subsequent_jobs_continue(self):
        for bad_text in ('not json', '{"questions":[],"questions":[]}', '{"questions":[{"kind":"forged"}]}'):
            with self.subTest(bad_text=bad_text):
                self.capture = {"calls": [], "jobs": []}
                def modify(index, request, payload, response):
                    if index == 0:
                        response["output"]["message"]["content"] = [{"text": bad_text}]
                    return response
                self.run_fake(fixtures.FakeNetwork(modify))
                self.assertEqual(len(self.capture["calls"]), 3)
                self.assertEqual(self.capture["jobs"][0]["provider_calls"], 1)
                self.assertFalse(self.capture["jobs"][0].get("native_schema_valid", False))

    def test_wrong_cardinality_and_nonend_response_never_get_full_batch_credit(self):
        for change in ('missing', 'extra', 'max_tokens', 'stop_sequence'):
            with self.subTest(change=change):
                self.capture = {"calls": [], "jobs": []}
                def modify(index, request, payload, response):
                    if index == 0:
                        if change == 'missing':
                            payload['questions'].pop()
                        elif change == 'extra':
                            payload['questions'].append(copy.deepcopy(payload['questions'][0]))
                        else:
                            response['stopReason'] = change
                        response['output']['message']['content'] = [{'text': json.dumps(payload)}]
                    return response
                self.run_fake(fixtures.FakeNetwork(modify))
                self.assertEqual(len(self.capture["calls"]), 3)
                self.assertEqual(self.capture["summary"]["normal_bounded_exact_count_jobs"], 2)
                self.assertEqual(self.capture["summary"]["requested_slots"], 15)

    def test_setup_and_native_configuration_errors_stop_globally_no_account_actions(self):
        for code in ('AccessDeniedException', 'ValidationException', 'ExpiredTokenException'):
            with self.subTest(code=code):
                self.capture = {"calls": [], "jobs": []}
                def modify(*args):
                    raise ClientError({'Error': {'Code': code, 'Message': 'synthetic error'}}, 'Converse')
                self.run_fake(fixtures.FakeNetwork(modify))
                self.assertEqual(len(self.capture["calls"]), 1)
                self.assertEqual(self.capture["summary"]["unattempted_jobs"], 2)
                self.assertTrue(self.capture.get('global_stop'))

    def test_source_drift_before_or_during_dispatch_stops_globally(self):
        count = 0
        def pins():
            nonlocal count
            count += 1
            if count == 2:
                raise probe.base.IntegrityError('synthetic source drift')
        self.run_fake(pin_check=pins)
        self.assertEqual(len(self.capture["calls"]), 0)
        self.assertEqual(self.capture["summary"]["unattempted_jobs"], 2)

    def test_final_call_source_drift_preserves_response_but_fails_integrity(self):
        count = 0
        def pins():
            nonlocal count
            count += 1
            if count == 9:
                raise probe.base.IntegrityError('synthetic final post-dispatch drift')
        network = self.run_fake(pin_check=pins)
        self.assertEqual(len(network.calls), 3)
        self.assertEqual(self.capture["summary"]["requested_slots"], 15)
        self.assertEqual(self.capture["summary"]["normal_bounded_exact_count_jobs"], 2)
        self.assertIn("response", self.capture["calls"][2])
        self.assertEqual(self.capture["global_stop"], "post_dispatch_source_drift")
        self.assertEqual(self.capture["status"], "globally_aborted")

    def test_transport_request_and_factory_integrity_stop_before_network(self):
        for field, value in (("read_timeout", 75), ("connect_timeout", 2), ("retries", {"total_max_attempts": 2})):
            with self.subTest(field=field):
                self.capture = {"calls": [], "jobs": []}
                def modify(client):
                    setattr(client.meta.config, field, value)
                network = self.run_fake(fixtures.FakeNetwork(factory_modify=modify))
                self.assertEqual(len(network.calls), 0)
                self.assertTrue(self.capture.get('global_stop'))
        self.capture = {"calls": [], "jobs": []}
        self.plan["calls"][0]["request"]["inferenceConfig"]["temperature"] = 0.2
        self.run_fake()
        self.assertEqual(len(self.capture["calls"]), 0)
        self.assertTrue(self.capture.get('global_stop'))

    def test_elapsed_bound_redaction_and_raw_visible_content(self):
        ticks = iter((0, 101, 102, 103, 104, 105))
        def modify(index, request, payload, response):
            response['output']['message']['content'].append({'reasoningContent': {'reasoningText': {'text': 'PRIVATE', 'signature': 'SECRET'}}})
            return response
        self.run_fake(fixtures.FakeNetwork(modify), clock=lambda: next(ticks))
        self.assertFalse(self.capture['jobs'][0]['normal_bounded_exact_count'])
        self.assertEqual(self.capture['calls'][0]['reasoning_blocks_omitted'], 1)
        self.assertNotIn('PRIVATE', self.path.read_text())
        self.assertNotIn('SECRET', self.path.read_text())
        self.assertEqual(len(self.capture['jobs'][0]['author_payload']['questions']), 5)

    def test_no_repeat_and_draft_source_hash_binding(self):
        self.run_fake()
        with self.assertRaises(probe.base.IntegrityError):
            self.run_fake()
        changed = copy.deepcopy(self.plan)
        changed['limits']['maximum_dispatches'] = 4
        with self.assertRaises(probe.base.IntegrityError):
            probe.check_plan(changed)


if __name__ == '__main__':
    unittest.main()
