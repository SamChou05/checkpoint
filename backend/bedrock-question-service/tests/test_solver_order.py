"""Exercise actual ordering interventions and unchanged gates without inference."""
import copy
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import complete_question_solution
from evals import checkpoint_solver_order as trial
from test_runtime_qualification import completed


@contextmanager
def historical_order_contract():
    """Exercise the archived trial's prompt/schema, not the new production order.

    Production trial code and its source/prompt admission guards stay unchanged.
    """
    path = trial.ROOT / "docs/evidence/solver-order-preparation-20260910/prepared-plan.json"
    archived_bytes = path.read_bytes()
    if hashlib.sha256(archived_bytes).hexdigest() != "3b31d7009563183b6cc8c071465028dcf1ad48b13e2cd0d7d9ab47c3431d7c97":
        raise AssertionError("Historical ordering plan fixture changed.")
    job = json.loads(archived_bytes)["jobs"][0]
    if job["arm"] != "judgment_first":
        raise AssertionError("Historical ordering control changed.")
    native_system = job["request"]["system"][0]["text"]
    native_suffix = trial.native.native_prompt("", trial.CONTRACT)
    if not native_system.endswith(native_suffix):
        raise AssertionError("Historical native prompt suffix changed.")
    system = native_system[:-len(native_suffix)]
    config = job["request"]["outputConfig"]
    current_config = trial.native.native_output_config

    def archived_config(contract):
        return copy.deepcopy(config) if contract == trial.CONTRACT else current_config(contract)

    with patch.object(complete_question_solution, "COMPLETE_SOLUTION_SYSTEM_PROMPT", system), patch.object(
        trial.native, "native_output_config", side_effect=archived_config,
    ):
        yield


class SolverOrderTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(historical_order_contract())
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.output = self.directory / "capture"
        self.path = self.directory / "plan.json"
        patcher = patch.object(trial, "_source_snapshot", return_value={"source_revision": "a" * 40})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.plan = trial.make_plan()
        trial.shared.write_json(self.path, self.plan)

    def value(self, job):
        order = ("choice", "judgment", "reason") if job["arm"] == "judgment_first" else ("choice", "reason", "judgment")
        records = []
        for item in job["batch"]["subject"]["items"]:
            rows = []
            for choice in item["choices"]:
                row = {"choice": choice, "judgment": "refuted", "reason": "Scripted test only."}
                rows.append({key: row[key] for key in order})
            records.append({"index": item["index"], "choices": rows})
        return {"solutions": records}

    def observer(self, request, *, on_progress, **kwargs):
        report = json.loads((self.output / "capture.json").read_text())
        call = report["calls"][-1]
        job = self.plan["jobs"][call["position"]]
        self.assertEqual(call["status"], "launch_intent")
        self.assertEqual(job["request"], request)
        state = completed(self.value(job))
        on_progress(state)
        return state

    def test_only_example_and_equivalent_schema_order_change(self):
        self.assertEqual(len(self.plan["jobs"]), 32)
        for index in range(0, 32, 2):
            a, b = sorted(self.plan["jobs"][index:index + 2], key=lambda j: j["arm"])
            self.assertEqual(a["arm"], "judgment_first")
            self.assertEqual(b["arm"], "reason_first")
            first, second = copy.deepcopy(a["request"]), copy.deepcopy(b["request"])
            schema_a = first.pop("outputConfig")["textFormat"]["structure"]["jsonSchema"]
            schema_b = second.pop("outputConfig")["textFormat"]["structure"]["jsonSchema"]
            self.assertEqual(json.loads(schema_a["schema"]), json.loads(schema_b["schema"]))
            def order(wrapper):
                return list(json.loads(wrapper["schema"])["properties"]["solutions"]["items"]["properties"]["choices"]["items"]["properties"])
            self.assertEqual(order(schema_a), ["choice", "judgment", "reason"])
            self.assertEqual(order(schema_b), ["choice", "reason", "judgment"])
            second["system"][0]["text"] = second["system"][0]["text"].replace(trial.NEW_EXAMPLE, trial.OLD_EXAMPLE)
            self.assertEqual(first, second)
            self.assertEqual(first["inferenceConfig"], {"maxTokens": 6000, "temperature": .2})
            self.assertEqual(first["additionalModelRequestFields"], {"thinking": {"type": "disabled"}})
        self.assertEqual(self.plan["jobs"][0]["request"], self.plan["jobs"][17]["request"])
        self.assertEqual(self.plan["jobs"][1]["request"], self.plan["jobs"][16]["request"])

    def test_dry_plan_and_unchanged_subject_have_no_key_leakage(self):
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No SDK")), patch.object(
            trial.probe.caller, "observe_request", side_effect=AssertionError("No inference"),
        ), patch("builtins.print"):
            trial.main(["--directory", str(self.directory / "dry")])
        for job in self.plan["jobs"]:
            subject = trial.probe._subject(job["request"], "solver")
            self.assertEqual(subject, job["batch"]["subject"])
            for item in subject["items"]:
                self.assertFalse({"expectedAnswer", "key", "explanation", "assessment"} & set(item))

    def test_existing_gates_and_emitted_order_are_recorded_without_prose_repair(self):
        job = self.plan["jobs"][0]
        value = self.value(job)
        for row in value["solutions"][0]["choices"]:
            row["reason"] = "This exact choice IS correct — supported."
        result = trial.content_observation(job, completed(value))
        self.assertEqual(result["stage_validation"], "passed")
        self.assertEqual(result["items"][0]["rejection_reason"], "solver_zero_supported")
        self.assertEqual(result["items"][0]["judgment_reason_consistency"], "unassessed")
        self.assertEqual(result["emitted_row_orders"][0], ["choice", "judgment", "reason"])

    def test_malformed_batch_is_format_loss_not_a_factual_catch(self):
        job = self.plan["jobs"][0]
        value = self.value(job)
        value["solutions"][0]["choices"][0]["choice"] += " altered"
        result = trial.content_observation(job, completed(value))
        self.assertEqual(result["stage_validation"], "rejected")
        self.assertEqual(result["items"], [])
        self.assertEqual(result["semantic_assessment"], "unassessed")

    def test_complete_fixed_run_is_durable_and_cannot_be_repeated_elsewhere(self):
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No SDK")):
            report = trial.run_trial(self.path, trial._hash(self.plan), self.output, observer=self.observer)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(report["calls"]), 32)
        self.assertTrue(all(r["stage_validation"] == "passed" for r in report["results"]))
        observer = Mock(side_effect=AssertionError("No repeat"))
        with self.assertRaises(FileExistsError):
            trial.run_trial(self.path, trial._hash(self.plan), self.directory / "elsewhere", observer=observer)
        observer.assert_not_called()

    def test_plan_tampering_stops_before_claim_or_dispatch(self):
        changed = copy.deepcopy(self.plan)
        changed["jobs"][0]["request"]["inferenceConfig"]["maxTokens"] = 16000
        trial.shared.write_json(self.path, changed)
        with self.assertRaises(ValueError):
            trial.run_trial(self.path, trial._hash(changed), self.output, observer=Mock())
        self.assertFalse(self.path.with_name(self.path.name + ".execution-claim.json").exists())

    def test_independent_subject_binding_and_disagreement_fail_preparation(self):
        original = json.loads(trial.CONTROL_REVIEW.read_text())
        for change in (lambda r: r.update(packet_sha256="0" * 64),
                       lambda r: r["batches"][0]["items"][0]["choices"][0].update(status="uncertain")):
            altered = copy.deepcopy(original)
            change(altered)
            path = self.directory / "altered-review.json"
            trial.shared.write_json(path, altered)
            with patch.object(trial, "CONTROL_REVIEW", path), self.assertRaises(ValueError):
                trial.make_plan()

    def test_operational_failure_stops_all_later_jobs(self):
        observer = Mock(return_value=completed("{}", status="operational_failure", error_type="ClientError"))
        report = trial.run_trial(self.path, trial._hash(self.plan), self.output, observer=observer)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(observer.call_count, 1)
        self.assertTrue(all(r["status"] == "unattempted" for r in report["results"][1:]))

    def test_observer_exception_records_attempted_job_instead_of_unattempted(self):
        observer = Mock(side_effect=RuntimeError("Scripted observation failure"))
        report = trial.run_trial(self.path, trial._hash(self.plan), self.output, observer=observer)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(report["calls"][0]["status"], "operational_failure")
        self.assertIsNone(report["calls"][0]["provider_dispatch_attempted"])
        self.assertEqual(report["results"][0]["status"], "operational_failure")
        self.assertTrue(all(r["status"] == "unattempted" for r in report["results"][1:]))

    def test_unknown_usage_stops_without_discarding_observed_response(self):
        state = completed("{}", usage_known=False)
        state["response"]["usage"] = None
        observer = Mock(return_value=state)
        report = trial.run_trial(self.path, trial._hash(self.plan), self.output, observer=observer)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(observer.call_count, 1)
        self.assertEqual(report["calls"][0]["observation"]["response"]["text"], "{}")
        self.assertFalse(report["calls"][0]["usage_known"])

    def test_content_observer_failure_preserves_completed_provider_evidence(self):
        with patch.object(trial, "content_observation", side_effect=RuntimeError("Scripted scoring failure")):
            report = trial.run_trial(self.path, trial._hash(self.plan), self.output, observer=self.observer)
        self.assertEqual(report["status"], "operational_failure")
        self.assertEqual(report["calls"][0]["status"], "completed")
        self.assertTrue(report["calls"][0]["usage_known"])
        self.assertEqual(report["results"][0]["status"], "operational_failure")
        self.assertTrue(all(r["status"] == "unattempted" for r in report["results"][1:]))


class CurrentSolverOrderingAdmissionTests(unittest.TestCase):
    def test_historical_trial_rejects_current_prompt_before_provider_dispatch(self):
        batch = json.loads(trial.FIXTURE.read_text())["batches"][0]
        for arm in trial.ARMS:
            with self.subTest(arm=arm):
                client = Mock()
                with self.assertRaisesRegex(ValueError, "Current solver example changed"):
                    trial._invoke(batch, arm, client)
                client.converse.assert_not_called()


if __name__ == "__main__":
    unittest.main()
