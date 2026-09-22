"""Offline prepare plus explicitly approved one-shot four-call model comparison."""
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = ROOT / "backend/bedrock-question-service"
sys.path.insert(0, str(SERVICE))

import boto3  # noqa: E402
import botocore  # noqa: E402
from botocore.config import Config  # noqa: E402
from native_output_contracts import adapt_native_response, contract_metadata  # noqa: E402
import question_generation as runtime  # noqa: E402
from question_verification import COMPLETE_REVIEW_SYSTEM_PROMPT, _contains_answer_label_references  # noqa: E402

CONTRACT = "default_reviewer_v1"
MODELS = {"sonnet": "us.anthropic.claude-sonnet-4-6", "opus": "us.anthropic.claude-opus-4-6-v1"}
ENVIRONMENT = {
    "BEDROCK_STRUCTURED_OUTPUT_MODE": "native", "BEDROCK_CLAUDE_THINKING": "disabled",
    "BEDROCK_MAX_TOKENS": "6000", "BEDROCK_TEMPERATURE": "0.2",
    "BEDROCK_GUARDRAIL_IDENTIFIER": "", "BEDROCK_GUARDRAIL_VERSION": "",
    "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3", "BEDROCK_READ_TIMEOUT_SECONDS": "75",
    "MIN_PROVIDER_REMAINING_MILLISECONDS": "0",
}
PLAN = HERE / "plan.json"
CAPTURE = HERE / "capture.json"


def sha(value):
    return hashlib.sha256(value).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False).encode()


def save(path, value, *, exclusive=False):
    encoded = json.dumps(value, indent=2, ensure_ascii=False) + "\n"
    if exclusive:
        with path.open("x") as stream:
            stream.write(encoded)
    else:
        temporary = path.with_suffix(".partial")
        temporary.write_text(encoded)
        temporary.replace(path)


def sources():
    files = [Path(__file__), HERE / "prepare_packet.py", HERE / "test_verifier_model_probe.py", HERE / "PLAN.md",
             *sorted(SERVICE.glob("*.py"))]
    return {str(path.relative_to(ROOT)): sha(path.read_bytes()) for path in files}


def dependencies():
    return {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__}


def input_payload(request):
    raw = request["messages"][0]["content"][0]["text"]
    return json.loads(raw[raw.index("{"):raw.rindex("}") + 1])


def payload(packet, batch):
    selected = [case for case in packet["cases"] if case["batch"] == batch]
    items, solutions = [], []
    for case in selected:
        item, solution = copy.deepcopy(case["historical_item"]), copy.deepcopy(case["historical_independent_solution"])
        item["index"] = solution["index"] = case["local_index"]
        items.append(item)
        solutions.append(solution)
    return {"goal": {"title": "Review self-contained multiple-choice applications",
                     "contentTopics": ["Unit rates", "Sentence punctuation", "Ratios", "Percent change", "Weighted averages"],
                     "questionDirective": "Audit the complete stated task in each item using standard written American English and the stated numerical facts."},
            "skillMap": None, "sourceDocuments": [], "existingQuestions": [],
            "items": items, "independentSolutions": solutions}


def provider_request(data, model_id):
    requests = []

    class Spy:
        def converse(self, **request):
            requests.append(copy.deepcopy(request))
            return {"stopReason": "end_turn", "output": {"message": {"content": [{"text": '{"reviews":[]}'}]}}}

    with patch.dict(os.environ, ENVIRONMENT):
        runtime._generate_with_bedrock(
            {}, Spy(), MODELS["sonnet"], user_prompt="<question_review_json>\n" + json.dumps(data, ensure_ascii=False) + "\n</question_review_json>",
            system_prompt=COMPLETE_REVIEW_SYSTEM_PROMPT, call_budget=runtime.ProviderCallBudget(1), contract=CONTRACT)
    assert len(requests) == 1
    # The current production allowlist excludes Opus4.6. This evaluation uses
    # the documented native-compatible model by changing only the actual
    # baseline request modelId; it does not modify or bypass a production path.
    assert model_id in MODELS.values()
    requests[0]["modelId"] = model_id
    return requests[0]


