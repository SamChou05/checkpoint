"""Exercise the one-job task-only pilot using fake provider responses only."""

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
SPEC = importlib.util.spec_from_file_location("quant_author_task_probe_tested", HERE / "task_probe.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)
from quantitative_authoring import _constructed_candidate  # noqa: E402
from quantitative_task_compiler import compile_question  # noqa: E402


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
        if name == probe.TASK_ONLY_AUTHOR_CONTRACT:
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


class TaskProbeTests(unittest.TestCase):
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
        self.assertEqual(len(self.capture["original_jobs"]), 1)
        self.assertEqual([len(job["slots"]) for job in self.capture["original_jobs"]], [5])
        self.assertTrue(all(slot["status"] == "unattempted" for job in self.capture["original_jobs"]
                            for slot in job["slots"]))
        self.assertEqual(len(self.capture["call_slots"]), 6)
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
        with self.assertRaises(probe.IntegrityError):
            probe.check_profile_files(config, Path(self.directory.name) / "missing-credentials",
                                      probe.file_hash(config), hashlib.sha256(b"test-session").hexdigest())
        config.write_text("[default]\nlogin_session = test-session\nregion = us-east-1\n"
                          "[services redirected]\nsignin =\n  endpoint_url = https://signin.invalid\n")
        probe.check_profile_files(config, Path(self.directory.name) / "missing-credentials",
                                  probe.file_hash(config), hashlib.sha256(b"test-session").hexdigest())
        marker = object()

        def inspect_export():
            process = probe.safe.subprocess.Popen(
                probe.safe.CREDENTIAL_COMMAND, stdout=probe.safe.subprocess.PIPE,
                stderr=probe.safe.subprocess.DEVNULL)
            probe.safe.export_credentials()
            return process, ()

        with patch.dict(os.environ, {"AWS_PROFILE": "default", "AWS_DEFAULT_PROFILE": "",
                                  "HOME": self.directory.name,
                                  "AWS_ENDPOINT_URL": "", "AWS_ENDPOINT_URL_STS": "",
                                  "AWS_IGNORE_CONFIGURED_ENDPOINT_URLS": "false",
                                  "AWS_LOGIN_CACHE_DIRECTORY": self.directory.name,
                                  "AWS_ROLE_ARN": "synthetic-role",
                                  "AWS_WEB_IDENTITY_TOKEN_FILE": "/synthetic/token"}), \
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
        self.assertEqual(child["AWS_CONFIG_FILE"], str(probe.FROZEN_CONFIG_PATH))
        self.assertEqual(child["AWS_SHARED_CREDENTIALS_FILE"], str(probe.FROZEN_CREDENTIALS_PATH))
        self.assertEqual(child["HOME"], str(probe.FROZEN_HOME))
        self.assertEqual(child["AWS_LOGIN_CACHE_DIRECTORY"], self.directory.name)
        self.assertFalse(any(key.upper().startswith("AWS_ENDPOINT_URL") for key in child))
        redirected = probe.controlled_cli_environment({**os.environ,
            "AWS_ENDPOINT_URL_SIGNIN": "https://env-signin.invalid",
            "AWS_ENDPOINT_URL_S3": "https://env-s3.invalid"})
        self.assertFalse(any(key.upper().startswith("AWS_ENDPOINT_URL") for key in redirected))
        self.assertNotIn("AWS_ROLE_ARN", child)
        self.assertNotIn("AWS_WEB_IDENTITY_TOKEN_FILE", child)
        self.assertIn("endpoint_url = https://signin.invalid", config.read_text())

    def test_profile_path_overrides_and_mutations_stop_before_credential_export(self):
        with patch.object(probe, "check_aws_cli") as cli, \
                patch.object(probe.safe, "credential_session") as export:
            for variable in ("AWS_CONFIG_FILE", "AWS_SHARED_CREDENTIALS_FILE"):
                with self.subTest(variable=variable), patch.dict(os.environ, {variable: "/alternate/aws-file"}):
                    with self.assertRaises(probe.IntegrityError):
                        probe.default_profile_session()
            cli.assert_not_called()
            export.assert_not_called()

        config = Path(self.directory.name) / "config"
        credentials = Path(self.directory.name) / "credentials"
        base = "[default]\nlogin_session = test-session\nregion = us-east-1\n"
        login_hash = hashlib.sha256(b"test-session").hexdigest()
        config.write_text(base)
        probe.check_profile_files(config, credentials, probe.file_hash(config), login_hash)
        for changed in (base + "credential_process = synthetic-helper\n",
                        base + "role_arn = synthetic-role\nsource_profile = other\n",
                        base + "web_identity_token_file = /synthetic/token\n",
                        base.replace("us-east-1", "us-west-2"),
                        base.replace("test-session", "other-session"),
                        base + "[profile default]\ncredential_process = synthetic-helper\n"):
            config.write_text(changed)
            with self.subTest(changed=hashlib.sha256(changed.encode()).hexdigest()), \
                    self.assertRaises(probe.IntegrityError):
                probe.check_profile_files(config, credentials, probe.file_hash(config), login_hash)
        config.write_text(base)
        credentials.write_text("[other]\naws_access_key_id = SYNTHETIC_OTHER\n")
        probe.check_profile_files(config, credentials, probe.file_hash(config), login_hash)
        credentials.write_text("[default]\naws_access_key_id = SYNTHETIC_DEFAULT\n")
        with self.assertRaises(probe.IntegrityError):
            probe.check_profile_files(config, credentials, probe.file_hash(config), login_hash)
        credentials.unlink()
        with self.assertRaises(probe.IntegrityError):
            probe.check_profile_files(config, credentials, "0" * 64, login_hash)

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
                patch.object(probe, "check_launch_record"), \
                patch.object(probe, "run_jobs") as run:
            result = probe.execute(probe.file_hash(plan_path))
        run.assert_not_called()
        self.assertEqual(session.identity_requests, 1)
        self.assertEqual([service for service, _ in session.client_calls], ["sts"])
        self.assertEqual(result["summary"]["planned_questions"], 5)
        self.assertEqual(result["summary"]["unattempted_jobs"], 1)
        self.assertEqual(result["summary"]["unattempted_call_slots"], 6)
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
                patch.object(probe, "check_launch_record"), \
                patch.object(probe, "run_jobs", side_effect=no_dispatch):
            result = probe.execute(probe.file_hash(plan_path))
        self.assertEqual(observed, [True])
        self.assertEqual([service for service, _ in session.client_calls], ["sts", "bedrock-runtime"])
        self.assertEqual(session.identity_requests, 1)
        self.assertEqual(json.loads(self.path.read_text())["identity_check"]["status"], "verified")
        self.assertEqual(result["summary"]["attempted_calls"], 0)

    def test_pretrial_refresh_records_only_freshness_metadata_and_one_sts_request(self):
        launch_path = Path(self.directory.name) / "launch-precheck.json"
        attempt_path = Path(self.directory.name) / "launch-precheck-attempt.json"
        fake_profile = FakeIdentitySession(signin_refreshes=1)
        expires_at = datetime.now(timezone.utc) + timedelta(seconds=875)
        with patch.dict(os.environ, {"AWS_PROFILE": "default", "AWS_ENDPOINT_URL": "",
                                  "AWS_ENDPOINT_URL_STS": ""}), \
                patch.object(probe, "LAUNCH_PRECHECK", launch_path), \
                patch.object(probe, "LAUNCH_ATTEMPT", attempt_path), \
                patch.object(probe, "check_aws_cli"), \
                patch.object(probe.boto3, "Session", return_value=fake_profile) as session_factory, \
                patch.object(probe, "default_profile_session", return_value=(
                    object(), ("SYNTHETIC_SECRET",), expires_at)) as export:
            record = probe.launch_precheck()
            probe.check_launch_record(self.plan)
            with self.assertRaises(probe.IntegrityError):
                probe.check_launch_record(self.plan, now=expires_at - timedelta(seconds=809))
        session_factory.assert_called_once_with(profile_name="default", region_name="us-east-1")
        export.assert_called_once()
        self.assertEqual(fake_profile.identity_requests, 1)
        self.assertEqual([service for service, _ in fake_profile.client_calls], ["sts"])
        self.assertEqual(record["pretrial_sts_requests"], 1)
        self.assertEqual(record["botocore_signin_refresh_operations"], 1)
        self.assertEqual(record["cli_signin_refresh_operations"], "unobserved; bounded 0-1")
        self.assertEqual(record["pretrial_aws_operations_budget"], 3)
        self.assertEqual(record["provider_calls"], 0)
        self.assertEqual(json.loads(launch_path.read_text()), record)
        self.assertEqual(json.loads(attempt_path.read_text())["maximum_sts_requests"], 1)
        self.assertNotIn("SYNTHETIC_SECRET", launch_path.read_text())
        self.assertNotIn("unretained-test-arn", launch_path.read_text())

    def test_short_pretrial_snapshot_and_missing_record_block_successor_launch(self):
        launch_path = Path(self.directory.name) / "launch-precheck.json"
        attempt_path = Path(self.directory.name) / "launch-precheck-attempt.json"
        fake_profile = FakeIdentitySession()
        with patch.dict(os.environ, {"AWS_PROFILE": "default", "AWS_ENDPOINT_URL": "",
                                  "AWS_ENDPOINT_URL_STS": ""}), \
                patch.object(probe, "LAUNCH_PRECHECK", launch_path), \
                patch.object(probe, "LAUNCH_ATTEMPT", attempt_path), \
                patch.object(probe, "check_aws_cli"), \
                patch.object(probe.boto3, "Session", return_value=fake_profile), \
                patch.object(probe, "default_profile_session", return_value=(
                    object(), (), datetime.now(timezone.utc) + timedelta(seconds=800))):
            with self.assertRaises(probe.IntegrityError):
                probe.launch_precheck()
            with self.assertRaises(probe.IntegrityError):
                probe.launch_precheck()
        self.assertEqual(fake_profile.identity_requests, 1)
        self.assertTrue(attempt_path.exists())
        self.assertFalse(launch_path.exists())

        plan_path = Path(self.directory.name) / "plan.json"
        probe.save(plan_path, {**self.plan, "state": "frozen"}, exclusive=True)
        with patch.object(probe, "PLAN", plan_path), patch.object(probe, "CAPTURE", self.path), \
                patch.object(probe, "LAUNCH_PRECHECK", launch_path), \
                patch.object(probe, "LAUNCH_ATTEMPT", attempt_path), \
                patch.object(probe, "default_profile_session") as export:
            with self.assertRaises(probe.IntegrityError):
                probe.execute(probe.file_hash(plan_path))
            export.assert_not_called()
        self.assertFalse(self.path.exists())

    def test_precheck_rejects_endpoint_overrides_before_credential_resolution(self):
        launch_path = Path(self.directory.name) / "launch-precheck.json"
        attempt_path = Path(self.directory.name) / "launch-precheck-attempt.json"
        for variable in ("AWS_ENDPOINT_URL_SIGNIN", "AWS_ENDPOINT_URL"):
            with self.subTest(variable=variable), \
                    patch.dict(os.environ, {variable: "https://redirect.invalid"}), \
                    patch.object(probe, "LAUNCH_PRECHECK", launch_path), \
                    patch.object(probe, "LAUNCH_ATTEMPT", attempt_path), \
                    patch.object(probe.boto3, "Session") as session_factory, \
                    patch.object(probe, "default_profile_session") as export:
                with self.assertRaises(probe.IntegrityError):
                    probe.launch_precheck()
                session_factory.assert_not_called()
                export.assert_not_called()
                self.assertFalse(attempt_path.exists())

    def test_precheck_caps_signin_refresh_before_sts_and_export(self):
        launch_path = Path(self.directory.name) / "launch-precheck.json"
        attempt_path = Path(self.directory.name) / "launch-precheck-attempt.json"
        fake_profile = FakeIdentitySession(signin_refreshes=2)
        with patch.dict(os.environ, {"AWS_PROFILE": "default", "AWS_ENDPOINT_URL": "",
                                  "AWS_ENDPOINT_URL_STS": ""}), \
                patch.object(probe, "LAUNCH_PRECHECK", launch_path), \
                patch.object(probe, "LAUNCH_ATTEMPT", attempt_path), \
                patch.object(probe, "check_aws_cli"), \
                patch.object(probe.boto3, "Session", return_value=fake_profile), \
                patch.object(probe, "default_profile_session") as export:
            with self.assertRaises(probe.IntegrityError):
                probe.launch_precheck()
        self.assertEqual(fake_profile.identity_requests, 0)
        export.assert_not_called()
        self.assertTrue(attempt_path.exists())
        self.assertFalse(launch_path.exists())

    def test_precheck_validates_resolved_sts_endpoint_before_signed_request(self):
        launch_path = Path(self.directory.name) / "launch-precheck.json"
        attempt_path = Path(self.directory.name) / "launch-precheck-attempt.json"
        fake_profile = FakeIdentitySession(endpoint="https://redirect.invalid")
        with patch.dict(os.environ, {"AWS_PROFILE": "default", "AWS_ENDPOINT_URL": "",
                                  "AWS_ENDPOINT_URL_STS": ""}), \
                patch.object(probe, "LAUNCH_PRECHECK", launch_path), \
                patch.object(probe, "LAUNCH_ATTEMPT", attempt_path), \
                patch.object(probe, "check_aws_cli"), \
                patch.object(probe.boto3, "Session", return_value=fake_profile), \
                patch.object(probe, "default_profile_session") as export:
            with self.assertRaises(probe.IntegrityError):
                probe.launch_precheck()
        self.assertEqual(fake_profile.identity_requests, 0)
        export.assert_not_called()
        self.assertTrue(attempt_path.exists())
        self.assertFalse(launch_path.exists())

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

    def test_one_numerical_job_uses_three_then_two_and_preserves_exact_proofs(self):
        network = self.run_fake()
        self.assertEqual(len(network.calls), 4)
        self.assertEqual(len(self.capture["reservations"]), 4)
        self.assertEqual(len(self.capture["jobs"]), 1)
        job = self.capture["jobs"][0]
        self.assertEqual((job["status"], len(job["returned"]), len(job["passes"])), ("finished", 5, 2))
        self.assertEqual([data(network.calls[i])["targetCount"] for i in (0, 2)], [3, 2])
        self.assertEqual([len(item["verified"]) for item in job["passes"]], [3, 2])
        for question, provenance in zip(job["returned"], job["returned_provenance"], strict=True):
            self.assertEqual(question["verificationPolicyRevision"], 8)
            self.assertEqual(probe.learner(question), provenance["learner"])
            self.assertEqual(probe.learner(question), compile_question(provenance["spec"]))
        self.assertEqual([slot["status"] for slot in self.capture["original_jobs"][0]["slots"]], ["returned"] * 5)
        self.assertEqual(self.capture["summary"]["unattempted_call_slots"], 2)

    def test_dispatch_marker_is_durable_at_provider_entry(self):
        def inspect_entry(index, request, payload, response):
            persisted = json.loads(self.path.read_text())
            self.assertEqual(persisted["calls"][index]["dispatch_attempted"], True)
            self.assertEqual(persisted["call_slots"][index]["status"], "dispatch_attempted")
            self.assertEqual(persisted["calls"][index]["request"], request)
            return response

        network = self.run_fake(FakeNetwork(inspect_entry))
        self.assertEqual(len(network.calls), 4)

    def test_first_author_uses_only_closed_task_schema(self):
        def inspect_schema(index, request, payload, response):
            if index == 0:
                structure = request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]
                self.assertEqual(structure["name"], probe.TASK_ONLY_AUTHOR_CONTRACT)
                serialized = json.dumps(structure["schema"])
                for forbidden in ("proseQuestion", "correctChoice", "explanation", "choices"):
                    self.assertNotIn('"' + forbidden + '"', serialized)
                self.assertTrue(all(row["kind"] == "quantitative" for row in payload["questions"]))
            return response

        self.run_fake(FakeNetwork(inspect_schema))

    def test_first_author_max_tokens_fails_closed_without_retry(self):
        def truncated(index, request, payload, response):
            if index == 0:
                response["stopReason"] = "max_tokens"
                response["usage"]["outputTokens"] = 16000
            return response
        network = self.run_fake(FakeNetwork(truncated))
        self.assertEqual(len(network.calls), 1)
        self.assertEqual(self.capture["summary"]["returned_questions"], 0)
        self.assertEqual(self.capture["jobs"][0]["metrics"]["QuestionQuality"]["provider"]["output_truncated"], 1)
        self.assertEqual([slot["status"] for slot in self.capture["original_jobs"][0]["slots"]], ["unfilled"] * 5)

    def test_native_grammar_rejection_does_not_fallback_to_prose(self):
        def reject_grammar(index, request, payload, response):
            raise ClientError({"Error": {"Code": "ValidationException", "Message": "synthetic grammar rejection"}},
                              "Converse")

        network = self.run_fake(FakeNetwork(reject_grammar))
        self.assertEqual(len(network.calls), 1)
        self.assertEqual(self.capture["summary"]["returned_questions"], 0)
        self.assertEqual(self.capture["calls"][0]["error"]["code"], "ValidationException")
        self.assertEqual([slot["status"] for slot in self.capture["original_jobs"][0]["slots"]], ["unfilled"] * 5)

    def test_failed_second_author_retains_three_verified_returns(self):
        def fail_second(index, request, payload, response):
            if index == 2:
                raise ClientError({"Error": {"Code": "ThrottlingException", "Message": "redacted"}}, "Converse")
            return response
        network = self.run_fake(FakeNetwork(fail_second))
        self.assertEqual(len(network.calls), 3)
        self.assertEqual(self.capture["summary"]["returned_questions"], 3)
        self.assertEqual([slot["status"] for slot in self.capture["original_jobs"][0]["slots"]],
                         ["returned"] * 3 + ["unfilled"] * 2)
        self.assertEqual(len(self.capture["jobs"][0]["returned_provenance"]), 3)
        self.assertEqual(self.capture["calls"][2]["error"]["code"], "ThrottlingException")

    def test_initial_author_prompt_drift_stops_before_dispatch(self):
        self.capture["plan"]["initial_author_prompts"][0]["user"] += " changed"
        network = self.run_fake()
        self.assertEqual(len(network.calls), 0)
        self.assertEqual(self.capture["summary"]["attempted_calls"], 0)
        self.assertTrue(self.capture["global_stop"])

    def test_resolved_bedrock_endpoint_drift_stops_before_dispatch(self):
        def redirect(client):
            client.meta.endpoint_url = "https://runtime.invalid"
        network = self.run_fake(FakeNetwork(factory_modify=redirect))
        self.assertEqual(network.calls, [])
        self.assertTrue(self.capture["global_stop"])

    def test_capture_drift_aborts_before_provider_dispatch(self):
        original = probe.save
        changed = False
        def corrupt_after_write(path, value, *, exclusive=False):
            nonlocal changed
            original(path, value, exclusive=exclusive)
            if not changed and value is self.capture and value["calls"]:
                path.write_text(path.read_text() + " ")
                changed = True
        network = FakeNetwork()
        with patch.object(probe, "save", side_effect=corrupt_after_write), self.assertRaises(probe.IntegrityError):
            probe.run_jobs(self.plan, self.capture, self.path, network.client, lambda: None)
        self.assertTrue(changed)
        self.assertEqual(len(network.calls), 0)
        self.assertTrue(self.capture["global_stop"])

    def test_second_run_cannot_resume_consumed_slots(self):
        self.run_fake()
        with self.assertRaises(probe.IntegrityError):
            self.run_fake()

    def test_prior_trial_and_first_author_pins_are_independently_checked(self):
        prior = json.loads(probe.PRIOR_PLAN.read_text())
        prior["environment"]["BEDROCK_CLAUDE_EFFORT"] = "medium"
        changed = Path(self.directory.name) / "changed-prior-plan.json"
        changed.write_text(json.dumps(prior))
        with patch.object(probe, "PRIOR_PLAN", changed), self.assertRaises(probe.IntegrityError):
            probe.build_plan()
        with patch.object(probe, "FIRST_USER_SHA256", "0" * 64), self.assertRaises(probe.IntegrityError):
            probe.build_plan()

    def test_deadline_after_verified_first_batch_keeps_three_and_blocks_topup(self):
        now = [0.0]
        def advance(index, request, payload, response):
            if index == 1:
                now[0] = 239.0
            return response
        network = self.run_fake(FakeNetwork(advance), clock=lambda: now[0])
        self.assertEqual(len(network.calls), 2)
        self.assertEqual(self.capture["summary"]["returned_questions"], 3)
        self.assertEqual(self.capture["jobs"][0]["within_deadline"], True)
        self.assertEqual(len(self.capture["reservations"]), 2)
        self.assertEqual([slot["status"] for slot in self.capture["original_jobs"][0]["slots"]],
                         ["returned"] * 3 + ["unfilled"] * 2)
