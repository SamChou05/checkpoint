"""Five-call Opus 5 JSON-prompted audit diagnostic; no account activation."""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from unittest.mock import patch

from botocore.config import Config

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MODEL = "us.anthropic.claude-opus-5"
PLAN, CAPTURE = HERE / "plan.json", HERE / "capture.json"


def load(name, relative):
    path = HERE.parent / relative
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# Reuse already verified bounded credentials, metadata filtering and source checks.
safe = load("opus5_safe_worker", "authored-feedback-worker-20260922/worker_pipeline_probe.py")
controls = load("opus5_control_source", "authored-feedback-combined-controls-20260922/combined_probe.py")
audit, author, native = controls.audit, controls.author, controls.native
LIMITS = {"maximum_calls": 5, "items_per_call": [5, 5, 5, 5, 4], "planned_items": 24,
          "connect_timeout_seconds": 3, "read_timeout_seconds": 100, "sdk_total_max_attempts": 1,
          "max_tokens": 16000, "thinking": "adaptive", "effort": "high", "sampling": "omitted"}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=True,
                                    allow_nan=False, separators=(",", ":")).encode()).hexdigest()


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value, *, exclusive=False):
    encoded = json.dumps(value, ensure_ascii=True, allow_nan=False, indent=2) + "\n"
    if exclusive:
        with path.open("x") as stream:
            stream.write(encoded)
    else:
        temporary = path.with_suffix(".partial")
        temporary.write_text(encoded)
        temporary.replace(path)


def require(condition, message):
    if not condition:
        raise controls.IntegrityError(message)


