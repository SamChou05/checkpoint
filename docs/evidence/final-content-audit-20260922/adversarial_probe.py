"""Inactive four-call counterexample-auditor trial with independent new controls."""

import argparse
import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess

import adaptive_only_probe as source_probe

original = source_probe.original
HERE = Path(__file__).resolve().parent
PLAN = HERE / "adversarial-plan.json"
CAPTURE = HERE / "adversarial-capture.json"
PACKET = HERE / "adversarial-holdout-controls-draft.json"
REVIEW = HERE / "independent-adversarial-holdout-review.json"


def build_plan():
    source = json.loads(source_probe.PLAN.read_text())
    assert source == source_probe.build_plan()
    packet, review = json.loads(PACKET.read_text()), json.loads(REVIEW.read_text())
    assert review["approved"] is True and review["reviewed_packet_sha256"] == original.sha(PACKET.read_bytes())
    for path, digest in packet["source_files"].items():
        assert original.sha((original.ROOT / path).read_bytes()) == digest
    new_cases = sorted(packet["cases"], key=lambda case: original.sha(original.canonical(case["learner_item"])))
    assert len(new_cases) == 6 and all(case["batch"] == 3 for case in new_cases)
    assert sum(case["gold"]["required_gate_decision"] == "accept" for case in new_cases) == 3
    cases = copy.deepcopy(source["cases"])
    for index, case in enumerate(new_cases):
        case = copy.deepcopy(case)
        case["slot"] = str(index)
        case["learner_content_sha256"] = original.contract.content_digest(case["learner_item"])
        cases.append(case)
    prompt = (HERE / "auditor-adversarial-prompt-proposal.txt").read_text().removesuffix("\n")
    calls = []
    for source_call in source["calls"]:
        call = copy.deepcopy(source_call)
        call["exposure"] = "repeated original diagnostic batch"
        call["provider_request"]["system"] = [{"text": prompt}]
        call["request_sha256"] = original.sha(original.canonical(call["provider_request"]))
        check = copy.deepcopy(call["provider_request"])
        check["system"] = source_call["provider_request"]["system"]
        assert check == source_call["provider_request"]
        calls.append(call)
    request = copy.deepcopy(calls[0]["provider_request"])
    data = {**copy.deepcopy(original.SCOPE), "items": {case["slot"]: case["learner_item"] for case in cases if case["batch"] == 3}}
    request["messages"][0]["content"][0]["text"] = "<final_content_audit_json>\n" + json.dumps(data, ensure_ascii=False) + "\n</final_content_audit_json>"
    calls.append({"sequence": 3, "source_sequence": None, "batch": 3, "arm": "adaptive",
                  "exposure": "new independent situations, not paired repairs; not previously dispatched",
                  "provider_request": request, "request_sha256": original.sha(original.canonical(request)),
                  "case_ids": [case["case_id"] for case in cases if case["batch"] == 3]})
    pins = {str((HERE / name).relative_to(original.ROOT)): original.sha((HERE / name).read_bytes())
            for name in ("adversarial_probe.py", "test_adversarial_probe.py", "ADVERSARIAL_PLAN.md", "auditor-adversarial-prompt-proposal.txt")}
    criteria = copy.deepcopy(source["prospective_criteria"])
    criteria.update(exact_dispositions_per_arm=24, sound_accepted_per_arm=12, defective_rejected_per_arm=12)
    return {"experiment": "General adversarial final-content audit: known regressions plus independent new cases",
            "source_sonnet_plan_sha256": original.sha(source_probe.PLAN.read_bytes()),
            "source_failed_sonnet_capture_sha256": original.sha(source_probe.CAPTURE.read_bytes()),
            "source_sha256": pins, "source_helper_sha256": source["source_sha256"],
            "source_original_sha256": source["frozen_original_source_sha256"],
            "input_sha256": {str(path.relative_to(original.ROOT)): original.sha(path.read_bytes()) for path in (PACKET, REVIEW)},
            "dependencies": source["dependencies"], "cases": cases, "calls": calls,
            "native_contract": source["native_contract"], "prospective_criteria": criteria,
            "limits": {**copy.deepcopy(source["limits"]), "maximum_calls": 4, "planned_items": 24},
            "failure_policy": source["failure_policy"],
            "request_isolation": "First3 request objects differ from frozen Sonnet adaptive-only requests solely in the approved system prompt. Fourth request uses same scope/prompt/model/schema/settings with six new independently designed learner payloads; gold/provenance hidden.",
            "claim_limits": "All earlier failures preserved. First18 cases are known repeated diagnostics; new6 are independent different situations rather than paired repairs, with prospective gold. Single candidate run, not a contemporaneous randomized causal effect or broad accuracy estimate. A pass still requires fresh worker yield/content qualification before release."}


def run_calls(client, plan, capture, path):
    # Reject an expanded or resumed plan before any provider request. With four
    # immutable entries, the original no-retry loop can dispatch at most four.
    if len(plan["calls"]) != 4 or capture.get("calls"):
        raise ValueError("Exactly four planned calls and a fresh capture are required.")
    original.run_calls(client, plan, capture, path)


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
        print(json.dumps({"plan_sha256": original.sha(PLAN.read_bytes()), "maximum_calls": 4, "provider_calls": 0}))
    else:
        execute(args.execute)
