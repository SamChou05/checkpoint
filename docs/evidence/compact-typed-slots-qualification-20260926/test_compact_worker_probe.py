"""Socket-blocked one-job mixed worker probe using fake provider responses only."""

import copy
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import socket
import stat
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from botocore.exceptions import ClientError

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("compact_mapped_probe_tested", HERE / "full_worker_probe.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)
from quantitative_authoring import _constructed_candidate  # noqa: E402


def data(request):
    text = request["messages"][0]["content"][0]["text"]
    match = re.search(r"<[^>]*_json>\n(.*?)\n</[^>]*_json>", text, re.S)
    return json.loads(match.group(1))


def fake_export(expires_after_seconds=900):
    return json.dumps({"Version": 1, "AccessKeyId": "SYNTHETIC_ACCESS_KEY",
                       "SecretAccessKey": "SYNTHETIC_SECRET_KEY",
                       "SessionToken": "SYNTHETIC_SESSION_TOKEN",
                       "Expiration": (datetime.now(timezone.utc)
                                      + timedelta(seconds=expires_after_seconds)).isoformat()}).encode()


class FakeNetwork:
    def __init__(self, modify=None, factory_modify=None):
        self.calls, self.known, self.authors = [], {}, 0
        self.modify, self.factory_modify = modify, factory_modify

    def client(self, *args, **kwargs):
        client = SimpleNamespace(meta=SimpleNamespace(config=kwargs["config"], endpoint_url=probe.ENDPOINT, region_name="us-east-1"),
                                 converse=self.converse)
        if self.factory_modify:
            self.factory_modify(client)
        return client

    def converse(self, **request):
        index = len(self.calls)
        self.calls.append(copy.deepcopy(request))
        name = request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"]
        given = data(request)
        if name.startswith("question_author_constructed_mapped_compact_"):
            rows = []
            self.authors += 1
            skills = given.get("skillMap", {}).get("skills", []) if given.get("skillMap") else []
            allocations = given.get("requestedSkillAllocation", {})
            assignments = [skill for skill in skills for _ in range(allocations.get(skill["id"], 0))]
            for number in range(given["targetCount"]):
                value = 10 * self.authors + number
                skill = assignments[number] if assignments else None
                prose = bool(skill and "English" in skill["name"])
                metadata = {"topic": skill["name"] if skill else "Arithmetic", "difficulty": 2}
                if skill:
                    metadata.update(skillID=skill["id"], objectiveID=skill["objectives"][0]["id"], objective=skill["objectives"][0]["name"])
                if prose:
                    prompt = f'In Python 3, what is the value of len("{"a" * value}")?'
                    choices = [str(value + 1), str(value), str(value + 2), str(value + 3)]
                    if skill:
                        prompt = f"Choose the grammatically correct sentence about the players on team {value}."
                        choices = ["The players runs.", "The players run.", "The player run.", "The players running."]
                    question = {"prompt": prompt, "choices": dict(zip("abcd", choices)), "correctChoice": "b",
                                "explanation": "Synthetic authored explanation for a fake transport fixture.",
                                "difficulty": 2, "format": "Multiple Choice"}
                    rows.append(question)
                    self.known[prompt] = choices[1]
                else:
                    task = {"kind": "exact_value", "unit": "unitless",
                            "nodes": [{"kind": "literal", "value": str(value)}, {"kind": "literal", "value": "3"},
                                      {"kind": "binary", "op": "add", "left": 0, "right": 1}], "root": 2}
                    rows.append(task)
                    content = _constructed_candidate(task).content()
                    self.known[content["prompt"]] = content["expectedAnswer"]
            questions_schema = request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"]
            shape = json.loads(questions_schema)["properties"]["questions"]["type"]
            if shape != "object":
                raise AssertionError("Compact author lost its fixed object slots")
            payload = {"questions": {str(i): row for i, row in enumerate(rows)}}
        elif name.startswith("complete_choice_solver"):
            payload = {"solutions": {str(item["index"]): {
                "choices": {slot: {"reason": "Synthetic fixed answer judgment.",
                                   "judgment": "supported" if choice == self.known[item["prompt"]] else "refuted"}
                            for slot, choice in item["choices"].items()},
                "choicePairs": {pair: {"reason": "Synthetic distinct-pair judgment.", "relation": "distinct"}
                                for pair in item["choicePairs"]}} for item in given["items"]}}
        else:
            payload = {"reviews": {str(item["index"]): {
                "valid": True, "answer": self.known[item["prompt"]], "difficulty": 2,
                "explanationSupport": "supported", "issueFlags": {flag: False for flag in ("answer_or_ambiguity", "explanation", "distractors", "scope_assignment", "novelty", "other")}} for item in given["items"]}}
        response = {"stopReason": "end_turn", "output": {"message": {"content": [{"text": json.dumps(payload)}]}},
                    "usage": {"inputTokens": 100, "outputTokens": 200}}
        return self.modify(index, request, payload, response) if self.modify else response


class FakeIdentitySession:
    def __init__(self, account=probe.EXPECTED_ACCOUNT_ID, endpoint=probe.STS_ENDPOINT,
                 signin_refreshes=0):
        self.account, self.endpoint = account, endpoint
        self.client_calls, self.identity_requests = [], 0
        self.signin_refreshes = signin_refreshes
        self.event_handlers = {}
        self.events = SimpleNamespace(register=self.register_event)

    def register_event(self, name, handler):
        self.event_handlers[name] = handler

    def client(self, service, **kwargs):
        self.client_calls.append((service, kwargs))
        if service != "sts":
            return SimpleNamespace(meta=SimpleNamespace(endpoint_url=probe.ENDPOINT))

        def identity():
            for _ in range(self.signin_refreshes):
                self.event_handlers["before-call.signin.CreateOAuth2Token"]()
            self.identity_requests += 1
            return {"Account": self.account, "Arn": "unretained-test-arn", "UserId": "unretained-test-id"}

        return SimpleNamespace(meta=SimpleNamespace(
            endpoint_url=self.endpoint, region_name=kwargs["region_name"], config=kwargs["config"]),
            get_caller_identity=identity)


class FakeAwsSession(FakeIdentitySession):
    def __init__(self, network, **kwargs):
        super().__init__(**kwargs)
        self.network = network

    def client(self, service, **kwargs):
        if service == "bedrock-runtime":
            self.client_calls.append((service, kwargs))
            return self.network.client(service, **kwargs)
        return super().client(service, **kwargs)


class MixedWorkerProbeTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(socket.socket, "connect", side_effect=AssertionError("No network in offline tests")))
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "capture.json"
        self.plan = probe.build_plan()
        self.capture = probe.new_capture(self.plan)

    def run_fake(self, network=None, **kwargs):
        network = network or FakeNetwork()
        probe.run_jobs(self.plan, self.capture, self.path, network.client,
                       kwargs.pop("pin_check", lambda: probe.check_plan(self.plan)), **kwargs)
        return network

    def fake_launch(self, network=None, *, account=probe.EXPECTED_ACCOUNT_ID,
                    expires_after_seconds=600):
        """Patch every external boundary, leaving durable state transitions real."""
        network = network or FakeNetwork()
        session = FakeAwsSession(network, account=account)
        expiry = datetime.now(timezone.utc) + timedelta(seconds=expires_after_seconds)
        paths = {name: Path(self.directory.name) / filename for name, filename in (
            ("LAUNCH_ATTEMPT", "launch-precheck-attempt.json"),
            ("LAUNCH_PRECHECK", "launch-precheck.json"),
            ("PLAN", "plan.json"), ("CAPTURE", "capture.json"))}
        for name, path in paths.items():
            self.enterContext(patch.object(probe, name, path))
        self.enterContext(patch.object(probe, "validate_identity_environment", return_value=None))
        self.enterContext(patch.object(probe, "check_default_profile", return_value=None))
        self.enterContext(patch.object(probe, "check_aws_cli", return_value=None))
        self.enterContext(patch.object(probe, "preflight", return_value={"provider_calls": 0, "result": "passed"}))
        self.enterContext(patch.object(probe, "require_live_candidate_ready", return_value=None))
        self.enterContext(patch.object(probe.boto3, "Session", return_value=session))
        credentials = self.enterContext(patch.object(
            probe, "default_profile_session", return_value=(session, ("SYNTHETIC_SECRET_NOT_IN_RESPONSE",), expiry)))
        return session, network, credentials, paths

    def test_draft_review_state_controls_live_precheck_gate(self):
        self.assertEqual(self.plan["state"], "draft_offline_ready")
        self.assertFalse(self.plan["qualification_ready"])
        self.assertEqual(self.plan["candidate_source_revision"],
                         "5183423ae31508ce0a8ac1eb316070a0230cf5d5")
        self.assertEqual(self.plan["candidate_pins"],
                         json.loads(probe.DRAFT_SPEC.read_text())["initial_author_pins"])
        self.assertEqual(self.plan["pins_status"], "source_prompt_schema_and_harness_reviewed")
        reviewed = probe.DRAFT_DATA["independent_harness_review"] == "go"
        self.assertEqual(self.plan["launch_precheck"]["status"],
                         "ready_for_one_shot_precheck" if reviewed else "pending_independent_harness_review")
        if reviewed:
            self.assertIsNone(probe.require_live_candidate_ready())
        else:
            with self.assertRaises(probe.IntegrityError):
                probe.require_live_candidate_ready()

    def test_fake_precheck_freeze_execute_preserves_exact_draft_and_frozen_plan(self):
        session, network, credentials, paths = self.fake_launch()
        precheck = probe.launch_precheck()
        draft = probe.build_plan()
        self.assertEqual(precheck["draft_digest"], probe.digest(draft))
        self.assertEqual(json.loads(paths["LAUNCH_ATTEMPT"].read_text())["draft_digest"], probe.digest(draft))
        frozen = probe.freeze(probe.digest(draft))
        saved = probe.safe.strict_json(paths["PLAN"].read_text())
        self.assertEqual(saved, {**draft, "state": "frozen"})
        self.assertEqual(probe.file_hash(paths["PLAN"]), frozen["plan_sha256"])
        probe.check_plan(saved, paths["PLAN"], frozen["plan_sha256"])
        result = probe.execute(frozen["plan_sha256"])
        self.assertEqual(result["status"], "completed_pending_review")
        self.assertEqual(result["summary"]["planned_questions"], 5)
        self.assertEqual(result["summary"]["returned_questions"], 5)
        capture = probe.safe.strict_json(paths["CAPTURE"].read_text())
        self.assertEqual(capture["plan_sha256"], frozen["plan_sha256"])
        self.assertEqual(len(capture["original_jobs"][0]["slots"]), 5)
        self.assertEqual(len(capture["call_slots"]), 6)
        self.assertEqual(len(network.calls), 3)
        self.assertEqual(session.identity_requests, 2)
        self.assertEqual(credentials.call_count, 2)
        with self.assertRaises(probe.IntegrityError):
            probe.launch_precheck()
        with self.assertRaises(FileExistsError):
            probe.execute(frozen["plan_sha256"])
        self.assertEqual(len(network.calls), 3)

    def test_fake_freeze_rejects_wrong_draft_digest_without_plan(self):
        _, network, credentials, paths = self.fake_launch()
        probe.launch_precheck()
        with self.assertRaises(probe.IntegrityError):
            probe.freeze("0" * 64)
        self.assertFalse(paths["PLAN"].exists())
        self.assertEqual(network.calls, [])
        self.assertEqual(credentials.call_count, 1)

    def test_fake_precheck_record_drift_blocks_freeze(self):
        _, network, credentials, paths = self.fake_launch()
        probe.launch_precheck()
        record = json.loads(paths["LAUNCH_PRECHECK"].read_text())
        record["draft_digest"] = "0" * 64
        paths["LAUNCH_PRECHECK"].write_text(json.dumps(record))
        with self.assertRaises(probe.IntegrityError):
            probe.freeze(probe.digest(probe.build_plan()))
        self.assertFalse(paths["PLAN"].exists())
        self.assertEqual(network.calls, [])
        self.assertEqual(credentials.call_count, 1)

    def test_fake_stale_precheck_window_blocks_freeze(self):
        _, network, _, paths = self.fake_launch()
        record = probe.launch_precheck()
        stale_now = datetime.fromisoformat(record["credential_expires_at"]) - timedelta(seconds=329)
        with self.assertRaises(probe.IntegrityError):
            probe.check_launch_record(probe.build_plan(), now=stale_now)
        self.assertFalse(paths["PLAN"].exists())
        self.assertEqual(network.calls, [])

    def test_fake_frozen_plan_drift_blocks_execute_before_credentials(self):
        _, network, credentials, paths = self.fake_launch()
        probe.launch_precheck()
        frozen = probe.freeze(probe.digest(probe.build_plan()))
        saved = probe.safe.strict_json(paths["PLAN"].read_text())
        saved["environment"]["BEDROCK_MODEL_ID"] = "changed-model"
        paths["PLAN"].write_text(json.dumps(saved))
        tampered_sha = probe.file_hash(paths["PLAN"])
        with self.assertRaises(probe.IntegrityError):
            probe.execute(tampered_sha)
        self.assertFalse(paths["CAPTURE"].exists())
        self.assertEqual(network.calls, [])
        self.assertEqual(credentials.call_count, 1)
        self.assertNotEqual(tampered_sha, frozen["plan_sha256"])

    def test_fake_wrong_account_stops_before_model_dispatch_with_five_slots(self):
        session, network, _, paths = self.fake_launch(account="000000000000")
        with self.assertRaises(probe.IntegrityError):
            probe.launch_precheck()
        self.assertEqual(session.identity_requests, 1)
        self.assertFalse(paths["LAUNCH_PRECHECK"].exists())
        self.assertFalse(paths["PLAN"].exists())
        self.assertFalse(paths["CAPTURE"].exists())
        self.assertEqual(network.calls, [])

    def test_fake_execute_expiring_credential_blocks_signed_dispatch(self):
        session, network, credentials, paths = self.fake_launch()
        probe.launch_precheck()
        frozen = probe.freeze(probe.digest(probe.build_plan()))
        credentials.return_value = (session, ("SYNTHETIC_SECRET_NOT_IN_RESPONSE",),
                                    datetime.now(timezone.utc) + timedelta(seconds=1))
        probe.execute(frozen["plan_sha256"])
        capture = probe.safe.strict_json(paths["CAPTURE"].read_text())
        self.assertEqual(network.calls, [])
        self.assertEqual(capture["calls"][0]["dispatch_attempted"], False)
        self.assertEqual(capture["call_slots"][0]["status"], "failed_before_dispatch")
        self.assertEqual(capture["summary"]["returned_questions"], 0)

    def test_fake_execute_deadline_after_request_write_blocks_dispatch(self):
        _, network, _, paths = self.fake_launch()
        probe.launch_precheck()
        frozen = probe.freeze(probe.digest(probe.build_plan()))
        now = [0]
        original_save = probe.save
        original_run_jobs = probe.run_jobs

        def advance_after_request(path, value, **kwargs):
            result = original_save(path, value, **kwargs)
            if path == paths["CAPTURE"] and value.get("calls") and value["calls"][-1]["dispatch_attempted"] is None:
                now[0] = 241
            return result

        def run_with_clock(*args, **kwargs):
            return original_run_jobs(*args, **kwargs, clock=lambda: now[0])

        with patch.object(probe, "save", side_effect=advance_after_request), \
                patch.object(probe, "run_jobs", side_effect=run_with_clock):
            probe.execute(frozen["plan_sha256"])
        capture = probe.safe.strict_json(paths["CAPTURE"].read_text())
        self.assertEqual(network.calls, [])
        self.assertEqual(capture["calls"][0]["dispatch_attempted"], False)
        self.assertEqual(capture["call_slots"][0]["status"], "deadline_blocked")
        self.assertEqual(capture["summary"]["returned_questions"], 0)

    def test_one_original_job_five_question_slots_six_call_slots(self):
        self.assertEqual([job["id"] for job in self.capture["original_jobs"]], ["mixed"])
        self.assertEqual(len(self.capture["original_jobs"][0]["slots"]), 5)
        self.assertEqual(len(self.capture["call_slots"]), 6)
        self.assertTrue(all(slot["status"] == "unattempted"
                            for slot in self.capture["original_jobs"][0]["slots"] + self.capture["call_slots"]))
        self.assertEqual(self.capture["identity_check"]["status"], "unattempted")

    def test_provisional_assignment_and_observed_request_are_mixed_only(self):
        self.assertEqual(len(self.plan["jobs"]), 1)
        request = self.plan["jobs"][0]["request"]
        self.assertEqual(request["targetCount"], 5)
        self.assertEqual(sorted(request["requestedSkillAllocation"].values()), [2, 3])
        self.assertEqual(len(self.plan["initial_author_prompts"]), 1)
        self.assertTrue(self.plan["initial_author_contract_name"].startswith(
            "question_author_constructed_mapped_compact_v1_n5_"))
        self.assertEqual(self.plan["environment"]["QUESTION_AUTHOR_CARDINALITY_CONTRACT"], "array")
        self.assertEqual(self.plan["environment"]["QUESTION_MAPPED_FIXED_FIVE_GOAL_SHA256"],
                         probe.PROVISIONAL_GOAL_SHA256)
        self.assertEqual(self.plan["environment"]["QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256"],
                         probe.PROVISIONAL_SCOPE_SHA256)
        self.assertEqual(self.plan["endpoint"], probe.ENDPOINT)

    def test_fake_full_worker_retains_all_five_and_exact_provenance(self):
        network = self.run_fake()
        self.assertEqual(len(network.calls), 3)
        summary = self.capture["summary"]
        self.assertEqual((summary["planned_jobs"], summary["planned_questions"],
                          summary["returned_questions"], summary["reserved_calls"]), (1, 5, 5, 3))
        self.assertFalse(summary["qualified"])
        self.assertEqual([slot["status"] for slot in self.capture["original_jobs"][0]["slots"]],
                         ["returned"] * 5)
        row = self.capture["jobs"][0]
        self.assertEqual(len(row["returned"]), 5)
        self.assertEqual(sorted(row["returned_slot_ordinals"]), list(range(5)))
        self.assertEqual(len(row["returned_sources"]), 5)
        self.assertEqual(len(row["returned_provenance"]), 5)
        compiled = [(question, source) for question, source in zip(
            row["returned"], row["returned_provenance"], strict=True) if source is not None]
        prose = [(question, source) for question, source in zip(
            row["returned"], row["returned_provenance"], strict=True) if source is None]
        self.assertEqual((len(compiled), len(prose)), (3, 2))
        for question, source in compiled:
            self.assertEqual(question["verificationPolicyRevision"], 8)
            self.assertEqual(probe.learner(question), source["learner"])
        for question, _ in prose:
            self.assertEqual(question["verificationPolicyRevision"], 7)
            self.assertEqual(question["choiceExplanations"], {})
            self.assertEqual(question["explanation"], "Synthetic authored explanation for a fake transport fixture.")
        self.assertEqual([call["stage"] for call in self.capture["calls"]][0],
                         self.plan["initial_author_contract_name"])
        self.assertTrue(any(call["stage"].startswith("complete_choice_solver") for call in self.capture["calls"]))
        self.assertTrue(any(call["stage"].startswith("authored_solution") for call in self.capture["calls"]))

    def test_scoped_mapped_object_transport_keeps_five_original_slots(self):
        network = self.run_fake()
        self.assertEqual(len(network.calls), 3)
        author = self.capture["calls"][0]
        self.assertEqual(author["stage"], self.plan["initial_author_contract_name"])
        schema = json.loads(author["request"]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
        self.assertEqual(schema["properties"]["questions"]["type"], "object")
        self.assertEqual(set(schema["properties"]["questions"]["properties"]), set("01234"))
        raw_author = json.loads(author["response"]["output"]["message"]["content"][0]["text"])
        self.assertEqual(set(raw_author["questions"]), set("01234"))
        self.assertEqual(author["raw_author_object"], raw_author)
        self.assertEqual(author["raw_author_object_status"], "captured_before_adapter")
        self.assertEqual(author["native_schema_sha256"], self.plan["candidate_pins"]["native_schema_sha256"])
        self.assertEqual([binding["kind"] for binding in author["trusted_original_slot_bindings"]],
                         ["quantitative"] * 3 + ["prose"] * 2)
        self.assertEqual(len(self.capture["jobs"][0]["passes"][0]["author_payload"]["questions"]), 5)
        self.assertEqual(self.capture["jobs"][0]["passes"][0]["original_slot_assignments"],
                         self.plan["mapped_assignment"])
        self.assertEqual(self.capture["summary"]["returned_questions"], 5)
        self.assertEqual(len(self.capture["call_slots"]), 6)

    def test_compiler_rejection_leaves_one_original_slot_unfilled_without_top_up(self):
        def reject_one_mapped_row(index, request, payload, response):
            name = request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"]
            if index == 0 and name == self.plan["initial_author_contract_name"]:
                task = payload["questions"]["0"]
                task["nodes"][1]["value"] = "0"
                task["nodes"][2]["op"] = "div"
                response["output"]["message"]["content"][0]["text"] = json.dumps(payload)
            return response

        network = self.run_fake(FakeNetwork(reject_one_mapped_row))
        author_calls = [call for call in self.capture["calls"]
                        if call["stage"].startswith("question_author_constructed_mapped_compact_")]
        self.assertEqual([call["stage"] for call in author_calls],
                         [self.plan["initial_author_contract_name"]])
        self.assertEqual([data(call["request"])["targetCount"] for call in author_calls], [5])
        self.assertEqual(self.capture["summary"]["returned_questions"], 4)
        self.assertEqual([slot["status"] for slot in self.capture["original_jobs"][0]["slots"]],
                         ["unfilled"] + ["returned"] * 4)
        self.assertEqual(sorted(self.capture["jobs"][0]["returned_slot_ordinals"]), [1, 2, 3, 4])
        self.assertLessEqual(len(network.calls), 6)
        self.assertEqual(self.capture["summary"]["planned_questions"], 5)
        self.assertEqual(len(self.capture["call_slots"]), 6)

    def test_model_written_english_assignment_rejects_batch_before_verification(self):
        def add_tag(index, request, payload, response):
            if request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"].startswith(
                    "question_author_constructed_mapped_compact_"):
                payload["questions"]["3"]["objectiveID"] = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
                response["output"]["message"]["content"][0]["text"] = json.dumps(payload)
            return response

        network = self.run_fake(FakeNetwork(add_tag))
        self.assertEqual(len(network.calls), 1)
        self.assertTrue(all(call["stage"].startswith("question_author_constructed_mapped_compact_")
                            for call in self.capture["calls"]))
        self.assertEqual(self.capture["jobs"][0]["passes"], [])
        self.assertEqual(self.capture["summary"]["returned_questions"], 0)
        self.assertEqual([slot["status"] for slot in self.capture["original_jobs"][0]["slots"]],
                         ["unfilled"] * 5)

    def test_wrong_arithmetic_tag_rejects_batch_before_solver_or_reviewer(self):
        def wrong_tag(index, request, payload, response):
            if request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"].startswith(
                    "question_author_constructed_mapped_compact_"):
                payload["questions"]["0"]["skillID"] = "22222222-2222-4222-8222-222222222222"
                response["output"]["message"]["content"][0]["text"] = json.dumps(payload)
            return response

        network = self.run_fake(FakeNetwork(wrong_tag))
        self.assertEqual(len(network.calls), 1)
        self.assertTrue(all(call["stage"].startswith("question_author_constructed_mapped_compact_")
                            for call in self.capture["calls"]))
        self.assertEqual(self.capture["jobs"][0]["passes"], [])
        self.assertEqual(self.capture["summary"]["returned_questions"], 0)

    def test_dispatch_attempt_and_request_are_durable_before_provider_entry(self):
        def inspect(index, request, payload, response):
            persisted = json.loads(self.path.read_text())
            call = persisted["calls"][index]
            slot = persisted["call_slots"][index]
            self.assertEqual(call["dispatch_attempted"], True)
            self.assertEqual(slot["status"], "dispatch_attempted")
            self.assertEqual(call["request"], request)
            self.assertEqual(persisted["reservations"][index], {"job": "mixed", "ordinal": index})
            return response

        self.run_fake(FakeNetwork(inspect))

    def test_capture_fsyncs_file_and_directory(self):
        events = []
        original_fsync, original_replace = os.fsync, os.replace

        def fsync(descriptor):
            events.append("directory" if stat.S_ISDIR(os.fstat(descriptor).st_mode) else "file")
            return original_fsync(descriptor)

        def replace(source, destination):
            events.append("replace")
            return original_replace(source, destination)

        with patch.object(probe.os, "fsync", side_effect=fsync), \
                patch.object(probe.os, "replace", side_effect=replace):
            probe.save(self.path, {"first": True}, exclusive=True)
            probe.save(self.path, {"second": True})
        self.assertEqual(events, ["file", "directory", "file", "replace", "directory"])

    def test_first_author_prompt_drift_stops_before_dispatch(self):
        original = probe.runtime._user_prompt
        network = FakeNetwork()
        with patch.object(probe.runtime, "_user_prompt", side_effect=lambda request: original(request) + " drift"):
            self.run_fake(network, pin_check=lambda: None)
        self.assertEqual(network.calls, [])
        self.assertEqual(self.capture["summary"]["attempted_calls"], 0)
        self.assertTrue(self.capture["global_stop"])

    def test_wrong_endpoint_stops_before_dispatch(self):
        network = FakeNetwork(factory_modify=lambda client: setattr(client.meta, "endpoint_url", "https://wrong.invalid"))
        self.run_fake(network)
        self.assertEqual(network.calls, [])
        self.assertEqual(self.capture["summary"]["attempted_calls"], 0)
        self.assertTrue(self.capture["global_stop"])

    def test_credential_expiry_after_request_write_blocks_signed_dispatch(self):
        network = FakeNetwork()
        self.run_fake(network, credential_expires_at=datetime.now(timezone.utc) + timedelta(seconds=1))
        self.assertEqual(network.calls, [])
        self.assertEqual(self.capture["calls"][0]["dispatch_attempted"], False)
        self.assertEqual(self.capture["call_slots"][0]["status"], "failed_before_dispatch")
        self.assertTrue(self.capture["global_stop"])

    def test_profile_override_stops_before_credential_export(self):
        with patch.dict(os.environ, {"AWS_PROFILE": "wrong-profile", "AWS_ENDPOINT_URL": ""}), \
                patch.object(probe.safe, "credential_session") as credentials:
            with self.assertRaises(probe.IntegrityError):
                probe.default_profile_session()
            credentials.assert_not_called()

    def test_exported_snapshot_has_one_job_margin(self):
        self.assertGreater((probe.validate_credential_lifetime(fake_export(301))
                            - datetime.now(timezone.utc)).total_seconds(), 300)
        with self.assertRaises(probe.IntegrityError):
            probe.validate_credential_lifetime(fake_export(299))
        with self.assertRaises(probe.IntegrityError):
            probe.validate_credential_lifetime(b'{"Version":1,"AccessKeyId":"fake"}')

    def test_child_cli_environment_strips_endpoint_and_credential_overrides(self):
        child = probe.controlled_cli_environment({
            "AWS_PROFILE": "wrong", "AWS_ENDPOINT_URL_STS": "https://wrong.invalid",
            "AWS_ACCESS_KEY_ID": "synthetic", "AWS_ROLE_ARN": "synthetic-role",
            "AWS_LOGIN_CACHE_DIRECTORY": "/tmp/synthetic-login-cache"})
        self.assertEqual(child["AWS_PROFILE"], "default")
        self.assertEqual(child["AWS_DEFAULT_PROFILE"], "default")
        self.assertEqual(child["AWS_IGNORE_CONFIGURED_ENDPOINT_URLS"], "true")
        self.assertEqual(child["AWS_LOGIN_CACHE_DIRECTORY"], "/tmp/synthetic-login-cache")
        self.assertNotIn("AWS_ENDPOINT_URL_STS", child)
        self.assertNotIn("AWS_ACCESS_KEY_ID", child)
        self.assertNotIn("AWS_ROLE_ARN", child)

    def test_sts_endpoint_is_checked_before_signed_identity_request(self):
        session = FakeIdentitySession(endpoint="https://wrong.invalid")
        with self.assertRaises(probe.IntegrityError):
            probe.checked_sts_client(session)
        self.assertEqual(session.identity_requests, 0)

    def test_retrying_sdk_config_is_rejected_before_dispatch(self):
        def alter(client):
            client.meta.config.retries["total_max_attempts"] = 2

        network = FakeNetwork(factory_modify=alter)
        self.run_fake(network)
        self.assertEqual(network.calls, [])
        self.assertEqual(self.capture["summary"]["attempted_calls"], 0)
        self.assertTrue(self.capture["global_stop"])

    def test_deadline_after_request_write_blocks_dispatch(self):
        now = [0]
        original_save = probe.save

        def advance_after_request(path, value, **kwargs):
            result = original_save(path, value, **kwargs)
            if value.get("calls") and value["calls"][-1]["dispatch_attempted"] is None:
                now[0] = 241
            return result

        network = FakeNetwork()
        with patch.object(probe, "save", side_effect=advance_after_request):
            self.run_fake(network, clock=lambda: now[0])
        self.assertEqual(network.calls, [])
        self.assertEqual(self.capture["calls"][0]["dispatch_attempted"], False)
        self.assertEqual(self.capture["call_slots"][0]["status"], "deadline_blocked")
        self.assertEqual(self.capture["summary"]["returned_questions"], 0)

    def test_provider_error_retains_type_and_code_without_request_id(self):
        def fail(index, request, payload, response):
            if index == 0:
                raise ClientError({"Error": {"Code": "ThrottlingException", "Message": "PRIVATE_ERROR_MESSAGE"},
                                   "ResponseMetadata": {"RequestId": "PRIVATE_REQUEST_ID"}}, "Converse")
            return response

        self.run_fake(FakeNetwork(fail))
        persisted = self.path.read_text()
        self.assertNotIn("PRIVATE_", persisted)
        self.assertEqual(json.loads(persisted)["calls"][0]["error"],
                         {"type": "ClientError", "code": "ThrottlingException"})
        self.assertEqual(self.capture["summary"]["planned_questions"], 5)

    def test_credential_echo_never_persists(self):
        secret = "SYNTHETIC_SECRET_DO_NOT_SAVE"

        def echo(index, request, payload, response):
            response["output"]["message"]["content"][0]["text"] = json.dumps({"echo": secret})
            return response

        self.run_fake(FakeNetwork(echo), secrets=(secret,))
        self.assertNotIn(secret, self.path.read_text())
        self.assertTrue(self.capture["global_stop"])

    def test_external_capture_tamper_stops_without_overwrite(self):
        def tamper(index, request, payload, response):
            self.path.write_text("EXTERNAL_TAMPER")
            return response

        network = FakeNetwork(tamper)
        with self.assertRaises(probe.IntegrityError):
            self.run_fake(network)
        self.assertEqual(len(network.calls), 1)
        self.assertEqual(self.path.read_text(), "EXTERNAL_TAMPER")

    def test_no_resume_or_second_run(self):
        self.run_fake()
        with self.assertRaises(probe.IntegrityError):
            self.run_fake()

    def test_current_main_source_drift_is_detected(self):
        original = probe.file_hash
        target = probe.SERVICE / "question_generation.py"
        with patch.object(probe, "file_hash", side_effect=lambda path: "bad" if path == target else original(path)):
            with self.assertRaises(probe.IntegrityError):
                probe.check_plan(self.plan)

    def test_reviewed_first_prompt_drift_is_rejected(self):
        original = probe.native.native_prompt
        with patch.object(probe.native, "native_prompt",
                          side_effect=lambda system, contract: original(system, contract) + " changed"):
            with self.assertRaises(probe.IntegrityError):
                probe.check_plan(self.plan)

    def test_reviewed_native_schema_drift_is_rejected(self):
        original = probe.native.native_output_config

        def changed(contract):
            config = original(contract)
            if isinstance(contract, probe.native.AuthorSlotContract) and contract.mapped_assignments is not None:
                config["textFormat"]["structure"]["jsonSchema"]["schema"] += " "
            return config

        with patch.object(probe.native, "native_output_config", side_effect=changed):
            with self.assertRaises(probe.IntegrityError):
                probe.check_plan(self.plan)


if __name__ == "__main__":
    unittest.main()