def build_plan():
    original, expectations = controls.source_cases()
    scopes = [{key: value for key, value in controls.data(call["provider_request"]["messages"][0]["content"][0]["text"]).items()
               if key != "items"} for call in original["calls"]]
    require(all(scope == scopes[0] for scope in scopes), "Original scopes differ.")
    scope = controls.runtime_scope(scopes[0])
    calls = []
    for start in range(0, 24, 5):
        cases = original["cases"][start:start + 5]
        originals = [author.freeze_learner_payload(case["learner_item"]) for case in cases]
        count = len(cases)
        declaration = native.native_output_config(native.AuthoredFeedbackReviewContract(count))["textFormat"]["structure"]["jsonSchema"]
        prompt = audit.build_user_prompt(originals, scope, assignments=[{} for _ in cases], history=[])
        system = (controls.verification.FULL_FEEDBACK_AUDIT_SYSTEM_PROMPT
                  + "\n\nReturn only one JSON object matching the following schema. No Markdown or surrounding text.\n"
                  + "<output_json_schema>\n" + declaration["schema"] + "\n</output_json_schema>")
        request = {"modelId": MODEL, "system": [{"text": system}],
                   "messages": [{"role": "user", "content": [{"text": prompt}]}],
                   "inferenceConfig": {"maxTokens": 16000},
                   "additionalModelRequestFields": {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}}}
        calls.append({"sequence": len(calls), "case_ids": [case["case_id"] for case in cases],
                      "source_indices": list(range(start, start + count)), "count": count,
                      "request": request, "request_sha256": digest(request), "local_schema": declaration,
                      "learner_hashes": [case["learner_content_sha256"] for case in cases]})
    evidence = {controls.SOURCE, controls.EXPECTATIONS,
                HERE.parent / "authored-feedback-20260922/KNOWN_CONTROLS_REVIEW.md"}
    expectation_file = json.loads(controls.EXPECTATIONS.read_text())
    evidence.update(ROOT / name for name in expectation_file["source_files"])
    paths = [HERE / name for name in ("opus5_probe.py", "test_opus5_probe.py", "PLAN.md")]
    paths.extend([Path(safe.__file__), Path(controls.__file__), *sorted(evidence)])
    return {"plan_state": "draft_unapproved", "experiment": "Fixed Opus5 final-audit-only known-control diagnostic",
            "transport": "ordinary_converse_json_prompt; no native structured-output guarantee",
            "model": MODEL, "endpoint": safe.ENDPOINT, "limits": copy.deepcopy(LIMITS),
            "cases": copy.deepcopy(original["cases"]), "field_expectations": copy.deepcopy(list(expectations.values())),
            "original_scope": scopes[0], "normalized_scope": scope,
            "scope_change": "Only exact empty skillMap [] becomes null, identically to the combined trial.",
            "calls": calls, "runtime_and_shared_helpers": safe.source_manifest(),
            "source_hashes": {str(path.resolve()): file_hash(path) for path in paths}, "dependencies": safe.dependencies(),
            "credential_limits": copy.deepcopy(safe.CREDENTIAL_LIMITS), "credential_command": list(safe.CREDENTIAL_COMMAND),
            "criteria": {"all_five_calls_end_turn_and_locally_valid_within_100s": True,
                         "correct_admission_decisions": 24, "sound_accepted": 12, "defective_rejected": 12,
                         "selected_learner_fields_exactly_original": True,
                         "difficulty": "Report 1–5; permissive gate, never a rescue for content errors.",
                         "task_answer_feedback_labels_and_144_reasons": "Separate diagnostics; independent reason audit pending."},
            "failure_policy": "One call per fixed batch, maximum five total. Continue independent batches after ordinary provider, timeout, non-end_turn or malformed-output failures; no retries or rescue. Global credential/setup, input/source/configuration/integrity or budget failure stops all dispatch. Failed or unattempted items remain in the 24-item denominator and earn zero credit. Recheck all pins before/after each dispatch and at completion.",
            "access_condition": "No agreement acceptance or account activation is authorized or implemented. Execute requires root confirmation that separately approved account access is available.",
            "commercial_review": {"source": "Root's read-only AWS offer check; no account mutation",
                "offer_id": "offer-f3u6lgbrem3zs", "public_terms": "https://aws.amazon.com/legal/bedrock/third-party-models/",
                "legal_pdf_bytes": 42878, "legal_pdf_sha256": "9959a0c298faab9e1375d42d8f1fa8894cff36ef64683441ee249d5c84def3c1",
                "standard_usd_per_million_input_tokens": 5.5, "standard_usd_per_million_output_tokens": 27.5,
                "maximum_output_tokens": 80000, "maximum_output_charge_usd": 2.20, "refund_policy": "No refunds",
                "total_charge": "Input charges are additional; timeout usage may be unavailable. This is not a hard total dollar cap."},
            "claim_limits": "Repeated known controls in original order regrouped 5+5+5+5+4. This tests this model/configuration only; it is not production qualification, fresh generation, deterministic accuracy or a causal model comparison. No author, solver, learner-bank, queue or deployment calls."}


def check_plan(plan, plan_path=None, expected_hash=None):
    require(plan == {**build_plan(), "plan_state": plan["plan_state"]}
            and plan["plan_state"] in {"draft_unapproved", "frozen"}, "Pinned source, gold, request or configuration changed.")
    if plan_path is not None:
        require(file_hash(plan_path) == expected_hash, "Frozen plan bytes changed.")


def safe_error(error, secrets):
    result = controls.safe_error(error, secrets)
    for key, value in result.items():
        if type(value) is str:
            value = re.sub(r'https?://[^\s<>"\']+', "[REDACTED_URL]", value)
            result[key] = re.sub(r'(?i)\bofferToken\s*[:=]\s*(?:"[^"]*"|[^\s,;]+)', "offerToken=[REDACTED]", value)
    return result


