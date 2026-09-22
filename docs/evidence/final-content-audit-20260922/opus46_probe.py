"""Separate three-call Opus4.6 qualification; only modelId changes in requests."""

import argparse
import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess

import adaptive_only_probe as shared

original = shared.original
HERE = Path(__file__).resolve().parent
PLAN = HERE / "opus46-plan.json"
CAPTURE = HERE / "opus46-capture.json"
MODEL = "us.anthropic.claude-opus-4-6-v1"


def build_plan():
    source = json.loads(shared.PLAN.read_text())
    prior = json.loads(shared.CAPTURE.read_text())
    assert source == shared.build_plan()
    assert original.sha(shared.PLAN.read_bytes()) == prior["plan_sha256"]
    assert len(prior["calls"]) == 3
    assert sum(item["matching_disposition"] for row in prior["calls"] for item in row["assessment"]["items"]) == 17
    preflight = json.loads((HERE / "opus46-read-only-preflight.json").read_text())
    availability = preflight["get_foundation_model_availability"]
    assert preflight["get_inference_profile"]["status"] == "ACTIVE"
    assert availability["agreementAvailability"]["status"] == "AVAILABLE"
    assert availability["authorizationStatus"] == "AUTHORIZED"
    calls = []
    for source_call in source["calls"]:
        call = copy.deepcopy(source_call)
        call["exposure"] = "reused diagnostic controls; no new held-out items"
        call["provider_request"]["modelId"] = MODEL
        call["request_sha256"] = original.sha(original.canonical(call["provider_request"]))
        comparison = copy.deepcopy(call["provider_request"])
        comparison["modelId"] = source_call["provider_request"]["modelId"]
        assert comparison == source_call["provider_request"]
        calls.append(call)
    pins = {str((HERE / name).relative_to(original.ROOT)): original.sha((HERE / name).read_bytes())
            for name in ("opus46_probe.py", "test_opus46_probe.py", "OPUS46_PLAN.md", "opus46-read-only-preflight.json")}
    return {"experiment": "Opus4.6 adaptive-high final-content auditor qualification",
            "source_sonnet_plan_sha256": original.sha(shared.PLAN.read_bytes()),
            "source_failed_sonnet_capture_sha256": original.sha(shared.CAPTURE.read_bytes()),
            "source_sha256": pins, "frozen_shared_source_sha256": source["source_sha256"],
            "frozen_original_source_sha256": source["frozen_original_source_sha256"],
            "dependencies": source["dependencies"], "calls": calls, "cases": source["cases"],
            "native_contract": source["native_contract"], "limits": source["limits"],
            "prospective_criteria": source["prospective_criteria"], "failure_policy": source["failure_policy"],
            "only_request_delta": "modelId: us.anthropic.claude-sonnet-4-6 -> us.anthropic.claude-opus-4-6-v1. Exact high effort, adaptive mode, max16000, no temperature, prompt, schema, content and order retained.",
            "claim_limits": "All18 controls are reused diagnostics. Three single candidate calls, not a randomized contemporaneous causal comparison or population estimate. Earlier Sonnet and six-call trials remain failed. No global worker thinking change or production routing/default promotion is authorized."}


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
    shared.run_calls(client, plan, capture, CAPTURE)


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
