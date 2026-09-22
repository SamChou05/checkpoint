"""Inactive paired prompt trial; prepare offline and dispatch only by frozen hash."""
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PREVIOUS = HERE.parent / "verifier-model-comparison-20260922"
sys.path.insert(0, str(HERE / "archive"))

import boto3  # noqa: E402
import botocore  # noqa: E402
from botocore.config import Config  # noqa: E402
from native_output_contracts_snapshot import adapt_native_response, contract_metadata  # noqa: E402
from answer_reference_snapshot import _contains_answer_label_references  # noqa: E402

CONTRACT = "default_reviewer_v1"
MODEL = "us.anthropic.claude-sonnet-4-6"
PLAN = HERE / "plan.json"
CAPTURE = HERE / "capture.json"


def sha(value):
    return hashlib.sha256(value).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False).encode()


def save(path, value, *, exclusive=False):
    text = json.dumps(value, indent=2, ensure_ascii=False) + "\n"
    if exclusive:
        with path.open("x") as stream:
            stream.write(text)
    else:
        temporary = path.with_suffix(".partial")
        temporary.write_text(text)
        temporary.replace(path)


def sources():
    paths = [Path(__file__), HERE / "test_refutation_probe.py", HERE / "PLAN.md", HERE / "archive-provenance.json",
             HERE / "candidate-paragraph.txt", HERE / "baseline-paragraph.txt", *sorted((HERE / "archive").glob("*.py"))]
    return {str(path.relative_to(ROOT)): sha(path.read_bytes()) for path in paths}


def dependencies():
    return {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__}


def user_data(request):
    text = request["messages"][0]["content"][0]["text"]
    return json.loads(text[len("<question_review_json>\n"):-len("\n</question_review_json>")])


def replace_paragraph(system):
    before = (HERE / "baseline-paragraph.txt").read_text().removesuffix("\n")
    after = (HERE / "candidate-paragraph.txt").read_text().removesuffix("\n")
    if system.count(before) != 1:
        raise ValueError("Original instruction span must occur exactly once.")
    return system.replace(before, after, 1)


def cases():
    familiar_packet = json.loads((PREVIOUS / "controls-draft.json").read_text())
    fresh_packet = json.loads((HERE / "holdout-controls-draft.json").read_text())
    result = []
    for index, case in enumerate(familiar_packet["cases"]):
        item, solution = copy.deepcopy(case["historical_item"]), copy.deepcopy(case["historical_independent_solution"])
        item["index"] = solution["index"] = index
        result.append({"batch": 0, "index": index, "case_id": case["case_id"], "item": item,
                       "solution": solution, "gold": case["gold"], "provenance": "Actual historical question and model solver output; only top-level index reassigned."})
    for index, case in enumerate(fresh_packet["cases"]):
        item, solution = copy.deepcopy(case["item"]), copy.deepcopy(case["synthetic_independent_solution"])
        item["index"] = solution["index"] = index
        result.append({"batch": 1, "index": index, "case_id": case["case_id"], "item": item,
                       "solution": solution, "gold": case["gold"],
                       "provenance": "Prospectively designed control with evaluator-authored fallible solver claims; not provider output."})
    for batch in (0, 1):
        selected = [case for case in result if case["batch"] == batch]
        assert len(selected) == 6 and sum(case["gold"]["eligible"] for case in selected) == 4
        for case in selected:
            assert set(case["item"]["choices"]) == {row["choice"] for row in case["solution"]["choices"]}
            assert len(case["item"]["choices"]) == 4 and len(set(case["item"]["choices"])) == 4
            assert sum(row["judgment"] == "supported" for row in case["solution"]["choices"]) == 1
    return result


