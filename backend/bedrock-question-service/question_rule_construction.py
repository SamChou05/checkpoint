"""Unintegrated MCQs about stipulated Boolean rules, with bounded entailment evidence.

This proves only formal consequences of the displayed premises. It does not
qualify source truth, semantic equivalence of labels, goal fit, distractor
plausibility, or human difficulty. Hashes bind content; they are not signatures.
"""

import hashlib
import itertools
import json
import unicodedata


MAX_ATOMS = 8
MAX_RULES = 8
FIELD_LIMITS = {
    "prompt": 320,
    "choice": 140,
    "explanation": 420,
    "choiceExplanation": 280,
}
CERTIFICATE_SCHEMA = "checkpoint.stipulated_boolean_entailment.v1"
SCOPE = (
    "Entailment relative to the exact displayed, stipulated Boolean premises only. "
    "Not source or subject truth, semantic label equivalence, plausible distractors, "
    "goal fit, calibrated difficulty, or a cryptographic trust signature."
)


class RuleConstructionError(ValueError):
    """The bounded family cannot faithfully construct this specification."""


def _reject(reason):
    raise RuleConstructionError(reason)


def _object(value, keys):
    if type(value) is not dict or set(value) != set(keys):
        _reject("invalid_object_fields")


def _literal(value, atoms):
    _object(value, ("atom", "value"))
    if type(value["atom"]) is not str or value["atom"] not in atoms:
        _reject("unknown_atom")
    if type(value["value"]) is not bool:
        _reject("literal_value_must_be_boolean")
    return value["atom"], value["value"]


def _literal_object(literal):
    return {"atom": literal[0], "value": literal[1]}


def _validated(spec):
    _object(spec, ("atoms", "facts", "rules"))
    atoms = spec["atoms"]
    if type(atoms) is not dict or not 4 <= len(atoms) <= MAX_ATOMS:
        _reject("atom_count_out_of_bounds")
    seen_labels = set()
    for atom, label in atoms.items():
        if type(atom) is not str or atom not in "ABCDEFGH" or len(atom) != 1:
            _reject("invalid_atom_identifier")
        if (
            type(label) is not str
            or not 1 <= len(label) <= 140
            or label != label.strip()
            or any(
                unicodedata.category(c) in ("Cc", "Cf", "Cs", "Zl", "Zp") for c in label
            )
        ):
            _reject("invalid_atom_label")
        # Reject display collisions without rewriting the original Unicode.
        identity = unicodedata.normalize("NFC", label)
        if identity in seen_labels:
            _reject("duplicate_atom_label")
        seen_labels.add(identity)
    atoms = dict(sorted(atoms.items()))
    if type(spec["facts"]) is not list or len(spec["facts"]) > 2 * len(atoms):
        _reject("invalid_facts")
    facts = [_literal(fact, atoms) for fact in spec["facts"]]
    if len(set(facts)) != len(facts):
        _reject("duplicate_fact")
    facts.sort()
    rules = spec["rules"]
    if type(rules) is not list or not 1 <= len(rules) <= MAX_RULES:
        _reject("rule_count_out_of_bounds")
    validated_rules = []
    for rule in rules:
        _object(rule, ("if", "then"))
        if type(rule["if"]) is not list or not 1 <= len(rule["if"]) <= 2:
            _reject("invalid_conjunction")
        antecedents = tuple(sorted(_literal(lit, atoms) for lit in rule["if"]))
        if len({lit[0] for lit in antecedents}) != len(antecedents):
            _reject("duplicate_or_contradictory_antecedent")
        consequent = _literal(rule["then"], atoms)
        if consequent in antecedents:
            _reject("tautological_rule")
        validated_rules.append((antecedents, consequent))
    if len(set(validated_rules)) != len(validated_rules):
        _reject("duplicate_rule")
    normalized = {
        "atoms": atoms,
        "facts": [_literal_object(lit) for lit in facts],
        "rules": [
            {"if": [_literal_object(lit) for lit in ants], "then": _literal_object(con)}
            for ants, con in validated_rules
        ],
    }
    return normalized, facts, validated_rules


def _holds(literal, world):
    return world[literal[0]] is literal[1]


def _allows(rule, world):
    ants, con = rule
    return not all(_holds(lit, world) for lit in ants) or _holds(con, world)


def _symbol(literal):
    return ("" if literal[1] else "!") + literal[0]


def _rule_text(rule):
    ants, con = rule
    return " & ".join(map(_symbol, ants)) + " -> " + _symbol(con)


