"""Adversarial offline checks for the eval-only source claim challenge."""

import copy
import hashlib
import json
import unittest

from evals import source_claim_challenge as challenge


def question():
    return {
        "prompt": "Four items are doubled. Which total follows from that operation?",
        "choices": ["8", "6", "4", "2"],
        "expectedAnswer": "8",
        "explanation": "Twice four is eight. Doubling multiplies the count by two.",
        "choiceExplanations": {},
        "topic": "Counting",
        "difficulty": 3,
        "format": "Multiple Choice",
        "verificationPolicyRevision": 999,
    }


def capture(text="Doubling four items produces eight items.", **changes):
    return {
        "status": "acquired",
        "source_text": text,
        "text_sha256": hashlib.sha256(text.encode()).hexdigest(),
        "text_characters": len(text),
        "raw_content_sha256": "a" * 64,
        "final_url": "https://example.org/counting",
        "retrieved_at_utc": "2026-09-26T00:00:00Z",
        "truncated": False,
        "source_text_complete": True,
        "representation_limits": ["Text only; diagrams omitted."],
        **changes,
    }


def slices(text, *, stem=False):
    boundary = text.index(".") + 1
    parts = [{"start": 0, "end": boundary},
             {"start": boundary, "end": len(text)}]
    if stem:
        parts[0]["role"] = "premise"
        parts[1]["role"] = "task"
    return parts


