"""Replay the captured author output offline; never call a provider."""

import copy
import hashlib
import itertools
import json
import os
from pathlib import Path
import sys
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = ROOT / "backend/bedrock-question-service"
sys.path.insert(0, str(SERVICE))

from agreement_task_constructor import prepare_mapped_agreement_rows  # noqa: E402
from answer_position_references import contains_answer_label_references  # noqa: E402
import native_output_contracts as native  # noqa: E402
import question_bank  # noqa: E402
from question_bank_common import _normalized_stem_identity  # noqa: E402
import question_generation as generation  # noqa: E402
from question_quality import _sanitize_questions  # noqa: E402

PLAN_SHA = "abfb96c1dbb533d4b2da2882a7c5f222a7464c5441335cb97f575eb6795b02cd"
CAPTURE_SHA = "9eeb2e11045d02f60911eba29911da995cb3c8469a545a2737cc819874b32ca4"
INDEPENDENT_KEYS = ("17/8", "7", "9", "are; is", "are; is")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True, allow_nan=False)


def checked(path, expected):
    raw = path.read_bytes()
    if sha(raw) != expected:
        raise ValueError(f"Historical evidence drifted: {path.name}")
    return json.loads(raw)


def audit():
    plan = checked(HERE / "plan.json", PLAN_SHA)
    capture = checked(HERE / "capture.json", CAPTURE_SHA)
    if sha((HERE / "probe.py").read_bytes()) != plan["harness_sha256"]:
        raise ValueError("Historical probe changed")
    for name, expected in plan["source_hashes"].items():
        if sha((ROOT / name).read_bytes()) != expected:
            raise ValueError(f"Service source changed: {name}")
    prior = ROOT / "docs/evidence/mapped-refill-qualification-20260927"
    prior_plan = checked(prior / "plan.json", plan["prior_plan_sha256"])
    checked(prior / "capture.json", plan["prior_capture_sha256"])
    seed = json.loads((ROOT / "docs/evidence/mapped-quant-families-qualification-20260927/capture.json").read_text())
    previous = seed["jobs"][0]["returned"]
    request = copy.deepcopy(prior_plan["bank"]["refill_request"])
    stored = [{"questionJSON": {"S": json.dumps(row)}} for row in previous]
    request["_mappedQuantitativeVariantIdentities"] = (
        question_bank._mapped_quantitative_variant_history(stored)
    )
    if sha(canonical(request).encode()) != plan["request_sha256"]:
        raise ValueError("Historical request changed")
    with patch.dict(os.environ, prior_plan["environment"], clear=True):
        assignments = generation._mapped_fixed_slot_assignments(
            request, "constructed_quantitative", "array"
        )
        contract = generation._mapped_author_contract(request, assignments, True, True)
        schema = native.native_output_config(contract)["textFormat"]["structure"]["jsonSchema"]["schema"]
        if contract.name != plan["author_contract"] or sha(schema.encode()) != plan["schema_sha256"]:
            raise ValueError("Historical author contract changed")
        if (capture["status"] != "completed" or capture["sts_calls"] != 1
                or capture["converse_calls"] != 1 or not capture["within_deadline"]
                or capture["plan_sha256"] != PLAN_SHA):
            raise ValueError("Capture is not a single successful bounded call")
        response = capture["author_response"]
        if response["stopReason"] != "end_turn":
            raise ValueError("Provider did not finish")
        content = response["output"]["message"]["content"]
        if len(content) != 1:
            raise ValueError("Response cardinality changed")
        authored = json.loads(native.adapt_native_response(content[0]["text"], contract))
        rows, numeric, english, failures = prepare_mapped_agreement_rows(
            authored, contract,
            existing_prompts=tuple(request["existingPrompts"]),
            blocked_variant_identities=tuple(request["_agreementVariantIdentities"]),
            blocked_quantitative_variant_identities=tuple(request["_mappedQuantitativeVariantIdentities"]),
            blocked_stem_fingerprints=tuple(request["blockedStemFingerprints"]),
            stem_fingerprint_version=request["stemFingerprintVersion"],
        )
        compiled_output, agreement_output = {}, {}
        candidates = _sanitize_questions(
            rows, request,
            {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0},
            preserve_authored_explanation=True,
            compiled_candidates=numeric, compiled_output=compiled_output,
            agreement_candidates=english, agreement_output=agreement_output,
            prefer_compiled_within_assignment=True,
        )
    if (failures or len(rows) != 5 or len(candidates) != 5
            or set(numeric) != {0, 1, 2} or set(english) != {3, 4}
            or len(compiled_output) != 3 or len(agreement_output) != 2):
        raise ValueError("Compilation or sanitizer rejected a requested slot")
    for slot, proof in {**numeric, **english}.items():
        proof.content(candidates[slot])
    identities = [_normalized_stem_identity(q["prompt"]) for q in previous + candidates]
    if len(set(identities)) != 10:
        raise ValueError("An exact stem was reused")
    for slot, row in enumerate(candidates):
        choices = row["choices"]
        if (len(choices) != 4 or len(set(choices)) != 4
                or choices.count(row["expectedAnswer"]) != 1
                or row["expectedAnswer"] != INDEPENDENT_KEYS[slot]
                or set(row["choiceExplanations"]) != set(choices)
                or contains_answer_label_references(row["explanation"], row)
                or any(contains_answer_label_references(text, row)
                       for text in row["choiceExplanations"].values())):
            raise ValueError(f"Answer or feedback failed at slot {slot}")
        for order in itertools.permutations(choices):
            if order.count(row["expectedAnswer"]) != 1 or set(order) != set(row["choiceExplanations"]):
                raise ValueError(f"Choice shuffle failed at slot {slot}")
    return {
        "status": "author_only_offline_audit_passed",
        "source_commit": plan["source_commit"],
        "plan_sha256": PLAN_SHA,
        "capture_sha256": CAPTURE_SHA,
        "converse_calls": 1,
        "elapsed_seconds": capture["elapsed_seconds"],
        "author_rows": len(authored["questions"]),
        "sanitized_candidates": len(candidates),
        "numeric_proofs": len(numeric),
        "english_proofs": len(english),
        "compiler_failures": failures,
        "all_ten_stems_distinct": True,
        "candidate_choice_pairs_checked": 30,
        "choice_permutations_checked": 120,
        "independent_keys": list(INDEPENDENT_KEYS),
        "verified_worker_returns": 0,
    }


if __name__ == "__main__":
    print(json.dumps(audit(), indent=2))
