"""No provider/fetch calls: exact data joins and declared-veto behavior only."""

import copy
import hashlib
import json
import unittest

from evals import claim_evidence_review as adapter


def question():
    return {
        "prompt": '  Given the literal "é  x", which option preserves it?\r\n',
        "choices": ['"é  x"', '"é x"', '"e  x"', '"é   x"'],
        "expectedAnswer": '"é  x"',
        "explanation": '  The original literal "é  x" contains exactly two spaces.\n',
        "choiceExplanations": {},
        "topic": "Literal content",
        "objective": "Preserve text",
        "format": "Multiple Choice",
        "difficulty": 3,
        "verificationVersion": 1,
        "verificationPolicyRevision": 999,
        "assessment": "DO NOT LEAK",
    }


def capture(text="Preface. The literal has two spaces. Afterword.", **changes):
    return {
        "status": "acquired",
        "source_text": text,
        "text_sha256": hashlib.sha256(text.encode()).hexdigest(),
        "text_characters": len(text),
        "raw_content_sha256": "a" * 64,
        "final_url": "https://example.org/rule",
        "retrieved_at_utc": "2026-09-08T00:00:00Z",
        "truncated": False,
        "source_text_complete": True,
        "representation_limits": ["No layout or images."],
        **changes,
    }


class ClaimEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.q = question()
        self.context = {
            "goal": {"title": "Reason about text", "key": "DO NOT LEAK"},
            "sourceDocuments": [{"text": "OLD SUMMARY DO NOT LEAK"}],
            "independentSolutions": "DO NOT LEAK",
        }
        self.challenge = {
            "field": "explanation",
            "choice": None,
            "quote": "contains exactly two spaces",
            "searchQuery": "literal text spacing",
            "rationale": "Check the stated count against the exact literal.",
        }
        self.bound = adapter.validate_discovery(
            json.dumps({"challenge": self.challenge}), self.q
        )
        self.records = [capture()]
        self.selections = [{"record_index": 0, "start": 9, "end": 36}]

    def response(self, **review_changes):
        packet = adapter.sources.prepare_sources(self.records, self.selections)
        span = packet["spans"][0]
        citation = {"source_id": span["source_id"], "quote": span["text"]}
        return {
            "reviews": [
                {
                    "index": 0,
                    "valid": True,
                    "answer": self.q["expectedAnswer"],
                    "difficulty": 3,
                    "explanationSupport": "supported",
                    "issues": [],
                    **review_changes,
                }
            ],
            "evidence": {
                "item": [copy.deepcopy(citation)],
                "mainExplanation": [copy.deepcopy(citation)],
                "target": {
                    **{k: self.challenge[k] for k in ("field", "choice", "quote")},
                    "relation": "supported",
                    "citations": [copy.deepcopy(citation)],
                },
            },
        }

    def observe(self, value, records=None, selections=None):
        return adapter.observe_review(
            value if type(value) is str else json.dumps(value),
            self.q,
            self.context,
            self.bound,
            self.records if records is None else records,
            self.selections if selections is None else selections,
            3,
        )

    def test_source_free_discovery_and_paired_review_differ_only_in_packet(self):
        original = copy.deepcopy((self.q, self.context, self.bound, self.records))
        _, discovery = adapter.discovery_prompt(self.q, self.context)
        self.assertNotIn("DO NOT LEAK", discovery)
        data = json.loads(discovery)
        self.assertEqual(data["sourceDocuments"], [])
        self.assertNotIn("expectedAnswer", data["items"][0])
        self.assertNotIn("difficulty", data["items"][0])
        self.assertNotIn("choiceExplanations", data["items"][0])
        system, grounded = adapter.review_prompt(
            self.q, self.context, self.bound, self.records, self.selections
        )
        empty_system, empty = adapter.review_prompt(
            self.q, self.context, self.bound, [], []
        )
        self.assertEqual(system, empty_system)
        grounded, empty = json.loads(grounded), json.loads(empty)
        self.assertEqual(
            grounded.pop("acquiredSources"),
            adapter.sources.prepare_sources(self.records, self.selections),
        )
        self.assertEqual(empty.pop("acquiredSources")["spans"], [])
        self.assertEqual(grounded, empty)
        self.assertIn("UNTRUSTED", system)
        self.assertEqual(original, (self.q, self.context, self.bound, self.records))

    def test_frozen_target_discovery_uses_prose_protocol_and_same_whitelisted_item(
        self,
    ):
        original = copy.deepcopy((self.q, self.context, self.bound))
        v1_system, v1_user = adapter.discovery_prompt(self.q, self.context)
        system, user = adapter.source_discovery_prompt(self.q, self.context, self.bound)
        data = json.loads(user)
        self.assertEqual(data.pop("challenge"), self.challenge)
        self.assertEqual(data, json.loads(v1_user))
        self.assertEqual(data["items"][0]["prompt"].encode(), self.q["prompt"].encode())
        self.assertEqual(
            data["items"][0]["explanation"].encode(), self.q["explanation"].encode()
        )
        self.assertNotIn("expectedAnswer", user)
        self.assertNotIn("difficulty", data["items"][0])
        self.assertNotIn("DO NOT LEAK", user)
        self.assertEqual(data["sourceDocuments"], [])
        self.assertIn("native citations", system)
        self.assertIn("ordinary prose, without a JSON", system)
        self.assertNotIn('Return only {"challenge"', system)
        self.assertIn("untrusted hypotheses", system)
        self.assertEqual(
            adapter.discovery_prompt(self.q, self.context), (v1_system, v1_user)
        )
        self.assertEqual((self.q, self.context, self.bound), original)

    def test_source_discovery_refuses_changed_question_or_target_binding(self):
        for changes in (
            {"prompt": self.q["prompt"] + "?"},
            {"expectedAnswer": self.q["choices"][1]},
            {"choices": list(reversed(self.q["choices"]))},
        ):
            with (
                self.subTest(changes=changes),
                self.assertRaises(adapter.ClaimEvidenceError),
            ):
                adapter.source_discovery_prompt(
                    {**self.q, **changes}, self.context, self.bound
                )
        for key, value in (
            ("question_sha256", "0" * 64),
            ("target_binding", {**self.bound["target_binding"], "start": True}),
            ("generated_text", "A prior discovery verdict must not be forwarded."),
        ):
            with self.subTest(key=key), self.assertRaises(adapter.ClaimEvidenceError):
                adapter.source_discovery_prompt(
                    self.q, self.context, {**self.bound, key: value}
                )

    def test_discovery_prose_and_prior_verdicts_do_not_enter_either_review_arm(self):
        prior = {
            "generated_text": "PRIVATE_DISCOVERY_PROSE",
            "verdict": "PRIVATE_PRIOR_VERDICT",
            "citation_urls": ["https://private.invalid/prior"],
        }
        self.context.update(discovery=prior, reviews=prior)
        self.q["prior_results"] = prior
        before = [
            adapter.review_prompt(self.q, self.context, self.bound, records, spans)
            for records, spans in (([], []), (self.records, self.selections))
        ]
        _, user = adapter.source_discovery_prompt(self.q, self.context, self.bound)
        after = [
            adapter.review_prompt(self.q, self.context, self.bound, records, spans)
            for records, spans in (([], []), (self.records, self.selections))
        ]
        self.assertEqual(before, after)
        for payload in [user, *[p[1] for p in after]]:
            self.assertNotIn("PRIVATE_DISCOVERY_PROSE", payload)
            self.assertNotIn("PRIVATE_PRIOR_VERDICT", payload)
            self.assertNotIn("https://private.invalid/prior", payload)

    def test_exact_preservation_no_stamp_and_bound_offsets(self):
        result = self.observe(self.response())
        self.assertTrue(result["eligible"])
        self.assertTrue(result["declared_content_eligible"])
        self.assertEqual(result["question"], adapter.freeze_question(self.q))
        self.assertEqual(result["question"]["choiceExplanations"], {})
        self.assertNotIn("verificationPolicyRevision", result["question"])
        self.assertNotIn("verificationVersion", result["question"])
        self.assertNotIn("assessment", result["question"])
        binding = result["evidence_bindings"]["target"][0]
        self.assertEqual(binding["quote"], self.records[0]["source_text"][9:36])
        self.assertEqual((binding["original_start"], binding["original_end"]), (9, 36))
        self.assertEqual((binding["start"], binding["end"]), (0, 27))
        result["question"]["choices"].reverse()
        self.assertEqual(self.q["choices"], question()["choices"])

    def test_target_all_fields_unique_literal_and_full_question_binding(self):
        for field, choice, quote in (
            ("prompt", None, '"é  x"'),
            ("choice", '"é  x"', "é  x"),
        ):
            challenge = {
                **self.challenge,
                "field": field,
                "choice": choice,
                "quote": quote,
            }
            bound = adapter.validate_discovery(
                json.dumps({"challenge": challenge}), self.q
            )
            self.assertEqual(bound["target_binding"]["quote"], quote)
        for changes in (
            {"quote": "contains exactly one space"},
            {"field": "expectedAnswer"},
            {"choice": self.q["choices"][0]},
            {"searchQuery": "x" * 201},
            {"rationale": " "},
            {"replacement": "fake"},
        ):
            with (
                self.subTest(changes=changes),
                self.assertRaises(adapter.ClaimEvidenceError),
            ):
                adapter.validate_discovery(
                    json.dumps({"challenge": {**self.challenge, **changes}}), self.q
                )
        changed = copy.deepcopy(self.q)
        changed["prompt"] += "?"
        with self.assertRaisesRegex(adapter.ClaimEvidenceError, "binding_changed"):
            adapter.review_prompt(changed, self.context, self.bound, [], [])
        self.bound["target_binding"]["start"] = True
        with self.assertRaises(adapter.ClaimEvidenceError):
            adapter.review_prompt(self.q, self.context, self.bound, [], [])

    def test_negative_key_is_allowed_and_same_stem_rotation_ignores_feedback(self):
        self.q["choices"][0] = "No solution exists under the stated conditions."
        self.q["expectedAnswer"] = self.q["choices"][0]
        self.bound = adapter.validate_discovery(
            json.dumps({"challenge": self.challenge}), self.q
        )
        self.assertTrue(self.observe(self.response())["eligible"])
        _, first = adapter.discovery_prompt(self.q, self.context)
        self.q["explanation"] += " "
        _, second = adapter.discovery_prompt(self.q, self.context)
        self.assertEqual(
            json.loads(first)["items"][0]["choices"],
            json.loads(second)["items"][0]["choices"],
        )

    def test_no_evidence_is_not_approval_and_preserves_semantic_rejection(self):
        for changes in ({}, {"explanationSupport": "unsupported"}):
            raw = self.response(**changes)
            raw["evidence"]["item"] = []
            raw["evidence"]["mainExplanation"] = []
            raw["evidence"]["target"]["citations"] = []
            result = self.observe(raw, [], [])
            self.assertEqual(result["reason"], "insufficient_evidence")
            self.assertEqual(result["declared_content_eligible"], not changes)
            self.assertEqual(
                result["review"]["explanationSupport"],
                changes.get("explanationSupport", "supported"),
            )
            self.assertIsNone(result["question"])
        with self.assertRaises(adapter.sources.AcquiredSourceReviewError):
            adapter.review_prompt(self.q, self.context, self.bound, self.records, [])

    def test_core_vetoes_and_target_contradiction_survive_approving_valid_flag(self):
        for changes, expected in (
            ({"explanationSupport": "unsupported"}, "unsupported_authored_explanation"),
            ({"explanationSupport": "uncertain"}, "uncertain_authored_explanation"),
            ({"issues": ["x" * 283]}, "reported_issues"),
            ({"answer": self.q["choices"][1]}, "answer_disagreement"),
            ({"difficulty": 2}, "difficulty_floor"),
        ):
            with self.subTest(expected=expected):
                result = self.observe(self.response(**changes))
                self.assertEqual(result["reason"], expected)
                self.assertFalse(result["declared_content_eligible"])
                self.assertIsNone(result["question"])
        for relation, expected in (
            ("contradicted", "contradicted_target"),
            ("unresolved", "unresolved_target"),
        ):
            raw = self.response()
            raw["evidence"]["target"]["relation"] = relation
            result = self.observe(raw)
            self.assertEqual(result["reason"], expected)
            self.assertTrue(result["declared_content_eligible"])
        raw["evidence"]["target"].update(relation="contradicted", citations=[])
        self.assertEqual(self.observe(raw)["reason"], "insufficient_target_evidence")

    def test_false_omitted_repeated_and_unknown_source_quotes_are_contract_failures(
        self,
    ):
        for change in (
            "invented",
            "omitted",
            "source",
            "offset",
            "duplicate",
            "target_echo",
            "coverage",
        ):
            with self.subTest(change=change):
                raw = self.response()
                citation = raw["evidence"]["target"]["citations"][0]
                if change == "invented":
                    citation["quote"] = "There are three spaces."
                elif change == "omitted":
                    citation["quote"] = "Preface."
                elif change == "source":
                    citation["source_id"] = "fake"
                elif change == "offset":
                    citation["start"] = 0
                elif change == "duplicate":
                    raw["evidence"]["target"]["citations"].append(
                        copy.deepcopy(citation)
                    )
                elif change == "target_echo":
                    raw["evidence"]["target"]["quote"] = "contains exactly one space"
                else:
                    raw["evidence"].pop("mainExplanation")
                self.assertEqual(self.observe(raw)["reason"], "invalid_review")
        text = "prefix aaaa and aaaa é e\u0301."
        self.records, self.selections = (
            [capture(text)],
            [{"record_index": 0, "start": 7, "end": len(text)}],
        )
        for quote in ("aaa", "aaaa", "é é"):
            raw = self.response()
            raw["evidence"]["target"]["citations"][0]["quote"] = quote
            self.assertEqual(self.observe(raw)["reason"], "invalid_review")

    def test_source_mutation_or_failure_never_becomes_evidence(self):
        raw = self.response()
        self.records[0]["final_url"] += "/mutated"
        self.assertEqual(self.observe(raw)["reason"], "invalid_review")
        for change in (
            {"status": "failed"},
            {"status": "partial"},
            {"source_text": "changed"},
        ):
            with (
                self.subTest(change=change),
                self.assertRaises(adapter.sources.AcquiredSourceReviewError),
            ):
                adapter.review_prompt(
                    self.q,
                    self.context,
                    self.bound,
                    [capture(**change)],
                    self.selections,
                )
        self.records = [capture(truncated=True, source_text_complete=False)]
        _, user = adapter.review_prompt(
            self.q, self.context, self.bound, self.records, self.selections
        )
        packet = json.loads(user)["acquiredSources"]
        self.assertTrue(packet["records"][0]["metadata"]["truncated"])
        self.assertTrue(packet["spans"][0]["omits_acquired_text"])

    def test_strict_envelope_no_replacement_duplicates_or_hidden_text_loss(self):
        for change in (
            "replacement",
            "bool",
            "index",
            "extra",
            "relation",
            "duplicate",
            "prose",
            "bound",
        ):
            with self.subTest(change=change):
                raw = self.response()
                if change == "replacement":
                    raw["reviews"][0]["explanation"] = "A rewritten solution."
                elif change == "bool":
                    raw["reviews"][0]["valid"] = 1
                elif change == "index":
                    raw["reviews"][0]["index"] = True
                elif change == "extra":
                    raw["verificationVersion"] = 1
                elif change == "relation":
                    raw["evidence"]["target"]["relation"] = True
                elif change == "duplicate":
                    raw = json.dumps(raw).replace(
                        '"valid": true', '"valid": true, "valid": false'
                    )
                elif change == "prose":
                    raw = json.dumps(raw) + " But the result is false."
                else:
                    raw = " " * (adapter.MAX_RAW_CHARACTERS + 1)
                result = self.observe(raw)
                self.assertEqual(result["reason"], "invalid_review")
                self.assertIsNone(result["declared_content_eligible"])
        with self.assertRaises(adapter.ClaimEvidenceError):
            adapter.validate_discovery(
                json.dumps({"challenge": self.challenge}) + " Extra objection.", self.q
            )

    def test_missing_citation_coverage_and_factual_truth_are_separate(self):
        raw = self.response()
        raw["evidence"]["mainExplanation"] = []
        self.assertEqual(self.observe(raw)["reason"], "insufficient_evidence")
        # The exact quote is structurally valid, but the parser cannot prove it
        # describes this item. A knowingly false model declaration can still pass.
        self.records = [
            capture("This unrelated sentence establishes no text-count rule.")
        ]
        self.selections = [
            {"record_index": 0, "start": 0, "end": len(self.records[0]["source_text"])}
        ]
        self.assertTrue(self.observe(self.response())["eligible"])

    def test_existing_feedback_and_bad_optional_metadata_are_not_silently_repaired(
        self,
    ):
        for changes in (
            {"choiceExplanations": {self.q["choices"][0]: "Existing teaching"}},
            {"explanation": "x" * 421},
            {"prompt": "x" * 321},
            {"topic": {"secret": "metadata"}},
            {"difficulty": True},
        ):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                adapter.freeze_question({**self.q, **changes})


if __name__ == "__main__":
    unittest.main()
