import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evals import checkpoint_prompt_ablation as experiment
from lambda_test_support import _raw_question


class PromptAblationTests(unittest.TestCase):
    def test_paired_arms_receive_identical_context(self):
        cases = experiment.experiment_cases()
        jobs = experiment.make_plan(cases, 123)
        self.assertEqual(len(jobs), 12)
        for case in cases:
            pair = [job for job in jobs if job["case_id"] == case["case_id"]]
            self.assertEqual({job["arm"] for job in pair}, {"simple", "current_author"})
            self.assertEqual(pair[0]["contextSHA256"], pair[1]["contextSHA256"])
            contexts = [
                json.loads(
                    job["user"]
                    .split("<generation_request_json>\n", 1)[1]
                    .split("\n</generation_request_json>", 1)[0]
                )
                for job in pair
            ]
            self.assertEqual(contexts[0], contexts[1])
            self.assertEqual(contexts[0]["targetCount"], 5)
            self.assertEqual(contexts[0]["minimumDifficulty"], 3)

    def test_capture_preserves_items_rejected_by_app_length_limit(self):
        job = experiment.make_plan(experiment.experiment_cases(), 123)[0]
        question = _raw_question("x" * 400)
        with patch.object(
            experiment,
            "_generate_with_bedrock",
            return_value=json.dumps({"questions": [question]}),
        ):
            result = experiment.capture(job, "test-model")
        self.assertEqual(result["questions"], [question])
        self.assertEqual(result["structurally_retained"], 0)
        self.assertEqual(
            result["metrics"]["QuestionQuality"]["sanitize"]["prompt_length"], 1
        )

    def test_blinded_material_hides_arm_key_and_authored_explanation(self):
        question = _raw_question(
            "A complete question that can be independently checked?"
        )
        request = experiment.experiment_cases()[0]["request"]
        with tempfile.TemporaryDirectory() as directory:
            experiment.write_outputs(
                Path(directory),
                [
                    {
                        "case_id": "synthetic",
                        "arm": "simple",
                        "request": request,
                        "questions": [question],
                    }
                ],
                "test-model",
                123,
                1,
            )
            blind = json.loads((Path(directory) / "blinded.json").read_text())[0]
            key = json.loads((Path(directory) / "answer_key.json").read_text())[0]
        self.assertEqual(
            set(blind), {"id", "goal", "sourceDocuments", "prompt", "choices"}
        )
        self.assertEqual(blind["id"], key["id"])
        self.assertEqual(key["question"]["expectedAnswer"], question["expectedAnswer"])
