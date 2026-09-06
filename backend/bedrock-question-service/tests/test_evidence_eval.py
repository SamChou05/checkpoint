import copy
import json
import unittest
from unittest.mock import patch

from evals.checkpoint_evidence_eval import SERVICE_DIR, make_plan
from evals.checkpoint_learning_eval import evaluate_review
from service_errors import ProviderError


class EvidenceComparisonTests(unittest.TestCase):
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