def _choice(literal):
    return literal[0] + (" is true." if literal[1] else " is false.")


def _json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _hash(value):
    return hashlib.sha256(_json(value).encode("utf-8")).hexdigest()


def _forward_proofs(facts, rules):
    """Least forward depth, not a learner-calibrated cognitive difficulty."""
    depths = dict.fromkeys(facts, 0)
    parents = {}
    changed = True
    while changed:
        changed = False
        for i, (ants, con) in enumerate(rules):
            if all(lit in depths for lit in ants):
                depth = 1 + max(depths[lit] for lit in ants)
                if depth < depths.get(con, float("inf")):
                    depths[con] = depth
                    parents[con] = i
                    changed = True
    return depths, parents


def _support(key, facts_worlds, rule_masks, worlds):
    """Find the smallest rule subset entailing the key, including contraposition."""
    key_mask = sum(1 << i for i, world in enumerate(worlds) if _holds(key, world))
    for size in range(len(rule_masks) + 1):
        for subset in itertools.combinations(range(len(rule_masks)), size):
            allowed = facts_worlds
            for i in subset:
                allowed &= rule_masks[i]
            if allowed and not allowed & ~key_mask:
                return list(subset)
    _reject("internal_entailment_failure")


def _proof_steps(key, parents, rules):
    indices = []

    def visit(literal):
        if literal in parents:
            i = parents[literal]
            if i not in indices:
                for ant in rules[i][0]:
                    visit(ant)
                indices.append(i)

    visit(key)
    return [
        {
            "rule_index": i,
            "if": [_literal_object(a) for a in rules[i][0]],
            "then": _literal_object(rules[i][1]),
        }
        for i in indices
    ]


def _distractors(key, literals, models, rules):
    vectors = {lit: tuple(_holds(lit, model) for model in models) for lit in literals}
    proposals = [((key[0], not key[1]), "negated_derived_conclusion")]
    negated_unknowns = []
    for ants, con in rules:
        if all(vectors[con]):
            proposals.extend((a, "rule_reversal") for a in ants)
            # Negating an unestablished prerequisite is a closed-world mistake,
            # not evidence that its absence from the facts establishes falsity.
            negated_unknowns.extend(
                ((a[0], not a[1]), "negated_unknown_prerequisite")
                for a in ants
                if any(vectors[a]) and not all(vectors[a])
            )
        if len(ants) == 2 and any(all(vectors[a]) for a in ants):
            proposals.append((con, "omitted_required_condition"))
    proposals.extend(negated_unknowns)
    selected, seen = [], set()
    for lit, origin in proposals:
        vector = vectors[lit]
        if all(vector) or vector in seen:
            continue
        seen.add(vector)
        selected.append(
            {
                "literal": _literal_object(lit),
                "choice": _choice(lit),
                "entailed": False,
                "truth_vector": list(vector),
                "countermodel": models[vector.index(False)],
                "candidate_origin": origin,
            }
        )
        if len(selected) == 3:
            return selected
    return None


def _render(spec, facts, rules, key, proof, options):
    labels = "; ".join(
        f"{atom}={json.dumps(label, ensure_ascii=False)}"
        for atom, label in spec["atoms"].items()
    )
    prompt = (
        f"Use only these Boolean premises. Labels (opaque): {labels}. Facts: "
        + (", ".join(map(_symbol, facts)) or "none")
        + ". Rules (one-way): "
        + "; ".join(map(_rule_text, rules))
        + ". ! means NOT; & means AND. Unlisted facts are unknown. Which must follow?"
    )
    needed = {tuple((a["atom"], a["value"])) for step in proof for a in step["if"]}
    given = [lit for lit in facts if lit in needed]
    explanation = (
        "Given "
        + ", ".join(map(_symbol, given))
        + ". "
        + "; ".join(
            _rule_text(rules[step["rule_index"]])
            + " gives "
            + _symbol(_literal(step["then"], spec["atoms"]))
            for step in proof
        )
        + f". Thus {_symbol(key)} holds in every permitted assignment."
    )
    feedback = {}
    for option in options:
        if option["entailed"]:
            text = (
                "Must follow: "
                + _choice(key)
                + " This holds in every assignment satisfying the premises."
            )
        else:
            world = option["countermodel"]
            assignment = ", ".join(
                f"{atom}={str(value).lower()}" for atom, value in world.items()
            )
            atom = option["literal"]["atom"]
            text = (
                f"Need not follow. Allowed assignment: {assignment}. "
                + f"Here {atom} is {str(world[atom]).lower()}."
            )
        feedback[option["choice"]] = text
    question = {
        "prompt": prompt,
        "choices": [o["choice"] for o in options],
        "expectedAnswer": _choice(key),
        "explanation": explanation,
        "choiceExplanations": feedback,
        "format": "Multiple Choice",
    }
    fields = [("prompt", prompt), ("explanation", explanation)]
    fields += [("choice", text) for text in question["choices"]]
    fields += [("choiceExplanation", text) for text in feedback.values()]
    if any(len(text) > FIELD_LIMITS[field] for field, text in fields):
        _reject("rendered_field_limit_exceeded")
    return question


