"""Offline contract and dispatch tests; all socket connections are denied."""

import importlib.util
import json
from pathlib import Path
import socket
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("author_count_probe", HERE / "author_probe.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class AuthorProbeTests(unittest.TestCase):
    def setUp(self):
        self.socket_guard = patch.object(socket.socket, "connect", side_effect=AssertionError("network prohibited"))
        self.socket_guard.start()
        self.addCleanup(self.socket_guard.stop)
        self.fixed = json.loads(probe.FIXED.read_text())

    def test_four_fake_dispatches_cover_two_balanced_pairs_and_exact_schemas(self):
        prepared = [probe.dry_job(self.fixed, job) for job in self.fixed["jobs"]]
        self.assertEqual([job["id"] for job in prepared], [
            "archive_circulation_array_n5", "archive_circulation_count_bound_n5",
            "greenhouse_alerts_count_bound_n5", "greenhouse_alerts_array_n5",
        ])
        self.assertEqual([job["contract"]["name"] for job in prepared],
                         ["question_author_v3", "question_author_v4_n5",
                          "question_author_v4_n5", "question_author_v3"])
        for pair_index in range(2):
            first, second = prepared[2 * pair_index:2 * pair_index + 2]
            self.assertEqual(first["assignment_id"], second["assignment_id"])
            self.assertEqual(first["normalized_request"], second["normalized_request"])
            self.assertEqual({first["cardinality_contract"], second["cardinality_contract"]},
                             {"array", "count_bound"})
        for job in prepared:
            self.assertEqual(job["schema_sha256"], job["contract"]["sha256"])
            self.assertEqual(job["provider_request"]["inferenceConfig"]["maxTokens"], 16000)
            self.assertEqual(job["provider_request"]["modelId"], self.fixed["model_id"])
            self.assertEqual(job["environment"]["BEDROCK_FALLBACK_MODEL_ID"], "")

    def test_structural_eligibility_counts_raw_rows_and_rejects_bad_keys(self):
        for job_spec in self.fixed["jobs"]:
            job = probe.dry_job(self.fixed, job_spec)
            response = probe.fake_response(job_spec)
            raw = response["output"]["message"]["content"][0]["text"]
            observation = {"outcome": "response", "stop_reason": "end_turn", "visible_text_blocks": [raw]}
            self.assertTrue(probe.structural_observation(job, observation)["eligible"])
            payload = json.loads(raw)
            if isinstance(payload["questions"], dict):
                payload["questions"].pop("0")
                observation["visible_text_blocks"] = [json.dumps(payload)]
                self.assertFalse(probe.structural_observation(job, observation)["eligible"])
                payload["questions"]["0"] = probe.fake_payload(
                    job["author_mode"], "count_bound", 1)["questions"]["0"]
                payload["questions"]["extra"] = payload["questions"]["0"]
            else:
                payload["questions"].pop()
            observation["visible_text_blocks"] = [json.dumps(payload)]
            self.assertFalse(probe.structural_observation(job, observation)["eligible"])

    def test_duplicate_keys_and_truncated_stop_are_ineligible(self):
        job = probe.dry_job(self.fixed, self.fixed["jobs"][1])
        observation = {"outcome": "response", "stop_reason": "end_turn",
                       "visible_text_blocks": ['{"questions":{"0":{},"0":{}}}']}
        self.assertEqual(probe.structural_observation(job, observation)["reason"], "duplicate_json_key")
        observation["stop_reason"] = "max_tokens"
        self.assertEqual(probe.structural_observation(job, observation)["reason"], "incomplete_stop")

    def test_invalid_native_output_cannot_trigger_retry_or_fallback_dispatch(self):
        spec = self.fixed["jobs"][1]
        for mutation in ("missing", "extra", "malformed"):
            response = probe.fake_response(spec)
            if mutation != "malformed":
                payload = json.loads(response["output"]["message"]["content"][0]["text"])
                if mutation == "missing":
                    del payload["questions"]["0"]
                else:
                    payload["questions"]["5"] = payload["questions"]["0"]
                response["output"]["message"]["content"][0]["text"] = json.dumps(payload)
            else:
                response["output"]["message"]["content"][0]["text"] = "{invalid"
            client = probe.FakeClient(response)
            environment = probe.job_environment(self.fixed, spec)
            with patch.dict(probe.os.environ, environment, clear=True):
                normalized = probe._normalize_request(spec["payload"])
                with self.assertRaises(Exception):
                    probe._generate_provider_payload(normalized, client, probe.ProviderCallBudget(1))
            self.assertEqual(len(client.requests), 1)

    def test_socket_blocked_recorder_omits_malformed_and_escaped_credentials(self):
        job = probe.dry_job(self.fixed, self.fixed["jobs"][1])
        secret = "SECRET123"
        samples = (
            ('{"questions":{"0":"\\u0053ECRET123"', "malformed_json"),
            ('{"questions":{"0":"safe","0":"\\u0053ECRET123"}}', "duplicate_json_key"),
            ('{"questions":{"0":"\\u0053ECRET123"}}', "credential_text"),
        )
        for raw, expected_reason in samples:
            response = {"stopReason": "end_turn", "output": {"message": {"content": [{"text": raw}]}}}
            fake = probe.FakeClient(response)
            recorder = probe.RecordingClient(fake, job, (secret,))
            self.assertEqual(recorder.converse(**job["provider_request"]), response)
            self.assertEqual(recorder.calls, 1)
            self.assertIsNone(recorder.observation["visible_text_blocks"])
            self.assertEqual(recorder.observation["capture_redaction"], expected_reason)

    def test_oversized_output_invalid_blocks_and_metadata_are_not_persisted(self):
        job = probe.dry_job(self.fixed, self.fixed["jobs"][1])
        oversized = '{"questions":"' + "x" * probe.MAX_VISIBLE_BYTES + '"}'
        response = {"stopReason": "SECRET_STOP", "usage": {"inputTokens": "SECRET_USAGE"},
                    "output": {"message": {"content": [{"text": oversized}]}}}
        recorder = probe.RecordingClient(probe.FakeClient(response), job)
        recorder.converse(**job["provider_request"])
        self.assertIsNone(recorder.observation["visible_text_blocks"])
        self.assertEqual(recorder.observation["capture_redaction"], "oversized_visible_text")
        self.assertIsNone(recorder.observation["stop_reason"])
        self.assertIsNone(recorder.observation["usage"])
        response["output"]["message"]["content"] = [{"text": "{}"}, "not_a_block"]
        recorder = probe.RecordingClient(probe.FakeClient(response), job)
        recorder.converse(**job["provider_request"])
        self.assertEqual(recorder.observation["capture_redaction"], "invalid_content_blocks")
        self.assertIsNone(recorder.observation["visible_text_blocks"])

    def test_setup_failure_is_durable_before_any_provider_call(self):
        with tempfile.TemporaryDirectory() as directory:
            location = Path(directory)
            plan = json.loads(probe.prepare().read_text())
            capture = location / "capture.json"
            plan["capture_path"] = str(capture)
            (location / "plan.json").write_text(json.dumps(plan))
            with patch.object(probe, "HERE", location), patch.object(probe, "check_frozen"), \
                    patch("boto3.Session", side_effect=RuntimeError("synthetic setup failure")):
                with self.assertRaisesRegex(RuntimeError, "synthetic setup failure"):
                    probe.execute("synthetic-frozen-hash", capture)
            saved = json.loads(capture.read_text())
            self.assertEqual(saved["preflight_status"], "failed")
            self.assertEqual(saved["preflight_error_type"], "RuntimeError")
            self.assertEqual(saved["jobs"], [])
            self.assertNotIn("synthetic setup failure", capture.read_text())

    def test_durable_reservation_and_capture_tamper_stop_next_dispatch(self):
        with tempfile.TemporaryDirectory() as directory:
            capture = Path(directory) / "capture.json"
            journal = probe.CaptureJournal(capture, {"jobs": [], "preflight_status": "passed"})
            jobs = [probe.dry_job(self.fixed, job) for job in self.fixed["jobs"][:2]]
            plan = {"jobs": jobs}
            with patch.object(probe, "check_frozen"):
                first = probe.RecordingClient(
                    probe.FakeClient(probe.fake_response(self.fixed["jobs"][0])), jobs[0],
                    before_dispatch=lambda: journal.reserve(jobs[0], plan, "reviewed"),
                )
                first.converse(**jobs[0]["provider_request"])
                durable = json.loads(capture.read_text())
                self.assertEqual(durable["jobs"][0]["dispatch_status"], "reserved_before_converse")
                journal.complete({"provider_calls": first.calls})
                capture.write_text(capture.read_text() + "tampered")
                with self.assertRaisesRegex(RuntimeError, "capture changed"):
                    journal.reserve(jobs[1], plan, "reviewed")
            self.assertEqual(first.calls, 1)

    def test_frozen_pin_drift_stops_before_any_fake_transport(self):
        with tempfile.TemporaryDirectory() as directory:
            capture = Path(directory) / "capture.json"
            journal = probe.CaptureJournal(capture, {"jobs": [], "preflight_status": "passed"})
            job = probe.dry_job(self.fixed, self.fixed["jobs"][0])
            fake = probe.FakeClient(probe.fake_response(self.fixed["jobs"][0]))
            recorder = probe.RecordingClient(
                fake, job, before_dispatch=lambda: journal.reserve(job, {"jobs": [job]}, "reviewed"),
            )
            with patch.object(probe, "check_frozen", side_effect=RuntimeError("source pin drift")):
                with self.assertRaisesRegex(RuntimeError, "source pin drift"):
                    recorder.converse(**job["provider_request"])
            self.assertEqual(fake.requests, [])
            self.assertEqual(json.loads(capture.read_text())["jobs"], [])

    def test_drift_after_response_preserves_sanitized_reserved_capture(self):
        with tempfile.TemporaryDirectory() as directory:
            capture = Path(directory) / "capture.json"
            journal = probe.CaptureJournal(capture, {"jobs": [], "preflight_status": "passed"})
            job = probe.dry_job(self.fixed, self.fixed["jobs"][0])
            plan = {"jobs": [job]}
            fake = probe.FakeClient(probe.fake_response(self.fixed["jobs"][0]))
            recorder = probe.RecordingClient(
                fake, job, before_dispatch=lambda: journal.reserve(job, plan, "reviewed"),
                after_response=journal.record_transport,
            )
            with patch.object(probe, "check_frozen", side_effect=[None, RuntimeError("post-response drift")]):
                recorder.converse(**job["provider_request"])
                with self.assertRaisesRegex(RuntimeError, "post-response drift"):
                    probe.finalize_author_job(journal, job, recorder, {}, plan, "reviewed")
            saved = json.loads(capture.read_text())
            self.assertEqual(len(fake.requests), 1)
            self.assertEqual(saved["jobs"][0]["dispatch_status"], "provider_response_captured")
            self.assertTrue(saved["jobs"][0]["transport"]["visible_text_blocks"])
            self.assertNotIn("structure", saved["jobs"][0])

    def test_non_dict_provider_error_response_is_safely_recorded(self):
        class BadResponseError(Exception):
            response = "unexpected error response shape"

        class ErrorClient:
            def converse(self, **request):
                raise BadResponseError("secret-bearing message must not be captured")

        with tempfile.TemporaryDirectory() as directory:
            capture = Path(directory) / "capture.json"
            journal = probe.CaptureJournal(capture, {"jobs": [], "preflight_status": "passed"})
            job = probe.dry_job(self.fixed, self.fixed["jobs"][0])
            plan = {"jobs": [job]}
            recorder = probe.RecordingClient(
                ErrorClient(), job, before_dispatch=lambda: journal.reserve(job, plan, "reviewed"),
                after_response=journal.record_transport,
            )
            with patch.object(probe, "check_frozen"):
                with self.assertRaises(BadResponseError):
                    recorder.converse(**job["provider_request"])
            saved = json.loads(capture.read_text())
            observation = saved["jobs"][0]["transport"]
            self.assertEqual(observation["error_type"], "BadResponseError")
            self.assertIsNone(observation["error_code"])
            self.assertNotIn("secret-bearing", capture.read_text())

    def test_attempted_budget_retry_stops_later_jobs_after_first_capture(self):
        with tempfile.TemporaryDirectory() as directory:
            location = Path(directory)
            plan = json.loads(probe.prepare().read_text())
            capture = location / "capture.json"
            plan["capture_path"] = str(capture)
            plan["status"] = "frozen"
            plan["credential_pin"] = {"profile": "synthetic", "account_id": "000000000000",
                                      "provider_method": "synthetic"}
            (location / "plan.json").write_text(json.dumps(plan))
            frozen = SimpleNamespace(access_key="synthetic-access", secret_key="synthetic-secret",
                                     token="synthetic-token")
            provider_calls = []

            class RuntimeClient:
                meta = SimpleNamespace(endpoint_url=plan["endpoint_url"])

                def converse(self, **request):
                    provider_calls.append(request)
                    return probe.fake_response(self.fixed["jobs"][0])

            runtime = RuntimeClient()
            runtime.fixed = self.fixed

            class ProfileSession:
                def get_credentials(self):
                    return SimpleNamespace(method="synthetic", get_frozen_credentials=lambda: frozen)

            class StaticSession:
                def get_credentials(self):
                    return SimpleNamespace(method="explicit", get_frozen_credentials=lambda: frozen)

                def client(self, name, **kwargs):
                    if name == "sts":
                        return SimpleNamespace(
                            meta=SimpleNamespace(endpoint_url=plan["sts_endpoint_url"]),
                            get_caller_identity=lambda: {"Account": "000000000000"})
                    return runtime

            def session_factory(**kwargs):
                return ProfileSession() if "profile_name" in kwargs else StaticSession()

            dispatches = []

            def attempted_retry(request, client, budget):
                dispatches.append(request)
                client.converse(**plan["jobs"][0]["provider_request"])
                raise probe.ProviderCallBudgetExceededError("synthetic retry denied")

            with patch.object(probe, "HERE", location), patch.object(probe, "check_frozen"), \
                    patch.object(probe, "_generate_provider_payload", side_effect=attempted_retry), \
                    patch("boto3.Session", side_effect=session_factory):
                with self.assertRaisesRegex(RuntimeError, "budget overrun attempt"):
                    probe.execute("synthetic-plan-hash", capture)
            saved = json.loads(capture.read_text())
            self.assertEqual(len(dispatches), 1)
            self.assertEqual(len(provider_calls), 1)
            self.assertEqual(len(saved["jobs"]), 1)
            self.assertEqual(saved["jobs"][0]["runtime_outcome"], "ProviderCallBudgetExceededError")
            self.assertEqual(saved["jobs"][0]["dispatch_status"], "completed")
            self.assertTrue(saved["jobs"][0]["transport"]["visible_text_blocks"])

    def test_sts_endpoint_mismatch_blocks_identity_request(self):
        with tempfile.TemporaryDirectory() as directory:
            location = Path(directory)
            plan = json.loads(probe.prepare().read_text())
            capture = location / "capture.json"
            plan["capture_path"] = str(capture)
            plan["status"] = "frozen"
            (location / "plan.json").write_text(json.dumps(plan))
            frozen = SimpleNamespace(access_key="fake-access", secret_key="fake-secret",
                                     token="fake-token")
            identity_calls = []

            class ProfileSession:
                def get_credentials(self):
                    return SimpleNamespace(method="login", get_frozen_credentials=lambda: frozen)

            class StaticSession:
                def get_credentials(self):
                    return SimpleNamespace(method="explicit", get_frozen_credentials=lambda: frozen)

                def client(self, name, **kwargs):
                    self_outer.assertEqual(name, "sts")
                    return SimpleNamespace(
                        meta=SimpleNamespace(endpoint_url="https://unreviewed.example"),
                        get_caller_identity=lambda: identity_calls.append(True))

            self_outer = self
            def session_factory(**kwargs):
                return ProfileSession() if "profile_name" in kwargs else StaticSession()

            with patch.dict(probe.os.environ, {}, clear=True), patch.object(probe, "HERE", location), \
                    patch.object(probe, "check_frozen"), patch("boto3.Session", side_effect=session_factory):
                with self.assertRaisesRegex(RuntimeError, "STS endpoint differs from reviewed pin"):
                    probe.execute("reviewed", capture)
            self.assertEqual(identity_calls, [])
            saved = json.loads(capture.read_text())
            self.assertEqual(saved["preflight_status"], "failed")
            self.assertEqual(saved["jobs"], [])

    def test_ambient_sts_endpoint_override_refused_before_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            location = Path(directory)
            plan = json.loads(probe.prepare().read_text())
            capture = location / "capture.json"
            plan["capture_path"] = str(capture)
            (location / "plan.json").write_text(json.dumps(plan))
            with patch.dict(probe.os.environ, {"AWS_ENDPOINT_URL_STS": "https://unreviewed.example"}, clear=True), \
                    patch.object(probe, "HERE", location), patch.object(probe, "check_frozen"), \
                    patch("boto3.Session", side_effect=AssertionError("credentials must not load")):
                with self.assertRaisesRegex(RuntimeError, "endpoint overrides are prohibited"):
                    probe.execute("reviewed", capture)
            self.assertEqual(json.loads(capture.read_text())["jobs"], [])

    def test_pinned_sts_endpoint_matches_offline_sdk_client(self):
        import boto3

        with patch.dict(probe.os.environ, {}, clear=True):
            session = boto3.Session(aws_access_key_id="fake-access",
                                    aws_secret_access_key="fake-secret",
                                    region_name="us-east-1")
            self.assertEqual(session.client("sts").meta.endpoint_url,
                             probe.STS_ENDPOINT_URL)

    def test_static_signing_snapshot_equals_scanned_credentials(self):
        frozen = SimpleNamespace(access_key="fake-access", secret_key="fake-secret", token="fake-token")
        calls = []

        class FakeStaticSession:
            def __init__(self, **kwargs):
                calls.append(kwargs)

            def get_credentials(self):
                return SimpleNamespace(method="explicit", get_frozen_credentials=lambda: frozen)

        provider = SimpleNamespace(Session=FakeStaticSession)
        session = probe.static_session_for_snapshot(provider, frozen, "us-east-1")
        self.assertIsInstance(session, FakeStaticSession)
        self.assertEqual(calls, [{"aws_access_key_id": "fake-access",
                                  "aws_secret_access_key": "fake-secret",
                                  "aws_session_token": "fake-token", "region_name": "us-east-1"}])
        wrong = SimpleNamespace(access_key="rotated-access", secret_key="fake-secret", token="fake-token")

        class WrongStaticSession(FakeStaticSession):
            def get_credentials(self):
                return SimpleNamespace(method="explicit", get_frozen_credentials=lambda: wrong)

        with self.assertRaisesRegex(RuntimeError, "differ from the scanned snapshot"):
            probe.static_session_for_snapshot(SimpleNamespace(Session=WrongStaticSession),
                                              frozen, "us-east-1")

    def test_blind_projection_lock_and_unblind_require_saved_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            location = Path(directory)
            plan = json.loads(probe.prepare().read_text())
            plan["status"] = "frozen"
            plan_path = location / "plan.json"
            plan_path.write_text(json.dumps(plan))
            capture_path = location / "capture.json"
            capture = {"plan_sha256": probe.file_hash(plan_path), "jobs": []}
            for job, fixed_job in zip(plan["jobs"], self.fixed["jobs"], strict=True):
                raw = probe.fake_response(fixed_job)["output"]["message"]["content"][0]["text"]
                capture["jobs"].append({"id": job["id"], "provider_request_sha256": job["provider_request_sha256"],
                                        "dispatch_status": "completed",
                                        "transport": {"visible_text_blocks": [raw]}})
            capture_path.write_text(json.dumps(capture))
            worksheet_path = location / "worksheet.json"
            private_path = location / "private.json"
            actual_hash = probe.file_hash

            def drifted_projection_code(path):
                if path == Path(probe.__file__):
                    return "0" * 64
                return actual_hash(path)

            with self.assertRaisesRegex(RuntimeError, "out-of-band capture SHA-256"):
                probe.project_blind(capture_path, plan_path, worksheet_path, private_path, "0" * 64)
            with patch.object(probe, "file_hash", side_effect=drifted_projection_code):
                with self.assertRaisesRegex(RuntimeError, "projection code or prospective criteria drifted"):
                    probe.project_blind(capture_path, plan_path, worksheet_path, private_path,
                                        actual_hash(capture_path))
            self.assertFalse(worksheet_path.exists())
            hashes = probe.project_blind(capture_path, plan_path, worksheet_path, private_path,
                                         probe.file_hash(capture_path))
            worksheet = json.loads(worksheet_path.read_text())
            private = json.loads(private_path.read_text())
            self.assertEqual(len(worksheet["items"]), 20)
            self.assertEqual(len({item["id"] for item in worksheet["items"]}), 20)
            by_id = {item["id"]: item for item in worksheet["items"]}
            candidate_ids = [opaque_id for opaque_id, source in private["mapping"].items()
                             if source["job_id"] == "archive_circulation_count_bound_n5"
                             and source["requested_slot"]]
            self.assertEqual(len(candidate_ids), 5)
            self.assertTrue(all("stem" in by_id[opaque_id] and len(by_id[opaque_id]["choices"]) == 4
                                for opaque_id in candidate_ids))
            self.assertEqual(private["raw_shape_diagnostics"]["archive_circulation_count_bound_n5"]["missing_keys"], [])
            self.assertEqual(private["raw_shape_diagnostics"]["archive_circulation_count_bound_n5"]["extra_keys"], [])
            self.assertNotIn("correctChoice", worksheet_path.read_text())
            self.assertNotIn("explanation", worksheet_path.read_text())
            self.assertNotIn("archive_circulation_array_n5", worksheet_path.read_text())
            self.assertEqual(hashes["worksheet_sha256"], probe.file_hash(worksheet_path))
            review_a_path = location / "blind-review-a.json"
            review_b_path = location / "blind-review-b.json"
            review_a_path.write_text(json.dumps({"answers": {
                item["id"]: {"independent_answer": "A", "reasoning": "Solved the stated rule independently.",
                             "uncertain": False, "premise_sufficiency": "sufficient",
                             "choice_judgments": {"A": "correct", "B": "incorrect",
                                                  "C": "incorrect", "D": "incorrect"},
                             "pair_relations": {pair: "distinct" for pair in probe.PAIR_LABELS}}
                for item in worksheet["items"]
            }}))
            lock_path = location / "blind-lock.json"
            with self.assertRaisesRegex(RuntimeError, "Two separate blind review files"):
                probe.lock_blind_reviews(capture_path, plan_path, worksheet_path, private_path,
                                         review_a_path, review_b_path, lock_path,
                                         hashes["private_map_sha256"])
            review_b_path.write_bytes(review_a_path.read_bytes())
            with self.assertRaisesRegex(RuntimeError, "Two distinct blind reviews"):
                probe.lock_blind_reviews(capture_path, plan_path, worksheet_path, private_path,
                                         review_a_path, review_b_path, lock_path,
                                         hashes["private_map_sha256"])
            second_review = json.loads(review_b_path.read_text())
            for response in second_review["answers"].values():
                response["reasoning"] = "A separate independent judgment of this synthetic item."
            review_b_path.write_text(json.dumps(second_review))
            incomplete_review = json.loads(review_a_path.read_text())
            first_id = worksheet["items"][0]["id"]
            ambiguous = json.loads(review_a_path.read_text())
            ambiguous["answers"][first_id]["independent_answer"] = "unavailable"
            ambiguous["answers"][first_id]["premise_sufficiency"] = "insufficient"
            ambiguous["answers"][first_id]["uncertain"] = True
            ambiguous["answers"][first_id]["choice_judgments"]["B"] = "correct"
            ambiguous["answers"][first_id]["pair_relations"]["AB"] = "equivalent"
            probe.validate_blind_answers(worksheet["items"], ambiguous["answers"])
            ambiguous["answers"][first_id]["uncertain"] = False
            with self.assertRaisesRegex(RuntimeError, "invalid available-row judgment"):
                probe.validate_blind_answers(worksheet["items"], ambiguous["answers"])
            original_review = json.loads(review_a_path.read_text())
            for field, value in (("premise_sufficiency", "insufficient"),
                                 ("second_correct", True), ("equivalent_pair", True)):
                contradictory = json.loads(json.dumps(original_review))
                answer = contradictory["answers"][first_id]
                if field == "second_correct":
                    answer["choice_judgments"]["B"] = "correct"
                elif field == "equivalent_pair":
                    answer["pair_relations"]["AB"] = "equivalent"
                else:
                    answer[field] = value
                with self.assertRaisesRegex(RuntimeError, "invalid available-row judgment"):
                    probe.validate_blind_answers(worksheet["items"], contradictory["answers"])
            del incomplete_review["answers"][first_id]["pair_relations"]["AB"]
            review_a_path.write_text(json.dumps(incomplete_review))
            with self.assertRaisesRegex(RuntimeError, "exact choice and pair judgments"):
                probe.lock_blind_reviews(capture_path, plan_path, worksheet_path, private_path,
                                        review_a_path, review_b_path, lock_path, hashes["private_map_sha256"])
            incomplete_review["answers"][first_id]["pair_relations"]["AB"] = "distinct"
            del incomplete_review["answers"][first_id]["choice_judgments"]["D"]
            review_a_path.write_text(json.dumps(incomplete_review))
            with self.assertRaisesRegex(RuntimeError, "exact choice and pair judgments"):
                probe.lock_blind_reviews(capture_path, plan_path, worksheet_path, private_path,
                                        review_a_path, review_b_path, lock_path, hashes["private_map_sha256"])
            incomplete_review["answers"][first_id]["choice_judgments"]["D"] = "incorrect"
            del incomplete_review["answers"][first_id]["premise_sufficiency"]
            review_a_path.write_text(json.dumps(incomplete_review))
            with self.assertRaisesRegex(RuntimeError, "exact choice and pair judgments"):
                probe.lock_blind_reviews(capture_path, plan_path, worksheet_path, private_path,
                                        review_a_path, review_b_path, lock_path, hashes["private_map_sha256"])
            incomplete_review["answers"][first_id]["premise_sufficiency"] = "sufficient"
            review_a_path.write_text(json.dumps(incomplete_review))
            original_private = private_path.read_bytes()
            for tampered_field, replacement in (("author_key", "b"),
                                                 ("author_explanation", "altered teaching"),
                                                 ("display_to_source_choice", ["d", "c", "b", "a"]),
                                                 ("original_row_position", 99)):
                tampered = json.loads(original_private)
                tampered["mapping"][first_id][tampered_field] = replacement
                private_path.write_text(json.dumps(tampered))
                with self.assertRaisesRegex(RuntimeError, "out-of-band private-map SHA-256"):
                    probe.lock_blind_reviews(capture_path, plan_path, worksheet_path, private_path,
                                            review_a_path, review_b_path, lock_path, hashes["private_map_sha256"])
                with self.assertRaisesRegex(RuntimeError, "differs from capture"):
                    probe.lock_blind_reviews(capture_path, plan_path, worksheet_path, private_path,
                                            review_a_path, review_b_path, lock_path, probe.file_hash(private_path))
                private_path.write_bytes(original_private)
            lock_hash = probe.lock_blind_reviews(capture_path, plan_path, worksheet_path, private_path,
                                                review_a_path, review_b_path, lock_path, hashes["private_map_sha256"])
            unblinded = location / "unblinded.json"
            with self.assertRaisesRegex(RuntimeError, "exact saved blind-lock hash"):
                probe.unblind_review(capture_path, plan_path, worksheet_path, private_path, review_a_path, review_b_path,
                                     lock_path, "wrong", unblinded)
            original_b = review_b_path.read_bytes()
            second_review["answers"][first_id]["reasoning"] = "Changed after the joint lock."
            review_b_path.write_text(json.dumps(second_review))
            with self.assertRaisesRegex(RuntimeError, "Blind artifacts changed after lock"):
                probe.unblind_review(capture_path, plan_path, worksheet_path, private_path,
                                     review_a_path, review_b_path, lock_path, lock_hash, unblinded)
            review_b_path.write_bytes(original_b)
            probe.unblind_review(capture_path, plan_path, worksheet_path, private_path, review_a_path, review_b_path,
                                 lock_path, lock_hash, unblinded)
            joined = json.loads(unblinded.read_text())
            self.assertEqual(len(joined["items"]), 20)
            self.assertTrue(all(set(item["blind_reviews"]) == {"a", "b"} for item in joined["items"]))

    def test_blind_projection_preserves_missing_and_extra_map_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            location = Path(directory)
            plan = json.loads(probe.prepare().read_text())
            plan["status"] = "frozen"
            plan_path = location / "plan.json"
            plan_path.write_text(json.dumps(plan))
            capture_path = location / "capture.json"
            capture = {"plan_sha256": probe.file_hash(plan_path), "jobs": []}
            for job, fixed_job in zip(plan["jobs"], self.fixed["jobs"], strict=True):
                raw = probe.fake_payload(fixed_job["author_mode"], fixed_job["cardinality_contract"],
                                         fixed_job["payload"]["targetCount"])
                if job["id"] == "archive_circulation_count_bound_n5":
                    del raw["questions"]["2"]
                    raw["questions"]["extra"] = probe.fake_row(99)
                capture["jobs"].append({"id": job["id"], "provider_request_sha256": job["provider_request_sha256"],
                                        "dispatch_status": "completed",
                                        "transport": {"visible_text_blocks": [json.dumps(raw)]}})
            capture_path.write_text(json.dumps(capture))
            worksheet_path = location / "worksheet.json"
            private_path = location / "private.json"
            probe.project_blind(capture_path, plan_path, worksheet_path, private_path,
                                probe.file_hash(capture_path))
            worksheet = json.loads(worksheet_path.read_text())
            private = json.loads(private_path.read_text())
            self.assertEqual(sum(item["requested_slot"] for item in worksheet["items"]), 20)
            self.assertEqual(len(worksheet["items"]), 21)
            candidate = private["raw_shape_diagnostics"]["archive_circulation_count_bound_n5"]
            self.assertEqual(candidate["missing_keys"], ["2"])
            self.assertEqual(candidate["extra_keys"], ["extra"])
            self.assertTrue(any(source["raw_question_key"] == "extra" and not source["requested_slot"]
                                for source in private["mapping"].values()))

    def test_incomplete_capture_keeps_all_four_five_slot_denominators_without_worksheet(self):
        with tempfile.TemporaryDirectory() as directory:
            location = Path(directory)
            plan = json.loads(probe.prepare().read_text())
            plan["status"] = "frozen"
            plan_path = location / "plan.json"
            plan_path.write_text(json.dumps(plan))
            capture_path = location / "capture.json"
            capture = {"plan_sha256": probe.file_hash(plan_path), "jobs": [{
                "id": plan["jobs"][0]["id"], "dispatch_status": "completed",
                "provider_request_sha256": plan["jobs"][0]["provider_request_sha256"],
            }]}
            capture_path.write_text(json.dumps(capture))
            worksheet_path = location / "worksheet.json"
            private_path = location / "private.json"
            with self.assertRaisesRegex(RuntimeError, "Capture incomplete; no blind worksheet"):
                probe.project_blind(capture_path, plan_path, worksheet_path, private_path,
                                    probe.file_hash(capture_path))
            denominator = probe.incomplete_capture_denominator(plan, capture)
            self.assertEqual([part["requested_original_slots"] for part in denominator.values()], [5] * 4)
            self.assertEqual([part["favorable_trial_credit"] for part in denominator.values()], [0] * 4)
            self.assertFalse(worksheet_path.exists())

    def test_plan_document_pin_rejects_assessment_drift(self):
        draft = json.loads(probe.prepare().read_text())
        draft["status"] = "frozen"
        draft["credential_pin"] = {"profile": "fake", "account_id": "000000000000",
                                   "provider_method": "explicit"}
        actual_hash = probe.file_hash

        def tampered_hash(path):
            if path == HERE / "PLAN.md":
                return "0" * 64
            return actual_hash(path)

        with patch.object(probe, "file_hash", side_effect=tampered_hash):
            with self.assertRaisesRegex(RuntimeError, "assessment criteria document drifted"):
                probe.check_frozen(draft, "unreachable")

    def test_candidate_cannot_execute_and_prepare_never_constructs_aws_client(self):
        with patch.dict("sys.modules", {"boto3": None}):
            draft_path = probe.prepare()
        draft = json.loads(draft_path.read_text())
        self.assertEqual(draft["status"], "candidate")
        self.assertEqual(draft["limits"]["maximum_bedrock_author_calls"], 4)
        self.assertEqual(draft["credential_pin"], {"profile": "default", "account_id": "239342516379",
                                                    "provider_method": "login"})
        self.assertEqual(draft["criteria"]["prose_replication"]["primary_novelty_scope"],
                         "within_each_five_row_arm_only")
        self.assertEqual(draft["criteria"]["prose_replication"]["cross_arm_novelty"],
                         "separate_sensitivity_only")
        with self.assertRaisesRegex(RuntimeError, "reviewed frozen plan"):
            probe.check_frozen(draft, "0" * 64)

    def test_frozen_proposal_passes_all_offline_pins(self):
        proposal_path = HERE / "plan-frozen-proposal.json"
        proposal = json.loads(proposal_path.read_text())
        expected_hash = "7599074d82324d8394f584dfb9dd15ac5577d1111a6f41d4f978e1b3a546aeca"
        self.assertEqual(probe.file_hash(proposal_path), expected_hash)
        self.assertEqual(proposal["status"], "frozen")
        self.assertEqual(proposal["source_revision"], probe.SOURCE_REVISION)
        self.assertEqual(proposal["sts_endpoint_url"], probe.STS_ENDPOINT_URL)
        self.assertEqual(proposal["criteria"]["blind_projection"]["required_independent_reviews"], 2)
        self.assertEqual({**json.loads(probe.prepare().read_text()), "status": "frozen"}, proposal)
        self.assertEqual(proposal["criteria"]["prose_replication"]["candidate_followup_minimum_usable_total"], 8)
        self.assertEqual(proposal["criteria"]["prose_replication"]["candidate_followup_minimum_pairs_not_below_baseline"], 2)
        original_hash = probe.file_hash

        def proposal_as_live_path(path):
            return original_hash(proposal_path if path == HERE / "plan.json" else path)

        with patch.object(probe, "file_hash", side_effect=proposal_as_live_path):
            probe.check_frozen(proposal, expected_hash)


if __name__ == "__main__":
    unittest.main()
