"""Offline post-failure proof audit; never invokes a provider."""

from fractions import Fraction
import hashlib
import itertools
import json
import os
from pathlib import Path
import re
import sys
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "backend/bedrock-question-service"))

import native_output_contracts as native  # noqa: E402
import question_generation as generation  # noqa: E402
from agreement_task_constructor import (  # noqa: E402
    blocked_fingerprint_variant_identities, compile_question as compile_english,
    prepare_mapped_agreement_rows,
)
from mapped_quantitative_families import (  # noqa: E402
    BOUNDARIES, FAMILIES, OPERANDS, flat_task, select_novel_task,
)
from question_bank_common import _normalized_stem_identity, _stem_fingerprint  # noqa: E402
from question_quality import _sanitize_questions  # noqa: E402

PLAN_SHA = "5681a27a407aebfad3f3b8e2ec6422859a912c28b7a77c7b972492aa0c5d44e2"
CAPTURE_SHA = "f27a207c6039f54cd7ad3e640184e9cbbcb5b42940e23b683c08999635496ec5"
WORKSHEET_SHA = "ff075ecd551b604ba84c8e57496733c69b7613102cb653c1d777a64dce90ae04"
PRIOR_SHA = "f9e81f34f19e4829b49587c3919d77bae2595784064e063631d3515b61e009fa"
FIELDS = ("prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations")
LABEL_REFERENCE = re.compile(r"\b(?:choice|option|answer)\s+[ABCD]\b", re.IGNORECASE)


def checked(path, digest):
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != digest:
        raise ValueError(f"Locked file drifted: {path.name}")
    return json.loads(raw)


def independent_key(slot, a, b):
    if slot == 0:
        return str(3 * (Fraction(a, a + 1) + Fraction(b, b + 2)))
    if slot == 1:
        offset = a + 3
        satisfying = [x for x in range(0, 16) if a * x + offset == a * b + offset]
        if satisfying != [b]:
            raise ValueError("Equation solution set drifted.")
        return str(b)
    domain = range(b - 3, b + 4)
    threshold = Fraction(b, b + a)
    satisfying = [x for x in domain if Fraction(x, x + a) >= threshold]
    if min(satisfying) != b:
        raise ValueError("Ratio threshold minimum drifted.")
    return str(b)


