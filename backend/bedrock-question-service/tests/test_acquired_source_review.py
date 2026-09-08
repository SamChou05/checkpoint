"""Pure captured-text tests; no fetch/model calls or source-truth claims."""

import copy
import hashlib
import json
import unittest
from unittest.mock import patch

from evals import acquired_source_review as adapter
from evals import question_immutable_review as immutable


def capture(text="Before. The rule uses two conditions. After.", **changes):
    return {
        "status": "acquired",
        "source_text": text,
        "text_sha256": hashlib.sha256(text.encode()).hexdigest(),
        "raw_content_sha256": "a" * 64,
        "text_characters": len(text),
        "truncated": False,
        "source_text_complete": True,
        "final_url": "https://example.org/rules/v2",
        "requested_url": "https://example.org/rules",
        "retrieved_at_utc": "2026-09-08T00:00:00+00:00",
        "representation_limits": ["Text extraction; layout and images omitted."],
        "trace": [{"url": "https://example.org/rules/v2", "http_status": 200}],
        "verification": "unverified_source_material",
        **changes,
    }


def question():
    return {
        "prompt": '  Given "red  blue", which description preserves its spacing?\n',
        "choices": ['"red  blue"', '"red blue"', '"redblue"', '"red   blue"'],
        "expectedAnswer": '"red  blue"',
        "explanation": "  The quoted input contains exactly two spaces.\n",
        "choiceExplanations": {
            '"red  blue"': "  This preserves the exact two spaces.\n",
            '"red blue"': "This removes one of the original spaces.",
            '"redblue"': "This removes both of the original spaces.",
            '"red   blue"': "This adds a third space to the original input.",
        },
        "topic": "Text handling",
        "objective": "Preserve literal content",
        "difficulty": 3,
        "format": "Multiple Choice",
        "verificationPolicyRevision": 999,
    }


