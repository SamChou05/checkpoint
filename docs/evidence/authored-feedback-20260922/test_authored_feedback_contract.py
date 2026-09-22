"""Offline structural tests; no provider, source routing, or semantic approval."""

import copy
import itertools
import json
import unittest

from jsonschema import Draft202012Validator, ValidationError

from authored_feedback_contract import (
    CONTRACT_NAME,
    LEARNER_FIELDS,
    SLOTS,
    AuthoredFeedbackFormatError,
    adapt_author_response,
    author_schema,
    freeze_learner_payload,
    learner_content_digest,
    metadata,
    output_config,
)


def question():
    return {
        "prompt": "A rectangle is 9 cm long and 4 cm wide. What is its perimeter?",
        "choices": {"a": "26 cm", "b": "36 cm", "c": "13 cm", "d": "18 cm"},
        "explanation": "The perimeter is 2×9 + 2×4 = 26 cm.",
        "choiceFeedback": {
            "a": "Two sides of each length give 18 + 8 = 26 cm.",
            "b": "9×4 = 36 gives area in square centimeters, not perimeter.",
            "c": "9 + 4 = 13 adds only one side of each length.",
            "d": "2×9 = 18 counts only the two longer sides.",
        },
        "correctChoice": "a",
        "topic": "Perimeter",
        "difficulty": 1,
        "format": "Multiple Choice",
    }


def encoded(*questions):
    return json.dumps({"questions": {str(index): value for index, value in enumerate(questions)}}, ensure_ascii=False)


def adapt(*questions):
    return adapt_author_response(encoded(*questions), expected_count=len(questions))


def learner(question_row=None):
    row = adapt(question_row or question())["questions"][0]
    return {field: row[field] for field in LEARNER_FIELDS}


