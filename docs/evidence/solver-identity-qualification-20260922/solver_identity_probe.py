"""Two-call structural qualification of actual count-bound solver transport."""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import importlib.metadata
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
SOURCE = HERE.parent / "choice-quality-release-20260922"
SERVICE = Path("/tmp/checkpoint-solver-identity-integration/backend/bedrock-question-service")
sys.path.insert(0, str(SERVICE))
import complete_question_solution as solver  # noqa: E402
import native_output_contracts as native  # noqa: E402

PLAN = HERE / "plan.json"
CAPTURE = HERE / "capture.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, allow_nan=False).encode()).hexdigest()


def save(path, value, *, exclusive=False):
    text = json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if exclusive:
        with path.open("x") as stream:
            stream.write(text)
    else:
        partial = path.with_suffix(".partial")
        partial.write_text(text)
        partial.replace(path)


def user_data(request):
    return json.loads(request["messages"][0]["content"][0]["text"].split("\n", 1)[1].rsplit("\n", 1)[0])


def build_plan():
    previous = json.loads((SOURCE / "adaptive-plan.json").read_text())
    capture = json.loads((SOURCE / "adaptive-capture.json").read_text())
    assert capture["plan_byte_sha256"] == sha(SOURCE / "adaptive-plan.json")
    packet = json.loads((SOURCE / "controls-draft.json").read_text())
    review = json.loads((SOURCE / "independent-gold-review.json").read_text())
    assert review["approved"] is True and review["reviewed_packet_sha256"] == sha(SOURCE / "controls-draft.json")
    assert previous["controls"] == packet["controls"]
    jobs = []
    for old in previous["jobs"][:2]:
        assert digest(old["request"]) == old["request_sha256"]
        assert len(old["items"]) == len(old["case_ids"]) == 5
        job = copy.deepcopy(old)
        system = old["runtime_system_prompt"]
        assert native.native_prompt(system, "complete_choice_solver_v3") == old["request"]["system"][0]["text"]
        assert native.native_output_config("complete_choice_solver_v3") == old["request"]["outputConfig"]
        job["request"]["system"] = [{"text": native.native_prompt(system, native.SolverSlotContract(5))}]
        job["request"]["outputConfig"] = native.native_output_config(native.SolverSlotContract(5))
        comparison = copy.deepcopy(job["request"])
        comparison["system"], comparison["outputConfig"] = old["request"]["system"], old["request"]["outputConfig"]
        assert comparison == old["request"]
        data = user_data(job["request"])
        generated_system, generated_user = solver.build_solver_prompt(job["items"], {key: value for key, value in data.items() if key != "items"},
                                                                      audit_choice_pairs=True, choice_slots=True)
        assert generated_system == system and generated_user == old["request"]["messages"][0]["content"][0]["text"]
        assert [item["index"] for item in data["items"]] == list(range(5))
        for item in data["items"]:
            assert set(item["choices"]) == set(solver.CHOICE_SLOTS)
            for pair, endpoints in item["choicePairs"].items():
                assert endpoints == {"leftChoice": item["choices"][pair[0]], "rightChoice": item["choices"][pair[1]]}
        job["source_request_sha256"] = old["request_sha256"]
        job["request_sha256"] = digest(job["request"])
        jobs.append(job)
    ids = [case_id for job in jobs for case_id in job["case_ids"]]
    controls = [next(case for case in previous["controls"] if case["id"] == case_id) for case_id in ids]
    sources = {str(path): sha(path) for path in sorted(SERVICE.glob("*.py"))}
    assert Path(native.__file__).resolve().is_relative_to(SERVICE.resolve())
    assert Path(solver.__file__).resolve().is_relative_to(SERVICE.resolve())
    return {"experiment": "Solver count-map structural qualification; semantics scored separately",
            "source_sha256": sources,
            "new_source_sha256": {name: sha(HERE / name) for name in ("PLAN.md", "solver_identity_probe.py", "test_solver_identity_probe.py")},
            "historical_sha256": {name: sha(SOURCE / name) for name in ("adaptive-plan.json", "adaptive-capture.json", "controls-draft.json", "independent-gold-review.json")},
            "dependencies": {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__,
                             "jsonschema": importlib.metadata.version("jsonschema")},
            "jobs": jobs, "controls": controls, "native_contract": native.contract_metadata(native.SolverSlotContract(5)),
            "settings": {"maximum_calls": 2, "items_per_call": 5, "region": "us-east-1", "sdk_total_max_attempts": 1,
                         "connect_timeout_seconds": 3, "read_timeout_seconds": 75, "max_shared_tokens": 16000,
                         "thinking": "adaptive", "effort": "high", "temperature": "omitted"},
            "structural_criteria": {"valid_calls": 2, "trusted_identities": 10, "choice_slots": 40, "pair_slots": 60,
                                    "exact_input_and_decoded_content": True, "all_end_turn_within_75_seconds": True},
            "semantic_reporting": {"unchanged_gold": True, "choice_denominator": 40, "pair_denominator": 60,
                                   "item_denominator": 10, "all_reasons_require_independent_audit": True,
                                   "semantic_errors_do_not_count_as_structural_errors": True},
            "stop_policy": "Stop after first provider/non-end_turn/native/local/identity/binding/elapsed-limit failure; retain all denominators. Exactly two calls maximum; no retries, warmups, rescue or replacements. Semantic errors stay reported separately.",
            "claim_limits": "Repeated diagnostics and structural qualification only. No semantic determinism, broad accuracy, causal effect or worker-yield claim. Prior failures unchanged; no production semantic prompt, policy or model settings changed."}


