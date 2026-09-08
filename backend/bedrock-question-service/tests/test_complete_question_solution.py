import copy
import json
import unittest

from complete_question_solution import (
    COMPLETE_SOLUTION_SYSTEM_PROMPT,
    CompleteSolutionFormatError,
    build_solver_prompt,
    rejection_reason,
    validate_batch,
)


def question(index=0, *, choices=None, answer=None):
    choices = choices or [
        "She walks to school.",
        "She walked to school.",
        "She visited school.",
        "She studied at school.",
    ]
    return {
        "index": index,
        "prompt": "Which sentence is not in the past tense?",
        "choices": choices,
        "expectedAnswer": answer or choices[0],
        "topic": "Verb tense",
        "skillID": "tense",
        "objectiveID": "identify-non-past",
        "difficulty": 4,
        "explanation": "PRIVATE AUTHOR FEEDBACK",
        "choiceExplanations": {choice: "PRIVATE CHOICE FEEDBACK" for choice in choices},
        "verificationVersion": 1,
        "verificationPolicyRevision": 99,
    }


def record(item, judgments=None):
    judgments = judgments or ["supported", "refuted", "refuted", "refuted"]
    return {
        "index": item["index"],
        "choices": [
            {
                "choice": choice,
                "judgment": judgment,
                "reason": f"Independent declared answer-adequacy reason {index}.",
            }
            for index, (choice, judgment) in enumerate(
                zip(item["choices"], judgments, strict=True)
            )
        ],
    }


def raw(*records):
    return json.dumps({"solutions": list(records)}, ensure_ascii=False)


def payload(prompt):
    return json.loads(prompt.split("\n", 1)[1].rsplit("\n", 1)[0])


