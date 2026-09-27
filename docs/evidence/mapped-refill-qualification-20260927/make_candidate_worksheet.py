"""Project an answer-hidden worksheet from a failed verified refill attempt."""

import hashlib
import json
import os
from pathlib import Path
import random
import sys
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "backend/bedrock-question-service"))

import native_output_contracts as native  # noqa: E402
import question_generation as generation  # noqa: E402
from agreement_task_constructor import (  # noqa: E402
    blocked_fingerprint_variant_identities, prepare_mapped_agreement_rows,
)
from question_quality import _sanitize_questions  # noqa: E402

PLAN_SHA = "5681a27a407aebfad3f3b8e2ec6422859a912c28b7a77c7b972492aa0c5d44e2"
CAPTURE_SHA = "f27a207c6039f54cd7ad3e640184e9cbbcb5b42940e23b683c08999635496ec5"
PRIOR_CAPTURE = ROOT / "docs/evidence/mapped-quant-families-qualification-20260927/capture.json"
PRIOR_SHA = "f9e81f34f19e4829b49587c3919d77bae2595784064e063631d3515b61e009fa"


def load_checked(path, digest):
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != digest:
        raise ValueError(f"Source digest changed: {path.name}")
    return json.loads(raw)


def project():
    plan = load_checked(HERE / "plan.json", PLAN_SHA)
    capture = load_checked(HERE / "capture.json", CAPTURE_SHA)
    prior = load_checked(PRIOR_CAPTURE, PRIOR_SHA)
    if (capture["attempted_calls"] != 3 or len(capture["calls"]) != 3
            or [call.get("response") is not None for call in capture["calls"]] != [True, True, False]
            or capture["calls"][2].get("error", {}).get("type") != "ReadTimeoutError"
            or capture["returned"]):
        raise ValueError("This is not the locked failed reviewer attempt.")
    request = plan["bank"]["refill_request"]
    raw_text = capture["calls"][0]["response"]["output"]["message"]["content"][0]["text"]
    raw_author = json.loads(raw_text)
    with patch.dict(os.environ, plan["environment"], clear=True):
        assignments = generation._mapped_fixed_slot_assignments(
            request, "constructed_quantitative", "array")
        if assignments is None:
            raise ValueError("Refill route drifted.")
        contract = generation._mapped_author_contract(request, assignments, True, True)
        adapted = json.loads(native.adapt_native_response(json.dumps(raw_author), contract))
        prior_prompts = tuple(dict.fromkeys(
            request["existingPrompts"] + request["reportedPrompts"]
            + [entry["prompt"] for entry in request["existingQuestionCoverage"]
               if entry.get("prompt")]))
        blocked_variants = tuple(sorted(
            set(request["_agreementVariantIdentities"])
            | blocked_fingerprint_variant_identities(
                request["blockedStemFingerprints"], request["stemFingerprintVersion"])))
        rows, numeric, english, failures = prepare_mapped_agreement_rows(
            adapted, contract, existing_prompts=prior_prompts,
            blocked_variant_identities=blocked_variants,
            blocked_stem_fingerprints=tuple(request["blockedStemFingerprints"]),
            stem_fingerprint_version=request["stemFingerprintVersion"])
        compiled_output, agreement_output = {}, {}
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        candidates = _sanitize_questions(
            rows, request, metrics, preserve_authored_explanation=True,
            compiled_candidates=numeric, compiled_output=compiled_output,
            agreement_candidates=english, agreement_output=agreement_output,
            prefer_compiled_within_assignment=True)
    if failures or len(candidates) != 5 or len(numeric) != 3 or len(english) != 2:
        raise ValueError("Compiler or sanitizer failed before answer-hidden projection.")
    previous = prior["jobs"][0]["returned"]
    combined = [("previous_verified", index, row) for index, row in enumerate(previous)]
    combined += [("refill_unverified_candidate", index, row)
                 for index, row in enumerate(candidates)]
    rng = random.Random(int(PLAN_SHA[:16], 16))
    rng.shuffle(combined)
    worksheet = {
        "status": "candidate_only_reviewer_timeout_no_verified_refill_return",
        "instructions": "For each item, select the best choice if one exists; rate self-containment and difficulty 1-5. Across all ten items, flag near-duplicate pairs and explain the repeated work. Item origin, key, model rating, and proof are hidden. The refill candidates were not verified because the reviewer provider call timed out.",
        "items": [],
    }
    private = {"plan_sha256": PLAN_SHA, "partial_capture_sha256": CAPTURE_SHA,
               "mapping": {}, "compiler_failures": failures,
               "prior_prompt_count": len(prior_prompts),
               "blocked_agreement_identities": len(blocked_variants)}
    for origin, index, row in combined:
        identifier = f"R{rng.getrandbits(40):010x}"
        if identifier in private["mapping"]:
            raise ValueError("Opaque ID collision.")
        choices = list(row["choices"])
        rng.shuffle(choices)
        worksheet["items"].append({"id": identifier, "prompt": row["prompt"],
                                   "choices": dict(zip("ABCD", choices, strict=True))})
        private["mapping"][identifier] = {
            "origin": origin, "original_slot": index,
            "correct_display_choice": "ABCD"[choices.index(row["expectedAnswer"])],
            "question": row,
        }
    worksheet_path = HERE / "candidate-worksheet.json"
    private_path = HERE / "candidate-private.json"
    if worksheet_path.exists() or private_path.exists():
        raise ValueError("Worksheet or private map already exists.")
    with worksheet_path.open("x", encoding="utf-8") as output:
        json.dump(worksheet, output, indent=2, ensure_ascii=False)
        output.write("\n")
    with private_path.open("x", encoding="utf-8") as output:
        json.dump(private, output, indent=2, ensure_ascii=False)
        output.write("\n")
    os.chmod(private_path, 0o600)
    return {"worksheet_path": str(worksheet_path),
            "worksheet_sha256": hashlib.sha256(worksheet_path.read_bytes()).hexdigest(),
            "items": len(worksheet["items"]), "previous_items": 5,
            "unverified_refill_candidates": 5,
            "private_map_path": str(private_path)}


if __name__ == "__main__":
    print(json.dumps(project(), indent=2))