def expected_veto(case):
    if len(case["supportedChoices"]) > 1:
        return "solver_multiple_supported"
    if not case["supportedChoices"]:
        return "solver_zero_supported"
    if case["supportedChoices"] != [case["expectedAnswer"]]:
        return "answer_disagreement"
    if case["equivalentPairs"]:
        return "solver_equivalent_choices"
    return None


def assess(raw, job, plan):
    adapted = native.adapt_native_response(raw, native.SolverSlotContract(5))
    received = json.loads(raw)
    jsonschema.Draft202012Validator(json.loads(job["request"]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])).validate(received)
    restored = json.loads(adapted)
    expected = {"solutions": [{"index": index, **received["solutions"][str(index)]} for index in range(5)]}
    assert restored == expected
    records = solver.validate_batch(adapted, job["items"], audit_choice_pairs=True, choice_slots=True)
    data = user_data(job["request"])
    cases = {case["id"]: case for case in plan["controls"]}
    rows = []
    for item, slots, record, case_id in zip(job["items"], data["items"], records, job["case_ids"], strict=True):
        assert record["index"] == item["index"] == slots["index"]
        offered = slots["choices"]
        source_row = received["solutions"][str(item["index"])]
        for judgment in record["choices"]:
            slot = next(key for key, text in offered.items() if text == judgment["choice"])
            assert {key: judgment[key] for key in ("reason", "judgment")} == source_row["choices"][slot]
        for pair in record["choicePairs"]:
            slot = next(key for key, endpoints in slots["choicePairs"].items()
                        if frozenset(endpoints.values()) == frozenset(pair[field] for field in ("leftChoice", "rightChoice")))
            # Existing local validation orders the two exact endpoints by the
            # trusted offered list. That orientation change is not new content.
            assert {key: pair[key] for key in ("reason", "relation")} == source_row["choicePairs"][slot]
        case = cases[case_id]
        equivalent = {frozenset(pair) for pair in case["equivalentPairs"]}
        choices = [{**value, "expected_judgment": "supported" if value["choice"] in case["supportedChoices"] else "refuted"}
                   for value in record["choices"]]
        for choice in choices:
            choice["judgment_agrees"] = choice["judgment"] == choice["expected_judgment"]
        pairs = [{**value, "expected_relation": "equivalent" if frozenset((value["leftChoice"], value["rightChoice"])) in equivalent else "distinct"}
                 for value in record["choicePairs"]]
        for pair in pairs:
            pair["relation_agrees"] = pair["relation"] == pair["expected_relation"]
        veto = solver.rejection_reason(record, {**item, "expectedAnswer": case["expectedAnswer"]}, audit_choice_pairs=True)
        rows.append({"case_id": case_id, "choices": choices, "pairs": pairs, "veto": veto,
                     "expected_veto": expected_veto(case), "expected_eligible": case["expectedEligible"], "eligible": veto is None,
                     "all_gold_agrees": veto == expected_veto(case) and all(value["judgment_agrees"] for value in choices) and all(value["relation_agrees"] for value in pairs)})
    return {"structural_valid": True, "trusted_identities": len(records), "choice_slots": sum(len(row["choices"]) for row in records),
            "pair_slots": sum(len(row["choicePairs"]) for row in records), "exact_bindings_and_decoded_content": True,
            "choice_reason_before_judgment_rows": sum(list(value) == ["reason", "judgment"] for row in received["solutions"].values() for value in row["choices"].values()),
            "pair_reason_before_relation_rows": sum(list(value) == ["reason", "relation"] for row in received["solutions"].values() for value in row["choicePairs"].values()),
            "decoded": restored, "semantic_rows": rows}


