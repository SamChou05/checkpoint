"""Audit the immutable one-call v9 capture without any network operation."""

import hashlib
import json
import os
from pathlib import Path
from unittest.mock import patch

from jsonschema import Draft202012Validator

import probe
from question_quality import _sanitize_questions

HERE = Path(__file__).resolve().parent
PLAN_SHA256 = "fdaf5ba1558c578aec177ba289f894577d65ddc57de1e86177fa5550d7d2d9ab"
CAPTURE_SHA256 = "17575d5a62b1fde235c3d43c7c9bc1d9e40385466e30b973fde1ca9cf1bbc9aa"
HARNESS_SHA256 = "85fd733d8bac1212fc50751d0a8cedbf381044e7562ac30db6bb413bf3369608"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replay():
    if (sha(HERE / "capture.json") != CAPTURE_SHA256
            or sha(HERE / "plan.json") != PLAN_SHA256
            or sha(HERE / "probe.py") != HARNESS_SHA256):
        raise ValueError("Frozen live source or capture changed")
    plan, wire, contract, request = probe.checked(PLAN_SHA256)
    capture = probe.safe.strict_json((HERE / "capture.json").read_text())
    if (capture["plan_sha256"] != PLAN_SHA256 or capture["status"] != "failed"
            or capture["error"]["type"] != "TypeError"
            or capture["sts_calls"] != 1 or capture["converse_calls"] != 1
            or capture["within_deadline"] is not True):
        raise ValueError("One-shot failure classification changed")
    response = capture["author_response"]
    if response["stopReason"] != "end_turn" or len(response["output"]["message"]["content"]) != 1:
        raise ValueError("Native author did not end with one visible result")
    raw = probe.safe.strict_json(response["output"]["message"]["content"][0]["text"])
    schema = json.loads(wire["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
    Draft202012Validator(schema).validate(raw)
    if set(raw) != {"questions"} or set(raw["questions"]) != {str(i) for i in range(5)}:
        raise ValueError("Native response lacks the exact five original keys")
    families = {str(i): raw["questions"][str(i)]["family"] for i in range(3)}
    if families["0"] != "fraction_product_complement" or families["2"] != "bounded_solution_count":
        raise ValueError("The two new live-selected families changed")
    with patch.dict(os.environ, plan["environment"], clear=True):
        adapted = probe.safe.strict_json(probe.native.adapt_native_response(
            response["output"]["message"]["content"][0]["text"], contract))
        if type(adapted["questions"]) is not list or len(adapted["questions"]) != 5:
            raise ValueError("The adapter did not normalize to five rows")
        rows, numeric, english, failures = probe.prepare_mapped_agreement_rows(adapted, contract)
        compiled_output, agreement_output = {}, {}
        sanitized = _sanitize_questions(
            rows, request,
            {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0},
            preserve_authored_explanation=True,
            compiled_candidates=numeric, compiled_output=compiled_output,
            agreement_candidates=english, agreement_output=agreement_output,
            prefer_compiled_within_assignment=True,
        )
    if (failures or len(rows) != 5 or len(numeric) != 3 or len(english) != 2
            or len(sanitized) != 5 or len(compiled_output) != 3 or len(agreement_output) != 2):
        raise ValueError("Compiler or sanitizer rejected a source slot")
    for ordinal, question in enumerate(sanitized):
        choices = question["choices"]
        if (len(choices) != 4 or len(set(choices)) != 4
                or choices.count(question["expectedAnswer"]) != 1
                or set(question["choiceExplanations"]) != set(choices)):
            raise ValueError(f"Candidate choice/key/feedback failure at {ordinal}")
    try:
        adapted["questions"]["0"]
    except TypeError:
        bookkeeping_error_reproduced = True
    else:
        raise ValueError("Captured harness TypeError did not reproduce")
    return {
        "classification": "native_author_and_offline_compiler_pass_probe_bookkeeping_failed",
        "plan_sha256": PLAN_SHA256, "capture_sha256": CAPTURE_SHA256,
        "harness_sha256": HARNESS_SHA256,
        "provider_status": "end_turn", "live_sts_calls": 1, "live_converse_calls": 1,
        "live_elapsed_seconds": capture["elapsed_seconds"],
        "native_schema_valid": True,
        "live_selected_numeric_families": families,
        "new_family_slot_0_selected": True, "new_family_slot_2_selected": True,
        "adapter_rows": len(adapted["questions"]),
        "compiled_rows": len(rows), "numeric_proofs": len(numeric),
        "english_proofs": len(english), "compiler_failures": failures,
        "sanitized_rows": len(sanitized), "candidate_key_count": 5,
        "all_four_choices_literal_distinct_and_feedback_keyed": True,
        "bookkeeping_typeerror_reproduced": bookkeeping_error_reproduced,
        "downstream_solver_or_reviewer_called": False,
        "candidate_questions": sanitized,
    }


if __name__ == "__main__":
    result = replay()
    path = HERE / "offline-replay.json"
    with path.open("x") as stream:
        json.dump(result, stream, indent=2, ensure_ascii=False)
        stream.write("\n")
    print(json.dumps({key: value for key, value in result.items() if key != "candidate_questions"}, indent=2))
