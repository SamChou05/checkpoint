"""Inactive six-call audit-only comparison. Dispatch requires exact frozen hash."""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

import boto3
import botocore
from botocore.config import Config
import jsonschema

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
import candidate_contract as contract  # noqa: E402

PLAN = HERE / "plan.json"
CAPTURE = HERE / "capture.json"
MODEL = "us.anthropic.claude-sonnet-4-6"
SCOPE = {"goal": {"title": "Educational questions using stated facts and rules",
                  "questionDirective": "Use each question's exact stated facts and requested result."},
         "skillMap": [], "sourceDocuments": []}


def sha(value):
    return hashlib.sha256(value).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, allow_nan=False).encode()


def save(path, value, *, exclusive=False):
    text = json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if exclusive:
        with path.open("x") as stream:
            stream.write(text)
    else:
        temporary = path.with_suffix(".partial")
        temporary.write_text(text)
        temporary.replace(path)


def sources():
    names = ("final_audit_probe.py", "test_final_audit_probe.py", "candidate_contract.py",
             "auditor-prompt.txt", "PROPOSAL.md", "SCOPE_AMENDMENT.md", "PLAN.md")
    return {str((HERE / name).relative_to(ROOT)): sha((HERE / name).read_bytes()) for name in names}


def dependencies():
    return {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__,
            "jsonschema": __import__("importlib.metadata", fromlist=["version"]).version("jsonschema")}


def user_data(request):
    text = request["messages"][0]["content"][0]["text"]
    return json.loads(text[len("<final_content_audit_json>\n"):-len("\n</final_content_audit_json>")])


def selected_cases():
    packets = [json.loads((HERE / name).read_text()) for name in ("controls-gold-draft.json", "supplemental-controls-draft.json")]
    result = []
    for batch in (0, 1, 2):
        selected = sorted((case for packet in packets for case in packet["cases"] if case["batch"] == batch),
                          key=lambda case: sha(canonical(case["learner_item"])))
        assert len(selected) == 6
        assert sum(case["gold"]["required_gate_decision"] == "accept" for case in selected) == 3
        for index, original in enumerate(selected):
            case = copy.deepcopy(original)
            case["slot"] = str(index)
            case["learner_content_sha256"] = contract.content_digest(case["learner_item"])
            result.append(case)
    return result


