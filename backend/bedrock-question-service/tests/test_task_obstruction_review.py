"""Pure obstruction gates; mock labels are not an accuracy qualification."""

import copy
import hashlib
import json
import unittest

try:
    import jsonschema
except ImportError:
    jsonschema = None

from evals import split_evidence_review as split
from evals import task_obstruction_review as adapter


def question(
    prompt="What is the total of two objects and two more objects?", choices=None
):
    choices = ["4", "5", "3", "2"] if choices is None else choices
    return {
        "prompt": prompt,
        "choices": choices,
        "expectedAnswer": choices[0],
        "explanation": "  Combining the two groups gives four objects in total.\n",
        "choiceExplanations": {},
        "topic": "Reasoning",
        "difficulty": 3,
        "format": "Multiple Choice",
        "verificationVersion": 1,
        "verificationPolicyRevision": 99,
    }


def captured(text):
    return {
        "status": "acquired",
        "source_text": text,
        "text_sha256": hashlib.sha256(text.encode()).hexdigest(),
        "text_characters": len(text),
        "raw_content_sha256": "a" * 64,
        "final_url": "https://example.org/lesson",
        "retrieved_at_utc": "2026-09-08T00:00:00Z",
        "truncated": False,
        "source_text_complete": True,
        "representation_limits": ["Extracted text; diagrams unavailable."],
    }


