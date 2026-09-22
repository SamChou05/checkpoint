"""Offline structural and admission tests; synthetic judgments prove no model quality."""

import copy
import hashlib
import json
import unittest

import jsonschema

import authored_feedback_audit as audit


def payload():
    choices = ["4", "5", "2", "3"]
    return {"prompt": "What is the value of 2 + 2?", "choices": choices, "expectedAnswer": "4",
            "explanation": "Adding two and two gives four.",
            "choiceExplanations": {choice: f"The offered answer is {choice}; compare it with the sum, 4."
                                   for choice in choices}}


def assessment(judgment="supported", reason="Synthetic independent check."):
    return {"reason": reason, "judgment": judgment}


def row(answer="a", difficulty=2):
    return {"task": assessment(), "answerChoice": answer, "difficulty": difficulty,
            "feedback": {field: assessment() for field in audit.FEEDBACK_FIELDS}}


def response(rows):
    return json.dumps({"reviews": {str(index): value for index, value in enumerate(rows)}}, ensure_ascii=False)


class AuthoredFeedbackAuditTests(unittest.TestCase):
    def test_all_forty_closed_schema_shapes_and_deliberate_generation_order(self):
        for count in range(1, 41):
            schema = audit.schema(count)
            jsonschema.Draft202012Validator.check_schema(schema)
            native = json.loads(audit.output_config(count)["textFormat"]["structure"]["jsonSchema"]["schema"])
            self.assertEqual(native, schema)
            reviews = schema["properties"]["reviews"]
            self.assertEqual(list(reviews["properties"]), [str(index) for index in range(count)])
            self.assertEqual(reviews["required"], list(reviews["properties"]))
            for spec in reviews["properties"].values():
                self.assertEqual(list(spec["properties"]), ["task", "answerChoice", "difficulty", "feedback"])
                self.assertEqual(list(spec["properties"]["task"]["properties"]), ["reason", "judgment"])
                feedback = spec["properties"]["feedback"]
                self.assertEqual(list(feedback["properties"]), ["main", "a", "b", "c", "d"])
                for field in feedback["properties"].values():
                    self.assertEqual(list(field["properties"]), ["reason", "judgment"])
                    self.assertFalse(field["additionalProperties"])
                self.assertFalse(spec["additionalProperties"])
                self.assertFalse(feedback["additionalProperties"])
            raw = response([row() for _ in range(count)])
            jsonschema.Draft202012Validator(schema).validate(json.loads(raw))
            self.assertEqual(len(audit.validate(raw, count)), count)
            configured = audit.output_config(count)["textFormat"]["structure"]["jsonSchema"]
            self.assertEqual(audit.metadata(count)["sha256"], hashlib.sha256(configured["schema"].encode()).hexdigest())
            self.assertEqual(audit.metadata(count)["name"], f"experimental_authored_feedback_audit_v1_n{count}")
        mutated = audit.schema(1)
        mutated["properties"].clear()
        self.assertIn("reviews", audit.schema(1)["properties"])

    def test_invalid_counts_and_non_json_responses_are_rejected(self):
        for count in (0, -1, 41, True, False, 1.0, "1", None):
            for function in (audit.schema, audit.output_config, audit.metadata):
                with self.subTest(count=count, function=function.__name__), self.assertRaises(audit.AuthoredFeedbackAuditError):
                    function(count)
            with self.assertRaises(audit.AuthoredFeedbackAuditError):
                audit.validate(response([row()]), count)
        for raw in (None, {}, [], 1, True, "", "```json\n{}\n```", "[]", "null"):
            with self.subTest(raw=raw), self.assertRaises(audit.AuthoredFeedbackAuditError):
                audit.validate(raw, 1)

    def test_hidden_explicit_key_and_exact_choice_feedback_association(self):
        original = payload()
        scope = {"goal": {"title": "Arithmetic"}, "skillMap": [], "sourceDocuments": []}
        before = copy.deepcopy(original)
        data = audit.build_input([original], scope)
        item = data["items"]["0"]
        self.assertEqual(set(item), {"prompt", "choices", "feedback"})
        self.assertEqual(item["choices"], dict(zip(audit.SLOTS, original["choices"], strict=True)))
        self.assertEqual(item["feedback"]["main"], original["explanation"])
        for slot, choice in item["choices"].items():
            self.assertEqual(item["feedback"][slot], original["choiceExplanations"][choice])
        for key in original["choices"]:
            changed = copy.deepcopy(original)
            changed["expectedAnswer"] = key
            self.assertEqual(audit.build_input([changed], scope), data)
        self.assertEqual(original, before)
        data["items"]["0"]["feedback"]["a"] = "Mutated copy"
        data["goal"]["title"] = "Mutated copy"
        self.assertEqual(original, before)
        self.assertEqual(scope["goal"]["title"], "Arithmetic")
        rendered = audit.build_user_prompt([original], scope)
        decoded = json.loads(rendered.removeprefix("<authored_feedback_audit_json>\n").removesuffix("\n</authored_feedback_audit_json>"))
        self.assertEqual(decoded, audit.build_input([original], scope))
        self.assertNotIn("expectedAnswer", rendered)
        self.assertNotIn("difficulty", rendered)

    def test_exact_case_whitespace_and_unicode_are_not_normalized(self):
        original = payload()
        original["choices"] = ["é", "e\u0301", "E", " e"]
        original["expectedAnswer"] = "e\u0301"
        original["choiceExplanations"] = {choice: f"  Literal offered text: {choice}; retain every character.  "
                                          for choice in original["choices"]}
        data = audit.build_input([original], {})
        self.assertEqual(list(data["items"]["0"]["choices"].values()), original["choices"])
        raw = response([row(answer="b")])
        selected = audit.select_accepted(raw, [original], difficulty_gate=lambda index, difficulty: True)
        self.assertEqual(selected, [original])
        self.assertEqual(audit.accepted_indices(raw, [original], difficulty_gate=lambda index, difficulty: True), [0])
        selected[0]["choices"][0] = "changed"
        self.assertEqual(original["choices"][0], "é")
        self.assertEqual(audit.select_accepted(response([row(answer="a")]), [original], difficulty_gate=lambda index, difficulty: True), [])

    def test_invalid_original_or_scope_cannot_reach_model_input_or_admission(self):
        bad = payload()
        bad["choiceExplanations"].pop("3")
        with self.assertRaises(ValueError):
            audit.build_input([payload(), bad], {})
        calls = []
        with self.assertRaises(ValueError):
            audit.accepted_indices(response([row(), row()]), [payload(), bad], difficulty_gate=lambda index, difficulty: calls.append(index) or True)
        self.assertEqual(calls, [])
        for originals in ([], tuple([payload()]), [payload()] * 41):
            with self.assertRaises(ValueError):
                audit.build_input(originals, {})
        for field in ("difficulty", "verified", "independentSolutions", "correctChoice"):
            added = payload()
            added[field] = "not permitted"
            with self.assertRaises(ValueError):
                audit.build_input([added], {})
            with self.assertRaises(ValueError):
                audit.build_input([payload()], {field: "not permitted"})
        for scope in (None, [], {"goal": float("nan")}, {"goal": object()}, {"goal": "\ud800"}):
            with self.assertRaises(ValueError):
                audit.build_input([payload()], scope)

    def test_closed_identities_fields_and_no_overall_approval_or_replacements(self):
        valid = json.loads(response([row(), row()]))
        mutations = []
        for identity in ("-1", "2", "01", "unknown"):
            changed = copy.deepcopy(valid)
            changed["reviews"][identity] = changed["reviews"].pop("1")
            mutations.append(changed)
        changed = copy.deepcopy(valid)
        del changed["reviews"]["1"]
        mutations.append(changed)
        for key, value in (("valid", True), ("accepted", True), ("answer", "4"), ("explanation", "replacement")):
            changed = copy.deepcopy(valid)
            changed["reviews"]["0"][key] = value
            mutations.append(changed)
        for field in ("main", "a", "b", "c", "d"):
            changed = copy.deepcopy(valid)
            del changed["reviews"]["0"]["feedback"][field]
            mutations.append(changed)
        changed = copy.deepcopy(valid)
        changed["reviews"]["0"]["feedback"]["e"] = assessment()
        mutations.append(changed)
        mutations.extend([{"reviews": [row(), row()]}, {"reviews": valid["reviews"], "extra": None}])
        for changed in mutations:
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                audit.validate(json.dumps(changed), 2)
        reordered = {"reviews": {"1": row(), "0": row()}}
        self.assertEqual(list(audit.validate(json.dumps(reordered), 2)), ["0", "1"])

    def test_duplicate_json_fields_and_nonfinite_numbers_fail(self):
        valid = response([row()])
        bad_values = [valid.replace('"difficulty": 2', '"difficulty": 2, "difficulty": 3'),
                      valid.replace('"task":', '"task": {}, "task":', 1),
                      valid.replace('"reason":', '"reason": "duplicated", "reason":', 1)]
        for token in ("NaN", "Infinity", "-Infinity", "1e999"):
            bad_values.append(valid.replace('"difficulty": 2', f'"difficulty": {token}'))
        for raw in bad_values:
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                audit.validate(raw, 1)

    def test_all_six_reason_fields_have_exact_codepoint_bounds_and_types(self):
        for field in ("task", *audit.FEEDBACK_FIELDS):
            for reason in ("x" * 240, "🙂" * 240, "  concrete supporting check  "):
                record = row()
                target = record["task"] if field == "task" else record["feedback"][field]
                target["reason"] = reason
                self.assertEqual(len(audit.validate(response([record]), 1)), 1)
            for reason in ("x" * 241, "🙂" * 241, "", " " * 240, None, True, 240, [], "\ud800"):
                record = row()
                target = record["task"] if field == "task" else record["feedback"][field]
                target["reason"] = reason
                with self.subTest(field=field, reason=repr(reason)), self.assertRaises(ValueError):
                    audit.validate(response([record]), 1)

    def test_strict_enum_integer_and_no_lossy_normalization(self):
        for value in (True, False, 0, 6, 2.0, "2", None):
            with self.subTest(value=value), self.assertRaises(ValueError):
                audit.validate(response([row(difficulty=value)]), 1)
        for value in ("A", " a", "a ", "4", 1, None):
            with self.subTest(value=value), self.assertRaises(ValueError):
                audit.validate(response([row(answer=value)]), 1)
        for value in ("SUPPORTED", " supported", "true", True, None):
            record = row()
            record["task"]["judgment"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                audit.validate(response([record]), 1)

    def test_every_negative_uncertain_or_key_disagreement_vetoes_without_repair(self):
        originals = [payload()]
        before = copy.deepcopy(originals)
        variants = []
        for value in ("unsupported", "uncertain"):
            changed = row()
            changed["task"]["judgment"] = value
            variants.append(changed)
            for field in audit.FEEDBACK_FIELDS:
                changed = row()
                changed["feedback"][field]["judgment"] = value
                variants.append(changed)
        variants.extend(row(answer=value) for value in ("b", "c", "d", "none", "multiple", "uncertain"))
        for changed in variants:
            raw = response([changed])
            self.assertEqual(audit.accepted_indices(raw, originals, difficulty_gate=lambda index, difficulty: True), [])
            self.assertEqual(audit.select_accepted(raw, originals, difficulty_gate=lambda index, difficulty: True), [])
            self.assertEqual(originals, before)

    def test_difficulty_gate_gets_original_index_and_reviewed_difficulty(self):
        originals = [payload(), payload(), payload()]
        raw = response([row(difficulty=2), row(difficulty=4), row(difficulty=3)])
        seen = []
        def gate(index, difficulty):
            seen.append((index, difficulty))
            return index == 2 and difficulty == 3
        self.assertEqual(audit.accepted_indices(raw, originals, difficulty_gate=gate), [2])
        self.assertEqual(seen, [(0, 2), (1, 4), (2, 3)])
        self.assertEqual(audit.select_accepted(raw, originals, difficulty_gate=lambda index, difficulty: index == 2), [originals[2]])
        for rejected in (False, None, 1, "yes"):
            self.assertEqual(audit.accepted_indices(response([row()]), [payload()], difficulty_gate=lambda index, difficulty: rejected), [])
        with self.assertRaises(ValueError):
            audit.accepted_indices(response([row()]), [payload()], difficulty_gate=None)
        def failed_gate(index, difficulty):
            raise RuntimeError("Caller gate failure must propagate.")
        with self.assertRaises(RuntimeError):
            audit.accepted_indices(response([row()]), [payload()], difficulty_gate=failed_gate)

    def test_whole_batch_validation_precedes_any_acceptance_callback(self):
        invalid = row()
        invalid["feedback"]["d"]["reason"] = "x" * 241
        called = []
        with self.assertRaises(ValueError):
            audit.accepted_indices(response([row(), invalid]), [payload(), payload()],
                                   difficulty_gate=lambda index, difficulty: called.append(index) or True)
        self.assertEqual(called, [])
        with self.assertRaises(ValueError):
            audit.select_accepted(response([row(), invalid]), [payload(), payload()],
                                  difficulty_gate=lambda index, difficulty: called.append(index) or True)
        self.assertEqual(called, [])


if __name__ == "__main__":
    unittest.main()
