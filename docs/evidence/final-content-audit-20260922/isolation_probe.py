"""Six-call singleton diagnostic; original prompt and exact learner content retained."""

import argparse
import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import time

import adaptive_only_probe as source_probe

original = source_probe.original
HERE = Path(__file__).resolve().parent
PLAN = HERE / "isolation-plan.json"
CAPTURE = HERE / "isolation-capture.json"


def build_plan():
    source = json.loads(source_probe.PLAN.read_text())
    assert source == source_probe.build_plan()
    prior = json.loads(source_probe.CAPTURE.read_text())
    assert prior["plan_sha256"] == original.sha(source_probe.PLAN.read_bytes())
    source_call = source["calls"][2]
    assert source_call["batch"] == 2 and source_call["arm"] == "adaptive"
    source_request = source_call["provider_request"]
    data = original.user_data(source_request)
    cases = [copy.deepcopy(next(case for case in source["cases"] if case["case_id"] == case_id))
             for case_id in source_call["case_ids"]]
    assert len(cases) == len(data["items"]) == 6
    calls = []
    for sequence, case in enumerate(cases):
        assert data["items"][case["slot"]] == case["learner_item"]
        request = copy.deepcopy(source_request)
        singleton_data = copy.deepcopy(data)
        singleton_data["items"] = {"0": copy.deepcopy(case["learner_item"])}
        request["messages"][0]["content"][0]["text"] = (
            "<final_content_audit_json>\n" + json.dumps(singleton_data, ensure_ascii=False)
            + "\n</final_content_audit_json>"
        )
        request["outputConfig"] = original.contract.output_config(1)
        comparison = copy.deepcopy(request)
        comparison["messages"] = source_request["messages"]
        comparison["outputConfig"] = source_request["outputConfig"]
        assert comparison == source_request
        calls.append({"sequence": sequence, "batch": sequence, "arm": "adaptive_singleton",
                      "source_batch": 2, "source_slot": case["slot"], "source_sequence": source_call["sequence"],
                      "case_ids": [case["case_id"]], "provider_request": request,
                      "request_sha256": original.sha(original.canonical(request))})
    assert sum(case["gold"]["required_gate_decision"] == "accept" for case in cases) == 3
    pins = {str((HERE / name).relative_to(original.ROOT)): original.sha((HERE / name).read_bytes())
            for name in ("isolation_probe.py", "test_isolation_probe.py", "ISOLATION_PLAN.md", "ISOLATION_PROPOSAL.md")}
    return {"experiment": "Original short final auditor: six singleton supplemental diagnostics",
            "source_plan_sha256": original.sha(source_probe.PLAN.read_bytes()),
            "source_failed_capture_sha256": original.sha(source_probe.CAPTURE.read_bytes()),
            "source_request_sha256": source_call["request_sha256"],
            "source_sha256": pins, "frozen_shared_source_sha256": source["source_sha256"],
            "frozen_original_source_sha256": source["frozen_original_source_sha256"],
            "dependencies": source["dependencies"], "calls": calls, "cases": cases,
            "native_contract": original.contract.metadata(1),
            "limits": {"maximum_calls": 6, "items_per_call": 1, "planned_items": 6, "region": "us-east-1",
                       "sdk_total_max_attempts": 1, "connect_timeout_seconds": 3, "read_timeout_seconds": 75,
                       "adaptive_shared_max_tokens": 16000},
            "prospective_criteria": {"exact_dispositions": 6, "sound_accepted": 3, "defective_rejected": 3,
                                     "uncertainty_is_failure": True,
                                     "all_reasons_factually_sound_and_item_specific": True,
                                     "all_accepted_content_exactly_unchanged": True,
                                     "all_calls_structurally_valid_end_turn_within_bounds": True,
                                     "no_after_output_gold_changes": True},
            "failure_policy": source["failure_policy"],
            "only_request_delta": "Retain one exact learner payload at ID0 and use count-one native contract; remove five neighbors. Original short system prompt, scope, model and settings unchanged.",
            "claim_limits": "Six repeated diagnostics, no new holdout or concurrent baseline. Neighboring context, workload and schema cardinality change together; no unique causal attribution. Six per-item calls do not qualify production throughput. No production changes or reinterpretation of prior failures."}


def assess(response, call, plan):
    raw = "\n".join(block["text"] for block in response["output"]["message"]["content"] if "text" in block)
    rows = original.contract.validate(raw, 1)
    original.jsonschema.Draft202012Validator(original.contract.schema(1)).validate({"audits": rows})
    data = original.user_data(call["provider_request"])
    assert list(data["items"]) == ["0"] and len(call["case_ids"]) == 1
    payload = data["items"]["0"]
    case = next(case for case in plan["cases"] if case["case_id"] == call["case_ids"][0])
    assert payload == case["learner_item"]
    originals = [copy.deepcopy(payload)]
    before = copy.deepcopy(originals)
    accepted = original.contract.select_accepted(raw, originals)
    row = rows["0"]
    assert originals == before
    assert accepted == ([payload] if row["verdict"] == "accepted" else [])
    gold = {"accept": "accepted", "reject": "rejected"}[case["gold"]["required_gate_decision"]]
    item = {"case_id": case["case_id"], "slot": "0", "source_slot": case["slot"],
            "verdict": row["verdict"], "gold_verdict": gold, "matching_disposition": row["verdict"] == gold,
            "reason": row["reason"], "reason_manual_audit": "pending",
            "learner_content_sha256": case["learner_content_sha256"]}
    if accepted:
        item["accepted_content_exactly_unchanged"] = original.contract.content_digest(accepted[0]) == case["learner_content_sha256"]
        assert item["accepted_content_exactly_unchanged"]
    return {"audits": rows, "items": [item], "originals_unchanged": originals == before,
            "accepted_content_hashes": [original.contract.content_digest(payload) for payload in accepted],
            "actual_reason_before_verdict_rows": int(list(row) == ["reason", "verdict"])}


def run_calls(client, plan, capture, path):
    if len(plan["calls"]) != 6 or capture["calls"]:
        raise ValueError("Requires exactly six planned calls and a fresh empty capture.")
    for call in plan["calls"]:
        if len(capture["calls"]) >= 6:
            raise RuntimeError("Six-call maximum reached.")
        row = {"sequence": call["sequence"], "batch": call["batch"], "arm": call["arm"],
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
                    row["assessment"] = assess(response, call, plan)
                except Exception as error:
                    row["validation_error_type"] = type(error).__name__
                    capture["stop_reason"] = "structural_failure"
        finally:
            row["elapsed_seconds"] = round(time.monotonic() - started, 3)
            original.save(path, capture)
        print(json.dumps({key: row.get(key) for key in ("sequence", "arm", "elapsed_seconds", "provider_error_type", "validation_error_type")}), flush=True)
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
        print(json.dumps({"plan_sha256": original.sha(PLAN.read_bytes()), "maximum_calls": 6, "provider_calls": 0}))
    else:
        execute(args.execute)
