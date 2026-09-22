"""Fake-only trace checks; synthetic approvals establish no educational quality."""

import copy
import importlib.util
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from botocore.config import Config
from botocore.exceptions import ClientError

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("authored_worker_draft", HERE / "worker_pipeline_probe.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class Clock:
    seconds = 0

    def __call__(self):
        return self.seconds


def question(serial):
    return {"prompt": f"Rectangle case {serial} has length 9 cm and width 4 cm. What is its perimeter?",
            "choices": {"a": "26 cm", "b": "36 cm", "c": "13 cm", "d": "18 cm"},
            "explanation": "  The perimeter is 2×9 + 2×4 = 26 cm.\r\n",
            "choiceFeedback": {"a": "Two sides of each length give 18 + 8 = 26 cm.",
                               "b": "9×4 = 36 gives area, not the perimeter.",
                               "c": "9 + 4 = 13 adds only one side of each length.",
                               "d": "2×9 = 18 counts only the two longer sides."},
            "correctChoice": "a", "topic": "Perimeter", "difficulty": 3, "format": "Multiple Choice"}


def assessment(judgment="supported"):
    return {"reason": "Synthetic assessment for offline boundary testing.", "judgment": judgment}


class FakeFactory:
    def __init__(self, clock, modify=None):
        self.clock, self.modify = clock, modify
        self.requests, self.configs, self.authors = [], [], 0

    def __call__(self, service, **kwargs):
        if service != "bedrock-runtime":
            raise AssertionError("Unexpected service; no network is permitted.")
        config = kwargs["config"]
        self.configs.append(config)
        return SimpleNamespace(meta=SimpleNamespace(config=config, endpoint_url=probe.ENDPOINT, region_name="us-east-1"), converse=self.converse)

    def converse(self, **request):
        self.requests.append(copy.deepcopy(request))
        name = request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"]
        count = int(name.rsplit("_n", 1)[1])
        if "authored_feedback_author" in name:
            self.authors += 1
            payload = {"questions": {str(index): question(self.authors * 100 + index) for index in range(count)}}
        elif "complete_choice_solver" in name:
            items = probe.tagged(request, "question_solution_json")["items"]
            payload = {"solutions": {str(item["index"]): {
                "choices": {slot: {"reason": "The perimeter follows from the two stated side lengths.",
                                     "judgment": "supported" if text == "26 cm" else "refuted"}
                            for slot, text in item["choices"].items()},
                "choicePairs": {pair: {"reason": "These are different numerical lengths.", "relation": "distinct"}
                                for pair in ("ab", "ac", "ad", "bc", "bd", "cd")}}
                                     for item in items}}
        else:
            payload = {"reviews": {str(index): {"task": assessment(), "answerChoice": "a", "difficulty": 3,
                                                "feedback": {key: assessment() for key in ("main", "a", "b", "c", "d")}}
                                    for index in range(count)}}
        response = {"stopReason": "end_turn", "output": {"message": {"content": [
            {"text": json.dumps(payload, ensure_ascii=False)}]}}, "usage": {"inputTokens": 10, "outputTokens": 20}}
        if self.modify:
            response = self.modify(request, payload, response)
        return response


class DraftHarnessTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(socket.socket, "connect", side_effect=AssertionError("Fake-only preflight prohibits network")))
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "capture.json"
        self.clock = Clock()
        self.jobs = probe.domain_jobs()
        self.capture = probe.initial_capture(self.jobs)

    def run_job(self, factory, job=None):
        original = probe.runtime._bedrock_client
        with patch("boto3.client", factory):
            probe.run_job(job or self.jobs[0], self.capture, self.path,
                          client_factory=original, clock=self.clock)

    @staticmethod
    def revised(response, payload):
        response["output"]["message"]["content"] = [{"text": json.dumps(payload, ensure_ascii=False)}]
        return response

    def test_six_unchanged_domains_real_three_stage_trace_and_exact_provenance(self):
        before = copy.deepcopy(self.jobs)
        factory = FakeFactory(self.clock)
        for job in self.jobs:
            self.run_job(factory, job)
        self.assertEqual(self.jobs, before)
        self.assertEqual(len(factory.requests), 18)
        self.assertEqual(len(self.capture["reservations"]), 18)
        for row in self.capture["jobs"]:
            self.assertEqual(row["status"], "finished", row)
            self.assertEqual(len(row["accepted"]), 5)
            self.assertEqual(row["provider_budget_calls"], 3)
            self.assertEqual(row["local_reservations"], 3)
            self.assertEqual(len(row["returned_provenance"]), 5)
            for item in row["accepted"]:
                self.assertEqual(item["verificationPolicyRevision"], 5)
                self.assertTrue(item["explanation"].startswith("  "))
                self.assertTrue(item["explanation"].endswith("\r\n"))
        for index, request in enumerate(factory.requests):
            if index % 3 == 0:
                self.assertEqual(request["inferenceConfig"], {"maxTokens": 6000, "temperature": 0.2})
                self.assertEqual(request["additionalModelRequestFields"], {"thinking": {"type": "disabled"}})
            else:
                self.assertEqual(request["inferenceConfig"], {"maxTokens": 16000})
                self.assertEqual(request["additionalModelRequestFields"], {
                    "thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}})
        result = probe.summary(self.capture)
        self.assertEqual(result["accepted_total"], 30)
        self.assertTrue(result["yield_criterion_passed"])
        self.assertTrue(result["all_attempts_succeeded"])
        self.assertFalse(result["release_qualified"])

    def test_all120_contracts_and_explicit_source_are_recorded_without_freezing(self):
        self.assertEqual(len(probe.contract_registry()), 120)
        self.assertEqual(probe.source_manifest()["source_root"], str(probe.SOURCE_ROOT.resolve()))
        self.assertEqual(probe.draft_description()["status"], "draft_not_frozen")
        self.assertFalse((HERE / "worker-plan.json").exists())

    def test_history_and_assignments_reach_dense_solver_survivors_without_answer_leakage(self):
        job = copy.deepcopy(self.jobs[0])
        job["request"]["existingQuestionCoverage"] = [
            {"prompt": f"Historical question {i}", "topic": "Arithmetic", "objective": f"Application {i}",
             "expectedAnswer": "SECRET_KEY", "explanation": "SECRET_TEACHING", "difficulty": 5, "valid": True}
            for i in range(32)]

        def modify(request, payload, response):
            if "solutions" in payload:
                for value in payload["solutions"]["0"]["choices"].values():
                    value["judgment"] = "uncertain"
                return self.revised(response, payload)
            return response

        factory = FakeFactory(self.clock, modify)
        with patch.dict(probe.ENVIRONMENT, {"GENERATION_ATTEMPTS": "1"}):
            self.run_job(factory, job)
        audit_request = factory.requests[2]
        data = probe.tagged(audit_request, "authored_feedback_audit_json")
        self.assertEqual(list(data["items"]), ["0", "1", "2", "3"])
        self.assertEqual(data["items"]["0"]["prompt"], question(101)["prompt"])
        self.assertEqual(data["items"]["0"]["assignment"], {"topic": "Perimeter"})
        self.assertEqual(len(data["existingQuestionCoverage"]), 30)
        self.assertEqual(data["existingQuestionCoverage"][0]["prompt"], "Historical question 2")
        self.assertNotIn("SECRET_", json.dumps(data))
        self.assertNotIn("expectedAnswer", json.dumps(data))
        self.assertEqual(self.capture["jobs"][0]["passes"][0]["audit_sources"], ["0:0:1", "0:0:2", "0:0:3", "0:0:4"])

    def test_audit_uncertainty_is_semantic_rejection_and_never_rewrites_teaching(self):
        def modify(request, payload, response):
            if "reviews" in payload:
                payload["reviews"]["0"]["feedback"]["main"] = assessment("uncertain")
            return self.revised(response, payload)
        factory = FakeFactory(self.clock, modify)
        with patch.dict(probe.ENVIRONMENT, {"GENERATION_ATTEMPTS": "1"}):
            self.run_job(factory)
        self.assertEqual(len(self.capture["jobs"][0]["accepted"]), 4)
        self.assertFalse(self.capture.get("stop_dispatching", False))

    def test_complete_sanitized_objective_assignment_survives_filtering_in_actual_trace(self):
        from request_contract import _normalize_request
        skill = "a0000000-0000-4000-8000-000000000001"
        objective = "b0000000-0000-4000-8000-000000000001"
        request = _normalize_request({"goal": {"title": "Apply geometry", "contentTopics": ["Geometry"]},
            "skillMap": {"version": 1, "skills": [{"id": skill, "name": "Geometry",
                "objectives": [{"id": objective, "name": "Compute perimeter"}]}]},
            "targetCount": 5, "minimumDifficulty": 2})
        job = {"index": 0, "request": request}

        def modify(request, payload, response):
            if "questions" in payload:
                for row in payload["questions"].values():
                    row.update(topic="Geometry", skillID=skill, objectiveID=objective, objective="Compute perimeter")
            if "solutions" in payload:
                for row in payload["solutions"]["0"]["choices"].values():
                    row["judgment"] = "uncertain"
            return self.revised(response, payload)

        factory = FakeFactory(self.clock, modify)
        with patch.dict(probe.ENVIRONMENT, {"GENERATION_ATTEMPTS": "1"}):
            self.run_job(factory, job)
        self.assertEqual(self.capture["jobs"][0]["status"], "finished", self.capture["failures"])
        data = probe.tagged(factory.requests[2], "authored_feedback_audit_json")
        self.assertEqual(data["items"]["0"]["prompt"], question(101)["prompt"])
        for item in data["items"].values():
            self.assertEqual(item["assignment"], {"topic": "Geometry", "skillID": skill,
                                                 "objectiveID": objective, "objective": "Compute perimeter"})
        self.assertEqual(data["existingQuestionCoverage"], [])

    def test_duplicate_authored_teaching_uses_actual_sanitizer_source_without_global_abort(self):
        for first_ineligible in (False, True):
            with self.subTest(first_ineligible=first_ineligible):
                self.capture = probe.initial_capture(self.jobs)
                def modify(request, payload, response):
                    if "questions" in payload:
                        payload["questions"]["1"] = copy.deepcopy(payload["questions"]["0"])
                        if first_ineligible:
                            payload["questions"]["0"]["difficulty"] = 1
                    return self.revised(response, payload)
                factory = FakeFactory(self.clock, modify)
                with patch.dict(probe.ENVIRONMENT, {"GENERATION_ATTEMPTS": "1"}):
                    self.run_job(factory)
                row = self.capture["jobs"][0]
                self.assertEqual(row["status"], "finished", self.capture["failures"])
                self.assertEqual(len(row["accepted"]), 4)
                self.assertEqual(row["returned_provenance"][0]["source_id"], f"0:0:{int(first_ineligible)}")
                self.assertFalse(self.capture.get("stop_dispatching", False))

    def test_audit_builder_content_scope_assignment_and_history_changes_stop_before_dispatch(self):
        original = probe.audit.build_input
        for field in ("feedback", "scope", "assignment", "history"):
            with self.subTest(field=field):
                self.capture = probe.initial_capture(self.jobs)
                def changed(original_payloads, scope, *, assignments=None, history=None):
                    result = original(original_payloads, scope, assignments=assignments, history=history)
                    if field == "feedback":
                        result["items"]["0"]["feedback"]["main"] = "Replaced teaching."
                    elif field == "scope":
                        result["goal"]["title"] = "Changed task scope"
                    elif field == "assignment":
                        result["items"]["0"]["assignment"]["topic"] = "Unrelated topic"
                    else:
                        result["existingQuestionCoverage"] = [{"prompt": "Invented history"}]
                    return result
                factory = FakeFactory(self.clock)
                with patch.object(probe.audit, "build_input", changed):
                    self.run_job(factory)
                self.assertEqual(len(factory.requests), 2)
                self.assertTrue(self.capture["stop_dispatching"])
                self.assertEqual(self.capture["jobs"][0]["accepted"], [])

    def test_returned_partial_survives_failed_topoff_and_next_fixed_job_runs(self):
        def modify(request, payload, response):
            if "reviews" in payload and len(payload["reviews"]) == 5:
                payload["reviews"]["4"]["task"] = assessment("unsupported")
                return self.revised(response, payload)
            if "questions" in payload and len(payload["questions"]) == 1:
                raise ClientError({"Error": {"Code": "ValidationException", "Message": "Compiled grammar is too large"},
                                   "ResponseMetadata": {"HTTPStatusCode": 400, "RequestId": "synthetic-request"}}, "Converse")
            return response
        factory = FakeFactory(self.clock, modify)
        self.run_job(factory)
        self.run_job(factory, self.jobs[1])
        row = self.capture["jobs"][0]
        self.assertEqual(len(row["accepted"]), 4)
        self.assertEqual(row["status"], "finished")
        self.assertEqual(len(factory.requests), 8)
        self.assertEqual(self.capture["jobs"][1]["status"], "finished")
        self.assertEqual(len(self.capture["jobs"][1]["accepted"]), 4)
        error = self.capture["calls"][-1]
        self.assertEqual(error["provider_code"], "ValidationException")
        self.assertEqual(error["provider_message"], "Compiled grammar is too large")
        self.assertEqual(error["http_status"], 400)
        self.assertFalse(probe.summary(self.capture)["all_attempts_succeeded"])
        self.assertFalse(self.capture.get("stop_dispatching", False))
        self.assertTrue(probe.summary(self.capture)["all_returned_content_has_exact_provenance"])

    def test_reasoning_blocks_are_removed_without_changing_visible_response(self):
        def modify(request, payload, response):
            response["output"]["message"]["content"].insert(0, {
                "reasoningContent": {"reasoningText": {"text": "PRIVATE_REASONING", "signature": "PRIVATE_SIGNATURE"}}})
            response["ResponseMetadata"] = {"HTTPHeaders": {"secret": "PRIVATE_HEADER"}, "Other": "PRIVATE_METADATA"}
            response["unknown"] = "PRIVATE_UNKNOWN"
            response["usage"]["unknown"] = "PRIVATE_USAGE"
            return response
        self.run_job(FakeFactory(self.clock, modify))
        self.assertNotIn("PRIVATE_", self.path.read_text())
        self.assertTrue(all(call["reasoning_content_block_count"] == 1 for call in self.capture["calls"]))

    def test_runtime_terminates_nonnormal_completion_or_wrong_author_identity(self):
        for kind in ("truncated", "missing", "duplicate"):
            self.capture = probe.initial_capture(self.jobs)
            def modify(request, payload, response):
                if kind == "truncated":
                    response["stopReason"] = "max_tokens"
                elif kind == "missing":
                    payload["questions"].pop("0")
                    self.revised(response, payload)
                else:
                    text = response["output"]["message"]["content"][0]["text"]
                    response["output"]["message"]["content"][0]["text"] = text.replace('"correctChoice": "a"', '"correctChoice":"a","correctChoice":"b"')
                return response
            factory = FakeFactory(self.clock, modify)
            with self.subTest(kind=kind):
                self.run_job(factory)
                self.assertEqual(len(factory.requests), 1)
                self.assertFalse(self.capture.get("stop_dispatching", False))
                self.assertEqual(self.capture["jobs"][0]["accepted"], [])

    def test_predispatch_client_failure_and_empty_capture_cannot_pass(self):
        self.assertFalse(probe.summary(self.capture)["all_attempts_succeeded"])
        self.assertFalse(probe.summary(self.capture)["deadline_criterion_passed"])
        def factory(budget):
            raise probe.ProviderError("Synthetic client setup failed")
        probe.run_job(self.jobs[0], self.capture, self.path, client_factory=factory, clock=self.clock)
        self.assertEqual(self.capture["calls"], [])
        self.assertEqual(self.capture["reservations"], [])
        self.assertTrue(self.capture["stop_dispatching"])
        self.assertEqual(self.capture["jobs"][0]["status"], "failed")

    def test_wrong_audit_settings_and_unsafe_sdk_retries_are_stopped_offline(self):
        factory = FakeFactory(self.clock)
        with patch.object(probe.runtime, "_authored_feedback_audit_settings", return_value=(
                {"maxTokens": 6000}, {"thinking": {"type": "disabled"}})):
            self.run_job(factory)
        self.assertEqual(len(factory.requests), 2)
        self.assertTrue(self.capture["stop_dispatching"])
        self.capture = probe.initial_capture(self.jobs)
        def unsafe(budget):
            return SimpleNamespace(meta=SimpleNamespace(config=Config(connect_timeout=3, read_timeout=100,
                retries={"total_max_attempts": 2})), converse=lambda **_: self.fail("Unsafe SDK dispatched"))
        probe.run_job(self.jobs[0], self.capture, self.path, client_factory=unsafe, clock=self.clock)
        self.assertEqual(self.capture["calls"], [])
        self.assertEqual(self.capture["reservations"], [])

    def test_runtime_deadline_shrinks100_second_ceiling_and_never_exceeds_six_reservations(self):
        def modify(request, payload, response):
            self.clock.seconds += 100
            return response
        factory = FakeFactory(self.clock, modify)
        self.run_job(factory)
        self.assertEqual([config.read_timeout for config in factory.configs[:2]], [100, 100])
        self.assertLess(factory.configs[2].read_timeout, 35)
        self.assertEqual(len(factory.requests), 3)
        self.assertFalse(self.capture["jobs"][0]["within_240_second_deadline"])
        self.assertLessEqual(len(self.capture["reservations"]), 6)
        self.assertFalse(self.capture.get("stop_dispatching", False))

    def test_two_passes_share_six_call_reservations_and_keep_verified_partial(self):
        def modify(request, payload, response):
            if "reviews" in payload:
                for index, row in payload["reviews"].items():
                    if len(payload["reviews"]) != 5 or int(index) >= 2:
                        row["task"] = assessment("unsupported")
                return self.revised(response, payload)
            return response
        factory = FakeFactory(self.clock, modify)
        self.run_job(factory)
        row = self.capture["jobs"][0]
        self.assertEqual(row["status"], "finished", row)
        self.assertEqual(len(row["accepted"]), 2)
        self.assertEqual(len(factory.requests), 6)
        self.assertEqual(row["local_reservations"], 6)
        self.assertEqual(row["provider_budget_calls"], 6)
        self.assertEqual(factory.authors, 2)

    def test_global36_reservation_ceiling_stops_before_network_dispatch(self):
        self.capture["reservations"] = [{"job": 5}] * 36
        factory = FakeFactory(self.clock)
        self.run_job(factory)
        self.assertEqual(factory.requests, [])
        self.assertEqual(len(self.capture["reservations"]), 36)
        self.assertEqual(self.capture["calls"], [])
        self.assertTrue(self.capture["stop_dispatching"])

    def test_routine_deadline_budget_and_durable_refusal_allow_next_independent_job(self):
        from service_errors import DurableProviderCallBudgetExceededError
        for error_type in (probe.ProviderDeadlineExceededError, probe.ProviderCallBudgetExceededError,
                           DurableProviderCallBudgetExceededError):
            with self.subTest(error=error_type.__name__):
                self.capture = probe.initial_capture(self.jobs)
                def refused(budget):
                    raise error_type("Synthetic per-job admission refusal")
                probe.run_job(self.jobs[0], self.capture, self.path, client_factory=refused, clock=self.clock)
                self.assertFalse(self.capture.get("stop_dispatching", False))
                self.assertEqual(self.capture["jobs"][0]["status"], "failed")
                factory = FakeFactory(self.clock)
                self.run_job(factory, self.jobs[1])
                self.assertEqual(len(factory.requests), 3)
                self.assertEqual(len(self.capture["jobs"][1]["accepted"]), 5)

    def test_first_provider_failure_keeps_all_six_fixed_jobs_and_raw_failure(self):
        def modify(request, payload, response):
            if len(factory.requests) == 1:
                raise TimeoutError("Synthetic initial provider timeout")
            return response
        factory = FakeFactory(self.clock, modify)
        original = probe.runtime._bedrock_client
        with patch("boto3.client", factory):
            probe.run_jobs(self.jobs, self.capture, self.path, client_factory=original, clock=self.clock)
        result = self.capture["summary"]
        self.assertEqual(result["requested_total"], 30)
        self.assertEqual(result["accepted_by_job"], [0, 5, 5, 5, 5, 5])
        self.assertEqual(result["provider_dispatch_attempts"], 16)
        self.assertEqual(result["provider_failure_calls"], 1)
        self.assertFalse(result["yield_criterion_passed"])
        self.assertFalse(result["global_integrity_abort"])
        self.assertEqual(self.capture["calls"][0]["error_type"], "TimeoutError")

    def test_credentials_failure_aborts_globally_with_all_six_jobs_in_denominator(self):
        def modify(request, payload, response):
            raise ClientError({"Error": {"Code": "ExpiredTokenException", "Message": "Synthetic expired credential"}}, "Converse")
        factory = FakeFactory(self.clock, modify)
        original = probe.runtime._bedrock_client
        with patch("boto3.client", factory):
            probe.run_jobs(self.jobs, self.capture, self.path, client_factory=original, clock=self.clock)
        self.assertEqual(len(factory.requests), 1)
        self.assertTrue(self.capture["summary"]["global_integrity_abort"])
        self.assertEqual(self.capture["summary"]["requested_total"], 30)
        self.assertEqual(self.capture["summary"]["accepted_by_job"], [0] * 6)
        self.assertEqual([row["status"] for row in self.capture["jobs"]], ["failed"] + ["unattempted"] * 5)

    def test_returned_teaching_rewrite_is_an_integrity_failure(self):
        original = probe.verifier.verify_authored_feedback
        def rewrite(*args, **kwargs):
            returned = original(*args, **kwargs)
            returned[0]["explanation"] = "This is an unreviewed replacement explanation."
            return returned
        factory = FakeFactory(self.clock)
        with patch.object(probe.verifier, "verify_authored_feedback", rewrite):
            self.run_job(factory)
        self.assertEqual(len(factory.requests), 3)
        self.assertTrue(self.capture["stop_dispatching"])
        self.assertEqual(self.capture["jobs"][0]["accepted"], [])

    def frozen_fixture(self):
        path = Path(self.directory.name) / "worker-plan.json"
        with patch.object(probe, "preflight", return_value={"result": "passed", "provider_network_calls": 0}):
            result = probe.freeze(path, "Synthetic interface test; no provider authorization")
        return path, result["plan_sha256"]

    def test_freeze_pins_exact_sources_gold_requests_all_stage_contracts_and_cannot_overwrite(self):
        path, digest = self.frozen_fixture()
        plan = probe.read_frozen_plan(path, digest)
        pins = plan["pins"]
        self.assertEqual(pins["jobs"], self.jobs)
        self.assertEqual(pins["domain_source_input_and_gold_rules"], json.loads(probe.DOMAIN_PLAN.read_text()))
        self.assertEqual(len(pins["registered_stage_contracts"]), 120)
        self.assertEqual(len(pins["sources"]["service"]), 28)
        self.assertEqual(pins["limits"]["maximum_calls"], 36)
        self.assertEqual(pins["limits"]["job_deadline_seconds"], 240)
        self.assertEqual(pins["prospective_criteria"]["minimum_total_admitted_of_30"], 27)
        with self.assertRaises(RuntimeError):
            probe.freeze(path, "Cannot replace a frozen experiment")

    def test_execute_rejects_hash_or_config_drift_before_credential_export(self):
        path, digest = self.frozen_fixture()
        with patch.object(probe, "credential_session") as credentials:
            with self.assertRaises(RuntimeError):
                probe.execute("0" * 64, path)
            plan = json.loads(path.read_text())
            plan["pins"]["limits"]["maximum_calls"] = 37
            probe.save(path, plan)
            with self.assertRaises(RuntimeError):
                probe.execute(probe.sha(path.read_bytes()), path)
            credentials.assert_not_called()
        self.assertFalse(path.with_name("worker-capture.json").exists())

    def test_execute_runs_six_fake_jobs_and_refuses_replay_before_credentials(self):
        path, digest = self.frozen_fixture()
        factory = FakeFactory(self.clock)
        with patch.object(probe, "credential_session", return_value=(SimpleNamespace(client=factory), ())):
            result = probe.execute(digest, path)
        self.assertEqual(result["summary"]["accepted_total"], 30)
        self.assertEqual(len(factory.requests), 18)
        capture = json.loads(Path(result["capture_path"]).read_text())
        self.assertTrue(all(call["integrity_after_dispatch"] for call in capture["calls"]))
        with patch.object(probe, "credential_session") as credentials:
            with self.assertRaises(FileExistsError):
                probe.execute(digest, path)
            credentials.assert_not_called()

    def test_source_change_during_dispatch_globally_aborts_without_qualification_credit(self):
        path, digest = self.frozen_fixture()
        factory = FakeFactory(self.clock)
        original = probe.source_manifest
        def changed():
            result = original()
            if factory.requests:
                result["domain_plan_sha256"] = "changed-during-response"
            return result
        with patch.object(probe, "credential_session", return_value=(SimpleNamespace(client=factory), ())), \
                patch.object(probe, "source_manifest", changed):
            result = probe.execute(digest, path)
        self.assertEqual(len(factory.requests), 1)
        self.assertTrue(result["summary"]["global_integrity_abort"])
        self.assertFalse(result["summary"]["qualification_evidence_eligible"])
        self.assertEqual(result["summary"]["accepted_total"], 0)
        capture = json.loads(Path(result["capture_path"]).read_text())
        self.assertFalse(capture["calls"][0]["integrity_after_dispatch"])

    def test_exact_exported_credential_values_are_redacted_before_error_persistence(self):
        path, digest = self.frozen_fixture()
        secrets = ("SYNTHETIC_ACCESS_KEY", "SYNTHETIC_SECRET_KEY", "SYNTHETIC_SESSION_TOKEN")
        def modify(request, payload, response):
            raise ClientError({"Error": {"Code": "ValidationException", "Message": " / ".join(secrets)},
                               "ResponseMetadata": {"RequestId": secrets[0], "HTTPHeaders": {"secret": secrets[1]}}}, "Converse")
        factory = FakeFactory(self.clock, modify)
        with patch.object(probe, "credential_session", return_value=(SimpleNamespace(client=factory), secrets)):
            result = probe.execute(digest, path)
        encoded = Path(result["capture_path"]).read_text()
        self.assertTrue(all(secret not in encoded for secret in secrets))
        self.assertIn("REDACTED_CREDENTIAL", encoded)
        self.assertEqual(len(factory.requests), 6)
        self.assertFalse(result["summary"]["global_integrity_abort"])

    def test_credential_export_size_and_time_limits_use_only_local_fake_processes(self):
        original = subprocess.Popen
        for code, limits in (("print('x' * 40000)", {"timeout_seconds": 2, "maximum_output_bytes": 32}),
                             ("import time; time.sleep(2)", {"timeout_seconds": 0.05, "maximum_output_bytes": 32768})):
            with self.subTest(code=code), patch.dict(probe.CREDENTIAL_LIMITS, limits):
                def fake_process(*args, **kwargs):
                    return original([sys.executable, "-c", code], **kwargs)
                with patch.object(probe.subprocess, "Popen", fake_process), self.assertRaises(RuntimeError):
                    probe.export_credentials()

    def test_equivalent_legacy_retry_config_is_rejected_when_total_max_attempts_is_absent(self):
        def factory(budget):
            return SimpleNamespace(meta=SimpleNamespace(config=Config(connect_timeout=3, read_timeout=100,
                retries={"max_attempts": 0}), endpoint_url=probe.ENDPOINT, region_name="us-east-1"),
                converse=lambda **_: self.fail("Unpinned SDK retry config dispatched"))
        probe.run_job(self.jobs[0], self.capture, self.path, client_factory=factory, clock=self.clock)
        self.assertEqual(self.capture["calls"], [])
        self.assertTrue(self.capture["stop_dispatching"])


if __name__ == "__main__":
    unittest.main()
