"""Pure split-role and exact-reference contracts; no provider or fetch calls."""

import copy
import hashlib
import json
import unittest

try:
    import jsonschema
except ImportError:
    jsonschema = None

from evals import split_evidence_review as adapter


def question():
    return {
        "prompt": "  In the stated counting exercise, what is 2 + 2?\r\n",
        "choices": ["4", "5", "3", "2"],
        "expectedAnswer": "4",
        "explanation": "  Joining two objects to two objects gives four objects in total.\n",
        "choiceExplanations": {},
        "topic": "Counting",
        "difficulty": 3,
        "format": "Multiple Choice",
        "verificationPolicyRevision": 999,
        "verificationVersion": 1,
    }


def capture(text, **changes):
    return {
        "status": "acquired",
        "source_text": text,
        "text_sha256": hashlib.sha256(text.encode()).hexdigest(),
        "text_characters": len(text),
        "raw_content_sha256": "a" * 64,
        "final_url": "https://example.org/counting",
        "retrieved_at_utc": "2026-09-08T00:00:00Z",
        "truncated": False,
        "source_text_complete": True,
        "representation_limits": ["Plain text; illustrations unavailable."],
        **changes,
    }


class SplitEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.q = question()
        self.context = {
            "goal": {"title": "Count objects", "expectedAnswer": "KEY_METADATA"},
            "sourceDocuments": [{"text": "OLD_SOURCE_SUMMARY"}],
            "challenge": "CHALLENGE_HYPOTHESIS",
            "searchQuery": "PRIVATE_SEARCH_QUERY",
            "rationale": "ADVERSARIAL_RATIONALE",
            "history": "HISTORY_VERDICT",
            "independentSolutions": "PRIOR_SOLVER_OUTPUT",
        }
        self.records = [
            capture("Before. Two objects plus two more gives four objects. After.")
        ]
        self.selections = [{"record_index": 0, "start": 8, "end": 53}]
        self.prepared = adapter.prepare(
            self.q, self.context, self.records, self.selections
        )
        self.correct = next(
            k
            for k, v in self.prepared["payload"]["item"]["choices"].items()
            if v == "4"
        )
        self.rival = next(k for k in adapter.LETTERS if k != self.correct)

    def choice_response(self):
        return {
            "task": "Find the total count after joining the two groups.",
            "choices": {
                letter: {
                    "reason": "This is the total."
                    if letter == self.correct
                    else "This does not equal the total.",
                    "status": "supported" if letter == self.correct else "refuted",
                    "evidence": ["S1U1"],
                }
                for letter in adapter.LETTERS
            },
            "issues": [],
        }

    def teaching_response(self):
        return {
            "assessment": {
                "reason": "The main applies the stated counts to obtain the total.",
                "status": "supported",
                "evidence": ["S1U1"],
            },
            "issues": [],
            "difficulty": 3,
        }

    def observe(self, value, role, prepared=None):
        return adapter.observe(
            value if type(value) is str else json.dumps(value),
            self.prepared if prepared is None else prepared,
            role,
        )

    def combined(self, choices=None, teaching=None, floor=3):
        return adapter.combine(
            self.prepared,
            self.observe(
                self.choice_response() if choices is None else choices, "choices"
            ),
            self.observe(
                self.teaching_response() if teaching is None else teaching, "teaching"
            ),
            floor,
        )

    def test_role_inputs_exclude_answers_challenge_history_and_prior_role_output(self):
        self.q.update(
            prior_solver="PRIOR_SOLVER_OUTPUT", rationale="ADVERSARIAL_RATIONALE"
        )
        prepared = adapter.prepare(self.q, self.context, self.records, self.selections)
        original = copy.deepcopy((self.q, self.context, prepared))
        system, solver = adapter.prompt(prepared, "choices")
        _, teaching = adapter.prompt(prepared, "teaching")
        a, b = json.loads(solver), json.loads(teaching)
        self.assertEqual(a["item"]["prompt"].encode(), self.q["prompt"].encode())
        self.assertEqual(
            b["item"].pop("explanation").encode(), self.q["explanation"].encode()
        )
        self.assertEqual(a, b)
        self.assertNotIn("explanation", a["item"])
        self.assertIn("AS AN ANSWER TO THIS STEM", system)
        self.assertNotIn('"solutions"', system)
        for raw in (solver, teaching):
            for secret in (
                "KEY_METADATA",
                "OLD_SOURCE_SUMMARY",
                "CHALLENGE_HYPOTHESIS",
                "PRIVATE_SEARCH_QUERY",
                "ADVERSARIAL_RATIONALE",
                "HISTORY_VERDICT",
                "PRIOR_SOLVER_OUTPUT",
                "expectedAnswer",
                "verificationPolicyRevision",
            ):
                self.assertNotIn(secret, raw)
            self.assertNotIn("difficulty", json.loads(raw)["item"])
        self.assertEqual((self.q, self.context, prepared), original)
        with self.assertRaises(ValueError):
            adapter.prompt(prepared, "unknown")

    def test_source_units_reassemble_exact_unicode_long_text_offsets_and_hashes(self):
        for selected in (
            "é e\u0301  x\r\n" * 570,
            "é e\u0301  x" * 700,
            "a" * 1500 + "\n" + "b" * 2600 + "\n" + "c" * 900,
        ):
            with self.subTest(length=len(selected)):
                whole = "PREFIX. " + selected + " SUFFIX"
                record = capture(whole, truncated=True, source_text_complete=False)
                selections = [{"record_index": 0, "start": 8, "end": 8 + len(selected)}]
                prepared = adapter.prepare(self.q, self.context, [record], selections)
                display = prepared["payload"]["evidenceSources"][0]
                units = display["units"]
                self.assertGreater(len(units), 1)
                self.assertEqual(
                    "".join(u["text"] for u in units).encode(), selected.encode()
                )
                offset = 8
                for i, unit in enumerate(units, 1):
                    self.assertEqual(unit["id"], f"S1U{i}")
                    self.assertLessEqual(len(unit["text"]), adapter.UNIT_CHARACTERS)
                    bound = prepared["source_units"][unit["id"]]
                    self.assertEqual(
                        (bound["original_start"], bound["original_end"]),
                        (offset, offset + len(unit["text"])),
                    )
                    self.assertEqual(
                        whole[bound["original_start"] : bound["original_end"]],
                        unit["text"],
                    )
                    self.assertEqual(
                        bound["text_sha256"],
                        hashlib.sha256(unit["text"].encode()).hexdigest(),
                    )
                    self.assertEqual(
                        bound["source_record_sha256"], adapter.previous._hash(record)
                    )
                    offset = bound["original_end"]
                self.assertEqual(offset, 8 + len(selected))
                self.assertTrue(display["omitsAcquiredText"])
                self.assertFalse(display["sourceTextComplete"])
                self.assertEqual(
                    display["representationLimits"], record["representation_limits"]
                )

    def test_multiple_spans_have_distinct_ids_and_preserve_source_order(self):
        record = capture("First selected block. Omitted middle. Second selected block.")
        spans = [
            {"record_index": 0, "start": 37, "end": len(record["source_text"])},
            {"record_index": 0, "start": 0, "end": 21},
        ]
        prepared = adapter.prepare(self.q, self.context, [record], spans)
        display = prepared["payload"]["evidenceSources"]
        self.assertEqual([s["units"][0]["id"] for s in display], ["S1U1", "S2U1"])
        self.assertEqual(
            [s["units"][0]["text"] for s in display],
            [record["source_text"][37:], record["source_text"][:21]],
        )

    def test_fixed_letter_coverage_and_strict_response_envelopes(self):
        for change in (
            "missing",
            "unknown",
            "array",
            "replacement",
            "duplicate",
            "prose",
            "type",
        ):
            with self.subTest(change=change):
                raw = self.choice_response()
                if change == "missing":
                    raw["choices"].pop("D")
                elif change == "unknown":
                    raw["choices"]["E"] = raw["choices"].pop("D")
                elif change == "array":
                    raw["choices"] = list(raw["choices"].values())
                elif change == "replacement":
                    raw["explanation"] = "An unsolicited rewrite."
                elif change == "duplicate":
                    raw = json.dumps(raw).replace(
                        '"task":', '"task":"Discarded task", "task":'
                    )
                elif change == "prose":
                    raw = json.dumps(raw) + " But the conclusion is impossible."
                else:
                    raw["choices"]["A"]["status"] = True
                self.assertFalse(self.observe(raw, "choices")["format_valid"])
        for changes in (
            {"difficulty": True},
            {"difficulty": 0},
            {"answer": "4"},
            {
                "assessment": {
                    "status": "supported",
                    "reason": "Reason without references.",
                }
            },
        ):
            self.assertFalse(
                self.observe({**self.teaching_response(), **changes}, "teaching")[
                    "format_valid"
                ]
            )

    def test_evidence_ids_require_known_distinct_bounded_references(self):
        for refs in (
            ["not-supplied"],
            ["S1U1", "S1U1"],
            [True],
            {"S1U1": True},
            ["S1U1"] * 9,
        ):
            for role in ("choices", "teaching"):
                with self.subTest(refs=refs, role=role):
                    raw = (
                        self.choice_response()
                        if role == "choices"
                        else self.teaching_response()
                    )
                    assessment = (
                        raw["choices"]["A"] if role == "choices" else raw["assessment"]
                    )
                    assessment["evidence"] = refs
                    self.assertFalse(self.observe(raw, role)["format_valid"])
        solved = self.observe(self.choice_response(), "choices")
        self.assertEqual(
            solved["evidence_bindings"]["A"]["S1U1"],
            self.prepared["source_units"]["S1U1"],
        )
        solved["evidence_bindings"]["A"]["S1U1"]["original_start"] = 999
        self.assertEqual(self.prepared["source_units"]["S1U1"]["original_start"], 8)

    def test_supported_teaching_cannot_rescue_solver_vetoes(self):
        for failure in ("uncertain", "zero", "multiple", "disagreement", "issues"):
            with self.subTest(failure=failure):
                raw = self.choice_response()
                if failure == "uncertain":
                    raw["choices"][self.rival]["status"] = "uncertain"
                    reason = "solver_uncertain"
                elif failure == "zero":
                    raw["choices"][self.correct]["status"] = "refuted"
                    reason = "solver_zero_supported"
                elif failure == "multiple":
                    raw["choices"][self.rival]["status"] = "supported"
                    reason = "solver_multiple_supported"
                elif failure == "disagreement":
                    raw["choices"][self.correct]["status"] = "refuted"
                    raw["choices"][self.rival]["status"] = "supported"
                    reason = "answer_disagreement"
                else:
                    raw["issues"] = ["The task requires an unstated assumption."]
                    reason = "solver_issues"
                result = self.combined(choices=raw)
                self.assertFalse(result["eligible"])
                self.assertEqual(result["reason"], reason)
                self.assertIsNone(result["question"])

    def test_teaching_objections_and_difficulty_remain_enforced(self):
        for status, issues, level, reason in (
            ("refuted", [], 3, "teaching_refuted"),
            ("uncertain", [], 3, "teaching_uncertain"),
            (
                "supported",
                ["The main introduces an unsupported cause."],
                3,
                "teaching_issues",
            ),
            ("supported", [], 2, "difficulty_floor"),
        ):
            with self.subTest(reason=reason):
                raw = self.teaching_response()
                raw["assessment"]["status"], raw["issues"], raw["difficulty"] = (
                    status,
                    issues,
                    level,
                )
                result = self.combined(teaching=raw)
                self.assertFalse(result["eligible"])
                self.assertEqual(result["reason"], reason)
        self.assertTrue(
            self.combined(
                teaching={**self.teaching_response(), "difficulty": 2}, floor=2
            )["eligible"]
        )

    def test_invalid_review_cannot_be_counted_as_a_semantic_catch(self):
        raw = self.choice_response()
        raw["choices"].pop("A")
        result = self.combined(choices=raw)
        self.assertFalse(result["eligible"])
        self.assertEqual(result["reason"], "invalid_review")

    def test_cross_case_swapped_role_and_changed_source_joins_fail(self):
        choices = self.observe(self.choice_response(), "choices")
        teaching = self.observe(self.teaching_response(), "teaching")
        other = adapter.prepare(
            {**self.q, "prompt": self.q["prompt"] + "?"},
            self.context,
            self.records,
            self.selections,
        )
        other_choices = self.observe(self.choice_response(), "choices", other)
        for left, right in ((teaching, choices), (other_choices, teaching)):
            with self.assertRaises(ValueError):
                adapter.combine(self.prepared, left, right)
        for location in ("payload", "source_units"):
            mutated = copy.deepcopy(self.prepared)
            if location == "payload":
                mutated[location]["evidenceSources"][0]["units"][0]["text"] += (
                    " Changed."
                )
            else:
                mutated[location]["S1U1"]["original_start"] = 9
            with self.assertRaises(ValueError):
                adapter.combine(mutated, choices, teaching)

    def test_prepared_main_and_key_mutation_cannot_reuse_original_bindings(self):
        choices = self.observe(self.choice_response(), "choices")
        teaching = self.observe(self.teaching_response(), "teaching")
        for field, value in (
            ("explanation", self.q["explanation"] + " Changed."),
            ("expectedAnswer", "3"),
        ):
            with self.subTest(field=field):
                mutated = copy.deepcopy(self.prepared)
                mutated["question"][field] = value
                with self.assertRaises(ValueError):
                    adapter.prompt(mutated, "teaching")
                with self.assertRaises(ValueError):
                    adapter.combine(mutated, choices, teaching)

    def test_success_preserves_exact_question_content_without_stamps(self):
        result = self.combined()
        self.assertTrue(result["eligible"])
        self.assertEqual(result["supported_choice_ids"], [self.correct])
        for field in ("prompt", "choices", "expectedAnswer", "explanation"):
            self.assertEqual(result["question"][field], self.q[field])
        self.assertEqual(result["question"]["choiceExplanations"], {})
        self.assertNotIn("verificationVersion", result["question"])
        self.assertNotIn("verificationPolicyRevision", result["question"])

    def test_confident_wrong_model_labels_are_not_factual_proof(self):
        wrong = {
            **self.q,
            "expectedAnswer": "3",
            "explanation": "Two plus two equals three, so the stated count is three.",
        }
        prepared = adapter.prepare(wrong, self.context, self.records, self.selections)
        wrong_id = next(
            k for k, v in prepared["payload"]["item"]["choices"].items() if v == "3"
        )
        raw = self.choice_response()
        for key, assessment in raw["choices"].items():
            assessment["status"] = "supported" if key == wrong_id else "refuted"
            assessment["reason"] = (
                "The model incorrectly asserts this status despite the arithmetic."
            )
        result = adapter.combine(
            prepared,
            self.observe(raw, "choices", prepared),
            self.observe(self.teaching_response(), "teaching", prepared),
        )
        self.assertTrue(result["eligible"])
        self.assertEqual(result["question"]["expectedAnswer"], "3")

    @unittest.skipIf(
        jsonschema is None,
        "Optional jsonschema package is available in the live-review test environment.",
    )
    def test_native_schemas_validate_shapes_but_do_not_prove_reference_or_semantic_validity(
        self,
    ):
        for role, raw in (
            ("choices", self.choice_response()),
            ("teaching", self.teaching_response()),
        ):
            with self.subTest(role=role):
                config = adapter.output_config(role)
                self.assertEqual(config["textFormat"]["type"], "json_schema")
                schema = json.loads(
                    config["textFormat"]["structure"]["jsonSchema"]["schema"]
                )
                jsonschema.Draft202012Validator.check_schema(schema)
                jsonschema.validate(raw, schema)
                with self.assertRaises(jsonschema.ValidationError):
                    jsonschema.validate(
                        {**raw, "replacement": "Not permitted."}, schema
                    )
                if role == "choices":
                    del raw["choices"]["D"]
                    with self.assertRaises(jsonschema.ValidationError):
                        jsonschema.validate(raw, schema)
                else:
                    raw["assessment"]["evidence"] = ["unknown-server-id"]
                    jsonschema.validate(raw, schema)
                    self.assertFalse(self.observe(raw, role)["format_valid"])


if __name__ == "__main__":
    unittest.main()