def audit():
    plan = checked(HERE / "plan.json", PLAN_SHA)
    capture = checked(HERE / "capture.json", CAPTURE_SHA)
    worksheet = checked(HERE / "candidate-worksheet.json", WORKSHEET_SHA)
    private = json.loads((HERE / "candidate-private.json").read_text())
    prior = checked(ROOT / "docs/evidence/mapped-quant-families-qualification-20260927/capture.json",
                    PRIOR_SHA)
    if (capture["attempted_calls"] != 3 or len(capture["calls"]) != 3
            or [call.get("response") is not None for call in capture["calls"]] != [True, True, False]
            or capture["calls"][2]["error"]["type"] != "ReadTimeoutError"
            or capture["returned"] or private["partial_capture_sha256"] != CAPTURE_SHA
            or private["plan_sha256"] != PLAN_SHA):
        raise ValueError("This was not the captured reviewer-timeout attempt.")
    request = plan["bank"]["refill_request"]
    raw = json.loads(capture["calls"][0]["response"]["output"]["message"]["content"][0]["text"])
    with patch.dict(os.environ, plan["environment"], clear=True):
        assignments = generation._mapped_fixed_slot_assignments(
            request, "constructed_quantitative", "array")
        if assignments is None or not generation._mapped_agreement_route(request, assignments):
            raise ValueError("Mapped scope or route lost.")
        contract = generation._mapped_author_contract(request, assignments, True, True)
        adapted = json.loads(native.adapt_native_response(json.dumps(raw), contract))
        existing = tuple(dict.fromkeys(request["existingPrompts"] + request["reportedPrompts"]
                     + [x["prompt"] for x in request["existingQuestionCoverage"] if x.get("prompt")]))
        blocked = tuple(sorted(set(request["_agreementVariantIdentities"])
                     | blocked_fingerprint_variant_identities(
                         request["blockedStemFingerprints"], request["stemFingerprintVersion"])))
        rows, numeric, english, failures = prepare_mapped_agreement_rows(
            adapted, contract, existing_prompts=existing,
            blocked_variant_identities=blocked,
            blocked_stem_fingerprints=tuple(request["blockedStemFingerprints"]),
            stem_fingerprint_version=request["stemFingerprintVersion"])
        compiled_output, agreement_output = {}, {}
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        candidates = _sanitize_questions(
            rows, request, metrics, preserve_authored_explanation=True,
            compiled_candidates=numeric, compiled_output=compiled_output,
            agreement_candidates=english, agreement_output=agreement_output,
            prefer_compiled_within_assignment=True)
    if failures or len(candidates) != 5 or set(numeric) != {0, 1, 2} or set(english) != {3, 4}:
        raise ValueError("Compiler or sanitizer yield drifted.")
    previous = prior["jobs"][0]["returned"]
    refs = private["mapping"]
    if len(worksheet["items"]) != 10 or len(refs) != 10:
        raise ValueError("Blind projection count drifted.")
    for item in worksheet["items"]:
        ref = refs[item["id"]]
        source = previous if ref["origin"] == "previous_verified" else candidates
        question = source[ref["original_slot"]]
        if question != ref["question"] or item["prompt"] != question["prompt"]:
            raise ValueError("Worksheet projection changed its question source.")
        choices = item["choices"]
        if set(choices) != set("ABCD") or sorted(choices.values()) != sorted(question["choices"]):
            raise ValueError("Worksheet choice projection drifted.")
        if choices[ref["correct_display_choice"]] != question["expectedAnswer"]:
            raise ValueError("Private answer map drifted.")
    identities = [_normalized_stem_identity(q["prompt"]) for q in previous + candidates]
    if len(set(identities)) != 10:
        raise ValueError("Cross-bank stem reuse.")
    blocked_fingerprints = set(request["blockedStemFingerprints"])
    numeric_detail = []
    for slot in range(3):
        proof = numeric[slot]
        question = candidates[slot]
        proof.content(question)
        source = adapted["questions"][slot]["task"]
        selected = select_novel_task(
            slot, source, existing_prompts=existing,
            blocked_fingerprints=tuple(request["blockedStemFingerprints"]),
            fingerprint_version=request["stemFingerprintVersion"])
        matches = [(a, b) for a in OPERANDS
                   for b in (OPERANDS if slot == 0 else BOUNDARIES)
                   if flat_task(slot, {"family": FAMILIES[slot], "a": a, "b": b}) == selected]
        if len(matches) != 1:
            raise ValueError("Numeric variant has no unique operand provenance.")
        a, b = matches[0]
        if question["expectedAnswer"] != independent_key(slot, a, b):
            raise ValueError("Independent numeric key disagrees.")
        if _stem_fingerprint(question["prompt"], version=1) in blocked_fingerprints:
            raise ValueError("Numeric variant reused a blocked fingerprint.")
        numeric_detail.append({"slot": slot, "family": FAMILIES[slot],
                               "model_operands_preserved": selected == source,
                               "selected_operands": [a, b],
                               "independent_key": independent_key(slot, a, b)})
    english_detail = []
    for slot in (3, 4):
        proof = english[slot]
        question = candidates[slot]
        proof.content(question)
        selected = json.loads(proof.task_json)
        expected = compile_english(selected, ordinal=slot)
        if any(question[key] != expected[key] for key in FIELDS):
            raise ValueError("English code-owned learner content drifted.")
        if proof.novelty_exhausted or _normalized_stem_identity(question["prompt"]) in set(
                request["_agreementVariantIdentities"]):
            raise ValueError("English bank variant was reused or exhausted.")
        english_detail.append({"slot": slot, "model_task_preserved":
                               json.loads(proof.source_task_json) == selected,
                               "selected_task": selected})
    for slot, question in enumerate(candidates):
        if (len(question["choices"]) != 4 or len(set(question["choices"])) != 4
                or question["choices"].count(question["expectedAnswer"]) != 1
                or set(question["choiceExplanations"]) != set(question["choices"])
                or any(not text.strip() for text in question["choiceExplanations"].values())
                or LABEL_REFERENCE.search(question["explanation"])
                or any(LABEL_REFERENCE.search(text)
                       for text in question["choiceExplanations"].values())):
            raise ValueError(f"Choice or feedback defect at slot {slot}.")
        for order in itertools.permutations(question["choices"]):
            if order.count(question["expectedAnswer"]) != 1 or set(order) != set(
                    question["choiceExplanations"]):
                raise ValueError("Choice shuffle changed key/feedback mapping.")
    return {"status": "offline_candidate_audit_passed_but_verified_refill_failed",
            "plan_sha256": PLAN_SHA, "partial_capture_sha256": CAPTURE_SHA,
            "worksheet_sha256": WORKSHEET_SHA,
            "author_rows": len(adapted["questions"]),
            "compiler_rejections": failures, "sanitized_candidates": len(candidates),
            "numeric": numeric_detail, "english": english_detail,
            "all_ten_stems_distinct": True,
            "candidate_choice_pair_checks": 5 * 6,
            "candidate_choice_permutations_checked": 5 * 24,
            "candidate_feedback_keys_complete": True,
            "verified_returned_questions": 0,
            "qualification": "FAIL_reviewer_read_timeout"}


if __name__ == "__main__":
    output = audit()
    path = HERE / "candidate-audit.json"
    with path.open("x", encoding="utf-8") as result:
        json.dump(output, result, indent=2, ensure_ascii=False)
        result.write("\n")
    print(json.dumps({key: value for key, value in output.items()
                      if key not in {"numeric", "english"}}, indent=2))
