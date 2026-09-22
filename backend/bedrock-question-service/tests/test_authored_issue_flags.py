"""Versioned native flags preserve strict issue vetoes and historical contracts."""

import copy
import hashlib
import json
from typing import get_args
import unittest

import native_output_contracts as native
from lambda_test_support import _raw_question
from question_teaching import (
    AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT,
    AuthoredTeachingFormatError,
    authored_review_rejection_reason,
    validate_authored_reviews,
)
from service_errors import ProviderError, ServiceConfigurationError


FLAGS = ("answer_or_ambiguity", "explanation", "distractors", "scope_assignment", "novelty", "other")


def row(answer="A supported conclusion", **changes):
    return {"valid": True, "answer": answer, "difficulty": 3, "explanationSupport": "supported",
            "issueFlags": dict.fromkeys(FLAGS, False), **changes}


class AuthoredIssueFlagTests(unittest.TestCase):
    def setUp(self):
        self.contract = native.AuthoredSolutionFlagReviewContract(1)
        self.question = _raw_question("The stated rule and its conditions apply here. What follows?")
        self.question["explanation"] = "The stated conditions satisfy the rule, establishing the offered conclusion."
        self.items = [{"index": 0, **self.question}]

    def decode(self, value):
        return native.adapt_native_response(json.dumps({"reviews": {"0": value}}), self.contract)

    def test_each_true_flag_reaches_the_unchanged_nonblank_issue_veto(self):
        for flags in ((), *((flag,) for flag in FLAGS), FLAGS):
            with self.subTest(flags=flags):
                value = row(self.question["expectedAnswer"], issueFlags={flag: flag in flags for flag in reversed(FLAGS)})
                before = copy.deepcopy(value)
                review = validate_authored_reviews(self.decode(value), self.items)[0]
                self.assertEqual(value, before)
                self.assertEqual(review["issues"], [flag for flag in FLAGS if flag in flags])
                self.assertEqual(authored_review_rejection_reason(review, self.question), "reported_issues" if flags else None)
                self.assertEqual(set(review), {"index", "valid", "answer", "difficulty", "explanationSupport", "issues"})

    def test_false_flags_cannot_override_support_valid_or_key_veto(self):
        for change, reason in (({"valid": False}, "rejected_by_model"),
                               ({"explanationSupport": "unsupported"}, "unsupported_authored_explanation"),
                               ({"explanationSupport": "uncertain"}, "uncertain_authored_explanation"),
                               ({"answer": self.question["choices"][1]}, "answer_disagreement")):
            with self.subTest(change=change):
                review = validate_authored_reviews(self.decode(row(**{"answer": self.question["expectedAnswer"], **change})), self.items)[0]
                self.assertEqual(authored_review_rejection_reason(review, self.question), reason)

    def test_missing_extra_nonboolean_and_legacy_issues_are_whole_response_errors(self):
        malformed = [None, [], True, {}, {**dict.fromkeys(FLAGS, False), "unexpected": False}]
        for flag in FLAGS:
            malformed.append({key: False for key in FLAGS if key != flag})
            for value in (0, 1, "false", "true", None, [], {}):
                malformed.append({**dict.fromkeys(FLAGS, False), flag: value})
        for flags in malformed:
            with self.subTest(flags=flags), self.assertRaises(ProviderError):
                self.decode(row(issueFlags=flags))
        for field in ("index", "issues", "explanation", "choiceExplanations", "verificationPolicyRevision"):
            with self.subTest(field=field), self.assertRaises(ProviderError):
                self.decode({**row(), field: []})
        for field in row():
            with self.subTest(missing=field), self.assertRaises(ProviderError):
                self.decode({key: value for key, value in row().items() if key != field})
        valid = json.dumps({"reviews": {"0": row()}})
        for raw in (valid.replace('"other": false', '"other": false,"other": true'),
                    valid.replace('"0":', '"0": {},"0":', 1),
                    valid.replace('"other": false', '"other": NaN')):
            with self.subTest(raw=raw), self.assertRaises(ProviderError):
                native.adapt_native_response(raw, self.contract)
        invalid_sibling = {"reviews": {"0": row(), "1": row(issueFlags={})}}
        with self.assertRaises(ProviderError):
            native.adapt_native_response(json.dumps(invalid_sibling), native.AuthoredSolutionFlagReviewContract(2))

    def test_only_integer_rubric_values_are_native_valid(self):
        for value in (1, 2, 3, 4, 5):
            self.assertEqual(json.loads(self.decode(row(difficulty=value)))["reviews"][0]["difficulty"], value)
        for value in (-1, 0, 6, True, 1.0, "3", None):
            with self.subTest(value=value), self.assertRaises(ProviderError):
                self.decode(row(difficulty=value))
        for change in ({"valid": 1}, {"valid": "false"}, {"answer": None}, {"explanationSupport": "maybe"}):
            with self.subTest(change=change), self.assertRaises(ProviderError):
                self.decode(row(**change))

    def test_every_count_has_exact_identity_shared_order_and_matching_prompt_example(self):
        for count in range(1, 41):
            contract = native.AuthoredSolutionFlagReviewContract(count)
            config = native.native_output_config(contract)
            schema = json.loads(config["textFormat"]["structure"]["jsonSchema"]["schema"])
            def expand(value):
                if isinstance(value, list):
                    return [expand(child) for child in value]
                if not isinstance(value, dict):
                    return value
                if "$ref" in value:
                    self.assertEqual(set(value), {"$ref"})
                    return expand(schema["$defs"][value["$ref"].removeprefix("#/$defs/")])
                return {key: expand(child) for key, child in value.items() if key != "$defs"}
            # String comparison also freezes object property order, not only semantics.
            self.assertEqual(json.dumps(expand(schema)), json.dumps(native._contract_schema(contract)))
            self.assertEqual(set(schema["$defs"]), {"review"})
            self.assertEqual(list(schema["$defs"]["review"]["properties"]["issueFlags"]["properties"]), list(FLAGS))
            reviews = {str(index): row(answer=f"exact choice {index}") for index in reversed(range(count))}
            decoded = json.loads(native.adapt_native_response(json.dumps({"reviews": reviews}), contract))["reviews"]
            self.assertEqual([(item["index"], item["answer"]) for item in decoded], [(i, f"exact choice {i}") for i in range(count)])
            self.assertTrue(all(item["issues"] == [] for item in decoded))
            self.assertEqual(native.contract_metadata(contract)["version"], "3")
            for changed in ({**reviews, str(count): row()}, {k: v for k, v in reviews.items() if k != "0"}):
                with self.assertRaises(ProviderError):
                    native.adapt_native_response(json.dumps({"reviews": changed}), contract)
            prompt = native.native_prompt(AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT, contract)
            example, _ = json.JSONDecoder().raw_decode(prompt.split("Return only this JSON shape: ", 1)[1])
            native._validate_schema_value(example, native._contract_schema(contract))
            self.assertEqual(prompt.count("Return only"), 1)
            for legacy_text in ('"issues"', '"reviews":[', '"index":', "240 characters", "600, with at most 8"):
                self.assertNotIn(legacy_text, prompt)
            for text in ("assigned skill", "cosmetic repeats", "Do not invent", "unsupported/uncertain",
                         "Multiple flags may be true", "Difficulty rubric:"):
                self.assertIn(text, prompt)
            self.assertEqual(list(example["reviews"]), [str(i) for i in range(count)])
        for count in (0, 41, -1, True, 1.0, "1", None):
            with self.assertRaises(ServiceConfigurationError):
                native.AuthoredSolutionFlagReviewContract(count)

    def test_prompt_drift_fails_instead_of_appending_a_conflicting_example(self):
        for prompt in ("Unrecognized rules", AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT.replace("240 characters", "241 characters"),
                       AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT * 2):
            with self.subTest(prompt=prompt), self.assertRaises(ServiceConfigurationError):
                native.native_prompt(prompt, self.contract)

    def test_historical_blank_issue_rejection_is_preserved(self):
        # The actual failed transport pattern remains native-valid/local-invalid
        # under v2. V3 does not rewrite history by discarding blank issue text.
        old = {key: value for key, value in row(self.question["expectedAnswer"]).items() if key != "issueFlags"}
        old["issues"] = ["", " ", " "]
        adapted = native.adapt_native_response(json.dumps({"reviews": {"0": old}}), native.AuthoredSolutionReviewContract(1))
        with self.assertRaises(AuthoredTeachingFormatError):
            validate_authored_reviews(adapted, self.items)
        with self.assertRaises(ProviderError):
            self.decode(old)

    def test_all_131_historical_configs_metadata_and_prompts_keep_their_bytes(self):
        # Snapshot from b33759b before v3; includes both placeholder and actual
        # historical authored prompt composition, all static contracts/counts.
        contracts = (*(c for c in get_args(native.Contract) if c != "question_author_constructed_v1"), *(native.SolverSlotContract(n) for n in range(1, 41)),
                     *(native.ReviewerSlotContract(n) for n in range(1, 41)),
                     *(native.AuthoredSolutionReviewContract(n) for n in range(1, 41)))
        self.assertEqual(len(contracts), 131)
        values = [{"config": native.native_output_config(c), "metadata": native.contract_metadata(c),
                   "prompt": native.native_prompt("UNCHANGED SYSTEM", c),
                   "authored_prompt": native.native_prompt(AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT, c)} for c in contracts]
        digest = hashlib.sha256(json.dumps(values, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        self.assertEqual(digest, "1488598e771542eaedde7695ad599b2111b28756d8fbc7dc4f9eac7f6be73e3a")


if __name__ == "__main__":
    unittest.main()
