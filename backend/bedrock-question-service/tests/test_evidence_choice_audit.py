import copy
import json
import unittest
from unittest.mock import patch

from evals import checkpoint_evidence_choice_audit as experiment
from service_errors import ProviderError


class EvidenceChoiceAuditTests(unittest.TestCase):
    def setUp(self):
        self.case = {
            "case_id": "private expected verdict label",
            "goal": {"title": "private goal"},
            "question": {
                "prompt": "A square has four sides. Which shape has four sides?",
                "choices": ["Square", "Triangle", "Circle", "Pentagon"],
                "expectedAnswer": "Square",
                "explanation": "private explanation",
            },
            "expected_accept": True,
            "rationale": "private rationale",
        }
        self.job = experiment.make_job(
            self.case,
            [
                {
                    "name": "Shapes",
                    "text": "A triangle has three sides; a circle has no straight sides; a pentagon has five sides.",
                }
            ],
            repeat=1,
            seed=123,
        )
        self.audit = {
            "stem": self.job["context"]["stem"],
            "requirements": [
                {
                    "id": "R1",
                    "stem_quote": "four sides",
                    "requirement": "Has exactly four sides.",
                }
            ],
            "choices": [],
        }
        for choice in self.job["context"]["choices"]:
            supported = choice["text"] == "Square"
            self.audit["choices"].append(
                {
                    **choice,
                    "claims": [
                        {
                            "claim": "The shape has four sides.",
                            "requirement_ids": ["R1"],
                            "status": "supported" if supported else "refuted",
                            "evidence": [
                                {
                                    "id": "stem" if supported else "E1",
                                    "quote": self.job["context"]["stem"]
                                    if supported
                                    else self.job["context"]["evidence"][0]["text"],
                                }
                            ],
                            "reason": "The stated side count satisfies or contradicts the required four sides.",
                            "limitations": [],
                        }
                    ],
                }
            )

    def parse(self, audit=None):
        return experiment.parse_audit(
            json.dumps(audit or self.audit), self.job["context"]
        )

    def test_blind_context_has_no_answer_explanation_goal_or_expected_verdict(self):
        self.assertEqual(
            set(json.loads(self.job["user_prompt"])), {"stem", "choices", "evidence"}
        )
        self.assertNotIn("private", self.job["user_prompt"])
        self.assertEqual(
            {item["text"] for item in self.job["context"]["choices"]},
            set(self.case["question"]["choices"]),
        )

    def test_acceptance_is_derived_and_matches_original_key_after_unblinding(self):
        result = {**self.job, **self.parse(), "outcome": "content_accept"}
        self.assertTrue(result["accepted"])
        self.assertTrue(experiment.score_result(result, self.case)["passed"])

    def test_changed_author_key_affects_only_offline_scoring(self):
        changed = copy.deepcopy(self.case)
        changed["question"]["expectedAnswer"] = "Triangle"
        changed["question"]["explanation"] = "A new private rationale."
        alternate_job = experiment.make_job(
            changed,
            [
                {"name": item["name"], "text": item["text"]}
                for item in self.job["context"]["evidence"]
            ],
            repeat=1,
            seed=123,
        )
        self.assertEqual(alternate_job["user_prompt"], self.job["user_prompt"])
        result = {**self.job, **self.parse(), "outcome": "content_accept"}
        self.assertFalse(experiment.score_result(result, changed)["passed"])

    def test_two_supported_choices_are_ambiguous_even_with_complete_coverage(self):
        triangle = next(
            choice for choice in self.audit["choices"] if choice["text"] == "Triangle"
        )
        triangle["claims"][0]["status"] = "supported"
        result = self.parse()
        self.assertFalse(result["accepted"])
        self.assertIsNone(result["selected_choice_id"])

    def test_unknown_distractor_is_not_treated_as_refuted(self):
        claim = next(
            choice for choice in self.audit["choices"] if choice["text"] == "Triangle"
        )["claims"][0]
        claim.update(
            status="undetermined",
            evidence=[],
            limitations=["Side count is not established."],
        )
        result = self.parse()
        self.assertFalse(result["accepted"])
        self.assertEqual(
            list(result["choice_states"].values()).count("undetermined"), 1
        )

    def test_refuted_necessary_component_defeats_partly_supported_choice(self):
        square = next(
            choice for choice in self.audit["choices"] if choice["text"] == "Square"
        )
        extra = copy.deepcopy(square["claims"][0])
        extra.update(
            status="refuted", claim="An additional necessary condition is contradicted."
        )
        square["claims"].append(extra)
        self.assertFalse(self.parse()["accepted"])

    def test_missing_or_duplicate_choices_are_format_failures(self):
        for replacement in (
            self.audit["choices"][:-1],
            self.audit["choices"][:-1] + [self.audit["choices"][0]],
        ):
            audit = copy.deepcopy(self.audit)
            audit["choices"] = replacement
            with self.assertRaises(experiment.AuditFormatError):
                self.parse(audit)

    def test_changed_text_fabricated_citation_and_incomplete_coverage_fail(self):
        mutations = [
            lambda audit: audit.update(stem="Repaired stem"),
            lambda audit: audit["choices"][0].update(text="Repaired choice"),
            lambda audit: audit["choices"][0]["claims"][0]["evidence"][0].update(
                quote="Fabricated source sentence"
            ),
            lambda audit: audit["choices"][0]["claims"][0]["evidence"][0].update(
                id="unknown source"
            ),
            lambda audit: audit["choices"][0]["claims"][0].update(evidence=[]),
            lambda audit: audit["requirements"].append(
                {
                    "id": "R2",
                    "stem_quote": "Which shape",
                    "requirement": "Select a shape.",
                }
            ),
            lambda audit: audit["choices"][0]["claims"][0].update(
                requirement_ids=["R99"]
            ),
        ]
        for mutate in mutations:
            audit = copy.deepcopy(self.audit)
            mutate(audit)
            with (
                self.subTest(mutation=mutate),
                self.assertRaises(experiment.AuditFormatError),
            ):
                self.parse(audit)

    def test_retained_limitation_cannot_be_supported(self):
        choice = next(
            choice for choice in self.audit["choices"] if choice["text"] == "Square"
        )
        choice["claims"][0]["limitations"] = ["A necessary condition is missing."]
        with self.assertRaises(experiment.AuditFormatError):
            self.parse()

    def test_duplicate_json_keys_are_not_silently_overwritten(self):
        raw = json.dumps(self.audit)
        raw = '{"stem":"changed",' + raw[1:]
        with self.assertRaises(experiment.AuditFormatError):
            experiment.parse_audit(raw, self.job["context"])

    def test_provider_and_parser_failures_never_count_as_bad_question_detection(self):
        invalid = {**self.case, "expected_accept": False}
        for response in (ProviderError("Bedrock invocation failed."), "invalid JSON"):
            kwargs = (
                {"side_effect": response}
                if isinstance(response, Exception)
                else {"return_value": response}
            )
            with patch.object(experiment, "_generate_with_bedrock", **kwargs):
                result = experiment.capture(self.job, "test-model")
            score = experiment.score_result(result, invalid)
            self.assertFalse(score["evaluable"])
            self.assertFalse(score["passed"])


if __name__ == "__main__":
    unittest.main()