def construct_rule_question(spec):
    """Return {question, certificate}, or raise RuleConstructionError; never clip.

    spec = {atoms: {A: label, ...}, facts: [{atom, value}],
            rules: [{if: [{atom, value}, ...], then: {atom, value}}]}.
    Atom IDs are A–H (4–8 atoms); values must be actual booleans. At most eight
    rules, each with one or two signed antecedents. The key requires forward
    depth >=2 and at least two rules in any entailing subset of the given rules.
    Unknown or unsupported content-qualification flags are never accepted.
    """
    spec, facts, rules = _validated(spec)
    worlds = [
        dict(zip(spec["atoms"], values))
        for values in itertools.product((False, True), repeat=len(spec["atoms"]))
    ]
    facts_mask = sum(
        1 << i for i, w in enumerate(worlds) if all(_holds(lit, w) for lit in facts)
    )
    masks = [
        sum(1 << i for i, w in enumerate(worlds) if _allows(rule, w)) for rule in rules
    ]
    allowed = facts_mask
    for mask in masks:
        allowed &= mask
    models = [w for i, w in enumerate(worlds) if allowed & (1 << i)]
    if not models:
        _reject("inconsistent_premises")
    depths, parents = _forward_proofs(facts, rules)
    literals = [(atom, value) for atom in spec["atoms"] for value in (True, False)]
    candidates = sorted(
        (lit for lit in depths if depths[lit] >= 2), key=lambda lit: (-depths[lit], lit)
    )
    has_nontrivial_key = False
    rendering_exceeded_limit = False
    for key in candidates:
        support = _support(key, facts_mask, masks, worlds)
        if len(support) < 2:
            continue
        has_nontrivial_key = True
        distractors = _distractors(key, literals, models, rules)
        if distractors is None:
            continue
        proof = _proof_steps(key, parents, rules)
        options = [
            {
                "literal": _literal_object(key),
                "choice": _choice(key),
                "entailed": True,
                "truth_vector": [True] * len(models),
                "countermodel": None,
                "candidate_origin": "forward_derivation",
            },
            *distractors,
        ]
        try:
            question = _render(spec, facts, rules, key, proof, options)
        except RuleConstructionError as error:
            if str(error) != "rendered_field_limit_exceeded":
                raise
            rendering_exceeded_limit = True
            continue
        certificate = {
            "schema": CERTIFICATE_SCHEMA,
            "scope": SCOPE,
            "spec": spec,
            "spec_sha256": _hash(spec),
            "content_sha256": _hash(question),
            "enumerated_assignment_count": len(worlds),
            "satisfying_assignment_count": len(models),
            "model_order": "Atoms ascending; assignments lexicographic false before true.",
            "key_literal": _literal_object(key),
            "minimum_forward_depth": depths[key],
            "minimum_entailing_rule_count": len(support),
            "minimum_entailing_rule_indices": support,
            "proof_steps": proof,
            "choice_evidence": options,
        }
        return {"question": question, "certificate": certificate}
    if rendering_exceeded_limit:
        _reject("rendered_field_limit_exceeded")
    _reject(
        "insufficient_distinct_distractors"
        if has_nontrivial_key
        else "no_nontrivial_derived_key"
    )


def verify_rule_certificate(question, certificate):
    """Recompute exact consistency, not provenance, factual approval or trust."""
    try:
        if type(question) is not dict or type(certificate) is not dict:
            return False
        expected = construct_rule_question(certificate["spec"])
        # JSON equality distinguishes booleans from integers and retains Unicode.
        return _json(question) == _json(expected["question"]) and _json(
            certificate
        ) == _json(expected["certificate"])
    except (KeyError, TypeError, ValueError, RecursionError):
        return False