def assess(raw, call, plan):
    # The legacy helper name denotes a strict local decoder, not provider support.
    adapted = native.adapt_native_response(raw, native.AuthoredFeedbackReviewContract(call["count"]))
    rows = audit.validate(adapted, call["count"])
    cases = {case["case_id"]: case for case in plan["cases"]}
    expected = {row["case_id"]: row for row in plan["field_expectations"]}
    originals = [copy.deepcopy(cases[cid]["learner_item"]) for cid in call["case_ids"]]
    accepted = audit.accepted_indices(adapted, originals, difficulty_gate=lambda *_: True)
    selected = audit.select_accepted(adapted, originals, difficulty_gate=lambda *_: True)
    require(selected == [originals[index] for index in accepted], "Selected teaching differs from originals.")
    require([author.learner_content_digest(item) for item in selected]
            == [call["learner_hashes"][index] for index in accepted], "Selected learner hashes changed.")
    decisions = [{"case_id": cid, "accepted": index in accepted,
                  "expected_accept": expected[cid]["original_required_gate_decision"] == "accept",
                  "matches_gold": (index in accepted) == (expected[cid]["original_required_gate_decision"] == "accept")}
                 for index, cid in enumerate(call["case_ids"])]
    return {"locally_valid": True, "rows": rows, "decisions": decisions, "selected_originals": selected,
            "selected_originals_unchanged": True, "independent_reason_audit": "pending"}


def finish(capture):
    assessed = [row for row in capture["calls"] if row.get("assessment")]
    decisions = [item for row in assessed for item in row["assessment"]["decisions"]]
    capture["summary"] = {"planned_calls": 5, "attempted_calls": len(capture["calls"]), "locally_valid_calls": len(assessed),
                          "planned_items": 24, "assessed_items": len(decisions), "unavailable_items": 24 - len(decisions),
                          "correct_admissions": sum(item["matches_gold"] for item in decisions),
                          "sound_accepted": sum(item["accepted"] and item["expected_accept"] for item in decisions),
                          "defective_admitted": sum(item["accepted"] and not item["expected_accept"] for item in decisions),
                          "known_admission_criteria_pass": not capture.get("global_stop") and len(decisions) == 24
                          and all(item["matches_gold"] for item in decisions),
                          "reason_audit": "pending_independent_audit", "production_qualified": False}
    usages = [row.get("response", {}).get("usage", {}) for row in capture["calls"]]
    capture["summary"]["reported_token_usage"] = {
        "input_tokens": sum(usage.get("inputTokens", 0) for usage in usages),
        "output_tokens": sum(usage.get("outputTokens", 0) for usage in usages),
        "calls_without_reported_usage": sum(not usage for usage in usages),
        "missing_timeout_usage_is_not_zero": True}
    capture["status"] = "globally_aborted" if capture.get("global_stop") else "complete_pending_independent_audit"
    capture["finished_at"] = datetime.now(timezone.utc).isoformat()


def run_calls(client, plan, capture, path, *, secrets=(), clock=time.monotonic, pin_check=None):
    require(not capture.get("calls"), "No retry or resume is permitted.")
    check = pin_check or (lambda: check_plan(plan))
    for call in plan["calls"]:
        try:
            check()
            cfg = client.meta.config
            require((cfg.connect_timeout, cfg.read_timeout, cfg.retries.get("total_max_attempts")) == (3, 100, 1)
                    and client.meta.endpoint_url == safe.ENDPOINT and client.meta.region_name == "us-east-1",
                    "Unplanned SDK transport.")
            require(len(capture["calls"]) < 5, "Five-call ceiling exceeded.")
        except Exception as error:
            capture.update(global_stop="pre_dispatch_integrity", global_error=safe_error(error, secrets))
            break
        row = {"sequence": call["sequence"], "case_ids": call["case_ids"], "request": copy.deepcopy(call["request"]),
               "dispatch_attempted": True, "actual_sdk": {"connect": 3, "read": 100, "total_max_attempts": 1}}
        capture["calls"].append(row)
        save(path, capture)
        started = clock()
        try:
            response = client.converse(**copy.deepcopy(call["request"]))
            row["elapsed_seconds"] = clock() - started
            row["response"], row["reasoning_blocks_omitted"] = safe.safe_response(response)
            if response.get("stopReason") != "end_turn" or row["elapsed_seconds"] > 100:
                row["failure"] = "non_end_turn_or_elapsed_limit"
            else:
                raw = "\n".join(block["text"] for block in row["response"]["output"]["message"]["content"])
                row["assessment"] = assess(raw, call, plan)
        except Exception as error:
            row.update(failure="provider_or_output_failure", error=safe_error(error, secrets))
            if (isinstance(error, controls.IntegrityError) or controls.setup_failure(error)
                    or type(error).__name__ in {"ParamValidationError", "NoRegionError"}):
                capture["global_stop"] = "credential_setup_or_content_integrity"
        finally:
            row["elapsed_seconds"] = round(clock() - started, 6)
            if row["elapsed_seconds"] > 100 and row.get("assessment"):
                row.pop("assessment")
                row["failure"] = "elapsed_limit"
            try:
                check()
            except Exception as error:
                row.pop("assessment", None)
                row.update(failure="post_dispatch_integrity", error=safe_error(error, secrets))
                capture["global_stop"] = "post_dispatch_integrity"
            save(path, capture)
        if capture.get("global_stop"):
            break
    try:
        check()
    except Exception as error:
        capture.update(global_stop="completion_integrity", global_error=safe_error(error, secrets))
    finish(capture)
    save(path, capture)


