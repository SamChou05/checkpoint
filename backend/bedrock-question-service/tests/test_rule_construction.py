"""Independent finite-world and rendered-language checks; no model execution."""

import copy
import itertools
import json
import re
import unittest
from unittest.mock import patch

import question_rule_construction as construction


def literal(symbol):
    return {"atom": symbol[-1], "value": not symbol.startswith("!")}


def rule(antecedents, conclusion):
    return {"if": [literal(a) for a in antecedents], "then": literal(conclusion)}


def spec(facts, rules, names="ABCDE"):
    return {
        "atoms": {a: f"tag {a}" for a in names},
        "facts": [literal(f) for f in facts],
        "rules": rules,
    }


def chain():
    return spec(
        ["A"], [rule(["A"], "B"), rule(["B"], "C"), rule(["D"], "B"), rule(["E"], "C")]
    )


def read_display(question):
    """Read only learner-visible text, without certificate or input spec."""
    match = re.fullmatch(
        r"Use only these Boolean premises\. Labels \(opaque\): (.*)\. Facts: (.*?)"
        r"\. Rules \(one-way\): (.*?)\. ! means NOT; & means AND\. "
        r"Unlisted facts are unknown\. Which must follow\?",
        question["prompt"],
    )
    assert match, "Incomplete displayed premises"
    labels, facts_text, rules_text = match.groups()
    atoms, pos = {}, 0
    while pos < len(labels):
        atom = labels[pos]
        assert atom in "ABCDEFGH" and labels[pos + 1] == "="
        value, end = json.JSONDecoder().raw_decode(labels[pos + 2 :])
        assert atom not in atoms
        atoms[atom] = value
        pos += end + 2
        if pos < len(labels):
            assert labels[pos : pos + 2] == "; "
            pos += 2
    facts = [] if facts_text == "none" else facts_text.split(", ")
    rules = []
    for text in rules_text.split("; "):
        left, right = text.split(" -> ")
        rules.append((left.split(" & "), right))
    for token in facts + [v for ants, con in rules for v in [*ants, con]]:
        assert re.fullmatch(r"!?[A-H]", token) and token[-1] in atoms
    return atoms, facts, rules


def displayed_worlds(question):
    atoms, facts, rules = read_display(question)

    def true(token, world):
        return world[token[-1]] == (token[0] != "!")

    models = []
    for values in itertools.product((False, True), repeat=len(atoms)):
        world = dict(zip(atoms, values))
        if all(true(f, world) for f in facts) and all(
            not all(true(a, world) for a in ants) or true(con, world)
            for ants, con in rules
        ):
            models.append(world)
    return models


def choice_literal(text):
    match = re.fullmatch(r"([A-H]) is (true|false)\.", text)
    assert match, text
    return match[1], match[2] == "true"