def build_plan(*, require_review=True):
    original_plan_path = PREVIOUS / "plan.json"
    original = json.loads(original_plan_path.read_text())
    baseline_template = original["calls"][0]["provider_request"]
    assert baseline_template["modelId"] == MODEL
    assert baseline_template["inferenceConfig"] == {"maxTokens": 6000, "temperature": 0.2}
    assert baseline_template["additionalModelRequestFields"] == {"thinking": {"type": "disabled"}}
    assert contract_metadata(CONTRACT) == original["registered_contract"]
    selected_cases = cases()
    review_hash = None
    if require_review:
        review_path = HERE / "independent-holdout-review.json"
        review = json.loads(review_path.read_text())
        assert review["approved"] is True
        assert review["reviewed_packet_sha256"] == sha((HERE / "holdout-controls-draft.json").read_bytes())
        review_hash = sha(review_path.read_bytes())
    calls = []
    for batch, arm in [(0, "baseline"), (0, "candidate"), (1, "candidate"), (1, "baseline")]:
        request = copy.deepcopy(baseline_template)
        selected = [case for case in selected_cases if case["batch"] == batch]
        data = user_data(baseline_template)
        if batch == 1:
            data["goal"] = {"title": "Review self-contained tasks under explicitly supplied rules",
                            "questionDirective": "Use each item's exact stated facts and requested result.",
                            "contentTopics": list(dict.fromkeys(case["item"].get("topic", "") for case in selected))}
        data["items"] = [case["item"] for case in selected]
        data["independentSolutions"] = [case["solution"] for case in selected]
        request["messages"][0]["content"][0]["text"] = "<question_review_json>\n" + json.dumps(data, ensure_ascii=False) + "\n</question_review_json>"
        if arm == "candidate":
            request["system"][0]["text"] = replace_paragraph(request["system"][0]["text"])
        calls.append({"sequence": len(calls), "batch": batch, "arm": arm, "provider_request": request,
                      "request_sha256": sha(canonical(request)), "case_ids": [case["case_id"] for case in selected]})
    for batch in (0, 1):
        pair = {call["arm"]: copy.deepcopy(call["provider_request"]) for call in calls if call["batch"] == batch}
        pair["baseline"]["system"][0]["text"] = replace_paragraph(pair["baseline"]["system"][0]["text"])
        assert pair["baseline"] == pair["candidate"]
    inputs = [PREVIOUS / "plan.json", PREVIOUS / "controls-draft.json", PREVIOUS / "independent-gold-review.json",
              HERE / "holdout-controls-draft.json"]
    return {"experiment": "Audit refutations and explanatory claims: one-paragraph prompt comparison",
            "calls": calls, "cases": selected_cases, "source_sha256": sources(), "dependencies": dependencies(),
            "input_sha256": {str(path.relative_to(ROOT)): sha(path.read_bytes()) for path in inputs},
            "independent_holdout_review_sha256": review_hash, "native_contract": contract_metadata(CONTRACT),
            "limits": {"maximum_calls": 4, "items_per_call": 6, "items_per_arm": 12, "sdk_total_max_attempts": 1,
                       "read_timeout_seconds": 75, "connect_timeout_seconds": 3, "max_output_tokens": 6000, "region": "us-east-1"},
            "sole_paired_request_delta": "Exact replacement of the final independent-solutions paragraph; all other system/user/schema/model/settings bytes identical.",
            "prospective_criteria": {"valid_retained_with_exact_key_and_sound_feedback_of_8": 8, "bad_correctly_rejected_of_4": 4,
                                     "all_twelve_full_content_checks_per_arm": True, "all_operational_and_exact_identity_checks": True,
                                     "uncertainty_counts_as_failure": True, "difficulty_floor_is_separate": True,
                                     "all_main_and_choice_feedback_manually_audited": True, "no_gold_relabeling": True},
            "failure_policy": "First provider error, non-end_turn or structural failure stops all further calls. No retry, warm-up, substitution or extra calls. Preserve failed and unattempted denominators.",
            "claim_limits": "Six reused regressions and six prospective controls (one labeled derivative). Fresh independentSolutions are evaluator-authored fixtures, not model judgments. Negative format exposes no rationale. This tests prompt behavior, not full production yield or universal semantic correctness."}


def assess(response, call, plan):
    raw = "\n".join(block["text"] for block in response["output"]["message"]["content"] if "text" in block)
    adapted = json.loads(adapt_native_response(raw, CONTRACT))
    rows = adapted["reviews"]
    indexes = [row.get("index") for row in rows]
    if not all(type(index) is int for index in indexes) or sorted(indexes) != list(range(6)):
        raise ValueError("Missing, duplicate or unplanned review identity.")
    by_index = {row["index"]: row for row in rows}
    selected = [case for case in plan["cases"] if case["batch"] == call["batch"]]
    items = []
    for case in selected:
        row, gold, item = by_index[case["index"]], case["gold"], case["item"]
        result = {"case_id": case["case_id"], "valid": row["valid"], "gold_eligible": gold["eligible"],
                  "matching_disposition": row["valid"] == gold["eligible"], "manual_feedback_audit": "pending"}
        if row["valid"]:
            feedback = row["choiceExplanations"]
            coverage = set(feedback) == set(item["choices"])
            bounded = all(isinstance(value, str) and 12 <= len(value.strip()) <= limit and len(value) <= limit
                          for value, limit in [(row["explanation"], 420), *[(text, 280) for text in feedback.values()]])
            labels = any(_contains_answer_label_references(text, item) for text in [row["explanation"], *feedback.values()])
            typed = type(row["difficulty"]) is int and 1 <= row["difficulty"] <= 5
            result.update(exact_gold_key=row["answer"] == gold["answer"], exact_feedback_coverage=coverage,
                          feedback_bounded=bounded, answer_display_references=labels, difficulty=row["difficulty"],
                          positive_local_validation_pass=coverage and bounded and not labels and typed)
        items.append(result)
    return {"adapted_response": adapted, "items": items}


def safe_response(response):
    result = copy.deepcopy(response)
    blocks = result.get("output", {}).get("message", {}).get("content", [])
    count = sum("reasoningContent" in block for block in blocks)
    if "output" in result and "message" in result["output"]:
        result["output"]["message"]["content"] = [block for block in blocks if "reasoningContent" not in block]
    return result, count


def run_calls(client, plan, capture, path):
    for call in plan["calls"]:
        if len(capture["calls"]) >= 4:
            raise RuntimeError("Four-call maximum reached.")
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
                    if any(item.get("positive_local_validation_pass") is False for item in row["assessment"]["items"]):
                        row["validation_error_type"] = "LocalPositiveValidationFailure"
                        capture["stop_reason"] = "structural_failure"
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
    capture = {"plan_sha256": expected_hash, "calls": [], "status": "preflight", "started_at": datetime.now(timezone.utc).isoformat()}
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
        print(json.dumps({"plan_sha256": sha(PLAN.read_bytes()), "maximum_calls": 4, "provider_calls": 0}))
    else:
        execute(args.execute)