def build_plan(*, require_review=True):
    packet_path = HERE / "controls-draft.json"
    packet = json.loads(packet_path.read_text())
    for case in packet["cases"]:
        assert sha((ROOT / case["source"]["path"]).read_bytes()) == case["source"]["sha256"]
    review_path = HERE / "independent-gold-review.json"
    review_hash = None
    if require_review:
        review = json.loads(review_path.read_text())
        assert review["approved"] is True and review["reviewed_packet_sha256"] == sha(packet_path.read_bytes())
        review_hash = sha(review_path.read_bytes())
    calls = []
    for batch, arm in [(0, "sonnet"), (0, "opus"), (1, "opus"), (1, "sonnet")]:
        request = provider_request(payload(packet, batch), MODELS[arm])
        calls.append({"sequence": len(calls), "batch": batch, "arm": arm, "provider_request": request,
                      "request_sha256": sha(canonical(request)),
                      "case_ids": [case["case_id"] for case in packet["cases"] if case["batch"] == batch]})
    for batch in [0, 1]:
        pair = [copy.deepcopy(call["provider_request"]) for call in calls if call["batch"] == batch]
        for request in pair:
            request.pop("modelId")
        assert pair[0] == pair[1]
    return {"experiment": "Matched Sonnet4.6 versus Opus4.6 final-reviewer comparison", "calls": calls,
            "packet_sha256": sha(packet_path.read_bytes()), "independent_gold_review_sha256": review_hash,
            "source_sha256": sources(), "dependencies": dependencies(), "environment": ENVIRONMENT,
            "registered_contract": contract_metadata(CONTRACT), "prospective_criteria": packet["prospective_criteria"],
            "limits": {"maximum_calls": 4, "items_per_call": 3, "connect_timeout_seconds": 3,
                       "read_timeout_seconds": 75, "sdk_total_max_attempts": 1, "maximum_output_tokens": 6000, "region": "us-east-1"},
            "sole_paired_request_delta": "modelId",
            "candidate_integration_requirement": "Current production native allowlist excludes Opus4.6. Experimental request clones the actual runtime-built Sonnet request and changes only modelId, using documented AWS native support. Any later production promotion requires an explicit tested allowlist update; this trial does not make that change.",
            "failure_policy": "Stop after first provider, non-end_turn or structural failure. Preserve all failures/unattempted denominators; no retries, replacements, warm-up or extra account actions.",
            "manual_audit": "Gold decisions and counterexamples remain evaluator-only. Audit every returned explanation; matching key/disposition is not proof of sound teaching or of a specific rejection rationale.",
            "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()}


def assess(response, call, packet):
    raw = "\n".join(block["text"] for block in response["output"]["message"]["content"] if "text" in block)
    adapted = json.loads(adapt_native_response(raw, CONTRACT))
    rows = adapted["reviews"]
    indexes = [row.get("index") for row in rows]
    if not all(type(index) is int for index in indexes) or sorted(indexes) != [0, 1, 2]:
        raise ValueError("Incomplete, unknown or duplicate reviewer indexes.")
    by_index = {row["index"]: row for row in rows}
    expected = {case["local_index"]: case for case in packet["cases"] if case["batch"] == call["batch"]}
    items = []
    for item in input_payload(call["provider_request"])["items"]:
        row, case = by_index[item["index"]], expected[item["index"]]
        valid, gold = row["valid"], case["gold"]
        result = {"case_id": case["case_id"], "valid": valid, "gold_eligible": gold["eligible"],
                  "matching_disposition": valid == gold["eligible"], "semantic_feedback_audit": "pending"}
        if valid:
            feedback = row["choiceExplanations"]
            exact_coverage = set(feedback) == set(item["choices"])
            bounded = all(isinstance(value, str) and 12 <= len(value.strip()) <= limit and len(value) <= limit
                          for value, limit in [(row["explanation"], 420), *[(value, 280) for value in feedback.values()]])
            labels = any(_contains_answer_label_references(value, item) for value in [row["explanation"], *feedback.values()])
            result.update(exact_gold_key=row["answer"] == gold["answer"], exact_feedback_coverage=exact_coverage,
                          feedback_within_bounds=bounded, answer_display_references=labels,
                          difficulty=row["difficulty"], difficulty_type_and_range=type(row["difficulty"]) is int and 1 <= row["difficulty"] <= 5)
            if not exact_coverage or not bounded or not result["difficulty_type_and_range"] or labels:
                result["local_positive_validation_pass"] = False
            else:
                result["local_positive_validation_pass"] = True
        items.append(result)
    return {"adapted_response": adapted, "items": items}


def redacted(response):
    result = copy.deepcopy(response)
    content = result.get("output", {}).get("message", {}).get("content", [])
    count = sum("reasoningContent" in block for block in content)
    if "output" in result and "message" in result["output"]:
        result["output"]["message"]["content"] = [block for block in content if "reasoningContent" not in block]
    return result, count


def run_calls(client, plan, packet, capture, path):
    for call in plan["calls"]:
        if len(capture["calls"]) >= 4:
            raise RuntimeError("Four-call ceiling reached.")
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
            row["response"], row["reasoning_content_blocks_omitted"] = redacted(response)
            if response.get("stopReason") != "end_turn":
                capture["stop_reason"] = "non_end_turn"
            else:
                try:
                    row["assessment"] = assess(response, call, packet)
                    if any(item.get("local_positive_validation_pass") is False for item in row["assessment"]["items"]):
                        row["validation_error_type"] = "LocalPositiveValidationFailure"
                        capture["stop_reason"] = "structural_failure"
                except Exception as error:
                    row["validation_error_type"] = type(error).__name__
                    capture["stop_reason"] = "structural_failure"
        finally:
            row["elapsed_seconds"] = round(time.monotonic() - started, 3)
            save(path, capture)
        print(json.dumps({key: row.get(key) for key in ["sequence", "arm", "elapsed_seconds", "provider_error_type", "validation_error_type"]}), flush=True)
        if capture.get("stop_reason"):
            break
    capture["status"] = "stopped_after_failure" if capture.get("stop_reason") else "complete_pending_manual_audit"
    capture["finished_at"] = datetime.now(timezone.utc).isoformat()
    save(path, capture)


def execute(expected_hash):
    encoded = PLAN.read_bytes()
    plan = json.loads(encoded)
    assert sha(encoded) == expected_hash and sources() == plan["source_sha256"]
    rebuilt = build_plan()
    rebuilt["source_revision"] = plan["source_revision"]
    assert rebuilt == plan
    packet = json.loads((HERE / "controls-draft.json").read_text())
    capture = {"plan_sha256": expected_hash, "calls": [], "status": "preflight", "started_at": datetime.now(timezone.utc).isoformat()}
    save(CAPTURE, capture, exclusive=True)
    credentials = json.loads(subprocess.check_output(["aws", "configure", "export-credentials", "--format", "process"], stderr=subprocess.DEVNULL))
    client = boto3.client("bedrock-runtime", region_name="us-east-1", aws_access_key_id=credentials["AccessKeyId"],
                         aws_secret_access_key=credentials["SecretAccessKey"], aws_session_token=credentials.get("SessionToken"),
                         config=Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1}))
    del credentials
    assert client.meta.config.retries["total_max_attempts"] == 1
    capture["status"] = "running"
    run_calls(client, plan, packet, capture, CAPTURE)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--prepare", action="store_true")
    action.add_argument("--execute", metavar="PLAN_SHA256")
    args = parser.parse_args()
    if args.prepare:
        save(PLAN, build_plan(), exclusive=True)
        print(json.dumps({"plan_sha256": sha(PLAN.read_bytes()), "calls": 4, "provider_calls": 0}))
    else:
        execute(args.execute)