class TaskObstructionTests(unittest.TestCase):
    def setUp(self):
        self.context = {
            "goal": {"title": "Reason from stated conditions", "key": "HIDDEN_KEY"},
            "challenge": "HIDDEN_CHALLENGE",
            "history": "HIDDEN_HISTORY",
            "independentSolutions": "HIDDEN_SOLVER",
            "sourceDocuments": "HIDDEN_SUMMARY",
        }
        text = "Two objects plus two more gives four objects."
        self.records = [captured(text)]
        self.selections = [{"record_index": 0, "start": 0, "end": len(text)}]
        self.prepared = adapter.prepare(
            question(), self.context, self.records, self.selections
        )

    def response(self, prepared=None, status="none"):
        prepared = self.prepared if prepared is None else prepared
        correct = next(
            k
            for k, v in prepared["payload"]["item"]["choices"].items()
            if v == prepared["question"]["expectedAnswer"]
        )
        return {
            "taskObstruction": {
                "status": status,
                "choiceId": correct if status == "answered_by_choice" else None,
                "reason": "The task is resolved by the supported answer.",
            },
            "choices": {
                letter: {
                    "reason": "This is warranted."
                    if letter == correct
                    else "This does not answer the task.",
                    "status": "supported" if letter == correct else "refuted",
                    "evidence": ["S1U1"] if prepared["source_units"] else [],
                }
                for letter in adapter.LETTERS
            },
        }

    def teaching(self):
        return {
            "assessment": {
                "reason": "The whole main correctly applies the stated rule.",
                "status": "supported",
                "evidence": [],
            },
            "issues": [],
            "difficulty": 3,
        }

    def observed(self, value, role, prepared=None):
        return adapter.observe(
            value if type(value) is str else json.dumps(value),
            self.prepared if prepared is None else prepared,
            role,
        )

    def combined(self, choices=None, teaching=None, prepared=None, floor=3):
        prepared = self.prepared if prepared is None else prepared
        return adapter.combine(
            prepared,
            self.observed(
                self.response(prepared) if choices is None else choices,
                "choices",
                prepared,
            ),
            self.observed(
                self.teaching() if teaching is None else teaching, "teaching", prepared
            ),
            floor,
        )

    def test_inputs_remain_independent_and_exact_with_shared_prepare(self):
        self.assertIs(adapter.prepare, split.prepare)
        snapshot = copy.deepcopy(self.prepared)
        choice_system, choice_raw = adapter.prompt(self.prepared, "choices")
        teaching_system, teaching_raw = adapter.prompt(self.prepared, "teaching")
        a, b = json.loads(choice_raw), json.loads(teaching_raw)
        self.assertEqual(
            b["item"].pop("explanation"), self.prepared["question"]["explanation"]
        )
        self.assertEqual(a, b)
        self.assertIn("AS AN ANSWER TO THIS STEM", choice_system)
        self.assertIn("Do not silently replace", teaching_system)
        self.assertNotIn("1200", choice_system + teaching_system)
        for raw in (choice_raw, teaching_raw):
            for secret in (
                "HIDDEN_",
                "expectedAnswer",
                "difficulty",
                "verificationVersion",
            ):
                self.assertNotIn(secret, raw)
        result = self.combined()
        self.assertTrue(result["eligible"])
        self.assertEqual(result["question"], self.prepared["question"])
        self.assertNotIn("verificationVersion", result["question"])
        result["question"]["choices"].reverse()
        self.assertEqual(self.prepared, snapshot)

    def test_reused_source_units_preserve_unicode_offsets_and_references(self):
        text = "prefix " + "é e\u0301  x\r\n" * 600 + " suffix"
        selected = {"record_index": 0, "start": 7, "end": len(text) - 7}
        prepared = adapter.prepare(
            question(), self.context, [captured(text)], [selected]
        )
        units = prepared["payload"]["evidenceSources"][0]["units"]
        self.assertEqual("".join(u["text"] for u in units), text[7:-7])
        for unit in units:
            bound = prepared["source_units"][unit["id"]]
            self.assertEqual(
                text[bound["original_start"] : bound["original_end"]], unit["text"]
            )
            self.assertEqual(
                bound["text_sha256"], hashlib.sha256(unit["text"].encode()).hexdigest()
            )
        observed = self.observed(self.response(prepared), "choices", prepared)
        self.assertEqual(
            observed["evidence_bindings"]["A"]["S1U1"], prepared["source_units"]["S1U1"]
        )

    def test_legitimate_diagnostic_negative_and_hypothetical_answers_survive(self):
        cases = [
            (
                "For a real number x, which answer resolves x + 1 = x?",
                ["There is no real solution.", "x = 0", "x = 1", "x = -1"],
                "answered_by_choice",
            ),
            (
                "Mira owns more marbles than Lee. How many marbles does Mira own?",
                ["The information does not determine the number.", "1", "2", "3"],
                "answered_by_choice",
            ),
            (
                "An integer is both even and odd. Which assessment is warranted?",
                [
                    "The premises are inconsistent.",
                    "The integer is 2.",
                    "The integer is 3.",
                    "The integer is 0.",
                ],
                "answered_by_choice",
            ),
            (
                "Which of these listed integers is NOT even?",
                ["3", "2", "4", "6"],
                "none",
            ),
            (
                "In this invented world every bird is blue. Ava is a bird. What follows?",
                ["Ava is blue.", "Ava is red.", "Ava is green.", "Ava is yellow."],
                "none",
            ),
        ]
        for stem, choices, status in cases:
            with self.subTest(stem=stem):
                q = question(stem, choices)
                q["explanation"] = (
                    "The stated conditions warrant the first listed answer for this task."
                )
                prepared = adapter.prepare(q, self.context, [], [])
                result = self.combined(
                    self.response(prepared, status), prepared=prepared
                )
                self.assertTrue(result["eligible"])
                self.assertEqual(result["question"]["expectedAnswer"], choices[0])

    def test_obstruction_blocks_despite_supported_choice_and_supported_main(self):
        for status, expected in (
            ("blocks_all_choices", "task_blocks_all_choices"),
            ("uncertain", "task_obstruction_uncertain"),
        ):
            with self.subTest(status=status):
                raw = self.response(status=status)
                self.assertTrue(self.observed(raw, "choices")["format_valid"])
                self.assertEqual(self.combined(raw)["reason"], expected)

    def test_diagnostic_choice_must_be_the_unique_supported_exact_key(self):
        raw = self.response(status="answered_by_choice")
        correct = raw["taskObstruction"]["choiceId"]
        rival = next(k for k in adapter.LETTERS if k != correct)
        raw["taskObstruction"]["choiceId"] = rival
        self.assertEqual(
            self.combined(raw)["reason"], "task_obstruction_answer_disagreement"
        )
        raw["choices"][correct]["status"] = "refuted"
        raw["choices"][rival]["status"] = "supported"
        self.assertEqual(self.combined(raw)["reason"], "answer_disagreement")

    def test_choice_uncertainty_zero_multiple_or_key_disagreement_cannot_be_rescued(
        self,
    ):
        for change, expected in (
            ("uncertain", "solver_uncertain"),
            ("zero", "solver_zero_supported"),
            ("multiple", "solver_multiple_supported"),
            ("wrong", "answer_disagreement"),
        ):
            with self.subTest(change=change):
                raw = self.response()
                correct = next(
                    k for k, v in raw["choices"].items() if v["status"] == "supported"
                )
                rival = next(k for k in adapter.LETTERS if k != correct)
                if change == "uncertain":
                    raw["choices"][rival]["status"] = "uncertain"
                if change in ("zero", "wrong"):
                    raw["choices"][correct]["status"] = "refuted"
                if change in ("multiple", "wrong"):
                    raw["choices"][rival]["status"] = "supported"
                self.assertEqual(self.combined(raw)["reason"], expected)

    def test_main_rejection_issues_and_difficulty_still_veto(self):
        for status in ("refuted", "uncertain"):
            raw = self.teaching()
            raw["assessment"]["status"] = status
            self.assertEqual(
                self.combined(teaching=raw)["reason"], "teaching_" + status
            )
        raw = self.teaching()
        raw["issues"] = ["The explanation asserts an unsupported universal rule."]
        self.assertEqual(self.combined(teaching=raw)["reason"], "teaching_issues")
        raw = self.teaching()
        raw["difficulty"] = 2
        self.assertEqual(self.combined(teaching=raw)["reason"], "difficulty_floor")

    def test_malformed_or_structurally_contradictory_obstruction_is_not_guessed(self):
        for changes in (
            {"status": "impossible"},
            {"status": True},
            {"choiceId": "A"},
            {"status": "answered_by_choice", "choiceId": None},
            {"status": "answered_by_choice", "choiceId": "a"},
            {"status": "blocks_all_choices", "choiceId": "A"},
            {"reason": " "},
            {"evidence": []},
        ):
            with self.subTest(changes=changes):
                raw = self.response()
                raw["taskObstruction"].update(changes)
                self.assertFalse(self.observed(raw, "choices")["format_valid"])
        raw = self.response()
        del raw["taskObstruction"]["choiceId"]
        self.assertFalse(self.observed(raw, "choices")["format_valid"])

    def test_strict_envelopes_coverage_and_known_distinct_source_ids(self):
        for mutation in (
            "old_issues",
            "missing",
            "extra",
            "duplicate_json",
            "trailing",
            "status_type",
            "unknown_source",
            "duplicate_source",
            "too_many_sources",
            "source_type",
        ):
            with self.subTest(mutation=mutation):
                raw = self.response()
                if mutation == "old_issues":
                    raw["issues"] = []
                elif mutation == "missing":
                    del raw["choices"]["D"]
                elif mutation == "extra":
                    raw["answer"] = "Replacement learner text."
                elif mutation == "duplicate_json":
                    raw = json.dumps(raw).replace(
                        '"choiceId": null', '"choiceId": "A", "choiceId": null', 1
                    )
                elif mutation == "trailing":
                    raw = json.dumps(raw) + " But this cannot work."
                elif mutation == "status_type":
                    raw["choices"]["A"]["status"] = True
                else:
                    raw["choices"]["A"]["evidence"] = {
                        "unknown_source": ["S9U9"],
                        "duplicate_source": ["S1U1"] * 2,
                        "too_many_sources": ["S1U1"] * 9,
                        "source_type": [True],
                    }[mutation]
                self.assertFalse(self.observed(raw, "choices")["format_valid"])
        for changes in (
            {"difficulty": True},
            {"explanation": "A replacement."},
            {"issues": ["x" * 601]},
            {"issues": ["error"] * 9},
            {"issues": [""]},
        ):
            self.assertFalse(
                self.observed({**self.teaching(), **changes}, "teaching")[
                    "format_valid"
                ]
            )

    def test_reasons_use_whole_response_bound_without_1200_character_cutoff(self):
        for role in ("choices", "teaching"):
            raw = self.response() if role == "choices" else self.teaching()
            target = raw["taskObstruction"] if role == "choices" else raw["assessment"]
            target["reason"] = "é" * 1300
            self.assertTrue(
                self.observed(json.dumps(raw, ensure_ascii=False), role)["format_valid"]
            )
            target["reason"] += "x" * (
                adapter.MAX_RAW_CHARACTERS - len(json.dumps(raw, ensure_ascii=False))
            )
            text = json.dumps(raw, ensure_ascii=False)
            self.assertEqual(len(text), adapter.MAX_RAW_CHARACTERS)
            self.assertTrue(self.observed(text, role)["format_valid"])
            self.assertFalse(self.observed(text + " ", role)["format_valid"])
        raw = self.response()
        raw["choices"]["A"]["reason"] = "A long choice reason. " * 100
        self.assertTrue(self.observed(raw, "choices")["format_valid"])

    def test_cross_case_role_contract_and_mutated_preparation_refused(self):
        choices = self.observed(self.response(), "choices")
        teaching = self.observed(self.teaching(), "teaching")
        other = adapter.prepare(
            question("What is the sum of two marbles and two more?"),
            self.context,
            self.records,
            self.selections,
        )
        with self.assertRaises(ValueError):
            adapter.combine(other, choices, teaching)
        with self.assertRaises(ValueError):
            adapter.combine(self.prepared, teaching, choices)
        legacy = copy.deepcopy(choices)
        legacy.pop("contract")
        with self.assertRaises(ValueError):
            adapter.combine(self.prepared, legacy, teaching)
        altered = copy.deepcopy(self.prepared)
        altered["payload"]["evidenceSources"][0]["units"][0]["text"] += " Altered."
        with self.assertRaises(ValueError):
            adapter.combine(altered, choices, teaching)
        altered = copy.deepcopy(self.prepared)
        altered["question"]["explanation"] = (
            "A different explanation with an unchanged old hash."
        )
        with self.assertRaises(ValueError):
            adapter.prompt(altered, "teaching")
        for role in ("unknown", None):
            with self.assertRaises(ValueError):
                adapter.observe("{}", self.prepared, role)
            with self.assertRaises(ValueError):
                adapter.output_config(role)

    def test_direct_malformed_observation_cannot_bypass_validator(self):
        choices = self.observed(self.response(), "choices")
        teaching = self.observed(self.teaching(), "teaching")
        choices["value"]["choices"].pop("D")
        self.assertEqual(
            adapter.combine(self.prepared, choices, teaching)["reason"],
            "invalid_review",
        )
        choices = self.observed(self.response(), "choices")
        choices["evidence_bindings"]["A"]["S1U1"]["original_start"] = 999
        self.assertEqual(
            adapter.combine(self.prepared, choices, teaching)["reason"],
            "invalid_review",
        )

    def test_binding_comparison_distinguishes_json_types_and_rejects_noncanonical_values(
        self,
    ):
        for role in ("choices", "teaching"):
            for mutated_start in (False, 0.0, float("nan"), {"not-json"}, "\ud800"):
                with self.subTest(role=role, value=repr(mutated_start)):
                    choices = self.observed(self.response(), "choices")
                    main = self.teaching()
                    main["assessment"]["evidence"] = ["S1U1"]
                    teaching = self.observed(main, "teaching")
                    target = choices if role == "choices" else teaching
                    field = "A" if role == "choices" else "main"
                    original = copy.deepcopy(target["evidence_bindings"])
                    self.assertIs(type(original[field]["S1U1"]["original_start"]), int)
                    self.assertEqual(original[field]["S1U1"]["original_start"], 0)
                    target["evidence_bindings"][field]["S1U1"]["original_start"] = (
                        mutated_start
                    )
                    if mutated_start is False:
                        self.assertEqual(original, target["evidence_bindings"])
                    self.assertEqual(
                        adapter.combine(self.prepared, choices, teaching)["reason"],
                        "invalid_review",
                    )

    def test_confident_wrong_or_contradictory_reason_is_not_a_truth_guarantee(self):
        raw = self.response()
        raw["taskObstruction"]["reason"] = (
            "No offered answer can possibly answer this question."
        )
        result = self.combined(raw)
        self.assertTrue(result["eligible"])
        self.assertIn("not factual certification", result["scope"])

    @unittest.skipIf(jsonschema is None, "Optional schema validator is unavailable.")
    def test_static_native_schemas_accept_contract_and_reject_extra_fields(self):
        for role in ("choices", "teaching"):
            config = adapter.output_config(role)
            schema = json.loads(
                config["textFormat"]["structure"]["jsonSchema"]["schema"]
            )
            raw = self.response() if role == "choices" else self.teaching()
            jsonschema.Draft202012Validator.check_schema(schema)
            jsonschema.validate(raw, schema)
            if role == "choices":
                self.assertEqual(list(schema["properties"])[0], "taskObstruction")
                for status in adapter.OBSTRUCTIONS:
                    jsonschema.validate(self.response(status=status), schema)
            raw["replacement"] = "Unasked-for teaching."
            with self.assertRaises(jsonschema.ValidationError):
                jsonschema.validate(raw, schema)


if __name__ == "__main__":
    unittest.main()