def build_plan():
    inputs, historical = [], {}
    for packet_name, review_name in (("controls-gold-draft.json", "independent-gold-review.json"),
                                     ("supplemental-controls-draft.json", "independent-supplemental-gold-review.json")):
        packet_path, review_path = HERE / packet_name, HERE / review_name
        packet, review = json.loads(packet_path.read_text()), json.loads(review_path.read_text())
        assert review["approved"] is True and review["reviewed_packet_sha256"] == sha(packet_path.read_bytes())
        for path, expected in packet["source_files"].items():
            assert sha((ROOT / path).read_bytes()) == expected
        historical.update(packet["source_files"])
        inputs.extend((packet_path, review_path))
    cases = selected_cases()
    calls = []
    for batch, arm in ((0, "disabled"), (0, "adaptive"), (1, "adaptive"), (1, "disabled"),
                       (2, "disabled"), (2, "adaptive")):
        selected = [case for case in cases if case["batch"] == batch]
        data = {**copy.deepcopy(SCOPE), "items": {case["slot"]: case["learner_item"] for case in selected}}
        request = {
            "modelId": MODEL,
            "system": [{"text": (HERE / "auditor-prompt.txt").read_text().removesuffix("\n")}],
            "messages": [{"role": "user", "content": [{"text": "<final_content_audit_json>\n"
                         + json.dumps(data, ensure_ascii=False) + "\n</final_content_audit_json>"}]}],
            "inferenceConfig": {"maxTokens": 6000, "temperature": 0.2} if arm == "disabled" else {"maxTokens": 16000},
            "additionalModelRequestFields": {"thinking": {"type": "disabled"}} if arm == "disabled" else {
                "thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}},
            "outputConfig": contract.output_config(6),
        }
        calls.append({"sequence": len(calls), "batch": batch, "arm": arm, "provider_request": request,
                      "request_sha256": sha(canonical(request)), "case_ids": [case["case_id"] for case in selected]})
    for batch in (0, 1, 2):
        pair = [copy.deepcopy(call["provider_request"]) for call in calls if call["batch"] == batch]
        for request in pair:
            del request["inferenceConfig"], request["additionalModelRequestFields"]
        assert pair[0] == pair[1]
    return {
        "experiment": "Read-only final learner-content gate: disabled versus adaptive-high Sonnet",
        "calls": calls, "cases": cases, "source_sha256": sources(), "dependencies": dependencies(),
        "input_sha256": {str(path.relative_to(ROOT)): sha(path.read_bytes()) for path in inputs},
        "historical_source_sha256": historical, "native_contract": contract.metadata(6),
        "limits": {"maximum_calls": 6, "items_per_call": 6, "items_per_arm": 18, "region": "us-east-1",
                   "sdk_total_max_attempts": 1, "connect_timeout_seconds": 3, "read_timeout_seconds": 75,
                   "disabled_max_tokens": 6000, "adaptive_shared_max_tokens": 16000},
        "paired_delta": "Reasoning configuration and required compatible sampling/output budget only; exact system, user, order and schema shared.",
        "prospective_criteria": {"exact_dispositions_per_arm": 18, "sound_accepted_per_arm": 9,
                                 "defective_rejected_per_arm": 9, "uncertainty_is_failure": True,
                                 "all_reasons_factually_sound_and_item_specific": True,
                                 "all_accepted_content_exactly_unchanged": True,
                                 "all_calls_structurally_valid_end_turn_within_bounds": True,
                                 "no_after_output_gold_changes": True},
        "failure_policy": "Stop all remaining calls after first provider, non-end_turn, native schema or strict local format failure. Preserve failed and unattempted denominators; no retries, warmups, replacements or rescue. Semantic failures remain in the planned comparison.",
        "claim_limits": "Nine paired diagnostic families; familiar capture defects and evaluator-authored repairs, three previously undispatched families with synthetic full feedback, and a supplemental batch covering grammatical ambiguity, equivalent wrong choices, and representation-sensitive distinctions. No full-worker yield or universal accuracy claim; a fourth stage requires separate runtime budget and end-to-end qualification.",
    }


def assess(response, call, plan):
    raw = "\n".join(block["text"] for block in response["output"]["message"]["content"] if "text" in block)
    rows = contract.validate(raw, 6)
    jsonschema.Draft202012Validator(contract.schema(6)).validate({"audits": rows})
    originals = list(user_data(call["provider_request"])["items"].values())
    before = copy.deepcopy(originals)
    accepted = contract.select_accepted(raw, originals)
    assert originals == before
    expected = [copy.deepcopy(originals[i]) for i in range(6) if rows[str(i)]["verdict"] == "accepted"]
    assert accepted == expected
    selected = [case for case in plan["cases"] if case["batch"] == call["batch"]]
    results = []
    for case in selected:
        row = rows[case["slot"]]
        gold = {"accept": "accepted", "reject": "rejected"}[case["gold"]["required_gate_decision"]]
        result = {"case_id": case["case_id"], "slot": case["slot"], "verdict": row["verdict"],
                  "gold_verdict": gold, "matching_disposition": row["verdict"] == gold,
                  "reason": row["reason"], "reason_manual_audit": "pending",
                  "learner_content_sha256": case["learner_content_sha256"]}
        if row["verdict"] == "accepted":
            result["accepted_content_exactly_unchanged"] = contract.content_digest(originals[int(case["slot"])]) == case["learner_content_sha256"]
            assert result["accepted_content_exactly_unchanged"]
        results.append(result)
    return {"audits": rows, "items": results, "accepted_content_hashes": [contract.content_digest(item) for item in accepted],
            "originals_unchanged": originals == before,
            "actual_reason_before_verdict_rows": sum(list(row) == ["reason", "verdict"] for row in rows.values())}


def safe_response(response):
    result = copy.deepcopy(response)
    blocks = result.get("output", {}).get("message", {}).get("content", [])
    count = sum("reasoningContent" in block for block in blocks)
    if "output" in result and "message" in result["output"]:
        result["output"]["message"]["content"] = [block for block in blocks if "reasoningContent" not in block]
    return result, count


def run_calls(client, plan, capture, path):
    for call in plan["calls"]:
        if len(capture["calls"]) >= 6:
            raise RuntimeError("Six-call maximum reached.")
        row = {"sequence": call["sequence"], "batch": call["batch"], "arm": call["arm"],
               "request": copy.deepcopy(call["provider_request"]), "dispatch_attempted": True,
               "started_at": datetime.now(timezone.utc).isoformat()}
        capture["calls"].append(row)
        save(path, capture)
        started = time.monotonic()
        try:
            response = client.converse(**copy.deepcopy(call["provider_request"]))
        except Exception as error:
            row["provider_error_type"] = type(error).__name__
            capture["stop_reason"] = "transport_failure"
        else:
            row["response"], row["reasoning_blocks_omitted"] = safe_response(response)
            if response.get("stopReason") != "end_turn":
                capture["stop_reason"] = "non_end_turn"
            else:
                try:
                    row["assessment"] = assess(response, call, plan)
                except Exception as error:
                    row["validation_error_type"] = type(error).__name__
                    capture["stop_reason"] = "structural_failure"
        finally:
            row["elapsed_seconds"] = round(time.monotonic() - started, 3)
            save(path, capture)
        print(json.dumps({key: row.get(key) for key in ("sequence", "arm", "elapsed_seconds", "provider_error_type", "validation_error_type")}), flush=True)
        if capture.get("stop_reason"):
            break
    capture["status"] = "stopped_after_failure" if capture.get("stop_reason") else "complete_pending_manual_audit"
    capture["finished_at"] = datetime.now(timezone.utc).isoformat()
    save(path, capture)


def execute(expected_hash):
    raw = PLAN.read_bytes()
    plan = json.loads(raw)
    assert sha(raw) == expected_hash and build_plan() == plan
    capture = {"plan_sha256": expected_hash, "calls": [], "status": "preflight",
               "started_at": datetime.now(timezone.utc).isoformat()}
    save(CAPTURE, capture, exclusive=True)
    credentials = json.loads(subprocess.check_output(["aws", "configure", "export-credentials", "--format", "process"], stderr=subprocess.DEVNULL))
    client = boto3.client("bedrock-runtime", region_name="us-east-1", aws_access_key_id=credentials["AccessKeyId"],
                         aws_secret_access_key=credentials["SecretAccessKey"], aws_session_token=credentials.get("SessionToken"),
                         config=Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1}))
    del credentials
    assert client.meta.config.retries["total_max_attempts"] == 1
    assert client.meta.config.read_timeout == 75 and client.meta.config.connect_timeout == 3
    capture["status"] = "running"
    run_calls(client, plan, capture, CAPTURE)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--prepare", action="store_true")
    action.add_argument("--execute", metavar="PLAN_SHA256")
    args = parser.parse_args()
    if args.prepare:
        save(PLAN, build_plan(), exclusive=True)
        print(json.dumps({"plan_sha256": sha(PLAN.read_bytes()), "maximum_calls": 6, "provider_calls": 0}))
    else:
        execute(args.execute)