class RuleConstructionTests(unittest.TestCase):
    def check_evidence(self, result):
        q, cert = result["question"], result["certificate"]
        atoms, facts, rules = read_display(q)
        models = displayed_worlds(q)
        self.assertTrue(models)
        self.assertEqual(len(models), cert["satisfying_assignment_count"])
        self.assertEqual(2 ** len(atoms), cert["enumerated_assignment_count"])
        vectors = []
        for option, evidence in zip(q["choices"], cert["choice_evidence"], strict=True):
            atom, value = choice_literal(option)
            vector = [world[atom] == value for world in models]
            vectors.append(tuple(vector))
            self.assertEqual(vector, evidence["truth_vector"])
            self.assertEqual(all(vector), evidence["entailed"])
            if all(vector):
                self.assertEqual(option, q["expectedAnswer"])
                self.assertIsNone(evidence["countermodel"])
            else:
                self.assertIn(evidence["countermodel"], models)
                self.assertNotEqual(evidence["countermodel"][atom], value)
                match = re.fullmatch(
                    r"Need not follow\. Allowed assignment: (.*?)\. Here ([A-H]) is (true|false)\.",
                    q["choiceExplanations"][option],
                )
                self.assertIsNotNone(match)
                world = {
                    key: val == "true"
                    for key, val in (part.split("=") for part in match[1].split(", "))
                }
                self.assertIn(world, models)
                self.assertNotEqual(world[atom], value)
                self.assertEqual(world[match[2]], match[3] == "true")
        self.assertEqual(4, len(set(vectors)))
        self.assertEqual(1, sum(all(v) for v in vectors))
        self.assertEqual(4, len(q["choices"]))
        self.assertEqual(set(q["choices"]), set(q["choiceExplanations"]))
        # Replay the displayed proof, independently of its certificate trace.
        prefix, proof_text = q["explanation"].split(". ", 1)
        self.assertTrue(prefix.startswith("Given "))
        known = set(prefix.removeprefix("Given ").split(", "))
        self.assertTrue(known <= set(facts))
        proof_text, conclusion = proof_text.split(". Thus ")
        for step in proof_text.split("; "):
            implication, output = step.split(" gives ")
            antecedents, consequent = implication.split(" -> ")
            ants = antecedents.split(" & ")
            self.assertIn((ants, consequent), rules)
            self.assertTrue(set(ants) <= known)
            self.assertEqual(consequent, output)
            known.add(output)
        atom, value = choice_literal(q["expectedAnswer"])
        symbol = ("" if value else "!") + atom
        self.assertIn(symbol, known)
        self.assertNotIn(symbol, facts)
        self.assertEqual(conclusion, f"{symbol} holds in every permitted assignment.")
        self.assertTrue(construction.verify_rule_certificate(q, cert))
        self.assertNotIn("difficulty", q)
        self.assertNotIn("verificationVersion", q)
        self.assertLessEqual(len(q["prompt"]), 320)
        self.assertLessEqual(len(q["explanation"]), 420)
        self.assertTrue(all(len(c) <= 140 for c in q["choices"]))
        self.assertTrue(all(len(t) <= 280 for t in q["choiceExplanations"].values()))

    def test_all_eight_signed_chains_against_rendered_worlds(self):
        for signs in itertools.product((False, True), repeat=3):
            a, b, c = [("" if val else "!") + atom for atom, val in zip("ABC", signs)]
            with self.subTest(signs=signs):
                r = construction.construct_rule_question(
                    spec(
                        [a],
                        [rule([a], b), rule([b], c), rule(["D"], b), rule(["E"], c)],
                    )
                )
                self.check_evidence(r)
                self.assertEqual(literal(c), r["certificate"]["key_literal"])
                self.assertEqual(2, r["certificate"]["minimum_forward_depth"])
                self.assertEqual(2, r["certificate"]["minimum_entailing_rule_count"])

    def test_conjunction_and_signed_condition_are_preserved(self):
        for second in ("B", "!B"):
            r = construction.construct_rule_question(
                spec(
                    ["A", second],
                    [
                        rule(["A", second], "!C"),
                        rule(["!C"], "!D"),
                        rule(["E"], "!C"),
                        rule(["F"], "!D"),
                    ],
                    "ABCDEF",
                )
            )
            self.check_evidence(r)
            self.assertEqual("D is false.", r["question"]["expectedAnswer"])
            self.assertIn(f"A & {second} -> !C", r["question"]["prompt"])

    def test_missing_positive_or_negative_condition_is_unknown(self):
        for condition in ("B", "!B"):
            s = spec(
                ["A"],
                [
                    rule(["A", condition], "C"),
                    rule(["C"], "D"),
                    rule(["E"], "C"),
                    rule(["F"], "D"),
                ],
                "ABCDEF",
            )
            with self.assertRaisesRegex(
                construction.RuleConstructionError, "no_nontrivial_derived_key"
            ):
                construction.construct_rule_question(s)

    def test_unknowns_remain_possible_with_converse_and_closed_world_traps(self):
        r = construction.construct_rule_question(chain())
        self.check_evidence(r)
        self.assertEqual(
            ["C is true.", "C is false.", "D is true.", "E is true."],
            r["question"]["choices"],
        )
        for e in r["certificate"]["choice_evidence"][2:]:
            self.assertIn(True, e["truth_vector"])
            self.assertIn(False, e["truth_vector"])
            self.assertEqual("rule_reversal", e["candidate_origin"])
            self.assertNotIn(
                "impossible", r["question"]["choiceExplanations"][e["choice"]]
            )
        s = chain()
        s["atoms"].pop("E")
        s["rules"].pop()
        r = construction.construct_rule_question(s)
        self.check_evidence(r)
        e = next(
            e
            for e in r["certificate"]["choice_evidence"]
            if e["choice"] == "D is false."
        )
        self.assertEqual("negated_unknown_prerequisite", e["candidate_origin"])
        self.assertTrue(e["countermodel"]["D"])

    def test_omitted_conjunct_distractor_has_real_countermodel(self):
        r = construction.construct_rule_question(
            spec(
                ["A"],
                [
                    rule(["A"], "C"),
                    rule(["C"], "D"),
                    rule(["A", "B"], "E"),
                    rule(["F"], "C"),
                ],
                "ABCDEF",
            )
        )
        self.check_evidence(r)
        e = next(
            e
            for e in r["certificate"]["choice_evidence"]
            if e["choice"] == "E is true."
        )
        self.assertEqual("omitted_required_condition", e["candidate_origin"])
        self.assertFalse(e["countermodel"]["B"])
        self.assertFalse(e["countermodel"]["E"])

    def test_unused_atoms_cannot_fill_wrong_choices(self):
        s = chain()
        s["rules"] = s["rules"][:2]
        with self.assertRaisesRegex(
            construction.RuleConstructionError, "insufficient_distinct_distractors"
        ):
            construction.construct_rule_question(s)

    def test_equivalent_unknowns_do_not_duplicate_choices(self):
        s = chain()
        s["rules"] += [rule(["D"], "E"), rule(["E"], "D")]
        r = construction.construct_rule_question(s)
        self.check_evidence(r)
        self.assertFalse({"D is true.", "E is true."} <= set(r["question"]["choices"]))
        self.assertFalse(
            {"D is false.", "E is false."} <= set(r["question"]["choices"])
        )

    def test_determined_chain_has_depth_but_insufficient_distinct_distractors(self):
        s = spec(["A"], [rule([a], b) for a, b in zip("ABCD", "BCDE")])
        with self.assertRaisesRegex(
            construction.RuleConstructionError, "insufficient_distinct_distractors"
        ):
            construction.construct_rule_question(s)

    def test_contradictions_do_not_exploit_vacuous_entailment(self):
        for derived in (False, True):
            s = chain()
            if derived:
                s["rules"].append(rule(["B"], "!A"))
            else:
                s["facts"].append(literal("!A"))
            with self.assertRaisesRegex(
                construction.RuleConstructionError, "inconsistent_premises"
            ):
                construction.construct_rule_question(s)

    def test_unseeded_cycles_and_given_answers_are_not_derived_keys(self):
        for cycle in (False, True):
            s = chain()
            if cycle:
                s["facts"] = []
                s["rules"].append(rule(["C"], "A"))
            else:
                s["facts"].append(literal("C"))
            with self.assertRaisesRegex(
                construction.RuleConstructionError, "no_nontrivial_derived_key"
            ):
                construction.construct_rule_question(s)

    def test_direct_and_contrapositive_shortcuts_disqualify_a_key(self):
        direct = chain()
        direct["rules"].append(rule(["A"], "C"))
        contra = chain()
        contra["atoms"]["F"] = "off tag"
        contra["facts"].append(literal("!F"))
        contra["rules"].append(rule(["!C"], "F"))
        # Independent two-variable truth table: !F and (!C -> F) entail C.
        allowed = [
            (c, f)
            for c, f in itertools.product((False, True), repeat=2)
            if not f and (c or f)
        ]
        self.assertEqual([(True, False)], allowed)
        for s in (direct, contra):
            with self.assertRaisesRegex(
                construction.RuleConstructionError, "no_nontrivial_derived_key"
            ):
                construction.construct_rule_question(s)

    def test_256_assignment_bound_and_strict_types(self):
        s = chain()
        s["atoms"].update({"F": "six", "G": "seven", "H": "eight"})
        r = construction.construct_rule_question(s)
        self.check_evidence(r)
        self.assertEqual(256, r["certificate"]["enumerated_assignment_count"])
        bad_specs = (
            None,
            [],
            {**s, "qualified": True},
            {**s, "facts": tuple(s["facts"])},
            {**s, "atoms": {**s["atoms"], "I": "nine"}},
            {**s, "rules": s["rules"] * 3},
        )
        for bad in bad_specs:
            with (
                self.subTest(bad=bad),
                self.assertRaises(construction.RuleConstructionError),
            ):
                construction.construct_rule_question(bad)
        for value in (0, 1, "true", None, [], {}):
            bad = chain()
            bad["facts"][0]["value"] = value
            with self.assertRaisesRegex(
                construction.RuleConstructionError, "literal_value_must_be_boolean"
            ):
                construction.construct_rule_question(bad)

    def test_invalid_rules_facts_and_label_collisions(self):
        mutations = [
            lambda s: s["facts"].append(literal("A")),
            lambda s: s["facts"][0].update(atom="Z"),
            lambda s: s["rules"][0].update(iff=True),
            lambda s: s["rules"][0].update({"if": []}),
            lambda s: s["rules"][0].update({"if": [literal("A"), literal("!A")]}),
            lambda s: s["rules"][0].update(
                {"if": [literal("A"), literal("B"), literal("C")]}
            ),
            lambda s: s["rules"][0].update(then=literal("A")),
            lambda s: s["rules"].append(copy.deepcopy(s["rules"][0])),
            lambda s: s["atoms"].update(D=s["atoms"]["E"]),
            lambda s: s["atoms"].update(D="\u00e9", E="e\u0301"),
            lambda s: s["atoms"].update(D="line\nbreak"),
            lambda s: s["atoms"].update(D="zero\u200bwidth"),
            lambda s: s["atoms"].update(D=" boundary "),
        ]
        for mutate in mutations:
            s = chain()
            mutate(s)
            with (
                self.subTest(spec=s),
                self.assertRaises(construction.RuleConstructionError),
            ):
                construction.construct_rule_question(s)

    def test_opaque_quoted_labels_preserve_unicode_and_delimiters(self):
        s = chain()
        label = 'not red; ". Facts: !A; \\ e\u0301'
        s["atoms"]["D"] = label
        r = construction.construct_rule_question(s)
        self.check_evidence(r)
        self.assertEqual(label, read_display(r["question"])[0]["D"])
        self.assertEqual(
            label.encode(), r["certificate"]["spec"]["atoms"]["D"].encode()
        )
        self.assertIn("semantic label equivalence", r["certificate"]["scope"])

    def test_hard_field_limits_and_shorter_candidate_fallback(self):
        s = chain()
        n = len(construction.construct_rule_question(s)["question"]["prompt"])
        s["atoms"]["A"] += "x" * (320 - n)
        r = construction.construct_rule_question(s)
        self.assertEqual(320, len(r["question"]["prompt"]))
        self.assertEqual(s["atoms"], read_display(r["question"])[0])
        s["atoms"]["A"] += "x"
        with self.assertRaisesRegex(
            construction.RuleConstructionError, "rendered_field_limit_exceeded"
        ):
            construction.construct_rule_question(s)
        s = chain()
        s["atoms"]["F"] = "last"
        s["rules"].append(rule(["C"], "F"))
        self.assertEqual(
            "F is true.",
            construction.construct_rule_question(s)["question"]["expectedAnswer"],
        )
        limit = len(
            construction.construct_rule_question(chain())["question"]["explanation"]
        )
        with patch.dict(construction.FIELD_LIMITS, explanation=limit):
            fallback = construction.construct_rule_question(s)
            self.check_evidence(fallback)
        self.assertEqual("C is true.", fallback["question"]["expectedAnswer"])
        for field in ("choice", "explanation", "choiceExplanation"):
            with (
                self.subTest(field=field),
                patch.dict(construction.FIELD_LIMITS, {field: 1}),
            ):
                with self.assertRaisesRegex(
                    construction.RuleConstructionError, "rendered_field_limit_exceeded"
                ):
                    construction.construct_rule_question(chain())

    def test_every_content_and_certificate_claim_is_recomputed(self):
        original = construction.construct_rule_question(chain())
        mutations = [
            lambda q: q.update(prompt=q["prompt"].replace("Facts: A.", "Facts: !A.")),
            lambda q: q.update(prompt=q["prompt"].replace("A -> B", "B -> A")),
            lambda q: q.update(expectedAnswer="D is true."),
            lambda q: q["choices"].reverse(),
            lambda q: q.update(
                explanation=q["explanation"] + " This proves shipping skill."
            ),
            lambda q: q["choiceExplanations"].update({q["choices"][1]: "Impossible."}),
            lambda q: q.update(qualified=True),
        ]
        for mutate in mutations:
            q, cert = (
                copy.deepcopy(original["question"]),
                copy.deepcopy(original["certificate"]),
            )
            mutate(q)
            self.assertFalse(construction.verify_rule_certificate(q, cert))
            cert["content_sha256"] = construction._hash(q)
            self.assertFalse(construction.verify_rule_certificate(q, cert))
        for key, value in (
            ("minimum_forward_depth", 99),
            ("satisfying_assignment_count", 0),
            ("minimum_entailing_rule_count", True),
            ("qualified", True),
        ):
            cert = copy.deepcopy(original["certificate"])
            cert[key] = value
            self.assertFalse(
                construction.verify_rule_certificate(original["question"], cert)
            )
        cert = copy.deepcopy(original["certificate"])
        cert["choice_evidence"][1]["countermodel"]["A"] = False
        self.assertFalse(
            construction.verify_rule_certificate(original["question"], cert)
        )
        for bad in (None, [], {}, {"spec": None}):
            self.assertFalse(
                construction.verify_rule_certificate(original["question"], bad)
            )


if __name__ == "__main__":
    unittest.main()