class AuthoredFeedbackContractTests(unittest.TestCase):
    def test_exported_schema_is_closed_and_orders_all_feedback_before_key(self):
        schema = author_schema(1)
        Draft202012Validator.check_schema(schema)
        Draft202012Validator(schema).validate({"questions": {"0": question()}})
        row = schema["properties"]["questions"]["properties"]["0"]
        self.assertEqual(list(row["properties"]), [
            "prompt", "choices", "explanation", "choiceFeedback", "correctChoice",
            "topic", "difficulty", "format", "skillID", "objectiveID", "objective",
        ])
        for name in ("choices", "choiceFeedback"):
            fixed = row["properties"][name]
            self.assertEqual(list(fixed["properties"]), list(SLOTS))
            self.assertEqual(fixed["required"], list(SLOTS))
            self.assertFalse(fixed["additionalProperties"])
        self.assertEqual(row["properties"]["correctChoice"]["enum"], list(SLOTS))
        self.assertFalse(row["additionalProperties"])
        self.assertFalse(schema["additionalProperties"])
        declaration = output_config(1)["textFormat"]["structure"]["jsonSchema"]
        self.assertEqual(declaration["name"], CONTRACT_NAME + "_n1")
        self.assertEqual(json.loads(declaration["schema"]), schema)
        self.assertNotIn("maxLength", declaration["schema"])
        self.assertNotIn("maxItems", declaration["schema"])
        self.assertEqual(metadata(1)["version"], "1")
        self.assertEqual(len(metadata(1)["sha256"]), 64)

    def test_schema_calls_return_independent_objects(self):
        original = output_config(1)
        mutated = author_schema(1)
        mutated["properties"]["questions"]["properties"]["0"]["properties"]["choices"]["properties"]["a"]["type"] = "integer"
        self.assertEqual(output_config(1), original)

    def test_all24_slot_orders_and4_keys_preserve_exact_choice_feedback_associations(self):
        texts = ['  "e\u0301"\t ', '"a  b"', "−1", "None\r\n"]
        choices = dict(zip(SLOTS, texts, strict=True))
        explanations = {slot: f"  Feedback for {text!r} keeps its exact spelling.\r\n"
                        for slot, text in choices.items()}
        for order in itertools.permutations(SLOTS):
            for key in SLOTS:
                with self.subTest(order=order, key=key):
                    q = {**question(), "choices": {slot: choices[slot] for slot in order},
                         "choiceFeedback": {slot: explanations[slot] for slot in reversed(order)},
                         "correctChoice": key,
                         "explanation": "  This main keeps é and e\u0301 distinct.\r\n  "}
                    before = copy.deepcopy(q)
                    result = adapt(q)["questions"][0]
                    self.assertEqual(result["choices"], texts)
                    self.assertEqual(result["expectedAnswer"].encode(), choices[key].encode())
                    self.assertEqual(result["explanation"].encode(), q["explanation"].encode())
                    self.assertEqual(result["choiceExplanations"],
                                     {choices[slot]: explanations[slot] for slot in SLOTS})
                    self.assertEqual(q, before)

    def test_every_exact_duplicate_pair_is_rejected_before_feedback_can_overwrite(self):
        for left, right in itertools.combinations(SLOTS, 2):
            q = question()
            q["choices"][right] = q["choices"][left]
            self.assertNotEqual(q["choiceFeedback"][left], q["choiceFeedback"][right])
            with self.subTest(left=left, right=right):
                # The native schema cannot express this cross-slot condition.
                Draft202012Validator(author_schema(1)).validate({"questions": {"0": q}})
                with self.assertRaisesRegex(AuthoredFeedbackFormatError, "Duplicate exact choice"):
                    adapt(q)

    def test_learner_field_limits_reject_without_clipping_or_trimming(self):
        cases = [("prompt", 12, 320), ("explanation", 12, 420)]
        for field, minimum, maximum in cases:
            for size in (minimum, maximum):
                q = question()
                q[field] = "é" * size
                self.assertEqual(adapt(q)["questions"][0][field], q[field])
            for value in ("x" * (minimum - 1), "x" * (maximum + 1), " " * minimum, 123, None):
                q = question()
                q[field] = value
                with self.subTest(field=field, value=str(value)[:20]):
                    with self.assertRaises(AuthoredFeedbackFormatError):
                        adapt(q)
        for size in (12, 280):
            q = question()
            q["choiceFeedback"]["a"] = "é" * size
            self.assertEqual(adapt(q)["questions"][0]["choiceExplanations"]["26 cm"], "é" * size)
        for value in ("x" * 11, "x" * 281, " " * 20, 123, None):
            q = question()
            q["choiceFeedback"]["a"] = value
            with self.subTest(feedback=str(value)[:20]):
                with self.assertRaises(AuthoredFeedbackFormatError):
                    adapt(q)

    def test_each_choice_bound_and_blank_value_is_checked_exactly(self):
        for value in ("", "  \t\r\n", "x" * 141, 1, True, None):
            q = question()
            q["choices"]["d"] = value
            with self.subTest(value=value):
                with self.assertRaises(AuthoredFeedbackFormatError):
                    adapt(q)
        q = question()
        q["choices"]["d"] = "é" * 140
        self.assertEqual(adapt(q)["questions"][0]["choices"][3], q["choices"]["d"])

    def test_missing_extra_and_wrong_type_slots_rejected_by_schema_and_adapter(self):
        for field in ("choices", "choiceFeedback"):
            for kind in ("missing", "extra", "list", "scalar", "null"):
                q = question()
                if kind == "missing":
                    del q[field]["b"]
                elif kind == "extra":
                    q[field]["e"] = "Unexpected extra text"
                else:
                    q[field] = {"list": list(q[field].values()), "scalar": "four slots", "null": None}[kind]
                with self.subTest(field=field, kind=kind):
                    with self.assertRaises(ValidationError):
                        Draft202012Validator(author_schema(1)).validate({"questions": {"0": q}})
                    with self.assertRaises(AuthoredFeedbackFormatError):
                        adapt(q)

    def test_answer_slot_must_be_exact_enum_and_difficulty_exact_integer(self):
        for value in ("A", "a ", "e", "26 cm", 0, True, None):
            q = {**question(), "correctChoice": value}
            with self.subTest(key=value):
                with self.assertRaises(AuthoredFeedbackFormatError):
                    adapt(q)
        for value in (True, False, 1.0, 0, 6, "3", None):
            q = {**question(), "difficulty": value}
            with self.subTest(difficulty=value):
                with self.assertRaises(AuthoredFeedbackFormatError):
                    adapt(q)

    def test_no_extra_content_replacement_or_forged_policy_fields(self):
        for key, value in (("expectedAnswer", "36 cm"), ("choiceExplanations", {}),
                           ("verificationVersion", 1), ("verificationPolicyRevision", 99),
                           ("valid", True), ("replacement", "different question")):
            with self.subTest(key=key):
                with self.assertRaises(AuthoredFeedbackFormatError):
                    adapt({**question(), key: value})
        for field in question():
            q = question()
            del q[field]
            with self.subTest(missing=field):
                with self.assertRaises(AuthoredFeedbackFormatError):
                    adapt(q)

    def test_strict_json_rejects_duplicates_fences_trailing_bytes_and_nonfinite_numbers(self):
        valid = encoded(question())
        invalid = [
            valid.replace('"correctChoice": "a"', '"correctChoice": "a", "correctChoice": "b"'),
            valid.replace('"a": "26 cm"', '"a": "26 cm", "a": "36 cm"'),
            '{"questions": [], "questions": []}',
            "```json\n" + valid + "\n```", valid + " {}", valid[:-1],
            valid.replace('"difficulty": 1', '"difficulty": NaN'),
            valid.replace('"difficulty": 1', '"difficulty": Infinity'),
            valid.replace('"difficulty": 1', '"difficulty": 1e999'),
            valid.encode(), {"questions": {"0": question()}}, None,
        ]
        for raw in invalid:
            with self.subTest(raw=str(raw)[:80]):
                with self.assertRaises(AuthoredFeedbackFormatError):
                    adapt_author_response(raw, expected_count=1)

    def test_trusted_count_is_exact_and_rejects_instead_of_slicing_or_filling(self):
        for count in (True, False, 0, 41, 1.0, "1", None):
            with self.subTest(count=count):
                with self.assertRaises(AuthoredFeedbackFormatError):
                    adapt_author_response(encoded(question()), expected_count=count)
                for build in (author_schema, output_config, metadata):
                    with self.assertRaises(AuthoredFeedbackFormatError):
                        build(count)
        for questions, count in (([], 1), ([question()], 2), ([question(), question()], 1)):
            with self.subTest(actual=len(questions), expected=count):
                with self.assertRaises(AuthoredFeedbackFormatError):
                    adapt_author_response(encoded(*questions), expected_count=count)
        self.assertEqual(len(adapt_author_response(encoded(*[question()] * 40), expected_count=40)["questions"]), 40)

    def test_every_supported_count_has_exact_native_identities_and_no_model_index(self):
        for count in range(1, 41):
            with self.subTest(count=count):
                schema = author_schema(count)
                Draft202012Validator.check_schema(schema)
                identities = schema["properties"]["questions"]
                self.assertEqual(identities["required"], [str(i) for i in range(count)])
                self.assertEqual(list(identities["properties"]), identities["required"])
                self.assertFalse(identities["additionalProperties"])
                self.assertNotIn("index", identities["properties"]["0"]["properties"])
                self.assertEqual(metadata(count)["name"], CONTRACT_NAME + f"_n{count}")
                payload = json.loads(encoded(*[question()] * count))
                Draft202012Validator(schema).validate(payload)
                self.assertEqual(len(adapt_author_response(json.dumps(payload), expected_count=count)["questions"]), count)
                for kind in ("missing", "extra", "renamed"):
                    changed = copy.deepcopy(payload)
                    if kind == "missing":
                        del changed["questions"]["0"]
                    elif kind == "extra":
                        changed["questions"][str(count)] = question()
                    else:
                        changed["questions"]["00"] = changed["questions"].pop("0")
                    with self.assertRaises(ValidationError):
                        Draft202012Validator(schema).validate(changed)
                    with self.assertRaises(AuthoredFeedbackFormatError):
                        adapt_author_response(json.dumps(changed), expected_count=count)

    def test_all24_question_map_orders_restore_trusted_order_without_changing_content(self):
        questions = {str(i): {**question(), "prompt": f"Question {i}: Which perimeter follows from these dimensions?"}
                     for i in range(4)}
        for order in itertools.permutations(questions):
            payload = {"questions": {index: questions[index] for index in order}}
            result = adapt_author_response(json.dumps(payload), expected_count=4)["questions"]
            self.assertEqual([row["prompt"] for row in result], [questions[str(i)]["prompt"] for i in range(4)])
        for invalid in ({"questions": list(questions.values())},
                        {"questions": {"0": {**question(), "index": 0}}}):
            with self.assertRaises(AuthoredFeedbackFormatError):
                adapt_author_response(json.dumps(invalid), expected_count=1)

    def test_invalid_sibling_aborts_entire_batch_and_never_mutates_inputs(self):
        good, bad = question(), question()
        bad["choiceFeedback"]["d"] = "x" * 281
        original = copy.deepcopy([good, bad])
        with self.assertRaises(AuthoredFeedbackFormatError):
            adapt(good, bad)
        self.assertEqual([good, bad], original)

    def test_optional_metadata_preserves_absence_and_exact_strings_without_defaults(self):
        q = question()
        q.update(skillID="  skill-1  ", objectiveID="", objective="Objective\r\n")
        result = adapt(q)["questions"][0]
        for key in ("skillID", "objectiveID", "objective", "topic", "difficulty", "format"):
            self.assertEqual(result[key], q[key])
        result_without = adapt(question())["questions"][0]
        self.assertFalse(set(("skillID", "objectiveID", "objective")) & result_without.keys())
        for key in ("skillID", "objectiveID", "objective", "topic", "format"):
            with self.subTest(key=key):
                with self.assertRaises(AuthoredFeedbackFormatError):
                    adapt({**question(), key: None})

    def test_unpaired_unicode_surrogates_cannot_enter_utf8_learner_or_metadata_text(self):
        for field in ("prompt", "explanation", "topic", "objective"):
            q = {**question(), field: "Enough text around \ud800 a surrogate"}
            with self.subTest(field=field):
                with self.assertRaises(AuthoredFeedbackFormatError):
                    adapt(q)
        for field in ("choices", "choiceFeedback"):
            q = question()
            q[field]["a"] = "Enough text around \ud800 a surrogate"
            with self.subTest(field=field):
                with self.assertRaises(AuthoredFeedbackFormatError):
                    adapt(q)

    def test_freeze_returns_deep_copy_and_digest_preserves_every_text_change(self):
        original = learner()
        frozen = freeze_learner_payload(original)
        digest = learner_content_digest(original)
        self.assertEqual(frozen, original)
        self.assertIsNot(frozen, original)
        self.assertIsNot(frozen["choices"], original["choices"])
        self.assertIsNot(frozen["choiceExplanations"], original["choiceExplanations"])
        for field in ("prompt", "explanation"):
            changed = copy.deepcopy(original)
            changed[field] += " "
            self.assertNotEqual(learner_content_digest(changed), digest)
        changed = copy.deepcopy(original)
        changed["choiceExplanations"][changed["choices"][0]] += " "
        self.assertNotEqual(learner_content_digest(changed), digest)
        frozen["choices"].reverse()
        frozen["choiceExplanations"]["26 cm"] = "Mutated copy only."
        self.assertEqual(learner_content_digest(original), digest)

    def test_existing_learner_map_requires_exact_keys_and_no_display_key_repair(self):
        source = learner()
        for change in ("missing", "extra", "wrong_type", "renamed_choice", "wrong_answer", "extra_policy"):
            value = copy.deepcopy(source)
            if change == "missing":
                del value["choiceExplanations"]["36 cm"]
            elif change == "extra":
                value["choiceExplanations"]["OTHER"] = "Another unexpected explanation."
            elif change == "wrong_type":
                value["choiceExplanations"] = list(value["choiceExplanations"].values())
            elif change == "renamed_choice":
                value["choices"][1] = "36 CM"
            elif change == "wrong_answer":
                value["expectedAnswer"] = "26 cm "
            else:
                value["verificationPolicyRevision"] = 99
            with self.subTest(change=change):
                with self.assertRaises(AuthoredFeedbackFormatError):
                    freeze_learner_payload(value)
        for field in LEARNER_FIELDS:
            value = copy.deepcopy(source)
            del value[field]
            with self.subTest(missing=field):
                with self.assertRaises(AuthoredFeedbackFormatError):
                    freeze_learner_payload(value)

    def test_freeze_does_not_normalize_unicode_whitespace_or_choice_order(self):
        q = question()
        q["choices"] = {"a": "é", "b": "e\u0301", "c": "X", "d": " x "}
        original = learner(q)
        self.assertEqual(freeze_learner_payload(original), original)
        for order in itertools.permutations(original["choices"]):
            value = {**original, "choices": list(order)}
            self.assertEqual(freeze_learner_payload(value)["choices"], list(order))

    def test_structural_success_does_not_claim_semantic_truth_or_shuffle_safety(self):
        q = question()
        q.update(prompt="What is the value of 2 + 2?", correctChoice="d",
                 choices={"a": "4", "b": "2", "c": "two", "d": "3"},
                 explanation="Only the fourth choice is correct because 2 + 2 = 3.",
                 choiceFeedback={slot: "This proposed answer is incorrectly asserted to be right."
                                 for slot in SLOTS})
        result = adapt(q)["questions"][0]
        self.assertEqual(result["expectedAnswer"], "3")
        self.assertEqual(result["explanation"], q["explanation"])
        self.assertNotIn("verificationVersion", result)
        self.assertNotIn("verificationPolicyRevision", result)
        # Later independent solution, semantic-pair, teaching and shuffle-safe
        # admission checks must reject this, rather than this adapter repairing it.


if __name__ == "__main__":
    unittest.main()
