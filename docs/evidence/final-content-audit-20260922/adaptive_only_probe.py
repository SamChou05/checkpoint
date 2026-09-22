"""Separate adaptive-only qualification; the original failed comparison is immutable."""

import argparse
import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import time

import final_audit_probe as original

HERE = Path(__file__).resolve().parent
PLAN = HERE / "adaptive-only-plan.json"
CAPTURE = HERE / "adaptive-only-capture.json"


def build_plan():
    source = json.loads(original.PLAN.read_text())
    prior = json.loads(original.CAPTURE.read_text())
    assert source == original.build_plan()
    assert original.sha(original.PLAN.read_bytes()) == prior["plan_sha256"]
    assert prior["status"] == "stopped_after_failure" and len(prior["calls"]) == 4
    calls = []
    for source_call in source["calls"]:
        if source_call["arm"] != "adaptive":
            continue
        call = copy.deepcopy(source_call)
        call["source_sequence"] = source_call["sequence"]
        call["sequence"] = len(calls)
        call["exposure"] = "repeated diagnostic batch" if call["batch"] < 2 else "previously unattempted supplemental batch"
        assert call["provider_request"] == source_call["provider_request"]
        calls.append(call)
    assert len(calls) == 3 and [call["source_sequence"] for call in calls] == [1, 2, 5]
    pins = {str((HERE / name).relative_to(original.ROOT)): original.sha((HERE / name).read_bytes())
            for name in ("adaptive_only_probe.py", "test_adaptive_only_probe.py", "ADAPTIVE_ONLY_PLAN.md")}
    return {"experiment": "Separate adaptive-only final-content auditor qualification",
            "source_plan_sha256": original.sha(original.PLAN.read_bytes()),
            "source_failed_capture_sha256": original.sha(original.CAPTURE.read_bytes()),
            "source_sha256": pins, "frozen_original_source_sha256": source["source_sha256"],
            "dependencies": source["dependencies"], "calls": calls, "cases": source["cases"],
            "native_contract": source["native_contract"],
            "prospective_criteria": copy.deepcopy(source["prospective_criteria"]),
            "limits": {"maximum_calls": 3, "items_per_call": 6, "planned_items": 18, "region": "us-east-1",
                       "connect_timeout_seconds": 3, "read_timeout_seconds": 75,
                       "sdk_total_max_attempts": 1, "shared_max_tokens": 16000},
            "failure_policy": "Stop after the first provider, non-end_turn, native-schema or strict-local-format failure. No retries, warmups, replacements, rescue or additional calls; remaining denominators stay unattempted.",
            "claim_limits": "Two repeated diagnostic batches and one previously unattempted supplemental batch. Requests, prompt, schema, gold and criteria unchanged. This does not replace or relabel the failed six-call comparison, estimate a population accuracy rate or causal thinking effect, qualify the earlier failed globally adaptive pipeline, or authorize production promotion."}


def run_calls(client, plan, capture, path):
    for call in plan["calls"]:
        if len(capture["calls"]) >= 3:
            raise RuntimeError("Three-call maximum reached.")
        row = {"sequence": call["sequence"], "source_sequence": call["source_sequence"],
               "batch": call["batch"], "arm": "adaptive", "exposure": call["exposure"],
               "request": copy.deepcopy(call["provider_request"]), "dispatch_attempted": True,
               "started_at": datetime.now(timezone.utc).isoformat()}
        capture["calls"].append(row)
        original.save(path, capture)
        started = time.monotonic()
        try:
            response = client.converse(**copy.deepcopy(call["provider_request"]))
        except Exception as error:
            row["provider_error_type"] = type(error).__name__
            capture["stop_reason"] = "transport_failure"
        else:
            row["response"], row["reasoning_blocks_omitted"] = original.safe_response(response)
            if response.get("stopReason") != "end_turn":
                capture["stop_reason"] = "non_end_turn"
            else:
                try:
                    row["assessment"] = original.assess(response, call, plan)
                except Exception as error:
                    row["validation_error_type"] = type(error).__name__
                    capture["stop_reason"] = "structural_failure"
        finally:
            row["elapsed_seconds"] = round(time.monotonic() - started, 3)
            original.save(path, capture)
        print(json.dumps({key: row.get(key) for key in ("sequence", "batch", "elapsed_seconds", "provider_error_type", "validation_error_type")}), flush=True)
        if capture.get("stop_reason"):
            break
    capture["status"] = "stopped_after_failure" if capture.get("stop_reason") else "complete_pending_manual_audit"
    capture["finished_at"] = datetime.now(timezone.utc).isoformat()
    original.save(path, capture)


def execute(expected_hash):
    raw = PLAN.read_bytes()
    plan = json.loads(raw)
    assert original.sha(raw) == expected_hash and build_plan() == plan
    capture = {"plan_sha256": expected_hash, "calls": [], "status": "preflight",
               "started_at": datetime.now(timezone.utc).isoformat()}
    original.save(CAPTURE, capture, exclusive=True)
    credentials = json.loads(subprocess.check_output(["aws", "configure", "export-credentials", "--format", "process"], stderr=subprocess.DEVNULL))
    client = original.boto3.client("bedrock-runtime", region_name="us-east-1", aws_access_key_id=credentials["AccessKeyId"],
                                  aws_secret_access_key=credentials["SecretAccessKey"], aws_session_token=credentials.get("SessionToken"),
                                  config=original.Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1}))
    del credentials
    assert (client.meta.config.connect_timeout, client.meta.config.read_timeout,
            client.meta.config.retries["total_max_attempts"]) == (3, 75, 1)
    capture["status"] = "running"
    run_calls(client, plan, capture, CAPTURE)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--prepare", action="store_true")
    action.add_argument("--execute", metavar="PLAN_SHA256")
    args = parser.parse_args()
    if args.prepare:
        original.save(PLAN, build_plan(), exclusive=True)
        print(json.dumps({"plan_sha256": original.sha(PLAN.read_bytes()), "maximum_calls": 3, "provider_calls": 0}))
    else:
        execute(args.execute)
