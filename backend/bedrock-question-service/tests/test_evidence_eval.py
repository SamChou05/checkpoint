import copy
import json
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from evals.checkpoint_evidence_eval import SERVICE_DIR, make_plan
from evals import checkpoint_evidence_eval as evidence_eval
from evals.checkpoint_learning_eval import evaluate_review
import question_verification
from service_errors import ProviderError


class EvidenceComparisonTests(unittest.TestCase):
    def test_selected_arm_reuses_actual_prompt_snapshot_at_requested_effort(self):
        snapshot = {
            "solution_prompt": "Frozen solution instructions.",
            "review_prompt": "Frozen review instructions.",
        }
        seen = []

        def check(case):
            self.assertEqual(
                question_verification.SOLUTION_SYSTEM_PROMPT,
                snapshot["solution_prompt"],
            )
            self.assertEqual(
                question_verification.REVIEW_SYSTEM_PROMPT, snapshot["review_prompt"]
            )
            self.assertEqual(os.environ["BEDROCK_CLAUDE_EFFORT"], "max")
            self.assertNotIn("sourceDocuments", case)
            seen.append(case["case_id"])
            return {"case_id": case["case_id"], "passed": True, "accepted": True}

        with tempfile.TemporaryDirectory() as directory:
            snapshot_path = Path(directory) / "snapshot.json"
            snapshot_path.write_text(json.dumps(snapshot))
            output = Path(directory) / "output.json"
            args = [
                "evidence-eval",
                "--output",
                str(output),
                "--arm",
                "unaided",
                "--effort",
                "max",
                "--prompt-snapshot",
                str(snapshot_path),
            ]
            with (
                patch("sys.argv", args),
                patch("sys.stdout", new_callable=io.StringIO),
                patch.dict(os.environ),
                patch.object(evidence_eval, "evaluate_review", side_effect=check),
                patch.object(
                    question_verification,
                    "SOLUTION_SYSTEM_PROMPT",
                    question_verification.SOLUTION_SYSTEM_PROMPT,
                ),
                patch.object(
                    question_verification,
                    "REVIEW_SYSTEM_PROMPT",
                    question_verification.REVIEW_SYSTEM_PROMPT,
                ),
            ):
                self.assertEqual(evidence_eval.main(), 0)
            result = json.loads(output.read_text())
        self.assertEqual(len(seen), 4)
        self.assertEqual(result["maximum_calls"], 8)
        self.assertEqual(result["settings"]["effort"], "max")
        self.assertEqual(result["review_prompt"], snapshot["review_prompt"])

    def test_provider_failure_preserves_earlier_solver_and_never_earns_rejection_credit(
        self,
    ):
        case = {
            "case_id": "provider_failure",
            "goal": {"title": "Learn addition"},
            "question": {
                "prompt": "What is two plus three?",
                "topic": "Addition",
                "choices": ["5", "6", "7", "8"],
                "expectedAnswer": "6",
            },
            "expected_accept": False,
            "rationale": "The authored key is wrong.",
        }
        solver = json.dumps(
            {
                "solutions": [
                    {
                        "index": 0,
                        "answer": "The sum is 5.",
                        "limitations": "",
                        "outcome": "resolved",
                        "assumptionsRequired": [],
                    }
                ]
            }
        )

        def invoke(*args, call_budget, request_metrics, **kwargs):
            call_budget.consume()
            request_metrics["ProviderCalls"] += 1
            if call_budget.calls == 1:
                return solver
            raise ProviderError("Bedrock invocation failed.")

        with patch(
            "evals.checkpoint_learning_eval._generate_with_bedrock", side_effect=invoke
        ):
            result = evaluate_review(case)
        self.assertFalse(result["passed"])
        self.assertEqual(result["error_type"], "ProviderError")
        self.assertEqual(result["provider_calls"], 2)
        self.assertEqual(result["metrics"]["ProviderCalls"], 2)
        self.assertEqual(result["reviews"], [solver])

    def test_solver_outcome_mismatch_and_uncertainty_have_distinct_scores(self):
        case = {
            "case_id": "typed_outcome",
            "goal": {"title": "Learn addition"},
            "question": {
                "prompt": "What is two plus three?",
                "topic": "Addition",
                "choices": ["5", "6", "7", "8"],
                "expectedAnswer": "6",
            },
            "expected_accept": False,
            "rationale": "The authored key is wrong.",
        }
        for outcome, reason, passed in (
            ("no_solution", "solver_outcome_mismatch", True),
            ("uncertain", "solver_uncertain", False),
        ):
            with self.subTest(outcome=outcome):
                raw = json.dumps(
                    {
                        "solutions": [
                            {
                                "index": 0,
                                "outcome": outcome,
                                "answer": "A synthetic result.",
                                "limitations": "",
                                "assumptionsRequired": [],
                            }
                        ]
                    }
                )

                def invoke(*args, call_budget, request_metrics, **kwargs):
                    call_budget.consume()
                    request_metrics["ProviderCalls"] += 1
                    return raw

                with patch(
                    "evals.checkpoint_learning_eval._generate_with_bedrock",
                    side_effect=invoke,
                ):
                    result = evaluate_review(case)
                self.assertEqual(result["passed"], passed)
                self.assertEqual(result["abstained"], outcome == "uncertain")
                self.assertEqual(result["provider_calls"], 1)
                self.assertEqual(result["reviews"], [raw])
                self.assertEqual(
                    result["stage_outputs"]["solver"]["solutions"][0]["outcome"],
                    outcome,
                )
                self.assertEqual(
                    result["metrics"]["QuestionQuality"]["review"], {reason: 1}
                )
                self.assertNotIn("error_type", result)

    def test_paired_context_changes_only_supplied_documents(self):
        packet = json.loads(
            (
                SERVICE_DIR / "evals/fixtures/question_evidence_feasibility.json"
            ).read_text()
        )
        original = copy.deepcopy(packet)
        jobs = make_plan(packet, 3, 123)
        self.assertEqual(len(jobs), 24)
        self.assertEqual(packet, original)
        for repeat in (1, 2, 3):
            for case in packet["cases"]:
                pair = {
                    job["arm"]: copy.deepcopy(job["case"])
                    for job in jobs
                    if job["repeat"] == repeat
                    and job["case"]["case_id"] == case["case_id"]
                }
                evidence = pair["evidence"].pop("sourceDocuments")
                self.assertEqual(pair["evidence"], pair["unaided"])
                self.assertEqual(
                    evidence, packet["evidence_by_case_id"][case["case_id"]]
                )
        # Evidence does not reveal which nearby control is meant to pass.
        documents = packet["evidence_by_case_id"]
        self.assertEqual(
            documents["all_pairs_output_bound"], documents["valid_pair_existence"]
        )
        self.assertEqual(
            documents["raw_highlight_recovery_unsupported_sequence"],
            documents["raw_nondestructive_valid"],
        )


if __name__ == "__main__":
    unittest.main()
