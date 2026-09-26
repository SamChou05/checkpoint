"""Exercise the selected real runtime using fake provider responses only."""

import copy
from datetime import datetime, timedelta, timezone
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
SPEC = importlib.util.spec_from_file_location("current_source_worker_probe_tested", HERE / "mixed_probe.py")
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
        if name == probe.CONSTRUCTED_AUTHOR_CONTRACT:
            rows = []
            self.authors += 1
            skills = given.get("skillMap", {}).get("skills", []) if given.get("skillMap") else []
            allocations = given.get("requestedSkillAllocation", {})
            assignments = [skill for skill in skills for _ in range(allocations.get(skill["id"], 0))]
            for number in range(given["targetCount"]):
                value = 10 * self.authors + number
                skill = assignments[number] if assignments else None
                prose = "Python" in given["goal"]["title"] or (skill and "English" in skill["name"])
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
                                "format": "Multiple Choice", **metadata}
                    rows.append({"kind": "prose", "question": question})
                    self.known[prompt] = choices[1]
                else:
                    task = {"kind": "exact_value", "unit": "unitless",
                            "nodes": [{"kind": "literal", "value": str(value)}, {"kind": "literal", "value": "3"},
                                      {"kind": "binary", "op": "add", "left": 0, "right": 1}], "root": 2}
                    rows.append({"kind": "quantitative", "task": task, **metadata})
                    content = _constructed_candidate(task).content()
                    self.known[content["prompt"]] = content["expectedAnswer"]
            payload = {"questions": rows}
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
    def __init__(self, account=probe.EXPECTED_ACCOUNT_ID, endpoint=probe.STS_ENDPOINT):
        self.account, self.endpoint = account, endpoint
        self.client_calls, self.identity_requests = [], 0

    def client(self, service, **kwargs):
        self.client_calls.append((service, kwargs))
        if service != "sts":
            return SimpleNamespace(meta=SimpleNamespace(endpoint_url=probe.ENDPOINT))

        def identity():
            self.identity_requests += 1
            return {"Account": self.account, "Arn": "unretained-test-arn", "UserId": "unretained-test-id"}

        return SimpleNamespace(meta=SimpleNamespace(
            endpoint_url=self.endpoint, region_name=kwargs["region_name"], config=kwargs["config"]),
            get_caller_identity=identity)


class MixedProbeTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(socket.socket, "connect", side_effect=AssertionError("No network in offline preflight")))
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "capture.json"
        self.plan = probe.build_plan()
        self.capture = probe.new_capture(self.plan)

    def run_fake(self, network=None, **kwargs):
        network = network or FakeNetwork()
        probe.run_jobs(self.plan, self.capture, self.path, network.client, kwargs.pop("pin_check", lambda: None), **kwargs)
        return network

    def test_initial_capture_materializes_all_original_slots(self):
        self.assertEqual(len(self.capture["original_jobs"]), 3)
        self.assertEqual([len(job["slots"]) for job in self.capture["original_jobs"]], [5, 5, 5])
        self.assertTrue(all(slot["status"] == "unattempted" for job in self.capture["original_jobs"]
                            for slot in job["slots"]))
        self.assertEqual(len(self.capture["call_slots"]), 18)
        self.assertTrue(all(slot["status"] == "unattempted" for slot in self.capture["call_slots"]))
        self.assertEqual(self.capture["identity_check"]["status"], "unattempted")

    def test_capture_writes_fsync_file_and_directory_before_and_after_replace(self):
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
        self.assertEqual(json.loads(self.path.read_text()), {"second": True})

    def test_default_profile_export_is_explicit_and_wrong_profile_stops_before_credentials(self):
        def inspect_command():
            probe.safe.export_credentials()
            return probe.safe.CREDENTIAL_COMMAND, ()

        with patch.dict(os.environ, {"AWS_PROFILE": "default", "AWS_DEFAULT_PROFILE": "",
                                          "AWS_ENDPOINT_URL": "", "AWS_ENDPOINT_URL_STS": ""}), \
                patch.object(probe, "check_aws_cli"), \
                patch.object(probe.safe, "export_credentials", return_value=fake_export()), \
                patch.object(probe.safe, "credential_session", side_effect=inspect_command):
            command, _, expires_at = probe.default_profile_session()
        self.assertEqual(command, (str(probe.AWS_CLI_PATH), "configure", "export-credentials", "--profile", "default",
                                   "--format", "process"))
        self.assertGreater((expires_at - datetime.now(timezone.utc)).total_seconds(), 780)

        with patch.dict(os.environ, {"AWS_PROFILE": "different", "AWS_ENDPOINT_URL": "",
                                          "AWS_ENDPOINT_URL_STS": ""}), \
                patch.object(probe.safe, "credential_session") as export:
            with self.assertRaises(probe.IntegrityError):
                probe.default_profile_session()
            export.assert_not_called()

    def test_aws_cli_version_is_pinned_without_credential_or_network_activity(self):
        with patch.object(probe.subprocess, "run", return_value=SimpleNamespace(
                returncode=0, stdout=b"aws-cli/2.33.15 Python/3.13.12 Darwin/25.6.0", stderr=b"")) as run:
            probe.check_aws_cli()
        command = run.call_args.args[0]
        environment = run.call_args.kwargs["env"]
        self.assertEqual(command, (str(probe.AWS_CLI_PATH), "--version"))
        self.assertEqual(environment["AWS_IGNORE_CONFIGURED_ENDPOINT_URLS"], "true")
        self.assertFalse(any(key.upper().startswith("AWS_ENDPOINT_URL") for key in environment))
        with patch.object(probe.subprocess, "run", return_value=SimpleNamespace(
                returncode=0, stdout=b"aws-cli/2.33.16", stderr=b"")):
            with self.assertRaises(probe.IntegrityError):
                probe.check_aws_cli()

    def test_export_child_ignores_environment_and_profile_service_endpoint_overrides(self):
        config = Path(self.directory.name) / "config"
        config.write_text("[default]\nlogin_session = test-session\nservices = redirected\n"
                          "[services redirected]\nsignin =\n  endpoint_url = https://signin.invalid\n")
        marker = object()

        def inspect_export():
            process = probe.safe.subprocess.Popen(
                probe.safe.CREDENTIAL_COMMAND, stdout=probe.safe.subprocess.PIPE,
                stderr=probe.safe.subprocess.DEVNULL)
            probe.safe.export_credentials()
            return process, ()

        with patch.dict(os.environ, {"AWS_PROFILE": "default", "AWS_DEFAULT_PROFILE": "",
                                  "AWS_CONFIG_FILE": str(config), "HOME": self.directory.name,
                                  "AWS_ENDPOINT_URL": "", "AWS_ENDPOINT_URL_STS": "",
                                  "AWS_ENDPOINT_URL_SIGNIN": "https://env-signin.invalid",
                                  "AWS_ENDPOINT_URL_S3": "https://env-s3.invalid",
                                  "AWS_IGNORE_CONFIGURED_ENDPOINT_URLS": "false"}), \
                patch.object(probe, "check_aws_cli"), \
                patch.object(probe.subprocess, "Popen", return_value=marker) as popen, \
                patch.object(probe.safe, "export_credentials", return_value=fake_export()), \
                patch.object(probe.safe, "credential_session", side_effect=inspect_export):
            process, _, _ = probe.default_profile_session()
        self.assertIs(process, marker)
        self.assertEqual(popen.call_args.args[0], (
            str(probe.AWS_CLI_PATH), "configure", "export-credentials", "--profile", "default",
            "--format", "process"))
        child = popen.call_args.kwargs["env"]
        self.assertEqual(child["AWS_IGNORE_CONFIGURED_ENDPOINT_URLS"], "true")
        self.assertEqual(child["AWS_PROFILE"], "default")
        self.assertEqual(child["AWS_DEFAULT_PROFILE"], "default")
        self.assertEqual(child["AWS_CONFIG_FILE"], str(config))
        self.assertEqual(child["HOME"], self.directory.name)
        self.assertFalse(any(key.upper().startswith("AWS_ENDPOINT_URL") for key in child))
        self.assertIn("endpoint_url = https://signin.invalid", config.read_text())

    def test_short_or_unbounded_credential_snapshot_stops_before_session_use(self):
        with self.assertRaises(probe.IntegrityError):
            probe.validate_credential_lifetime(fake_export(700))
        with self.assertRaises(probe.IntegrityError):
            probe.validate_credential_lifetime(b'{"Version":1,"AccessKeyId":"SYNTHETIC"}')
        with patch.dict(os.environ, {"AWS_PROFILE": "default", "AWS_ENDPOINT_URL": "",
                                  "AWS_ENDPOINT_URL_STS": ""}), \
                patch.object(probe, "check_aws_cli"), \
                patch.object(probe.safe, "export_credentials", return_value=fake_export(700)), \
                patch.object(probe.safe.boto3, "Session") as session:
            with self.assertRaises(probe.IntegrityError):
                probe.default_profile_session()
            session.assert_not_called()

    def test_sts_endpoint_override_and_wrong_resolved_endpoint_stop_before_signed_request(self):
        session = FakeIdentitySession()
        with patch.dict(os.environ, {"AWS_PROFILE": "default", "AWS_ENDPOINT_URL": "",
                                          "AWS_ENDPOINT_URL_STS": "https://example.invalid"}):
            with self.assertRaises(probe.IntegrityError):
                probe.verify_account_identity(session, self.capture, self.path)
        self.assertEqual(session.client_calls, [])
        self.assertEqual(session.identity_requests, 0)

        session = FakeIdentitySession(endpoint="https://example.invalid")
        with patch.dict(os.environ, {"AWS_PROFILE": "default", "AWS_ENDPOINT_URL": "",
                                          "AWS_ENDPOINT_URL_STS": ""}):
            with self.assertRaises(probe.IntegrityError):
                probe.verify_account_identity(session, self.capture, self.path)
        self.assertEqual(session.identity_requests, 0)

    def test_wrong_account_stops_before_bedrock_and_only_error_type_code_persist(self):
        plan_path = Path(self.directory.name) / "plan.json"
        probe.save(plan_path, {**self.plan, "state": "frozen"}, exclusive=True)
        session = FakeIdentitySession(account="000000000000")
        with patch.dict(os.environ, {"AWS_PROFILE": "default", "AWS_ENDPOINT_URL": "",
                                          "AWS_ENDPOINT_URL_STS": ""}), \
                patch.object(probe, "PLAN", plan_path), patch.object(probe, "CAPTURE", self.path), \
                patch.object(probe, "default_profile_session", return_value=(
                    session, ("SYNTHETIC_SECRET",), datetime.now(timezone.utc) + timedelta(seconds=900))), \
                patch.object(probe, "run_jobs") as run:
            result = probe.execute(probe.file_hash(plan_path))
        run.assert_not_called()
        self.assertEqual(session.identity_requests, 1)
        self.assertEqual([service for service, _ in session.client_calls], ["sts"])
        self.assertEqual(result["summary"]["planned_questions"], 15)
        self.assertEqual(result["summary"]["unattempted_jobs"], 3)
        self.assertEqual(result["summary"]["unattempted_call_slots"], 18)
        persisted = json.loads(self.path.read_text())
        self.assertEqual(set(persisted["error"]), {"type", "code"})
        self.assertNotIn("unretained-test-arn", self.path.read_text())
        self.assertNotIn("unretained-test-id", self.path.read_text())

    def test_verified_sts_and_bedrock_share_one_frozen_session(self):
        plan_path = Path(self.directory.name) / "plan.json"
        probe.save(plan_path, {**self.plan, "state": "frozen"}, exclusive=True)
        session = FakeIdentitySession()
        observed = []

        def no_dispatch(plan, capture, path, client_factory, pin_check, **kwargs):
            observed.append(client_factory.__self__ is session)
            client_factory("bedrock-runtime", region_name="us-east-1", config=probe.Config())
            probe.finish(capture)
            probe.save(path, capture)

        with patch.dict(os.environ, {"AWS_PROFILE": "default", "AWS_ENDPOINT_URL": "",
                                          "AWS_ENDPOINT_URL_STS": ""}), \
                patch.object(probe, "PLAN", plan_path), patch.object(probe, "CAPTURE", self.path), \
                patch.object(probe, "default_profile_session", return_value=(
                    session, (), datetime.now(timezone.utc) + timedelta(seconds=900))), \
                patch.object(probe, "run_jobs", side_effect=no_dispatch):
            result = probe.execute(probe.file_hash(plan_path))
        self.assertEqual(observed, [True])
        self.assertEqual([service for service, _ in session.client_calls], ["sts", "bedrock-runtime"])
        self.assertEqual(session.identity_requests, 1)
        self.assertEqual(json.loads(self.path.read_text())["identity_check"]["status"], "verified")
        self.assertEqual(result["summary"]["attempted_calls"], 0)

    def test_final_deadline_guard_blocks_dispatch_after_durable_request_write(self):
        now = [0.0]
        network = FakeNetwork()
        original_save = probe.save
        advanced = False

        def slow_persistence(path, value, *, exclusive=False):
            nonlocal advanced
            original_save(path, value, exclusive=exclusive)
            if (not advanced and value is self.capture and value["calls"]
                    and value["calls"][-1]["dispatch_attempted"] is None):
                now[0] = 230.0
                advanced = True

        with patch.object(probe, "save", side_effect=slow_persistence):
            probe.run_job(self.plan["jobs"][0], self.capture, self.path,
                          network.client, lambda: None, clock=lambda: now[0])
        self.assertTrue(advanced)
        self.assertEqual(network.calls, [])
        self.assertEqual(len(self.capture["reservations"]), 1)
        self.assertEqual(self.capture["calls"][0]["dispatch_attempted"], False)
        self.assertEqual(self.capture["call_slots"][0]["status"], "deadline_blocked")
        self.assertEqual(json.loads(self.path.read_text())["call_slots"][0]["status"], "deadline_blocked")

    def test_credential_expiry_after_request_write_blocks_signed_dispatch(self):
        start = datetime(2026, 9, 26, tzinfo=timezone.utc)
        wall = [start]
        expires_at = start + timedelta(seconds=900)
        network = FakeNetwork()
        original_save = probe.save
        advanced = False

        def slow_persistence(path, value, *, exclusive=False):
            nonlocal advanced
            original_save(path, value, exclusive=exclusive)
            if (not advanced and value is self.capture and value["calls"]
                    and value["calls"][-1]["dispatch_attempted"] is None):
                wall[0] = start + timedelta(seconds=800)
                advanced = True

        with patch.object(probe, "save", side_effect=slow_persistence):
            probe.run_job(self.plan["jobs"][0], self.capture, self.path,
                          network.client, lambda: None, clock=lambda: 0.0,
                          credential_expires_at=expires_at, credential_clock=lambda: wall[0])
        self.assertTrue(advanced)
        self.assertEqual(network.calls, [])
        self.assertEqual(self.capture["calls"][0]["dispatch_attempted"], False)
        self.assertEqual(self.capture["calls"][0]["credential_remaining_before_ms"], 100_000)
        self.assertEqual(self.capture["call_slots"][0]["status"], "failed_before_dispatch")
        self.assertTrue(self.capture["global_stop"])

    def test_provider_error_and_response_metadata_never_persist_messages_or_request_ids(self):
        def fail(index, request, payload, response):
            if index == 0:
                raise ClientError({"Error": {"Code": "ThrottlingException", "Message": "PRIVATE_MESSAGE"},
                                   "ResponseMetadata": {"RequestId": "PRIVATE_REQUEST_ID"}}, "Converse")
            response["ResponseMetadata"] = {"RequestId": "PRIVATE_SUCCESS_ID", "HTTPStatusCode": 200}
            return response

        self.run_fake(FakeNetwork(fail))
        persisted_text = self.path.read_text()
        self.assertNotIn("PRIVATE_", persisted_text)
        persisted = json.loads(persisted_text)
        self.assertEqual(persisted["calls"][0]["error"],
                         {"type": "ClientError", "code": "ThrottlingException"})
        self.assertTrue(all(set(call["error"]) == {"type", "code"}
                            for call in persisted["calls"] if "error" in call))
        self.assertTrue(all("safeResponseMetadata" not in call.get("response", {})
                            for call in persisted["calls"]))

    def test_three_real_mixed_jobs_use_eight_calls_and_preserve_compiler_fields(self):
        network = self.run_fake()
        self.assertEqual(len(network.calls), 8)
        self.assertEqual(self.capture["summary"]["returned_questions"], 15)
        self.assertFalse(self.capture["summary"]["qualified"])
        self.assertEqual([len(row["returned"]) for row in self.capture["jobs"]], [5, 5, 5])
        for row in self.capture["jobs"]:
            for question, source in zip(row["returned"], row["returned_provenance"], strict=True):
                if source:
                    self.assertEqual(probe.learner(question), source["learner"])
                    self.assertNotIn("Synthetic reviewer", question["explanation"])
                else:
                    self.assertEqual(question["verificationPolicyRevision"], 7)
                    self.assertEqual(question["choiceExplanations"], {})
                    self.assertEqual(question["explanation"], "Synthetic authored explanation for a fake transport fixture.")
            self.assertEqual(len(row["returned_sources"]), len(row["returned"]))
        for call in network.calls:
            self.assertEqual(call["modelId"], "us.anthropic.claude-sonnet-4-6")
            self.assertEqual(call["inferenceConfig"], {"maxTokens": 16000})
            self.assertEqual(call["additionalModelRequestFields"], {
                "thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}})
        self.assertFalse(any(call["stage"].startswith("complete_choice_solver") for call in self.capture["calls"] if call["job"] == "quantitative"))
        mixed_solver = next(call for call in self.capture["calls"] if call["job"] == "mixed" and call["stage"].startswith("complete_choice_solver"))
        self.assertEqual(len(data(mixed_solver["request"])["items"]), 2)
        self.assertEqual(self.plan["environment"]["QUESTION_AUTHOR_MODE"], "constructed_quantitative")
        self.assertEqual(len(probe.IMPORTED_SERVICE_HASHES), 29)
        self.assertIn("quantitative_choice_construction.py", probe.IMPORTED_SERVICE_HASHES)
        for job in self.capture["jobs"]:
            for record in job["passes"]:
                for row in record["author_payload"]["questions"]:
                    if row["kind"] == "quantitative":
                        self.assertNotIn("choices", row["task"])
                        self.assertNotIn("expectedAnswer", row)
                        self.assertNotIn("correctChoice", row["task"])

    def test_current_boolean_guard_rejects_incomplete_main_and_retains_complete_rule(self):
        network = FakeNetwork()
        changed = False

        def modify(index, request, payload, response):
            nonlocal changed
            if (not changed and request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"]
                    == probe.CONSTRUCTED_AUTHOR_CONTRACT and "Python" in data(request)["goal"]["title"]):
                changed = True
                for position, label in enumerate(("yes", "ok")):
                    question = payload["questions"][position]["question"]
                    network.known.pop(question["prompt"])
                    question["prompt"] = f'What does 0 or "{label}" evaluate to in Python 3?'
                    question["choices"] = {"a": "0", "b": f'"{label}"', "c": "True", "d": "None"}
                    question["correctChoice"] = "b"
                    question["explanation"] = (
                        '`or` returns the first truthy operand. The result is "yes".' if position == 0
                        else '`or` returns the first truthy operand, or the final operand if none is truthy. The result is "ok".'
                    )
                    network.known[question["prompt"]] = question["choices"]["b"]
                response["output"]["message"]["content"][0]["text"] = json.dumps(payload)
            return response

        network.modify = modify
        self.run_fake(network)
        self.assertTrue(changed)
        python_job = next(job for job in self.capture["jobs"] if job["id"] == "python")
        first_pass = python_job["passes"][0]
        self.assertEqual(len(first_pass["author_payload"]["questions"]), 5)
        sanitized_prompts = [entry["question"]["prompt"] for entry in first_pass["sanitized"]]
        self.assertFalse(any('"yes"' in prompt for prompt in sanitized_prompts))
        self.assertTrue(any('"ok"' in prompt for prompt in sanitized_prompts))
        self.assertEqual(len(python_job["returned"]), 5)
        self.assertEqual(python_job["provider_calls"], 6)

    def test_current_source_jobs_environment_and_evidence_are_exactly_pinned(self):
        spec = probe.safe.strict_json(probe.DRAFT_SPEC.read_text())
        self.assertEqual(probe.file_hash(probe.DRAFT_SPEC), probe.IMPORTED_DRAFT_SHA256)
        self.assertEqual(self.plan["source_revision"]["commit"], probe.SOURCE_COMMIT)
        self.assertEqual(self.plan["source_revision"]["module_count"], 29)
        self.assertEqual(self.plan["jobs"], spec["fixed_jobs"])
        self.assertEqual(self.plan["environment"], spec["trial_environment"])
        self.assertEqual(self.plan["environment"]["QUESTION_AUTHOR_CARDINALITY_CONTRACT"], "array")
        self.assertEqual(self.plan["environment"]["BEDROCK_MODEL_ID"], probe.AUTHOR_MODEL)
        self.assertEqual(self.plan["limits"], spec["limits"])
        self.assertEqual(self.plan["criteria"], spec["criteria"])
        self.assertEqual(self.plan["dependencies"]["python"], "3.12.11")
        self.assertEqual(self.plan["dependencies"]["awscrt"], "0.36.0")
        self.assertEqual(self.plan["source_revision"]["boolean_guard_sha256"],
                         spec["source_hashes"]["backend/bedrock-question-service/python_boolean_teaching.py"])
        for relative, sha in {**spec["source_hashes"],
                              **spec["prior_failed_full_worker_evidence_sha256"],
                              **spec["preflight_artifact_sha256"]}.items():
            self.assertEqual(self.plan["source_hashes"][str(probe.ROOT / relative)], sha)

    def test_exact_current_source_and_prior_evidence_changes_are_rejected(self):
        spec = probe.safe.strict_json(probe.DRAFT_SPEC.read_text())
        original_hash = probe.file_hash
        targets = [probe.DRAFT_SPEC, probe.HERE / "mixed_probe.py",
                   probe.SERVICE / "question_generation.py",
                   probe.SERVICE / "python_boolean_teaching.py",
                   probe.ROOT / next(iter(spec["prior_failed_full_worker_evidence_sha256"]))]
        for target in targets:
            with self.subTest(target=target), patch.object(
                    probe, "file_hash",
                    side_effect=lambda path, target=target: "bad" if path == target else original_hash(path)):
                with self.assertRaises(probe.IntegrityError):
                    probe.check_plan(self.plan)
        original_read = Path.read_bytes
        actual = probe.SERVICE / "question_generation.py"
        for transform in (lambda value: value + b"\n# unauthorized extra change\n",
                          lambda value: value.replace(b"\n", b"\r\n")):
            def changed(path, *args, **kwargs):
                value = original_read(path, *args, **kwargs)
                return transform(value) if path == actual else value
            with patch.object(Path, "read_bytes", changed), self.assertRaises(probe.IntegrityError):
                probe.check_current_source(sorted(probe.SERVICE.glob("*.py")))

    def test_slow_author_over100_then_audit_fits_unchanged_worker_deadline(self):
        now = 0
        def modify(index, request, payload, response):
            nonlocal now
            if index == 0:
                now += 150
            elif index == 1:
                now += 50
            return response
        self.run_fake(FakeNetwork(modify), clock=lambda: now)
        first = self.capture["jobs"][0]
        self.assertEqual(first["provider_calls"], 2)
        self.assertEqual(len(first["returned"]), 5)
        self.assertEqual(first["elapsed_seconds"], 200)
        self.assertTrue(first["within_deadline"])
        calls = [c for c in self.capture["calls"] if c["job"] == "quantitative"]
        self.assertEqual(calls[0]["read_timeout"], 200)
        self.assertEqual(calls[0]["elapsed_seconds"], 150)
        self.assertAlmostEqual(calls[1]["read_timeout"], 83.999)
        self.assertEqual(calls[1]["elapsed_seconds"], 50)
        self.assertEqual(self.capture["summary"]["returned_questions"], 15)
        self.assertEqual(self.capture["summary"]["planned_questions"], 15)
        self.assertFalse(self.capture["summary"]["qualified"])

    def test_author_deadline_overrun_cannot_acquire_audit_or_yield_credit(self):
        now = 0
        def modify(index, request, payload, response):
            nonlocal now
            if index == 0:
                now += 241
            return response
        self.run_fake(FakeNetwork(modify), clock=lambda: now)
        first = self.capture["jobs"][0]
        self.assertEqual(first["provider_calls"], 1)
        self.assertEqual(first["returned"], [])
        self.assertFalse(first["within_deadline"])
        self.assertEqual(first["elapsed_seconds"], 241)
        self.assertEqual(self.capture["summary"]["returned_questions"], 10)
        self.assertEqual(self.capture["summary"]["planned_questions"], 15)
        self.assertFalse(self.capture.get("global_stop"))

    def test_real_plan_guard_rebuilding_keeps_all_three_model_roles_and_eight_calls(self):
        network = self.run_fake(pin_check=lambda: probe.check_plan(self.plan))
        self.assertEqual(len(network.calls), 8)
        self.assertFalse(self.capture.get("global_stop"))
        stages = [call["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"] for call in network.calls]
        self.assertEqual(stages.count(probe.CONSTRUCTED_AUTHOR_CONTRACT), 3)
        self.assertEqual(sum(name.startswith("complete_choice_solver_v5_n") for name in stages), 2)
        self.assertEqual(sum(name.startswith("authored_solution_reviewer_v3_n") for name in stages), 3)
        self.assertEqual(self.capture["summary"]["planned_questions"], 15)
        self.assertEqual(self.capture["summary"]["returned_questions"], 15)
        self.assertFalse(self.capture["summary"]["qualified"])

    def test_partial_return_survives_failed_topup_and_other_jobs_continue(self):
        def modify(index, request, payload, response):
            if index == 1:
                for key in ("3", "4"):
                    payload["reviews"][key].update(valid=False, answer="")
                response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            if index == 2:
                raise TimeoutError("Synthetic failed top-up")
            return response
        self.run_fake(FakeNetwork(modify))
        self.assertEqual([len(row["returned"]) for row in self.capture["jobs"]], [3, 5, 5])
        self.assertFalse(self.capture.get("global_stop"))
        self.assertEqual(self.capture["summary"]["planned_questions"], 15)
        self.assertEqual(self.capture["summary"]["reported_token_usage"]["calls_without_reported_usage"], 1)

    def test_native_configuration_failure_in_topup_stops_globally_despite_partial_return(self):
        def modify(index, request, payload, response):
            if index == 1:
                for key in ("3", "4"):
                    payload["reviews"][key].update(valid=False, answer="")
                response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            if index == 2:
                raise ClientError({"Error": {"Code": "ValidationException", "Message": "Synthetic unsupported schema"}}, "Converse")
            return response
        network = self.run_fake(FakeNetwork(modify))
        self.assertEqual(len(network.calls), 3)
        self.assertEqual(len(self.capture["jobs"]), 1)
        self.assertEqual(len(self.capture["jobs"][0]["returned"]), 3)
        self.assertEqual(self.capture["calls"][2]["error"]["code"], "ValidationException")
        self.assertEqual(self.capture["global_stop"], "native_stage_configuration")
        self.assertEqual(self.capture["status"], "globally_aborted")
        self.assertEqual(self.capture["summary"]["planned_questions"], 15)
        self.assertFalse(self.capture["summary"]["qualified"])

    def test_endpoint_or_request_drift_latches_before_runtime_can_wrap_it(self):
        network = FakeNetwork(factory_modify=lambda client: setattr(client.meta, "endpoint_url", "https://invalid.example.test"))
        self.run_fake(network)
        self.assertEqual(network.calls, [])
        self.assertEqual(len(self.capture["jobs"]), 1)
        self.assertTrue(self.capture["global_stop"])
        self.capture = probe.new_capture(self.plan)
        original = probe.runtime.native_output_config
        with patch.object(probe.runtime, "native_output_config", side_effect=lambda contract: {**original(contract), "unexpected": True}):
            network = self.run_fake()
        self.assertEqual(network.calls, [])
        self.assertEqual(len(self.capture["jobs"]), 1)
        self.assertTrue(self.capture["global_stop"])

    def test_ordinary_provider_failure_preserves_all_jobs_in_denominator(self):
        def modify(index, request, payload, response):
            if index == 0:
                raise TimeoutError("Synthetic timeout")
            return response
        self.run_fake(FakeNetwork(modify))
        self.assertEqual(len(self.capture["jobs"]), 3)
        self.assertEqual(self.capture["jobs"][0]["status"], "failed")
        self.assertEqual(self.capture["summary"]["returned_questions"], 10)
        self.assertEqual(self.capture["summary"]["planned_questions"], 15)

    def test_guardrail_intervention_ends_only_the_affected_independent_job(self):
        def modify(index, request, payload, response):
            if index == 0:
                response["stopReason"] = "guardrail_intervened"
            return response
        network = self.run_fake(FakeNetwork(modify))
        self.assertEqual(len(network.calls), 7)
        self.assertEqual([len(row["returned"]) for row in self.capture["jobs"]], [0, 5, 5])
        self.assertEqual(self.capture["jobs"][0]["error"]["type"], "SafetyInterventionError")
        self.assertEqual(self.capture["calls"][0]["response"]["stopReason"], "guardrail_intervened")
        self.assertFalse(self.capture.get("global_stop"))
        self.assertEqual(self.capture["summary"]["planned_questions"], 15)
        self.assertFalse(self.capture["summary"]["qualified"])

    def test_source_change_after_dispatch_stops_globally(self):
        changed = False
        def modify(index, request, payload, response):
            nonlocal changed
            changed = True
            return response
        def pin_check():
            if changed:
                raise probe.IntegrityError("Synthetic source drift")
        with self.assertRaises(probe.IntegrityError):
            self.run_fake(FakeNetwork(modify), pin_check=pin_check)
        self.assertEqual(len(self.capture["calls"]), 1)
        self.assertEqual(len(self.capture["jobs"]), 1)
        self.assertTrue(self.capture["global_stop"])

    def test_raw_runtime_usage_cannot_bypass_response_filter(self):
        def modify(index, request, payload, response):
            response["usage"]["unrecognized"] = "PRIVATE_USAGE"
            response["output"]["message"]["content"].append({"reasoningContent": {"reasoningText": {"text": "PRIVATE_REASON", "signature": "PRIVATE_SIGNATURE"}}})
            response["ResponseMetadata"] = {"HTTPHeaders": {"authorization": "PRIVATE_HEADER"}}
            return response
        self.run_fake(FakeNetwork(modify))
        self.assertNotIn("PRIVATE_", self.path.read_text())

    def test_runtime_stop_reason_cannot_echo_credentials_outside_safe_response(self):
        secret = "SYNTHETIC_EXPORTED_CREDENTIAL"
        def modify(index, request, payload, response):
            if index == 0:
                response["stopReason"] = secret
            return response
        self.run_fake(FakeNetwork(modify), secrets=(secret,))
        persisted_text = self.path.read_text()
        self.assertNotIn(secret, persisted_text)
        persisted = json.loads(persisted_text)
        self.assertEqual(persisted["calls"][0]["response"]["stopReason"], "[REDACTED_CREDENTIAL]")
        observations = persisted["jobs"][0]["metrics"]["ProviderObservations"]
        self.assertTrue(observations)
        self.assertTrue(all("stopReason" not in observation for observation in observations))
        self.assertEqual(persisted["summary"]["planned_questions"], 15)
        self.assertEqual(persisted["jobs"][0]["status"], "failed")

    def test_late_return_is_retained_for_audit_but_earns_no_yield_credit(self):
        now = 0
        def modify(index, request, payload, response):
            nonlocal now
            if index == 1:
                now = 241
            return response
        self.run_fake(FakeNetwork(modify), clock=lambda: now)
        self.assertEqual(len(self.capture["jobs"][0]["returned"]), 5)
        self.assertFalse(self.capture["jobs"][0]["within_deadline"])
        self.assertEqual(self.capture["summary"]["returned_questions"], 10)

    def test_bad_plan_or_existing_capture_prevents_credentials(self):
        plan_path = Path(self.directory.name) / "plan.json"
        probe.save(plan_path, {**self.plan, "state": "frozen"})
        with patch.object(probe, "PLAN", plan_path), patch.object(probe, "CAPTURE", self.path), \
                patch.object(probe.safe, "credential_session") as credentials:
            with self.assertRaises(probe.IntegrityError):
                probe.execute("0" * 64)
            probe.save(self.path, {"existing": True})
            with self.assertRaises(FileExistsError):
                probe.execute(probe.file_hash(plan_path))
            credentials.assert_not_called()

    def test_mixed_prose_solver_filtering_keeps_compiled_provenance_and_dense_audit(self):
        filtered = False
        def modify(index, request, payload, response):
            nonlocal filtered
            items = data(request).get("items", [])
            if "solutions" in payload and not filtered and any("grammatically" in item["prompt"] for item in items):
                filtered = True
                for choice in payload["solutions"]["0"]["choices"].values():
                    choice["judgment"] = "uncertain"
                response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        self.run_fake(FakeNetwork(modify))
        mixed = self.capture["jobs"][2]
        self.assertEqual(mixed["provider_calls"], 6)
        self.assertEqual(len(mixed["returned"]), 5)
        sources = mixed["returned_provenance"]
        self.assertEqual([source["source"][1:] for source in sources if source], [[0, 0], [0, 1], [0, 2]])
        reviewer = next(c for c in self.capture["calls"] if c["job"] == "mixed" and c["stage"].startswith("authored_solution_reviewer"))
        self.assertEqual(len(data(reviewer["request"])["items"]), 4)
        self.assertEqual(reviewer["stage"], probe.native.contract_metadata(probe.native.AuthoredSolutionFlagReviewContract(4))["name"])

    def test_insufficient_pools_use_only_bounded_author_attempts_without_falling_back(self):
        def modify(index, request, payload, response):
            if index < 3:
                self.assertEqual(request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"], probe.CONSTRUCTED_AUTHOR_CONTRACT)
                for row in payload["questions"]:
                    row["task"] = {"kind": "exact_value", "unit": "unitless",
                                   "nodes": [{"kind": "literal", "value": "1"}], "root": 0}
                response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        self.run_fake(FakeNetwork(modify))
        self.assertEqual(self.capture["jobs"][0]["provider_calls"], 3)
        self.assertEqual(self.capture["jobs"][0]["returned"], [])
        self.assertEqual(self.capture["summary"]["returned_questions"], 10)
        for record in self.capture["jobs"][0]["passes"]:
            self.assertEqual(record["compiler_rejections"], ["insufficient_distractors"] * 5)
            self.assertEqual(record["compiled"], [])
            self.assertEqual(record["sanitized"], [])

    def test_insufficient_pool_keeps_valid_siblings_and_exact_raw_source_holes(self):
        def modify(index, request, payload, response):
            if index == 0:
                payload["questions"][2]["task"] = {
                    "kind": "exact_value", "unit": "unitless",
                    "nodes": [{"kind": "literal", "value": "1"}], "root": 0}
                response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        self.run_fake(FakeNetwork(modify))
        first = self.capture["jobs"][0]
        self.assertEqual((first["provider_calls"], len(first["returned"])), (4, 5))
        self.assertEqual(first["passes"][0]["compiler_rejections"], ["insufficient_distractors"])
        self.assertIsNone(first["passes"][0]["prepared"][2])
        self.assertEqual([source["source"] for source in first["returned_provenance"]],
                         [["quantitative", 0, i] for i in (0, 1, 3, 4)] + [["quantitative", 1, 0]])
        audit = self.capture["calls"][1]
        self.assertEqual(audit["stage"], "authored_solution_reviewer_v3_n4")
        self.assertEqual([item["index"] for item in data(audit["request"])["items"]], list(range(4)))
        self.assertEqual(self.capture["summary"]["returned_questions"], 15)

    def test_provider_supplied_choices_fail_native_contract_without_old_mode_fallback(self):
        def modify(index, request, payload, response):
            if index == 0:
                payload["questions"][0]["task"]["choices"] = dict(zip("abcd", ("13", "14", "15", "16")))
                response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        self.run_fake(FakeNetwork(modify))
        first = self.capture["jobs"][0]
        self.assertEqual(first["provider_calls"], 1)
        self.assertEqual(first["returned"], [])
        self.assertEqual(first["passes"], [])
        self.assertEqual(self.capture["summary"]["planned_questions"], 15)
        self.assertEqual(self.capture["summary"]["returned_questions"], 10)
        self.assertFalse(self.capture.get("global_stop"))

    def test_actual_runtime_shrinks_the_final_socket_read_timeout(self):
        now = 0
        def modify(index, request, payload, response):
            nonlocal now
            if index == 2:
                now += 70
            if index == 3:
                now += 75
            return response
        self.run_fake(FakeNetwork(modify), clock=lambda: now)
        self.assertEqual(self.capture["calls"][0]["read_timeout"], 200)
        self.assertGreater(self.capture["calls"][4]["read_timeout"], 2)
        self.assertLess(self.capture["calls"][4]["read_timeout"], 90)
        self.assertEqual(self.capture["jobs"][1]["provider_calls"], 3)
        self.assertTrue(self.capture["jobs"][1]["within_deadline"])

    def test_normal_attempts_exhaust_exactly_eighteen_reservations(self):
        def modify(index, request, payload, response):
            # Force all prose only in this synthetic call-ceiling fixture. The
            # real mixed author cannot promise its next pass needs only two calls.
            for index, row in enumerate(payload.get("questions", [])):
                if row["kind"] == "quantitative":
                    content = _constructed_candidate(row["task"]).content()
                    metadata = {key: value for key, value in row.items() if key not in {"kind", "task"}}
                    payload["questions"][index] = {"kind": "prose", "question": {
                        **metadata, "prompt": content["prompt"], "choices": dict(zip("abcd", content["choices"])),
                        "correctChoice": "abcd"[content["choices"].index(content["expectedAnswer"])],
                        "explanation": content["explanation"], "format": "Multiple Choice"}}
            if "reviews" in payload:
                for key, row in payload["reviews"].items():
                    if int(key) >= 2:
                        row.update(valid=False, answer="")
            response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        network = self.run_fake(FakeNetwork(modify))
        self.assertEqual(len(network.calls), 18)
        self.assertEqual(len(self.capture["reservations"]), 18)
        self.assertEqual([row["provider_calls"] for row in self.capture["jobs"]], [6, 6, 6])
        self.assertEqual([len(row["returned"]) for row in self.capture["jobs"]], [4, 4, 4])
        with self.assertRaises(probe.IntegrityError):
            self.run_fake(network)
        self.assertEqual(len(network.calls), 18)

    def test_sdk_factory_failure_cannot_be_swallowed_as_an_ordinary_job_failure(self):
        def fail(_):
            raise RuntimeError("Synthetic factory setup failure")
        network = self.run_fake(FakeNetwork(factory_modify=fail))
        self.assertEqual(network.calls, [])
        self.assertEqual(len(self.capture["jobs"]), 1)
        self.assertTrue(self.capture["global_stop"])

    def test_execute_setup_failure_still_records_all_fifteen_planned_items(self):
        plan_path = Path(self.directory.name) / "plan.json"
        probe.save(plan_path, {**self.plan, "state": "frozen"})
        with patch.object(probe, "PLAN", plan_path), patch.object(probe, "CAPTURE", self.path), \
                patch.object(probe.safe, "credential_session", side_effect=probe.safe.CaptureBoundaryError("Synthetic credential failure")):
            result = probe.execute(probe.file_hash(plan_path))
        self.assertEqual(result["summary"]["planned_questions"], 15)
        self.assertEqual(result["summary"]["returned_questions"], 0)
        self.assertEqual(result["summary"]["attempted_calls"], 0)
        self.assertFalse(result["summary"]["qualified"])

    def test_repeated_raw_surplus_candidate_binds_to_actual_later_accepted_pass(self):
        repeated = None
        def modify(index, request, payload, response):
            nonlocal repeated
            if index == 0:
                repeated = copy.deepcopy(payload["questions"][0])
                repeated["task"]["nodes"][0]["value"] = "777"
                content = _constructed_candidate(repeated["task"]).content()
                network.known[content["prompt"]] = content["expectedAnswer"]
                payload["questions"].append(copy.deepcopy(repeated))
            if index == 1:
                payload["reviews"]["4"].update(valid=False, answer="")
            if index == 2:
                payload["questions"] = [copy.deepcopy(repeated)]
            response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        network = FakeNetwork(modify)
        self.run_fake(network)
        first = self.capture["jobs"][0]
        self.assertEqual(first["provider_calls"], 4)
        self.assertEqual(len(first["returned"]), 5)
        self.assertEqual(first["passes"][0]["author_payload"]["questions"][5],
                         first["passes"][1]["author_payload"]["questions"][0])
        self.assertEqual(first["returned_provenance"][-1]["source"], ["quantitative", 1, 0])
        self.assertEqual(first["returned_sources"][-1], ["quantitative", 1, 0])
        self.assertFalse(self.capture.get("global_stop"))

    def test_repeated_rejected_content_obeys_actual_topup_deduplication(self):
        repeated = None
        def modify(index, request, payload, response):
            nonlocal repeated
            if index == 0:
                repeated = copy.deepcopy(payload["questions"][0])
            if index == 1:
                payload["reviews"]["0"].update(valid=False, answer="")
            if index == 2:
                payload["questions"] = [copy.deepcopy(repeated)]
            response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        self.run_fake(FakeNetwork(modify))
        first = self.capture["jobs"][0]
        self.assertEqual((first["provider_calls"], len(first["returned"])), (5, 5))
        self.assertEqual(first["passes"][1]["sanitized"], [])
        self.assertEqual(first["passes"][1]["verified"], [])
        self.assertTrue(all(source[1] == 0 for source in first["returned_sources"][:4]))
        # The saved solver calls leave enough budget for a third fresh author pass.
        self.assertEqual(first["returned_sources"][-1], ["quantitative", 2, 0])
        self.assertEqual(len(first["passes"]), 3)
        self.assertFalse(self.capture.get("global_stop"))

    def test_authored_crlf_main_and_reversed_review_maps_preserve_dense_items(self):
        main = "  Exact authored main teaching remains unchanged.\r\nThis is a synthetic fixture.  "
        def modify(index, request, payload, response):
            for row in payload.get("questions", []):
                if row["kind"] == "prose":
                    row["question"]["explanation"] = main
            if "reviews" in payload:
                payload["reviews"] = dict(reversed(list(payload["reviews"].items())))
            response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
            return response
        self.run_fake(FakeNetwork(modify))
        for job in self.capture["jobs"]:
            for question, provenance in zip(job["returned"], job["returned_provenance"], strict=True):
                if provenance is None:
                    self.assertEqual(question["explanation"].encode(), main.encode())
                    self.assertEqual(question["choiceExplanations"], {})
        self.assertEqual(self.capture["summary"]["returned_questions"], 15)

    def test_immutable_audit_replacement_is_not_repaired_and_support_vetoes_remain(self):
        for invalid in ("replacement", "support", "issues"):
            self.capture = probe.new_capture(self.plan)
            def modify(index, request, payload, response):
                if index == 1:
                    if invalid == "replacement":
                        payload["reviews"]["0"]["explanation"] = "An unauthorized replacement."
                    elif invalid == "support":
                        payload["reviews"]["0"]["explanationSupport"] = "uncertain"
                    else:
                        payload["reviews"]["0"]["issueFlags"]["scope_assignment"] = True
                    response["output"]["message"]["content"] = [{"text": json.dumps(payload)}]
                return response
            with self.subTest(invalid=invalid):
                self.run_fake(FakeNetwork(modify))
                first = self.capture["jobs"][0]
                if invalid == "replacement":
                    self.assertEqual(first["status"], "failed")
                    self.assertEqual(first["provider_calls"], 2)
                    self.assertEqual(first["returned"], [])
                else:
                    self.assertEqual(len(first["passes"][0]["verified"]), 4)
                    self.assertEqual(first["provider_calls"], 4)
                    self.assertEqual(len(first["returned"]), 5)
                self.assertFalse(self.capture.get("global_stop"))

    def test_visible_credential_echo_stops_before_capture_or_runtime_adaptation(self):
        secret = "SYNTHETIC_VISIBLE_EXPORTED_CREDENTIAL"
        def modify(index, request, payload, response):
            response["output"]["message"]["content"] = [{"text": secret}]
            return response
        network = FakeNetwork(modify)
        self.run_fake(network, secrets=(secret,))
        self.assertEqual(len(network.calls), 1)
        self.assertTrue(self.capture.get("global_stop"))
        self.assertNotIn(secret, self.path.read_text())
        self.assertNotIn("response", self.capture["calls"][0])
        self.assertEqual(self.capture["jobs"][0]["passes"], [])

    def test_unicode_escaped_credential_stops_before_native_decode_or_capture(self):
        secret = "SYNTHETIC_UNICODE_EXPORTED_CREDENTIAL"
        escaped = "".join("\\u%04x" % ord(char) for char in secret)
        def modify(index, request, payload, response):
            payload["questions"][0]["task"]["nodes"][0]["value"] = secret
            encoded = json.dumps(payload).replace(secret, escaped)
            self.assertNotIn(secret, encoded)
            # Split at an existing legal JSON whitespace boundary; the runtime
            # joins visible blocks with a newline before strict native parsing.
            cut = encoded.index(' "')
            response["output"]["message"]["content"] = [{"text": encoded[:cut]}, {"text": encoded[cut:]}]
            return response
        network = FakeNetwork(modify)
        with patch.object(probe.native, "adapt_native_response", wraps=probe.native.adapt_native_response) as adapt:
            self.run_fake(network, secrets=(secret,))
            adapt.assert_not_called()
        self.assertEqual(len(network.calls), 1)
        self.assertTrue(self.capture.get("global_stop"))
        self.assertNotIn(secret, self.path.read_text())
        self.assertNotIn(escaped, self.path.read_text())
        self.assertNotIn("response", self.capture["calls"][0])
        self.assertEqual(self.capture["jobs"][0]["passes"], [])

    def test_decoded_echo_scan_does_not_turn_malformed_json_into_setup_failure(self):
        def modify(index, request, payload, response):
            if index == 0:
                response["output"]["message"]["content"] = [{"text": '{"questions":['}]
            return response
        network = self.run_fake(FakeNetwork(modify), secrets=("SYNTHETIC_CREDENTIAL",))
        self.assertEqual(len(network.calls), 7)
        self.assertEqual(self.capture["jobs"][0]["status"], "failed")
        self.assertEqual(self.capture["summary"]["returned_questions"], 10)
        self.assertFalse(self.capture.get("global_stop"))
        self.assertIn("response", self.capture["calls"][0])

    def test_decoded_echo_scan_checks_duplicate_members_without_approving_json(self):
        secret = "SYNTHETIC_DUPLICATE_MEMBER_CREDENTIAL"
        escaped = "".join("\\u%04x" % ord(char) for char in secret)
        response = {"output": {"message": {"content": [
            {"text": '{"member":"' + escaped + '","member":"other"}'}]}}}
        self.assertTrue(probe.decoded_credential_echo(response, (secret,)))

    def test_external_capture_change_is_not_overwritten_or_followed_by_dispatch(self):
        def modify(index, request, payload, response):
            self.path.write_text("external capture modification")
            return response
        network = FakeNetwork(modify)
        with self.assertRaises(probe.IntegrityError):
            self.run_fake(network)
        self.assertEqual(len(network.calls), 1)
        self.assertTrue(self.capture.get("global_stop"))
        self.assertEqual(self.path.read_text(), "external capture modification")

    def test_imported_runtime_cannot_be_pinned_to_newer_or_foreign_source(self):
        with patch.object(probe, "IMPORTED_SERVICE_HASHES", {}), self.assertRaises(probe.IntegrityError):
            probe.build_plan()
        with patch.object(probe, "IMPORTED_HELPER_HASH", "0" * 64), self.assertRaises(probe.IntegrityError):
            probe.build_plan()
        with patch.object(probe.runtime, "__file__", "/tmp/foreign/question_generation.py"), self.assertRaises(probe.IntegrityError):
            probe.build_plan()


if __name__ == "__main__":
    unittest.main()