def run_calls(client, plan, capture, path):
    if len(plan["jobs"]) != 2 or capture["calls"]:
        raise ValueError("Exactly two jobs and a fresh empty capture are required.")
    for job in plan["jobs"]:
        row = {"call_index": job["call_index"], "request": copy.deepcopy(job["request"]), "request_sha256": job["request_sha256"], "dispatch_attempted": True}
        capture["calls"].append(row)
        save(path, capture)
        started = time.monotonic()
        try:
            response = client.converse(**copy.deepcopy(job["request"]))
        except Exception as error:
            row["provider_error_type"] = type(error).__name__
            capture["stop_reason"] = "provider_failure"
        else:
            blocks = response.get("output", {}).get("message", {}).get("content", [])
            row.update({"raw": "\n".join(block["text"] for block in blocks if "text" in block),
                        "usage": response.get("usage"), "stop_reason": response.get("stopReason"),
                        "reasoning_content_block_count": sum("reasoningContent" in block for block in blocks)})
            if row["stop_reason"] != "end_turn":
                capture["stop_reason"] = "non_end_turn"
            elif time.monotonic() - started > 75:
                capture["stop_reason"] = "provider_elapsed_limit"
            else:
                try:
                    row["assessment"] = assess(row["raw"], job, plan)
                except Exception as error:
                    row["validation_error_type"] = type(error).__name__
                    capture["stop_reason"] = "structural_failure"
        finally:
            row["elapsed_seconds"] = round(time.monotonic() - started, 3)
            save(path, capture)
        print(json.dumps({key: row.get(key) for key in ("call_index", "elapsed_seconds", "provider_error_type", "validation_error_type")}), flush=True)
        if capture.get("stop_reason"):
            break
    capture["status"] = "stopped_after_failure" if capture.get("stop_reason") else "complete_pending_independent_audit"
    capture["completed_at"] = datetime.now(timezone.utc).isoformat()
    save(path, capture)


def execute(expected_hash):
    plan = json.loads(PLAN.read_text())
    assert sha(PLAN) == expected_hash and build_plan() == plan
    capture = {"plan_sha256": expected_hash, "calls": [], "status": "preflight", "started_at": datetime.now(timezone.utc).isoformat()}
    save(CAPTURE, capture, exclusive=True)
    credentials = json.loads(subprocess.check_output(["aws", "configure", "export-credentials", "--format", "process"], stderr=subprocess.DEVNULL))
    client = boto3.client("bedrock-runtime", region_name="us-east-1", aws_access_key_id=credentials["AccessKeyId"],
                         aws_secret_access_key=credentials["SecretAccessKey"], aws_session_token=credentials.get("SessionToken"),
                         config=Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1}))
    del credentials
    assert (client.meta.config.connect_timeout, client.meta.config.read_timeout, client.meta.config.retries["total_max_attempts"]) == (3, 75, 1)
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
        print(json.dumps({"plan_sha256": sha(PLAN), "maximum_calls": 2, "provider_calls": 0}))
    else:
        execute(args.execute)