def preflight():
    result = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", str(HERE),
                             "-p", "test_opus5_probe.py", "-q"], capture_output=True, text=True, check=False)
    require(result.returncode == 0, "Fake preflight failed: " + result.stderr)
    return {"result": "passed", "provider_calls": 0, "output": result.stderr.strip()}


def freeze(expected_draft_hash, plan_path=PLAN):
    draft = build_plan()
    require(digest(draft) == expected_draft_hash, "Reviewed draft digest changed.")
    preflight()
    require(draft == build_plan(), "Pins changed during offline preflight.")
    save(plan_path, {**draft, "plan_state": "frozen"}, exclusive=True)
    return {"plan_sha256": file_hash(plan_path), "provider_calls": 0}


def execute(expected_hash, *, agreement_confirmed=False, plan_path=PLAN, capture_path=CAPTURE):
    require(agreement_confirmed, "Root must confirm separately authorized account access; this harness cannot accept agreements.")
    require(plan_path.stat().st_size <= 8 * 1024 * 1024 and file_hash(plan_path) == expected_hash, "Plan bound/hash failed.")
    plan = safe.strict_json(plan_path.read_text())
    require(plan["plan_state"] == "frozen", "A frozen plan is required.")
    check_plan(plan, plan_path, expected_hash)
    capture = {"plan_sha256": expected_hash, "status": "setup", "calls": [], "started_at": datetime.now(timezone.utc).isoformat()}
    save(capture_path, capture, exclusive=True)
    previous, secrets = safe._CREDENTIAL_REDACTIONS, ()
    try:
        session, secrets = safe.credential_session()
        safe._CREDENTIAL_REDACTIONS = secrets
        with patch.dict(os.environ, {}, clear=True):
            client = session.client("bedrock-runtime", region_name="us-east-1", config=Config(
                connect_timeout=3, read_timeout=100, retries={"total_max_attempts": 1, "mode": "standard"}))
        run_calls(client, plan, capture, capture_path, secrets=secrets,
                  pin_check=lambda: check_plan(plan, plan_path, expected_hash))
    except BaseException as error:
        capture.update(global_stop="setup_or_interruption", global_error=safe_error(error, secrets))
        finish(capture)
        save(capture_path, capture)
        if isinstance(error, (KeyboardInterrupt, SystemExit)):
            raise
    finally:
        safe._CREDENTIAL_REDACTIONS = previous
    return {"capture_path": str(capture_path), "summary": capture["summary"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--preflight", action="store_true")
    action.add_argument("--draft", action="store_true")
    action.add_argument("--freeze", metavar="REVIEWED_DRAFT_DIGEST")
    action.add_argument("--execute", metavar="APPROVED_PLAN_SHA256")
    parser.add_argument("--agreement-confirmed", action="store_true")
    args = parser.parse_args()
    result = preflight() if args.preflight else ({"draft_digest": digest(build_plan()), "plan": build_plan()} if args.draft
             else freeze(args.freeze) if args.freeze else execute(args.execute, agreement_confirmed=args.agreement_confirmed))
    print(json.dumps(result, ensure_ascii=True, indent=2))