class SourceClaimChallengeTests(unittest.TestCase):
    def setUp(self):
        self.q = question()
        self.context = {"goal": {"title": "Apply doubling"},
                        "sourceDocuments": [{"text": "Untrusted old summary"}],
                        "independentSolutions": "UNTRUSTED_PRIOR_VERDICT"}
        self.records = [capture()]
        self.selections = [{"record_index": 0, "start": 0,
                            "end": len(self.records[0]["source_text"])}]
        self.prepared = self.prepare()

    def prepare(self, question_value=None, records=None, selections=None,
                stem_slices=None, teaching_slices=None):
        q = self.q if question_value is None else question_value
        return challenge.prepare(
            q, self.context, self.records if records is None else records,
            self.selections if selections is None else selections,
            slices(q["prompt"], stem=True) if stem_slices is None else stem_slices,
            slices(q["explanation"]) if teaching_slices is None else teaching_slices,
        )

    def assessment(self, status="supported", *, evidence=None, conditions=None):
        return {"reason": "The stated operation fixes this judgment.",
                "status": status,
                "evidence": ["S1U1"] if evidence is None else evidence,
                "missingConditions": [] if conditions is None else conditions}

    def choice_response(self, prepared=None):
        p = self.prepared if prepared is None else prepared
        correct = next(letter for letter, text in p["base"]["payload"]["item"]["choices"].items()
                       if text == p["base"]["question"]["expectedAnswer"])
        return {
            "premises": {"P1": self.assessment()},
            "choices": {letter: self.assessment("supported" if letter == correct else "refuted")
                        for letter in challenge.split.LETTERS},
            "pairs": {pair: {"reason": "Different proposed totals.", "relation": "distinct"}
                      for pair in challenge.PAIRS},
            "issues": [],
        }

    def teaching_response(self):
        return {"claims": {"M1": self.assessment(), "M2": self.assessment()},
                "issues": [], "difficulty": 3}

    def observe(self, value, role, prepared=None):
        p = self.prepared if prepared is None else prepared
        return challenge.observe(json.dumps(value), p, role)

    def combined(self, choices=None, teaching=None, prepared=None):
        p = self.prepared if prepared is None else prepared
        c = self.choice_response(p) if choices is None else choices
        t = self.teaching_response() if teaching is None else teaching
        return challenge.combine(p, self.observe(c, "choices", p),
                                 self.observe(t, "teaching", p))

    def test_exact_partition_server_ids_and_role_isolation(self):
        p = self.prepared
        self.assertEqual([x["id"] for x in p["layout"]["stem"]], ["P1", "T1"])
        self.assertEqual([x["id"] for x in p["layout"]["teaching"]], ["M1", "M2"])
        self.assertEqual("".join(x["text"] for x in p["layout"]["stem"]), self.q["prompt"])
        self.assertEqual("".join(x["text"] for x in p["layout"]["teaching"]),
                         self.q["explanation"])
        _, solver = challenge.prompt(p, "choices")
        _, auditor = challenge.prompt(p, "teaching")
        self.assertNotIn("expectedAnswer", solver + auditor)
        self.assertNotIn("UNTRUSTED_PRIOR_VERDICT", solver + auditor)
        self.assertNotIn(self.q["explanation"], solver)
        self.assertIn(self.q["explanation"], auditor)
        self.assertIn("choicePairs", solver)
        self.assertNotIn("choicePairs", auditor)
        result = self.combined()
        self.assertTrue(result["eligible"])
        self.assertEqual(result["question"]["explanation"], self.q["explanation"])
        self.assertNotIn("verificationPolicyRevision", result["question"])

    def test_incomplete_or_overlapping_claim_layout_fails_before_dispatch(self):
        for bad in ([{"start": 0, "end": 3, "role": "premise"}],
                    [{"start": 0, "end": 3, "role": "premise"},
                     {"start": 2, "end": len(self.q["prompt"]), "role": "task"}],
                    [{"start": 0, "end": len(self.q["prompt"]), "role": "premise"}]):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                self.prepare(stem_slices=bad)
        with self.assertRaises(ValueError):
            self.prepare(teaching_slices=[{"start": 0,
                                            "end": self.q["explanation"].index(".") + 1}])

    def test_missing_unknown_ids_and_missing_conditions_fail_closed(self):
        for field, item in (("premises", "P1"), ("choices", "A")):
            response = self.choice_response()
            del response[field][item]
            self.assertEqual(self.combined(choices=response)["reason"], "invalid_review")
        response = self.teaching_response()
        response["claims"]["M3"] = self.assessment()
        self.assertEqual(self.combined(teaching=response)["reason"], "invalid_review")
        response = self.choice_response()
        response["choices"]["A"]["evidence"] = ["UNKNOWN"]
        self.assertEqual(self.combined(choices=response)["reason"], "invalid_review")
        response = self.choice_response()
        response["premises"]["P1"]["missingConditions"] = ["Only if a separate rule applies."]
        self.assertEqual(self.combined(choices=response)["reason"], "missing_conditions")

    def test_premise_key_main_and_pair_vetoes(self):
        response = self.choice_response()
        response["premises"]["P1"]["status"] = "uncertain"
        self.assertEqual(self.combined(choices=response)["reason"], "premise_unresolved")
        response = self.choice_response()
        response["choices"]["A"]["status"] = "uncertain"
        self.assertEqual(self.combined(choices=response)["reason"], "choice_uncertain")
        response = self.choice_response()
        for row in response["choices"].values():
            row["status"] = "refuted"
        self.assertEqual(self.combined(choices=response)["reason"], "zero_supported")
        response = self.choice_response()
        for row in response["choices"].values():
            row["status"] = "supported"
        self.assertEqual(self.combined(choices=response)["reason"], "multiple_supported")
        response = self.choice_response()
        response["pairs"]["AB"]["relation"] = "equivalent"
        self.assertEqual(self.combined(choices=response)["reason"],
                         "equivalent_or_uncertain_choices")
        response = self.choice_response()
        correct = next(letter for letter, row in response["choices"].items()
                       if row["status"] == "supported")
        wrong = next(letter for letter in response["choices"] if letter != correct)
        response["choices"][correct]["status"] = "refuted"
        response["choices"][wrong]["status"] = "supported"
        self.assertEqual(self.combined(choices=response)["reason"], "answer_disagreement")
        teaching = self.teaching_response()
        teaching["claims"]["M2"]["status"] = "refuted"
        self.assertEqual(self.combined(teaching=teaching)["reason"], "teaching_unresolved")
        teaching = self.teaching_response()
        teaching["claims"]["M1"]["missingConditions"] = ["Only if the count is unchanged."]
        self.assertEqual(self.combined(teaching=teaching)["reason"], "missing_conditions")
        teaching = self.teaching_response()
        teaching["difficulty"] = 2
        self.assertEqual(self.combined(teaching=teaching)["reason"], "difficulty_floor")

    def test_semantically_equivalent_choice_text_is_vetoed_when_declared(self):
        q = {**self.q, "choices": ["8", "eight", "6", "4"]}
        p = self.prepare(question_value=q)
        response = self.choice_response(p)
        choices = p["base"]["payload"]["item"]["choices"]
        left, right = [letter for letter, text in choices.items() if text in {"8", "eight"}]
        pair = "".join(sorted((left, right)))
        response["pairs"][pair]["relation"] = "equivalent"
        self.assertEqual(self.combined(choices=response, prepared=p)["reason"],
                         "equivalent_or_uncertain_choices")

    def test_incomplete_and_truncated_source_never_silently_approve(self):
        records = [capture("Intro. Doubling four gives eight. End.")]
        selected = [{"record_index": 0, "start": 7, "end": 33}]
        p = self.prepare(records=records, selections=selected)
        self.assertEqual(self.combined(prepared=p)["reason"], "incomplete_source_scope")
        records = [capture(truncated=True, source_text_complete=False)]
        p = self.prepare(records=records)
        self.assertEqual(self.combined(prepared=p)["reason"], "incomplete_source_scope")

    def test_source_and_prepared_mutation_cannot_reuse_a_binding(self):
        records = [capture(text_sha256="0" * 64)]
        with self.assertRaises(ValueError):
            self.prepare(records=records)
        for mutate in (
            lambda p: p["base"]["payload"]["evidenceSources"][0]["units"][0].update(text="Altered"),
            lambda p: p["source_packet"]["spans"][0].update(text="Altered"),
            lambda p: p["layout"]["teaching"][0].update(text="Altered"),
            lambda p: p["base"]["question"].update(expectedAnswer="6"),
        ):
            p = copy.deepcopy(self.prepared)
            mutate(p)
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                challenge.prompt(p, "choices")
        first = self.observe(self.choice_response(), "choices")
        changed_result = copy.deepcopy(first)
        changed_result["value"]["choices"]["A"]["status"] = "uncertain"
        with self.assertRaises(ValueError):
            challenge.combine(self.prepared, changed_result,
                              self.observe(self.teaching_response(), "teaching"))
        other = copy.deepcopy(self.prepared)
        other["base"]["question"]["expectedAnswer"] = "6"
        with self.assertRaises(ValueError):
            challenge.combine(other, first, self.observe(self.teaching_response(), "teaching"))

    def test_irrelevant_exact_source_id_still_does_not_prove_entailment(self):
        records = [capture("The Moon is gray.")]
        selected = [{"record_index": 0, "start": 0, "end": len(records[0]["source_text"])}]
        p = self.prepare(records=records, selections=selected)
        result = self.combined(prepared=p)
        self.assertTrue(result["eligible"])
        self.assertIn("no semantic certification", result["scope"])

    def test_valid_insufficient_information_answer_is_not_blanket_rejected(self):
        q = {**self.q,
             "prompt": "A cyclist travels 18 km. Which exact speed follows without the travel time?",
             "choices": ["9 km/h", "18 km/h", "36 km/h", "No unique speed follows"],
             "expectedAnswer": "No unique speed follows",
             "explanation": "Speed equals distance divided by time. The travel time is absent, so several speeds fit."}
        p = self.prepare(question_value=q, stem_slices=[
            {"start": 0, "end": q["prompt"].index(".") + 1, "role": "premise"},
            {"start": q["prompt"].index(".") + 1, "end": len(q["prompt"]), "role": "task"},
        ], teaching_slices=slices(q["explanation"]))
        self.assertTrue(self.combined(prepared=p)["eligible"])


if __name__ == "__main__":
    unittest.main()
