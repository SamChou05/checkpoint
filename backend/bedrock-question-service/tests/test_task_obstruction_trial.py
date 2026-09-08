"""Bounded ten-case qualification using local synthetic origins and responses."""

import copy
import hashlib
import json
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_claim_evidence_trial as trial
import test_split_evidence_trial as earlier
from test_claim_evidence_trial import completed, provider


class TaskObstructionTrialTests(unittest.TestCase):
    def setUp(self):
        # Reuse the existing synthetic origin builder without inheriting or
        # duplicating its tests, or pinning future runtime code to live evidence.
        self.base = earlier.SplitEvidenceTrialTests(methodName="runTest")
        self.base.setUp()
        self.addCleanup(self.base.doCleanups)
        self.root = self.base.root
        cases = []
        for index in range(6):
            original = self.base.origin["plan"]["fixture"]["cases"][0]
            cases.append({"case_id": f"control-{index}",
                          "question": {**original["question"],
                                       "prompt": f"For control {index}, what is the sum of two and two?"},
                          "context": {"goal": {"title": "Arithmetic", "expectedAnswer": "GOAL SECRET"},
                                      "sourceDocuments": [], "minimumDifficulty": 2},
                          "assessment": {"expected": "ASSESSMENT SECRET"},
                          "provenance": {"reference": "https://reference.invalid/NOT-FOR-MODEL"}})
        self.controls = {"experiment": "premise-and-nondefect-controls-v1", "cases": cases,
                         "primary_sources": [{"text": "REFERENCE SECRET"}]}
        self.control_path = self.root / "controls.json"
        self.control_path.write_text(json.dumps(self.controls))
        for name, value in (("PREMISE_CONTROLS", self.control_path),
                            ("PREMISE_CONTROLS_SHA256", hashlib.sha256(self.control_path.read_bytes()).hexdigest())):
            patcher = patch.object(trial, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.fixture = {"experiment": trial.OBSTRUCTION_EXPERIMENT}
        self.plan = trial.make_plan(self.fixture)

    def transport(self, request, **kwargs):
        data = json.loads(request["messages"][0]["content"][0]["text"])
        self.assertIs(kwargs["worker"], trial.structured_review_worker)
        self.assertEqual(kwargs["timeout"], 300)
        if "explanation" in data["item"]:
            value = {"assessment": {"reason": "The complete main correctly combines the two groups.",
                                     "status": "supported", "evidence": []},
                     "issues": [], "difficulty": 2}
        else:
            value = {"taskObstruction": {"status": "none", "choiceId": None,
                                          "reason": "All necessary counting facts are supplied."},
                     "choices": {key: {"reason": "RESPONSE SECRET", "status": "supported" if text == "4" else "refuted", "evidence": []}
                                 for key, text in data["item"]["choices"].items()}}
            if "exercise 0" in data["item"]["prompt"]:
                value["taskObstruction"]["status"] = "blocks_all_choices"
                for item in value["choices"].values():
                    item["status"] = "refuted"
            elif "exercise 1" in data["item"]["prompt"]:
                value = {"malformed": "format rejection must not prevent the independent teaching observation"}
        observed = completed(trial.caller.recorded._response(provider(json.dumps(value))))
        kwargs["on_progress"](copy.deepcopy(observed))
        return observed

    def test_twenty_independent_calls_preserve_origins_and_replay(self):
        output = self.root / "twenty"
        fetch = Mock(side_effect=AssertionError("No fetching."))
        def transport(request, **kwargs):
            durable = json.loads((output / "capture.json").read_text())
            self.assertEqual(durable["calls"][-1]["request"], request)
            self.assertEqual(durable["calls"][-1]["status"], "launch_intent")
            return self.transport(request, **kwargs)
        report = trial.run(self.plan, output, transport=transport, fetch=fetch)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(len(report["cases"]), 10)
        self.assertEqual([c["role"] for c in report["calls"]], ["choices", "teaching"] * 10)
        self.assertEqual([c["candidate"]["eligible"] for c in report["cases"]], [False, False] + [True] * 8)
        fetch.assert_not_called()
        self.assertEqual(self.plan["maximum_calls"], 20)
        self.assertEqual(self.plan["maximum_fetches"], 0)
        self.assertEqual(self.plan["maximum_input_bytes_total"], 20 * 65536)
        self.assertEqual(self.plan["controls_fixture"], self.controls)
        self.assertEqual(self.plan["frozen_cases"][:4], self.base.plan["frozen_cases"])
        self.assertIn("evals/task_obstruction_review.py", self.plan["source_sha256"])
        for index, job in enumerate(self.plan["jobs"]):
            self.assertEqual(set(job["requests"]), {"choices", "teaching"})
            choices, teaching = (json.loads(job["requests"][role]["messages"][0]["content"][0]["text"])
                                 for role in ("choices", "teaching"))
            self.assertEqual(set(choices), {"goal", "item", "evidenceSources"})
            self.assertEqual(set(choices["item"]), {"prompt", "choices"})
            self.assertEqual(teaching["item"].pop("explanation"), self.plan["frozen_cases"][index]["question"]["explanation"])
            self.assertEqual(teaching, choices)
            for marker in ("ASSESSMENT SECRET", "REFERENCE SECRET", "GOAL SECRET", "NOT-FOR-MODEL", "RESPONSE SECRET", "HYPOTHESIS SECRET", "OLD SUMMARY SECRET", "expectedAnswer", "difficulty"):
                self.assertNotIn(marker, json.dumps(choices))
            if index >= 4:
                self.assertEqual(choices["evidenceSources"], [])
                self.assertEqual(job["source_units"], {})
            for request in job["requests"].values():
                self.assertEqual(request["inferenceConfig"], {"maxTokens": 6000, "temperature": 0.2})
                self.assertEqual(request["modelId"], trial.REVIEW_MODEL)
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No replay client.")):
            self.assertEqual(trial.replay_split_capture(report), report)

    def test_freeze_tampering_and_input_boundary_refuse_before_dispatch(self):
        transport = Mock()
        for mutate in (
            lambda p: p.update(maximum_calls=21),
            lambda p: p["controls_fixture"]["cases"][0]["assessment"].update(expected="changed"),
            lambda p: p["jobs"][0]["requests"].update(old_review=p["jobs"][0]["requests"]["choices"]),
            lambda p: p["jobs"][0]["requests"]["choices"]["inferenceConfig"].update(maxTokens=16000),
        ):
            changed = copy.deepcopy(self.plan)
            mutate(changed)
            with self.assertRaises(ValueError):
                trial.run(changed, self.root / "forbidden", transport=transport)
        transport.assert_not_called()
        self.assertFalse((self.root / "forbidden").exists())
        with self.assertRaises(ValueError):
            trial.make_plan({**self.fixture, "cases": []})
        self.control_path.write_text(self.control_path.read_text() + " ")
        with self.assertRaisesRegex(ValueError, "exact six-control"):
            trial.make_plan(self.fixture)

    def test_failure_stop_and_dry_load_need_no_client(self):
        plan_path = self.root / "plan.json"
        trial.shared.write_json(plan_path, self.plan)
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No preflight clients.")):
            self.assertEqual(trial.load_plan(plan_path, trial._hash(self.plan)), self.plan)
        for index, state in enumerate((
            {"status": "operational_failure", "provider_dispatch_attempted": True},
            {**completed(trial.caller.recorded._response(provider("{}"))),
             "local_process_group_cleanup_confirmed": False},
        )):
            transport = Mock(return_value=state)
            report = trial.run(self.plan, self.root / f"failed-{index}", transport=transport)
            self.assertEqual(report["status"], "operational_failure")
            self.assertEqual(len(report["calls"]), 1)
            transport.assert_called_once()
            self.assertEqual(trial.replay_split_capture(report), report)
        transport = Mock()
        with patch.object(trial.shared, "write_json", side_effect=OSError("fixed disk failure")), self.assertRaises(OSError):
            trial.run(self.plan, self.root / "disk-failure", transport=transport)
        transport.assert_not_called()


if __name__ == "__main__":
    unittest.main()