class AcquiredSourceReviewTests(unittest.TestCase):
    def setUp(self):
        self.question = question()
        self.records = [capture()]
        self.selections = [{"record_index": 0, "start": 8, "end": 37}]
        self.context = {
            "goal": {"title": "Apply written rules", "expectedAnswer": "SECRET"},
            "sourceDocuments": [{"text": "OLD SUMMARY SECRET"}],
            "expected_accept": True,
        }

    def response(self, **changes):
        packet = adapter.prepare_sources(self.records, self.selections)
        span = packet["spans"][0]
        citation = {"source_id": span["source_id"], "quote": span["text"]}
        return {
            "review": {
                "valid": True,
                "answer": self.question["expectedAnswer"],
                "difficulty": 3,
                "mainExplanation": "supported",
                "choiceExplanations": {
                    c: "supported" for c in self.question["choices"]
                },
                "issues": [],
                **changes,
            },
            "evidence": {
                "item": [copy.deepcopy(citation)],
                "mainExplanation": [copy.deepcopy(citation)],
                "choiceExplanations": {
                    c: [copy.deepcopy(citation)] for c in self.question["choices"]
                },
            },
        }

    def observe(self, response):
        raw = (
            response
            if type(response) is str
            else json.dumps(response, ensure_ascii=False)
        )
        return adapter.observe_review(
            raw, self.question, self.context, self.records, self.selections, 3
        )

    def test_prompt_keeps_original_content_rotation_and_only_acquired_sources(self):
        original = copy.deepcopy(
            (self.question, self.context, self.records, self.selections)
        )
        system, user = adapter.review_prompt(*original)
        data = json.loads(user.split("\n", 1)[1].rsplit("\n", 1)[0])
        _, old_user = immutable.review_prompt(
            self.question, {"goal": self.context["goal"], "sourceDocuments": []}
        )
        old = json.loads(old_user.split("\n", 1)[1].rsplit("\n", 1)[0])
        self.assertEqual(data["question"], old["question"])
        self.assertEqual(data["sourceDocuments"], [])
        self.assertNotIn("SECRET", user)
        self.assertNotIn("expectedAnswer", user)
        self.assertNotIn("verificationPolicyRevision", user)
        self.assertEqual(
            data["acquiredSources"]["records"][0]["metadata"],
            {k: v for k, v in self.records[0].items() if k != "source_text"},
        )
        span = data["acquiredSources"]["spans"][0]
        self.assertEqual(span["text"], self.records[0]["source_text"][8:37])
        self.assertTrue(span["omits_acquired_text"])
        self.assertEqual((span["original_start"], span["original_end"]), (8, 37))
        self.assertIn('"evidence"', system)
        self.assertNotIn(
            'Return ONLY {"review":{"valid":true', system.split('"evidence"', 1)[1]
        )
        self.assertEqual(
            (self.question, self.context, self.records, self.selections), original
        )

    def test_valid_fenced_response_retains_exact_question_and_no_stamp(self):
        original = copy.deepcopy(self.question)
        result = self.observe("```json\n" + json.dumps(self.response()) + "\n```")
        self.assertTrue(result["eligible"])
        self.assertEqual(result["question"], immutable.freeze_question(original))
        self.assertEqual(self.question, original)
        self.assertNotIn("verificationPolicyRevision", result["question"])
        self.assertNotIn("verificationVersion", result["question"])
        binding = result["evidence_bindings"]["item"][0]
        self.assertEqual((binding["start"], binding["end"]), (0, 29))
        self.assertEqual((binding["original_start"], binding["original_end"]), (8, 37))
        self.assertEqual(self.records[0]["source_text"][8:37], binding["quote"])

    def test_false_quote_unknown_source_offsets_and_missing_coverage_fail(self):
        for change in (
            "quote",
            "source",
            "offset",
            "omitted",
            "missing_choice",
            "extra",
            "bool",
            "duplicate",
        ):
            with self.subTest(change=change):
                raw = self.response()
                ref = raw["evidence"]["item"][0]
                if change == "quote":
                    ref["quote"] = "The rule uses one condition."
                elif change == "source":
                    ref["source_id"] = "invented-source"
                elif change == "offset":
                    ref["start"] = 0
                elif change == "omitted":
                    ref["quote"] = "Before."
                elif change == "missing_choice":
                    raw["evidence"]["choiceExplanations"].pop(
                        self.question["choices"][0]
                    )
                elif change == "extra":
                    ref["replacement"] = "new feedback"
                elif change == "bool":
                    ref["quote"] = False
                else:
                    raw["evidence"]["item"].append(copy.deepcopy(ref))
                self.assertEqual(self.observe(raw)["reason"], "invalid_evidence")

    def test_unsupported_uncertain_and_issues_cannot_be_overridden_by_citations(self):
        for fields, reason in (
            ({"mainExplanation": "unsupported"}, "unsupported_feedback"),
            (
                {
                    "choiceExplanations": {
                        **self.response()["review"]["choiceExplanations"],
                        self.question["choices"][1]: "uncertain",
                    }
                },
                "uncertain_feedback",
            ),
            ({"issues": ["x" * 283]}, "reported_issues"),
            ({"answer": self.question["choices"][1]}, "answer_disagreement"),
        ):
            with self.subTest(reason=reason):
                result = self.observe(self.response(**fields))
                self.assertFalse(result["eligible"])
                self.assertEqual(result["reason"], reason)
                self.assertIsNone(result["question"])

    def test_empty_evidence_blocks_approval_but_preserves_declared_rejection(self):
        raw = self.response()
        raw["evidence"]["mainExplanation"] = []
        self.assertEqual(self.observe(raw)["reason"], "insufficient_evidence")
        raw["review"]["mainExplanation"] = "uncertain"
        self.assertEqual(self.observe(raw)["reason"], "uncertain_feedback")

    def test_source_mutation_failed_and_partial_fetch_cannot_be_cited(self):
        original = copy.deepcopy(self.records[0])
        for changes in (
            {"source_text": "Mutated source"},
            {"status": "failed"},
            {"status": "partial"},
            {"source_text_complete": False},
            {"source_text": ""},
            {"text_characters": True},
        ):
            with self.subTest(changes=changes):
                self.records[0] = {**original, **changes}
                with self.assertRaises(adapter.AcquiredSourceReviewError):
                    adapter.prepare_sources(self.records, self.selections)
        self.records[0] = original
        raw = self.response()
        self.records[0]["final_url"] += "/changed"
        self.assertEqual(self.observe(raw)["reason"], "invalid_evidence")

    def test_explicit_truncated_extraction_preserves_limits_and_omission(self):
        self.records[0].update(truncated=True, source_text_complete=False)
        packet = adapter.prepare_sources(self.records, self.selections)
        metadata = packet["records"][0]["metadata"]
        self.assertTrue(metadata["truncated"])
        self.assertFalse(metadata["source_text_complete"])
        self.assertEqual(
            metadata["representation_limits"], self.records[0]["representation_limits"]
        )
        self.assertTrue(packet["spans"][0]["omits_acquired_text"])

    def test_exact_unicode_offsets_no_normalization_and_bounded_whole_packet(self):
        text = 'prefix é e\u0301 "red  blue"\r\nend'
        self.records = [capture(text)]
        self.selections = [{"record_index": 0, "start": 7, "end": len(text)}]
        packet = adapter.prepare_sources(self.records, self.selections)
        self.assertEqual(packet["spans"][0]["text"].encode(), text[7:].encode())
        with patch.object(adapter, "MAX_SOURCE_CHARACTERS", len(text[7:]) - 1):
            with self.assertRaisesRegex(
                adapter.AcquiredSourceReviewError, "source_text_budget"
            ):
                adapter.prepare_sources(self.records, self.selections)
        raw = self.response()
        raw["evidence"]["item"][0]["quote"] = text[7:].replace("e\u0301", "é")
        self.assertEqual(self.observe(raw)["reason"], "invalid_evidence")

    def test_malformed_core_replacement_and_raw_bounds_fail_without_new_content(self):
        for change in ("replacement", "type", "missing", "extra", "raw"):
            with self.subTest(change=change):
                raw = self.response()
                if change == "replacement":
                    raw["review"]["explanation"] = "Replacement explanation"
                elif change == "type":
                    raw["review"]["valid"] = 1
                elif change == "missing":
                    raw.pop("review")
                elif change == "extra":
                    raw["verificationPolicyRevision"] = 3
                else:
                    raw = " " * (immutable.MAX_RAW_REVIEW_CHARACTERS + 1)
                result = self.observe(raw)
                self.assertFalse(result["eligible"])
                self.assertIn(result["reason"], {"invalid_evidence", "invalid_review"})
                self.assertIsNone(result["question"])

    def test_selection_ranges_types_and_duplicate_source_ids_are_rejected(self):
        for selected in (
            {"record_index": True, "start": 0, "end": 5},
            {"record_index": 0, "start": -1, "end": 5},
            {"record_index": 0, "start": 0, "end": 999},
        ):
            with self.subTest(selected=selected):
                with self.assertRaises(adapter.AcquiredSourceReviewError):
                    adapter.prepare_sources(self.records, [selected])
        with self.assertRaisesRegex(
            adapter.AcquiredSourceReviewError, "duplicate_source_id"
        ):
            adapter.prepare_sources(
                self.records * 2,
                [
                    {"record_index": 0, "start": 0, "end": 5},
                    {"record_index": 1, "start": 0, "end": 5},
                ],
            )

    def test_repeated_and_overlapping_quotes_require_a_unique_longer_quote(self):
        self.records = [capture("prefix aaaa then aaaa.")]
        self.selections = [{"record_index": 0, "start": 7, "end": 21}]
        for quote in ("aaaa", "aaa"):
            raw = self.response()
            raw["evidence"]["item"][0]["quote"] = quote
            self.assertEqual(self.observe(raw)["reason"], "invalid_evidence")
        raw = self.response()
        raw["evidence"]["item"][0]["quote"] = "then aaaa"
        result = self.observe(raw)
        self.assertTrue(result["eligible"])
        binding = result["evidence_bindings"]["item"][0]
        self.assertEqual((binding["start"], binding["end"]), (5, 14))
        self.assertEqual((binding["original_start"], binding["original_end"]), (12, 21))

    def test_quote_fidelity_does_not_imply_entailment(self):
        # Deliberately unrelated rule-source quotes can satisfy structure while
        # the canned model approves a spacing question. No truth claim follows.
        self.assertTrue(self.observe(self.response())["eligible"])


if __name__ == "__main__":
    unittest.main()