class CompleteQuestionSolutionTests(unittest.TestCase):
    def test_prompt_whitelists_metadata_and_preserves_subject_content(self):
        item = question()
        item["prompt"] = '    s = "e\u0301  x"\r\nWhich exact value is stored?\t '
        item["choices"] = [' "e\u0301  x" ', '"e x"', '"E X"', '""']
        item["expectedAnswer"] = item["choices"][0]
        request = {
            "goal": {
                "title": "Read literal Unicode text",
                "contentTopics": ["Python strings"],
                "needsSkillMap": False,
                "expectedAnswer": "PRIVATE NESTED KEY",
                "difficulty": 99,
                "history": "PRIVATE NESTED HISTORY",
            },
            "skillMap": {
                "version": 1,
                "growthMode": "automatic",
                "explanation": "PRIVATE MAP FEEDBACK",
                "skills": [{
                    "id": "text",
                    "name": "String values",
                    "detail": 'Keep "a  b" unchanged.\n    source',
                    "challenge": "adaptive",
                    "difficulty": 99,
                    "objectives": [{
                        "id": "literal", "name": "Trace literal strings",
                        "detail": 'Distinguish "é" from "e\u0301".',
                        "expectedAnswer": "PRIVATE OBJECTIVE KEY",
                    }],
                }],
            },
            "sourceDocuments": [{
                "name": "source.py", "text": '    s = "e\u0301  x"\r\n',
                "url": "https://example.invalid/source", "truncated": False,
                "choiceExplanations": "PRIVATE SOURCE FEEDBACK",
            }],
            "existingQuestionCoverage": [item],
            "adaptiveSkillPlans": [{"recentMistakes": [item]}],
            "minimumDifficulty": 4,
            "expectedAnswer": "PRIVATE REQUEST KEY",
        }
        originals = copy.deepcopy((item, request))
        system, user = build_solver_prompt([item], request)
        data = payload(user)
        self.assertEqual(system, COMPLETE_SOLUTION_SYSTEM_PROMPT)
        self.assertNotIn("PRIVATE", user)
        for field in (
            "expectedAnswer", "choiceExplanations", "explanation", "difficulty",
            "existingQuestionCoverage", "adaptiveSkillPlans", "verificationVersion",
        ):
            self.assertNotIn(f'"{field}"', user)
        self.assertEqual(set(data), {"goal", "skillMap", "sourceDocuments", "items"})
        self.assertEqual(data["items"][0]["prompt"].encode(), item["prompt"].encode())
        self.assertEqual(data["items"][0]["choices"], item["choices"])
        self.assertEqual(data["sourceDocuments"][0]["text"], request["sourceDocuments"][0]["text"])
        self.assertFalse(data["sourceDocuments"][0]["truncated"])
        self.assertEqual(data["skillMap"]["skills"][0]["detail"], request["skillMap"]["skills"][0]["detail"])
        self.assertEqual((item, request), originals)

    def test_authored_key_and_feedback_cannot_change_solver_input(self):
        first, second = question(), question()
        second.update(expectedAnswer=second["choices"][1], explanation="CHANGED PRIVATE")
        second["choiceExplanations"] = {}
        second["difficulty"] = 1
        self.assertEqual(
            build_solver_prompt([first], {}), build_solver_prompt([second], {})
        )
        second["choices"][0] = "She will walk to school."
        self.assertNotEqual(
            build_solver_prompt([first], {}), build_solver_prompt([second], {})
        )

    def test_subject_prose_is_not_scrubbed_as_if_metadata(self):
        source = 'A JSON example has a field called "expectedAnswer".\n    Keep spaces.'
        _, user = build_solver_prompt(
            [question()], {"sourceDocuments": [{"name": "JSON", "text": source}]}
        )
        self.assertEqual(payload(user)["sourceDocuments"][0]["text"], source)

    def test_reordered_batch_and_choice_rows_join_exactly_without_mutation(self):
        first = question()
        second = question(1, choices=[
            "She walked to school.", "She visited school.",
            "She will walk to school.", "She studied at school.",
        ], answer="She will walk to school.")
        records = [record(first), record(second, ["refuted", "refuted", "supported", "refuted"])]
        records[0]["choices"].reverse()
        records[1]["choices"] = records[1]["choices"][2:] + records[1]["choices"][:2]
        items = [second, first]
        originals = copy.deepcopy((items, records))
        validated = validate_batch("```json\n" + raw(*reversed(records)) + "\n```", items)
        self.assertEqual([row["index"] for row in validated], [0, 1])
        for item, solution in zip([first, second], validated, strict=True):
            self.assertEqual([r["choice"] for r in solution["choices"]], item["choices"])
            self.assertIsNone(rejection_reason(solution, item))
        _, user = build_solver_prompt(items, {})
        self.assertEqual([q["index"] for q in payload(user)["items"]], [0, 1])
        self.assertEqual((items, records), originals)
        validated[0]["choices"][0]["reason"] = "Changed copy"
        self.assertEqual((items, records), originals)

    def test_mixed_batch_eligibility_keeps_original_indexes_for_caller_reindex(self):
        items = [question(i) for i in range(6)]
        records = [
            record(items[0], ["refuted"] * 4),
            record(items[1]),
            record(items[2], ["supported", "supported", "refuted", "refuted"]),
            record(items[3], ["supported", "uncertain", "refuted", "refuted"]),
            record(items[4]),
            record(items[5], ["refuted", "supported", "refuted", "refuted"]),
        ]
        normalized = validate_batch(raw(*reversed(records)), items)
        decisions = [rejection_reason(r, items[r["index"]]) for r in normalized]
        self.assertEqual(decisions, [
            "solver_zero_supported", None, "solver_multiple_supported",
            "solver_uncertain", None, "answer_disagreement",
        ])
        self.assertEqual([r["index"] for r, veto in zip(normalized, decisions) if veto is None], [1, 4])
        self.assertEqual([r["index"] for r in normalized], list(range(6)))

    def test_all_aggregate_veto_states_are_deterministic(self):
        item = question()
        for judgments, expected in (
            (["refuted"] * 4, "solver_zero_supported"),
            (["supported"] * 4, "solver_multiple_supported"),
            (["supported", "supported", "uncertain", "refuted"], "solver_multiple_supported"),
            (["uncertain"] * 4, "solver_uncertain"),
            (["refuted", "uncertain", "refuted", "refuted"], "solver_uncertain"),
            (["supported", "uncertain", "refuted", "refuted"], "solver_uncertain"),
            (["refuted", "supported", "refuted", "refuted"], "answer_disagreement"),
            (["supported", "refuted", "refuted", "refuted"], None),
        ):
            with self.subTest(judgments=judgments):
                self.assertEqual(rejection_reason(record(item, judgments), item), expected)

    def test_natural_negative_zero_and_negated_tasks_need_no_magic_wording(self):
        cases = [
            ("Which real number x satisfies x² = -1?", ["No real number satisfies it.", "0", "1", "-1"]),
            ("A pump fills 10 L at an unspecified constant rate. How many minutes are required?", ["The rate is needed to determine the duration.", "1", "5", "10"]),
            ("How many integers are strictly between 2 and 3?", ["0", "1", "2", "3"]),
            ("Which sentence is not in the past tense?", question()["choices"]),
        ]
        for prompt, choices in cases:
            with self.subTest(prompt=prompt):
                item = {**question(choices=choices), "prompt": prompt}
                parsed = validate_batch(raw(record(item)), [item])
                self.assertIsNone(rejection_reason(parsed[0], item))

    def test_missing_duplicate_extra_and_noninteger_solution_indexes_fail_batch(self):
        items = [question(), question(1)]
        base = [record(item) for item in items]
        malformed = [base[:1], base + [record(question(2))], [base[0], base[0]]]
        for index in (True, False, "0", 0.0, -1, 2, None):
            changed = copy.deepcopy(base)
            changed[0]["index"] = index
            malformed.append(changed)
        changed = copy.deepcopy(base)
        del changed[0]["index"]
        malformed.append(changed)
        for records in malformed:
            with self.subTest(records=records):
                with self.assertRaises(CompleteSolutionFormatError):
                    validate_batch(raw(*records), items)

    def test_malformed_input_indexes_and_unrepresentable_choices_are_not_repaired(self):
        inputs = [[], [question(), question()], [question(1)]]
        for index in (True, "0", 0.0, -1, None):
            inputs.append([{**question(), "index": index}])
        for choices in (
            ["one", "two", "three"], ["one", "one", "three", "four"],
            ["one", " one ", "three", "four"], ["é", "e\u0301", "three", "four"],
            ["", "two", "three", "four"], ["\t ", "two", "three", "four"],
            ["x" * 141, "two", "three", "four"], [True, "two", "three", "four"],
        ):
            inputs.append([{**question(), "choices": choices}])
        for items in inputs:
            with self.subTest(items=items):
                with self.assertRaises(CompleteSolutionFormatError):
                    build_solver_prompt(items, {})
                with self.assertRaises(CompleteSolutionFormatError):
                    validate_batch(raw(record(question())), items)

    def test_choice_coverage_rejects_missing_duplicate_added_or_rewritten_text(self):
        item = question(choices=['"e\u0301"', '"a  b"', "−1", "four"])
        base = record(item)
        mutations = []
        for replacement in ['"é"', ' "e\u0301"', '"e\u0301" ', "UNKNOWN"]:
            changed = copy.deepcopy(base)
            changed["choices"][0]["choice"] = replacement
            mutations.append(changed)
        for position, replacement in [(1, '"a b"'), (2, "-1"), (0, '"a  b"')]:
            changed = copy.deepcopy(base)
            changed["choices"][position]["choice"] = replacement
            mutations.append(changed)
        mutations.append({**base, "choices": base["choices"][:3]})
        mutations.append({**base, "choices": base["choices"] + [base["choices"][0]]})
        for changed in mutations:
            with self.subTest(record=changed):
                with self.assertRaises(CompleteSolutionFormatError):
                    validate_batch(raw(changed), [item])

    def test_malformed_rows_and_legacy_shapes_fail_without_a_default(self):
        item = question()
        base = record(item)
        mutations = [
            None,
            {**base, "answer": item["expectedAnswer"]},
            {"index": 0, "outcome": "resolved", "answer": item["expectedAnswer"], "limitations": "", "assumptionsRequired": []},
        ]
        for key, value in (
            ("choice", 1), ("judgment", "correct"), ("judgment", []),
            ("judgment", True), ("reason", None), ("reason", " \t\n"),
            ("reason", "x" * 601),
        ):
            changed = copy.deepcopy(base)
            changed["choices"][0][key] = value
            mutations.append(changed)
        for key in ("choice", "judgment", "reason"):
            changed = copy.deepcopy(base)
            del changed["choices"][0][key]
            mutations.append(changed)
        changed = copy.deepcopy(base)
        changed["choices"][0]["expectedAnswer"] = "FORGED"
        mutations.append(changed)
        for changed in mutations:
            with self.subTest(record=changed):
                with self.assertRaises(CompleteSolutionFormatError):
                    validate_batch(raw(changed), [item])
                with self.assertRaises(CompleteSolutionFormatError):
                    rejection_reason(changed, item)

    def test_malformed_envelopes_and_duplicate_json_keys_fail(self):
        for value in (
            None, "broken", "{}", "[]", '{"solutions":[]}',
            '{"solutions":[],"solutions":[]}',
            json.dumps({"solutions": [record(question())], "answer": "EXTRA"}),
            raw(record(question())).replace('"index": 0', '"index": 0, "index": 0'),
        ):
            with self.subTest(raw=value):
                with self.assertRaises(CompleteSolutionFormatError):
                    validate_batch(value, [question()])

    def test_reason_bounds_count_codepoints_and_preserve_boundary_whitespace(self):
        item = question(choices=["x" * 140, "two", "three", "four"])
        solution = record(item)
        reason = " \t" + "e" + "\u0301" * 595 + "\n "
        self.assertEqual(len(reason), 600)
        solution["choices"][0]["reason"] = reason
        validated = validate_batch(raw(solution), [item])
        self.assertEqual(validated[0]["choices"][0]["reason"].encode(), reason.encode())
        self.assertEqual(validated[0]["choices"][0]["choice"], "x" * 140)
        self.assertIsNone(rejection_reason(validated[0], item))

    def test_decision_revalidates_exact_question_key_and_choice_coverage(self):
        item = question(choices=[' "e\u0301" ', "two", "three", "four"])
        solution = record(item)
        for key in ('"e\u0301"', ' "é" ', "absent", None, True):
            with self.subTest(key=key):
                with self.assertRaises(CompleteSolutionFormatError):
                    rejection_reason(solution, {**item, "expectedAnswer": key})
        solution["choices"].pop()
        with self.assertRaises(CompleteSolutionFormatError):
            rejection_reason(solution, item)

    def test_invalid_subject_field_types_cannot_smuggle_structured_metadata(self):
        contexts = [
            {"goal": {"title": {"expectedAnswer": "private"}}},
            {"goal": {"contentTopics": [1]}},
            {"goal": {"needsSkillMap": 1}},
            {"skillMap": {"version": True, "skills": []}},
            {"skillMap": {"skills": [{"name": "x", "objectives": "wrong"}]}},
            {"sourceDocuments": {"text": "x"}},
            {"sourceDocuments": [{"text": {"answer": "private"}}]},
            {"sourceDocuments": [{"text": "x", "truncated": 0}]},
        ]
        for context in contexts:
            with self.subTest(context=context):
                with self.assertRaises(CompleteSolutionFormatError):
                    build_solver_prompt([question()], context)

    def test_confident_wrong_or_contradictory_reasons_remain_an_explicit_semantic_limit(self):
        item = {**question(choices=["5", "4", "3", "2"]), "prompt": "What is 2 + 2?"}
        for explanation in (
            "Two plus two equals five.",
            "Two plus two equals four, so the offered five cannot be the answer.",
        ):
            solution = record(item)
            solution["choices"][0]["reason"] = explanation
            validated = validate_batch(raw(solution), [item])
            # The arithmetic truth is 4. This adapter enforces the declared
            # mapping only, and must not be described as a factual judge.
            self.assertIsNone(rejection_reason(validated[0], item))
            self.assertEqual(validated[0]["choices"][0]["reason"], explanation)
            self.assertNotIn("verificationVersion", validated[0])
            self.assertNotIn("verificationPolicyRevision", validated[0])


if __name__ == "__main__":
    unittest.main()
