"""Socket-free replay of the source-pinned generic full-worker harness."""

import copy
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import live_probe as probe

sys.path.insert(0, str(probe.SERVICE / "tests"))
from test_native_pipeline import (  # noqa: E402
    ScriptedNativeClient, author_payload, authored_issue_flags,
    solver_map, solver_record, task_data,
)


class LiveGenericReserveProbeTests(unittest.TestCase):
    def setUp(self):
        self.plan = probe.build_plan()
        self.questions = []
        for index in range(7):
            marked = index + 1
            total = index + 8
            answer = f"{marked}/{total}"
            choices = [answer, f"{marked + 1}/{total}",
                       f"{marked}/{total + 1}", f"{total}/{marked}"]
            choices = choices[index % 4:] + choices[:index % 4]
            self.questions.append({
                "prompt": f"A fair spinner has {total} equal sectors, {marked} of them blue. What is the chance of blue?",
                "choices": choices, "expectedAnswer": answer,
                "explanation": f"There are {marked} blue sectors out of {total} equally likely sectors, so the ratio is {answer}.",
                "topic": "Probability", "difficulty": 3, "format": "Multiple Choice",
            })

    def scripted(self, *, reviewer_rejected=(), solver_rejected=(),
                 sanitizer_rejected=(), authored_prompt_overrides=None,
                 authored_question_overrides=None,
                 expected_sanitized_sources=None, usage_canary=None, response_canary=None):
        author_rows = copy.deepcopy(self.questions)
        for ordinal, update in (authored_question_overrides or {}).items():
            author_rows[ordinal].update(copy.deepcopy(update))
        for ordinal in sanitizer_rejected:
            author_rows[ordinal]["difficulty"] = 1
        for ordinal, source in (authored_prompt_overrides or {}).items():
            author_rows[ordinal]["prompt"] = self.questions[source]["prompt"]
        sanitized_sources = (list(expected_sanitized_sources)
                             if expected_sanitized_sources is not None
                             else [index for index in range(7)
                                   if index not in sanitizer_rejected])
        originals = {question["prompt"]: question for question in author_rows}
        source_ordinals = {question["prompt"]: index for index, question in enumerate(author_rows)}
        reviewer_rejected = set(reviewer_rejected)
        solver_rejected = set(solver_rejected)

        def solve(request):
            items = task_data(request, "question_solution_json")["items"]
            records = []
            for item in items:
                self.assertNotIn("expectedAnswer", item)
                record = solver_record(item, originals[item["prompt"]]["expectedAnswer"])
                if source_ordinals[item["prompt"]] in solver_rejected:
                    for choice in record["choices"].values():
                        choice["judgment"] = "refuted"
                records.append(record)
            return solver_map(*records)

        def review(request):
            data = task_data(request, "question_review_json")
            items = data["items"]
            history = data["existingQuestions"]
            second_batch_prompts = {author_rows[ordinal]["prompt"]
                                    for ordinal in sanitized_sources[4:]}
            if items[0]["prompt"] in second_batch_prompts:
                self.assertEqual([entry["prompt"] for entry in history],
                                 [author_rows[ordinal]["prompt"]
                                  for ordinal in sanitized_sources[:4]
                                  if ordinal not in reviewer_rejected
                                  and ordinal not in solver_rejected])
                self.assertTrue(all("expectedAnswer" not in entry and "choices" not in entry
                                    for entry in history))
            else:
                self.assertEqual(history, [])
            rows = {}
            for item in items:
                original = originals[item["prompt"]]
                self.assertNotIn("expectedAnswer", item)
                rows[str(item["index"])] = {
                    "valid": source_ordinals[item["prompt"]] not in reviewer_rejected,
                    "answer": original["expectedAnswer"], "difficulty": 3,
                    "explanationSupport": "supported",
                    "issueFlags": authored_issue_flags(),
                }
            return {"reviews": rows}

        scripted_calls = [("question_author_v4_n7", author_payload(*author_rows))]
        for batch in (sanitized_sources[:4], sanitized_sources[4:]):
            scripted_calls.append((f"complete_choice_solver_v5_n{len(batch)}", solve))
            survivor_count = len(set(batch) - solver_rejected)
            if survivor_count:
                scripted_calls.append((f"authored_solution_reviewer_v3_n{survivor_count}", review))
        script = ScriptedNativeClient(*scripted_calls)

        class FakeClient:
            def __init__(self, config):
                self.meta = SimpleNamespace(
                    endpoint_url=probe.ENDPOINT, region_name="us-east-1", config=config)

            def converse(self, **wire):
                response = script.converse(**wire)
                if usage_canary:
                    response["usage"]["untrustedCanary"] = usage_canary
                if response_canary:
                    response["output"]["message"]["content"][0]["text"] = json.dumps({
                        "credential_echo": response_canary})
                return response

        return script, lambda _service, **kwargs: FakeClient(kwargs["config"])

    def replay(self, **kwargs):
        script, factory = self.scripted(**kwargs)
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name) / "capture.json"
        capture = probe.new_capture(self.plan)
        probe.save(path, capture, exclusive=True)
        row = probe.run_job(self.plan, capture, path, factory, lambda: None,
                            secrets=(kwargs["response_canary"],)
                            if kwargs.get("response_canary") else ())
        return script, row, capture, path

    def test_offline_plan_pins_native_seven_author_wire(self):
        plan = self.plan
        self.assertEqual(plan["source_commit"], probe.SOURCE_COMMIT)
        self.assertEqual(plan["author_contract_name"], "question_author_v4_n7")
        self.assertEqual(plan["native_author_schema_bytes"], 1117)
        self.assertEqual(plan["native_author_schema_sha256"],
                         "48c4cebb7cf7478f7a049d9ca795ce366b3cb4f47488ac05f1301a10b6a34408")
        self.assertEqual(plan["author_wire_sha256"],
                         "6acf130d9bab1dfedea157c2ca8249f98ceb84111bca45d115fff970d62d47db")
        self.assertEqual(plan["author_wire"]["inferenceConfig"],
                         {"maxTokens": 6000, "temperature": 0.2})
        self.assertEqual(plan["author_wire"]["additionalModelRequestFields"],
                         {"thinking": {"type": "disabled"}})
        baseline_plan = json.loads((probe.HERE.parent /
                                    "generic-reserve-seven-probe-v4-20260927/plan.json").read_text())
        self.assertEqual(plan["request"], baseline_plan["request"])
        self.assertEqual(plan["environment"], baseline_plan["environment"])
        self.assertEqual(plan["limits"], baseline_plan["limits"])
        self.assertEqual(plan["prespecified_gate"], baseline_plan["prespecified_gate"])
        self.assertEqual(plan["blind_review"], baseline_plan["blind_review"])
        self.assertEqual(plan["native_author_schema_sha256"],
                         baseline_plan["native_author_schema_sha256"])
        self.assertEqual(plan["author_wire"], baseline_plan["author_wire"])

    def test_seven_original_rows_return_earliest_five_verified(self):
        script, row, capture, path = self.replay()
        self.assertEqual(len(script.calls), 5)
        self.assertTrue(all(call["inferenceConfig"] == {"maxTokens": 6000,
                                                        "temperature": 0.2}
                            and call["additionalModelRequestFields"] == {
                                "thinking": {"type": "disabled"}}
                            for call in script.calls))
        self.assertEqual(row["status"], "finished")
        self.assertEqual(row["returned_source_ordinals"], [0, 1, 2, 3, 4])
        self.assertEqual(row["accepted_source_ordinals"], list(range(7)))
        self.assertEqual(row["stage_names"], [
            "question_author_v4_n7", "complete_choice_solver_v5_n4",
            "authored_solution_reviewer_v3_n4", "complete_choice_solver_v5_n3",
            "authored_solution_reviewer_v3_n3",
        ])
        self.assertEqual([batch["input_count"] for batch in row["verifier_batches"]], [4, 3])
        self.assertEqual([item["status"] for item in capture["original_rows"]],
                         ["returned"] * 5 + ["unfilled_verified"] * 2)
        self.assertEqual([item["status"] for item in capture["call_slots"][:5]],
                         ["completed"] * 5)
        self.assertEqual(len(capture["reservations"]), 5)
        self.assertEqual(json.loads(path.read_text())["jobs"][0]["provider_calls"], 5)

    def test_production_pin_callback_does_not_reenter_patched_author_stage(self):
        """Use the execute callback and real SDK metadata; Converse stays local."""
        script, _ = self.scripted()
        session = probe.boto3.Session(
            aws_access_key_id="OFFLINE_TEST_KEY",
            aws_secret_access_key="OFFLINE_TEST_SECRET",
            region_name="us-east-1",
        )

        def factory(*args, **kwargs):
            client = session.client(*args, **kwargs)
            client.converse = script.converse
            return client

        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            plan_path = directory / "plan.json"
            frozen = {**self.plan, "state": "frozen"}
            probe.save(plan_path, frozen, exclusive=True)
            capture_path = directory / "capture.json"
            capture = probe.new_capture(frozen)
            probe.save(capture_path, capture, exclusive=True)
            with patch.object(probe, "PLAN", plan_path), \
                    patch.object(probe, "author_wire", side_effect=AssertionError(
                        "Live pin check re-entered the offline author stage.")):
                row = probe.run_job(
                    frozen, capture, capture_path, factory,
                    probe.production_pin_callback(frozen, probe.file_hash(plan_path)),
                )
            self.assertEqual(row["status"], "finished")
            self.assertIsNone(capture["global_stop"])
            self.assertEqual(len(capture["reservations"]), 5)
            self.assertEqual(len(capture["calls"]), 5)
            self.assertEqual(len(script.calls), 5)
            self.assertTrue(all(call["inferenceConfig"] == {"maxTokens": 6000,
                                                            "temperature": 0.2}
                                and call["additionalModelRequestFields"] == {
                                    "thinking": {"type": "disabled"}}
                                for call in script.calls))
            self.assertEqual(row["returned_source_ordinals"], [0, 1, 2, 3, 4])

    def test_two_rejections_use_later_source_rows_without_relabeling(self):
        _, row, capture, _ = self.replay(reviewer_rejected={1, 4})
        self.assertEqual(row["returned_source_ordinals"], [0, 2, 3, 5, 6])
        self.assertEqual(row["accepted_source_ordinals"], [0, 2, 3, 5, 6])
        self.assertEqual(capture["original_rows"][1]["status"], "unfilled_sanitized")

    def test_code_owned_expected_money_gate_filters_verified_repeat(self):
        money_rows = {
            0: {
                "prompt": "A game pays $8 if a fair coin lands heads and $0 if it lands tails. Each play costs $3. What is the expected net gain per play?",
                "choices": ["$1", "$4", "-$1", "$0"],
                "expectedAnswer": "$1",
                "explanation": "Half of $8 minus the $3 cost is $1.",
            },
            1: {
                "prompt": "A lottery ticket wins $50 with probability 1/20 and wins nothing otherwise. What is the expected value of the winnings from one ticket?",
                "choices": ["$2.50", "$5.00", "$0.50", "$50.00"],
                "expectedAnswer": "$2.50",
                "explanation": "The expected winnings are (1/20) times $50, or $2.50.",
            },
        }
        script, row, capture, _ = self.replay(authored_question_overrides=money_rows)
        self.assertEqual(len(script.calls), 5)
        self.assertEqual(row["verified_source_ordinals"], list(range(7)))
        self.assertEqual(row["accepted_source_ordinals"], [0, 2, 3, 4, 5, 6])
        self.assertEqual(row["returned_source_ordinals"], [0, 2, 3, 4, 5])
        self.assertEqual(row["metrics"]["QuestionQuality"]["reserve"],
                         {"repeated_expected_money": 1})
        self.assertEqual(capture["original_rows"][1]["status"],
                         "unfilled_diversity_filtered")
        self.assertEqual(probe.finish(capture)["qualification"], "pending_content_review")

    def test_six_sanitized_rows_use_four_plus_two_and_return_earliest_five(self):
        script, row, capture, _ = self.replay(sanitizer_rejected={6})
        self.assertEqual(len(script.calls), 5)
        self.assertEqual(row["status"], "finished")
        self.assertEqual(row["returned_source_ordinals"], [0, 1, 2, 3, 4])
        self.assertEqual(row["stage_names"][3], "complete_choice_solver_v5_n2")
        self.assertEqual([batch["source_ordinals"] for batch in row["verifier_batches"]],
                         [[0, 1, 2, 3], [4, 5]])
        self.assertEqual(probe.finish(capture)["qualification"], "pending_content_review")

    def test_five_sanitized_rows_use_four_plus_one_and_return_all_five(self):
        script, row, capture, _ = self.replay(sanitizer_rejected={5, 6})
        self.assertEqual(len(script.calls), 5)
        self.assertEqual(row["returned_source_ordinals"], [0, 1, 2, 3, 4])
        self.assertEqual(row["stage_names"][3], "complete_choice_solver_v5_n1")
        self.assertEqual([batch["source_ordinals"] for batch in row["verifier_batches"]],
                         [[0, 1, 2, 3], [4]])
        self.assertEqual(probe.finish(capture)["qualification"], "pending_content_review")

    def test_first_invalid_later_valid_duplicate_authored_stem_keeps_later_source(self):
        script, row, capture, _ = self.replay(
            sanitizer_rejected={0}, authored_prompt_overrides={0: 5},
            expected_sanitized_sources=[1, 2, 3, 4, 5, 6],
        )
        self.assertEqual(len(script.calls), 5)
        self.assertEqual(row["returned_source_ordinals"], [1, 2, 3, 4, 5])
        self.assertEqual([batch["source_ordinals"] for batch in row["verifier_batches"]],
                         [[1, 2, 3, 4], [5, 6]])
        self.assertEqual(capture["original_rows"][0]["status"], "unfilled_authored")
        self.assertEqual(probe.finish(capture)["qualification"], "pending_content_review")

    def test_underfilled_job_stays_failed_without_second_author_call(self):
        script, row, capture, _ = self.replay(reviewer_rejected={0, 2, 4})
        self.assertEqual(len(script.calls), 5)
        self.assertEqual(row["returned"], [])
        self.assertEqual(row["returned_source_ordinals"], [])
        self.assertEqual(len(row["accepted_source_ordinals"]), 4)
        self.assertTrue(all(item["status"] != "returned" for item in capture["original_rows"]))

    def test_solver_provider_failure_is_terminal_without_retry_or_second_job(self):
        script, factory = self.scripted()
        script.steps[1] = ("complete_choice_solver_v5_n4", RuntimeError("offline solver failure"))
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "capture.json"
            capture = probe.new_capture(self.plan)
            probe.save(path, capture, exclusive=True)
            row = probe.run_job(self.plan, capture, path, factory, lambda: None)
        self.assertEqual(row["status"], "failed")
        self.assertEqual(row["returned"], [])
        self.assertEqual(len(script.calls), len(capture["reservations"]))
        self.assertEqual(len(script.calls), 2)
        self.assertEqual(len(capture["jobs"]), 1)
        self.assertEqual(probe.finish(capture)["qualification"], "failed")

    def test_first_chunk_total_solver_rejection_still_checks_later_sources_and_fails_closed(self):
        script, row, capture, _ = self.replay(solver_rejected={0, 1, 2, 3})
        self.assertEqual(len(script.calls), 4)
        self.assertEqual(row["stage_names"], [
            "question_author_v4_n7", "complete_choice_solver_v5_n4",
            "complete_choice_solver_v5_n3", "authored_solution_reviewer_v3_n3",
        ])
        self.assertEqual(row["returned"], [])
        self.assertEqual(row["accepted_source_ordinals"], [4, 5, 6])
        self.assertEqual(probe.finish(capture)["qualification"], "failed")

    def test_capture_bounds_untrusted_usage_and_refuses_visible_credential_echo(self):
        _, row, _, path = self.replay(usage_canary="UNTRUSTED_USAGE_CANARY")
        self.assertEqual(row["status"], "finished")
        self.assertNotIn("UNTRUSTED_USAGE_CANARY", path.read_text())
        secret = "FAKE_CREDENTIAL_ECHO_CANARY"
        _, row, _, path = self.replay(response_canary=secret)
        self.assertEqual(row["status"], "failed")
        self.assertNotIn(secret, path.read_text())

    def test_capture_tamper_and_missing_review_lock_block_before_aws(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            capture_path = directory / "capture.json"
            probe.save(capture_path, probe.new_capture(self.plan), exclusive=True)
            capture_path.write_text("{}")
            with self.assertRaises(probe.IntegrityError):
                probe.check_capture(capture_path)
            plan_path = directory / "plan.json"
            probe.save(plan_path, {**self.plan, "state": "frozen"}, exclusive=True)
            with patch.object(probe, "PLAN", plan_path), \
                    patch.object(probe, "REVIEW_LOCK", directory / "missing-review.json"):
                with self.assertRaises(probe.IntegrityError):
                    probe.launch_precheck()
            self.assertFalse((directory / "launch-precheck-attempt.json").exists())

    def test_five_returned_cannot_hide_late_global_failure(self):
        _, row, capture, _ = self.replay()
        self.assertEqual(row["status"], "finished")
        self.assertEqual(probe.finish(capture)["qualification"], "pending_content_review")
        capture["global_stop"] = "late_failure"
        self.assertEqual(probe.finish(capture)["qualification"], "failed")
        capture["global_stop"] = None
        capture["status"] = "deadline_exceeded"
        self.assertEqual(probe.finish(capture)["qualification"], "failed")

    def test_five_returned_cannot_hide_low_or_malformed_difficulty_and_choices(self):
        _, _, capture, _ = self.replay()
        self.assertEqual(probe.finish(capture)["qualification"], "pending_content_review")
        for change in (
            {"difficulty": 1},
            {"difficulty": "3"},
            {"choices": ["1", "1", "2", "3"]},
            {"expectedAnswer": "not offered"},
        ):
            with self.subTest(change=change):
                damaged = copy.deepcopy(capture)
                damaged["jobs"][0]["returned"][2].update(change)
                self.assertEqual(probe.finish(damaged)["qualification"], "failed")

    def test_five_returned_cannot_hide_batch_source_or_solver_count_drift(self):
        _, _, capture, _ = self.replay(sanitizer_rejected={6})
        self.assertEqual(probe.finish(capture)["qualification"], "pending_content_review")
        for change in ("source_membership", "solver_count", "authored_identity"):
            with self.subTest(change=change):
                damaged = copy.deepcopy(capture)
                if change == "source_membership":
                    damaged["jobs"][0]["verifier_batches"][1]["source_ordinals"] = [3, 5]
                elif change == "solver_count":
                    damaged["jobs"][0]["stage_names"][3] = "complete_choice_solver_v5_n3"
                else:
                    damaged["original_rows"][6]["ordinal"] = 5
                self.assertEqual(probe.finish(damaged)["qualification"], "failed")

    def test_expired_deadline_refuses_before_provider_or_capture_mutation(self):
        script, factory = self.scripted()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "capture.json"
            capture = probe.new_capture(self.plan)
            probe.save(path, capture, exclusive=True)
            deadline = probe.Deadline(lambda: 1_000.0)
            deadline.started = 0.0
            with self.assertRaises(probe.IntegrityError):
                probe.run_job(self.plan, capture, path, factory, lambda: None,
                              deadline=deadline)
            self.assertEqual(script.calls, [])
            self.assertEqual(capture["jobs"], [])

    def test_endpoint_drift_refuses_before_scripted_provider_call(self):
        script, factory = self.scripted()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "capture.json"
            capture = probe.new_capture(self.plan)
            probe.save(path, capture, exclusive=True)

            def wrong_endpoint(*args, **kwargs):
                client = factory(*args, **kwargs)
                client.meta.endpoint_url = "https://unreviewed.invalid"
                return client

            row = probe.run_job(self.plan, capture, path, wrong_endpoint,
                                lambda: None)
            self.assertEqual(row["status"], "failed")
            self.assertEqual(script.calls, [])
            self.assertEqual(capture["global_stop"], "request_or_provenance_integrity")


if __name__ == "__main__":
    unittest.main()
