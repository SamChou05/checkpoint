"""Frozen demonstration-transfer capture tests; mocks are not quality evidence."""

import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from evals import checkpoint_author_examples_trial as trial
from test_runtime_qualification import completed


class AuthorExamplesTrialTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.fixture = {
            "experiment": trial.EXPERIMENT,
            "assessment_notes": "ASSESSOR PRIVATE",
            "demonstration_sources": "SOURCE PROVENANCE PRIVATE",
            "demonstrations": [{
                "id": f"DEMO ID PRIVATE {i}",
                "subject_context": "For this invented example, blue tokens count twice and green tokens once.",
                "question": {
                    "prompt": "One blue token is replaced by two green tokens. How does the total change?",
                    "choices": ["It stays the same.", "It increases by one.",
                                "It decreases by one.", "It doubles."],
                    "expectedAnswer": "It stays the same.",
                    "explanation": "A blue token contributes two; two green tokens also contribute two.",
                    "topic": "Synthetic weighting", "difficulty": 3, "format": "Multiple Choice",
                },
            } for i in range(3)],
            "cases": [{
                "case_id": f"synthetic-{i}", "assessment_scope": "CASE PRIVATE",
                "payload": {
                    "goal": {"title": f"Study synthetic rule system {i}",
                             "currentLevel": "I know the separate rules."},
                    "targetCount": 2, "minimumDifficulty": 3,
                    "sourceDocuments": [{"name": "Supplied partial rules",
                                         "text": "Every gate opens after the third green pulse.",
                                         "truncated": True}],
                },
            } for i in range(3)],
        }
        self.plan = trial.make_plan(self.fixture)

    def test_paired_actual_requests_add_only_projected_examples_without_capacity_change(self):
        original = copy.deepcopy(self.fixture)
        compiler_fixture = copy.deepcopy(self.fixture)
        compiler_fixture["experiment"] = trial.capacity.EXPERIMENT
        compiled = trial.capacity.make_plan(compiler_fixture)
        self.assertEqual(self.fixture, original)
        self.assertEqual(self.plan["fixture"], self.fixture)
        self.assertEqual(self.plan["fixture_sha256"], trial._hash(self.fixture))
        self.assertEqual([j["arm"] for j in self.plan["jobs"]],
                         ["no_examples", "checked_examples", "checked_examples",
                          "no_examples", "no_examples", "checked_examples"])
        self.assertEqual(self.plan["maximum_calls"], 6)
        self.assertEqual(self.plan["maximum_input_utf8_bytes_total"], 192 * 1024)
        self.assertEqual(self.plan["planned_input_utf8_bytes"],
                         sum(j["input_utf8_bytes"] for j in self.plan["jobs"]))
        for name in ("checkpoint_author_examples_trial.py", "checkpoint_main_capacity_trial.py"):
            key = "evals/" + name
            self.assertEqual(self.plan["source_sha256"][key], hashlib.sha256(
                (trial.SERVICE_DIR / key).read_bytes()).hexdigest())
        self.assertEqual(self.plan["settings"], trial.capacity.SETTINGS)
        for index in range(3):
            pair = {j["arm"]: j for j in self.plan["jobs"] if j["case_index"] == index}
            baseline, examples = pair["no_examples"], pair["checked_examples"]
            compiled_baseline = next(j for j in compiled["jobs"]
                                     if j["case_index"] == index and j["arm"] == "main_320")
            self.assertEqual(baseline["request"], compiled_baseline["request"])
            self.assertEqual(baseline["normalized_request"], examples["normalized_request"])
            system = examples["request"]["system"][0]["text"]
            projected = json.loads(system.split("<checked_author_examples_json>\n", 1)[1].split(
                "\n</checked_author_examples_json>", 1)[0])
            self.assertEqual(projected, [{"subject_context": d["subject_context"],
                                          "question": d["question"]}
                                         for d in self.fixture["demonstrations"]])
            expected = copy.deepcopy(baseline["request"])
            expected["system"][0]["text"] += (
                trial.EXAMPLE_INSTRUCTION + "<checked_author_examples_json>\n"
                + trial.shared.canonical(projected) + "\n</checked_author_examples_json>")
            self.assertEqual(examples["request"], expected)
            for job in pair.values():
                request = job["request"]
                self.assertEqual(request["modelId"], "moonshotai.kimi-k2.5")
                self.assertEqual(request["inferenceConfig"], {"maxTokens": 6000, "temperature": 0.2})
                self.assertEqual(request["additionalModelRequestFields"], {"thinking": {"type": "disabled"}})
                self.assertIn("320 characters, each choice at most 140, explanation at most 320",
                              request["system"][0]["text"])
                self.assertNotIn("explanation at most 900", request["system"][0]["text"])
                self.assertNotIn("PRIVATE", json.dumps(request))
                self.assertEqual(job["request_sha256"], trial._hash(request))
                self.assertEqual(job["input_utf8_bytes"],
                                 len(trial.shared.canonical(request).encode("utf-8")))

    def test_example_contract_rejects_unknown_fields_invalid_keys_and_oversized_inputs(self):
        for mutate in (
            lambda p: p.update(experiment=trial.capacity.EXPERIMENT),
            lambda p: p["demonstrations"].pop(),
            lambda p: p["demonstrations"][1].update(id=p["demonstrations"][0]["id"]),
            lambda p: p["demonstrations"][0].update(assessment_notes="must stay outside"),
            lambda p: p["demonstrations"][0].update(subject_context=" "),
            lambda p: p["demonstrations"][0]["question"].update(choiceFeedback=[]),
            lambda p: p["demonstrations"][0]["question"].update(expectedAnswer="A"),
            lambda p: p["demonstrations"][0]["question"].update(format="multiple_choice"),
            lambda p: p["demonstrations"][0]["question"].update(difficulty=True),
            lambda p: p["demonstrations"][0]["question"].update(difficulty=2),
            lambda p: p["demonstrations"][0]["question"].update(choices=["A", "A", "C", "D"]),
            lambda p: p["demonstrations"][0]["question"].update(choices=["A", "a ", "C", "D"]),
            lambda p: p["demonstrations"][0]["question"].update(choices=[{"id": "A"}] * 4),
            lambda p: p["demonstrations"][0]["question"].update(prompt="x" * 321),
            lambda p: p["demonstrations"][0]["question"].update(explanation="x" * 321),
            lambda p: p["demonstrations"][0]["question"]["choices"].__setitem__(1, "x" * 141),
            lambda p: p["demonstrations"][0].update(subject_context="é" * 17000),
        ):
            with self.subTest(mutate=mutate):
                changed = copy.deepcopy(self.fixture)
                mutate(changed)
                with self.assertRaises(ValueError):
                    trial.make_plan(changed)

    def test_new_plan_uses_shared_capture_and_replays_all_raw_observations(self):
        texts = ["not JSON", '{"questions":[]}', '{"questions":[null,null,null]}',
                 json.dumps({"questions": [{"explanation": "x" * 1300}]}), "[]", "{}"]
        transport = Mock(side_effect=[completed(t) for t in texts])
        with patch.object(trial.capacity, "run", wraps=trial.capacity.run) as shared_run:
            report = trial.run(self.plan, self.root / "capture", transport=transport)
            self.assertIs(shared_run.call_args.kwargs["plan_builder"], trial.make_plan)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(transport.call_count, 6)
        self.assertEqual([c["observation"]["response"]["text"] for c in report["calls"]], texts)
        for invocation in transport.call_args_list:
            self.assertIs(invocation.kwargs["worker"], trial.capacity.author_worker)
            self.assertEqual(invocation.kwargs["timeout"], 90)
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No replay client.")):
            self.assertEqual(trial.replay_capture(report), report)
        with self.assertRaises(ValueError):
            trial.capacity.replay_capture(report)
        changed = copy.deepcopy(report)
        changed["calls"][0]["arm"] = "checked_examples"
        with self.assertRaises(ValueError):
            trial.replay_capture(changed)

    def test_frozen_plan_load_and_tamper_rejection_use_explicit_builder(self):
        fixture_path, plan_path = self.root / "fixture.json", self.root / "plan.json"
        trial.shared.write_json(fixture_path, self.fixture)
        with patch.object(trial.shared, "new_client", side_effect=AssertionError("No dry client.")):
            self.assertEqual(trial.main(["--fixture", str(fixture_path), "--plan", str(plan_path)]), 0)
            self.assertEqual(trial.load_plan(plan_path, trial._hash(self.plan)), self.plan)
        with self.assertRaises(ValueError):
            trial.capacity.load_plan(plan_path, trial._hash(self.plan))
        with self.assertRaises(ValueError):
            trial.load_plan(plan_path, "0" * 64)
        transport = Mock()
        for mutate in (
            lambda p: p["fixture"].update(assessment_notes="changed"),
            lambda p: p["fixture"]["demonstrations"][0]["question"].update(explanation="changed"),
            lambda p: p["source_sha256"].update({"evals/checkpoint_author_examples_trial.py": "0" * 64}),
            lambda p: p["jobs"][1]["request"]["system"][0].update(text="replacement"),
            lambda p: p.update(maximum_calls=7),
        ):
            changed = copy.deepcopy(self.plan)
            mutate(changed)
            with self.assertRaises(ValueError):
                trial.run(changed, self.root / "forbidden", transport=transport)
            trial.shared.write_json(self.root / "tampered.json", changed)
            with self.assertRaises(ValueError):
                trial.load_plan(self.root / "tampered.json", trial._hash(changed))
        transport.assert_not_called()
        self.assertFalse((self.root / "forbidden").exists())


if __name__ == "__main__":
    unittest.main()
