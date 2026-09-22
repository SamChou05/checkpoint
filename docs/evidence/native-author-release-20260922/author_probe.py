"""Two-call, dry-by-default native fixed-slot author qualification.

Prepare exact requests before authorization. Execute a frozen plan once with
its SHA256, no retries, repair, fallback, persistence to the question bank, or
deployment. Credentials exist only in process memory.
"""

import argparse
from collections import Counter
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

ROOT = Path(__file__).resolve().parents[3]
SERVICE = ROOT / "backend/bedrock-question-service"
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(SERVICE))

import boto3  # noqa: E402
import botocore  # noqa: E402
from botocore.config import Config  # noqa: E402

from native_output_contracts import contract_metadata  # noqa: E402
from question_generation import ProviderCallBudget, _generate_with_bedrock  # noqa: E402
from question_quality import _sanitize_questions  # noqa: E402
from request_contract import _has_unambiguous_choices, _normalize_request  # noqa: E402


CONTRACT = "question_author_v2"
MODEL = "moonshotai.kimi-k2.5"
ENVIRONMENT = {
    "BEDROCK_STRUCTURED_OUTPUT_MODE": "native", "BEDROCK_MODEL_ID": MODEL,
    "BEDROCK_FALLBACK_MODEL_ID": "", "BEDROCK_KIMI_THINKING": "disabled",
    "BEDROCK_MAX_TOKENS": "6000", "BEDROCK_TEMPERATURE": "0.2",
    "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3", "BEDROCK_READ_TIMEOUT_SECONDS": "75",
    "BEDROCK_GUARDRAIL_IDENTIFIER": "", "BEDROCK_GUARDRAIL_VERSION": "",
    "QUESTION_FEEDBACK_CONTRACT": "reviewer_written", "CHECKPOINT_PROMPT_VARIANT": "balanced",
}


def sha(value):
    return hashlib.sha256(value).hexdigest()


def digest(value):
    return sha(json.dumps(value, sort_keys=True, ensure_ascii=False).encode())


def source_hashes():
    paths = [Path(__file__), *[SERVICE / name for name in (
        "native_output_contracts.py", "question_generation.py", "question_quality.py",
        "request_contract.py", "generation_diagnostics.py",
    )]]
    return {str(path.relative_to(ROOT)): sha(path.read_bytes()) for path in paths}


def save(path, value, *, exclusive=False):
    encoded = json.dumps(value, indent=2, ensure_ascii=False) + "\n"
    if exclusive:
        with path.open("x") as stream:
            stream.write(encoded)
    else:
        temporary = path.with_suffix(".partial")
        temporary.write_text(encoded)
        temporary.replace(path)


class DryClient:
    def converse(self, **request):
        self.request = copy.deepcopy(request)
        return {"stopReason": "end_turn", "output": {"message": {"content": [{"text": '{"questions":[]}'}]}}}


def prepare():
    goals = [
        {
            "id": "applied_arithmetic_logic",
            "title": "Apply arithmetic and logical conditions to everyday decisions",
            "contentTopics": ["Ratios and unit rates", "Percent changes", "Conditional reasoning"],
            "questionDirective": "Create five varied, self-contained application questions at difficulty 2 or 3. Use explicit numerical facts or clear fictional rules. Include ratios, costs or rates, and simple conditional reasoning. Avoid trivia and ambiguous real-world assumptions.",
        },
        {
            "id": "python_expressions_control_flow",
            "title": "Predict Python 3 expression values and short control-flow outcomes",
            "contentTopics": ["Arithmetic and comparison expressions", "Boolean short-circuiting", "Conditionals and small loops"],
            "questionDirective": "Create five varied, self-contained Python 3 application questions at difficulty 2 or 3. Give complete short expressions or code with exact indentation and explicit variable values. Test expression results and conditionals or bounded loops. Preserve case, operators and literal whitespace.",
        },
    ]
    jobs = []
    with patch.dict(os.environ, ENVIRONMENT):
        for index, goal in enumerate(goals):
            request = _normalize_request({
                "goal": {key: value for key, value in goal.items() if key != "id"} | {
                    "needsSkillMap": False, "preferredQuestionStyle": "Multiple Choice",
                },
                "targetCount": 5, "minimumDifficulty": 2,
            })
            client = DryClient()
            _generate_with_bedrock(request, client, MODEL, contract=CONTRACT,
                                   call_budget=ProviderCallBudget(1))
            jobs.append({"index": index, "id": goal["id"], "normalized_request": request,
                         "provider_request": client.request, "provider_request_sha256": digest(client.request)})
    plan = {
        "experiment": "Native author v2 fixed-slot bounded release qualification",
        "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_sha256": source_hashes(), "contract": contract_metadata(CONTRACT),
        "environment": ENVIRONMENT,
        "limits": {"maximum_calls": 2, "target_items_per_call": 5, "sdk_total_max_attempts": 1,
                   "region": "us-east-1", "read_timeout_seconds": 75, "connect_timeout_seconds": 3},
        "prospective_criteria": {
            "end_turn_and_strict_native_valid_calls": 2, "exact_item_count_per_call": 5,
            "all_items_have_four_distinct_visible_choices_and_mapped_key": True,
            "all_items_within_existing_prompt_choice_feedback_display_bounds": True,
            "all_items_difficulty_2_or_3": True, "all_ten_items_retained_by_existing_sanitizer": True,
            "no_changed_choice_or_answer_text_during_sanitization": True,
        },
        "failure_policy": "Stop after a provider, stop-reason or strict-adapter failure. Record item count, bounds and sanitizer failures without repair; the other independent goal may still run. Never retry, fall back, replace a capture or add calls.",
        "interpretation": "Uses the actual default author system/user prompts plus exact v2 native transport override. No solver or reviewer call occurs; sanitizer admission is not factual verification. Distinct visible text is a local representation check, not a semantic-diversity guarantee. Two different batches do not estimate determinism or general error rates. Sanitizer reordering/other existing transformations are recorded, not hidden.",
        "jobs": jobs,
    }
    path = HERE / "plan.json"
    save(path, plan, exclusive=True)
    print(json.dumps({"plan": str(path), "plan_sha256": sha(path.read_bytes()),
                      "maximum_calls": 2, "source_sha256": plan["source_sha256"]}))


class Recorder:
    def __init__(self, client, capture, path, job):
        self.client, self.capture, self.path, self.job = client, capture, path, job

    def converse(self, **request):
        if request != self.job["provider_request"] or digest(request) != self.job["provider_request_sha256"]:
            raise RuntimeError("Actual request differs from frozen plan before dispatch.")
        if len(self.capture["calls"]) >= 2:
            raise RuntimeError("Two-dispatch ceiling reached.")
        call = {"index": self.job["index"], "id": self.job["id"], "request": copy.deepcopy(request),
                "started_at": datetime.now(timezone.utc).isoformat(), "dispatch_attempted": True}
        self.capture["calls"].append(call)
        save(self.path, self.capture)
        started = time.monotonic()
        try:
            response = self.client.converse(**request)
            call["response"] = response
            return response
        except Exception as error:
            call["provider_error_type"] = type(error).__name__
            call["provider_error_code"] = getattr(error, "response", {}).get("Error", {}).get("Code")
            raise
        finally:
            call["elapsed_seconds"] = round(time.monotonic() - started, 3)
            save(self.path, self.capture)


def inspect_items(adapted, request):
    rows, previous_counts, previous_count = [], {}, 0
    questions = adapted["questions"]
    for index, item in enumerate(questions):
        metrics = {}
        retained = _sanitize_questions(questions[:index + 1], request, metrics)
        counts = metrics.get("QuestionQuality", {}).get("sanitize", {})
        admitted = len(retained) > previous_count
        output = retained[-1] if admitted else None
        bounds = {
            "prompt": 12 <= len(item["prompt"]) <= 320,
            "choices": all(1 <= len(choice) <= 140 for choice in item["choices"]),
            "explanation": bool(item["explanation"].strip()) and len(item["explanation"]) <= 420,
            "topic": bool(item["topic"].strip()) and len(item["topic"]) <= 48,
            "difficulty": item["difficulty"] in (2, 3),
        }
        rows.append({
            "index": index, "adapted_question": item, "bounds": bounds,
            "four_distinct_visible_choices": len(item["choices"]) == 4 and _has_unambiguous_choices(item["choices"]),
            "mapped_key_present": item["expectedAnswer"] in item["choices"],
            "sanitizer_admitted": admitted, "sanitized_question": output,
            "sanitizer_diagnostics": {key: count - previous_counts.get(key, 0) for key, count in counts.items()
                                      if count - previous_counts.get(key, 0) > 0},
            "choice_text_unchanged": admitted and Counter(item["choices"]) == Counter(output["choices"]),
            "answer_text_unchanged": admitted and item["expectedAnswer"] == output["expectedAnswer"],
            "changed_fields": [] if not admitted else [key for key in item if item.get(key) != output.get(key)],
        })
        previous_counts, previous_count = counts, len(retained)
    return {"item_count": len(questions), "rows": rows, "sanitizer_admitted_count": previous_count}


def execute(expected_hash):
    plan_bytes = (HERE / "plan.json").read_bytes()
    if sha(plan_bytes) != expected_hash:
        raise RuntimeError("Frozen plan checksum mismatch.")
    plan = json.loads(plan_bytes)
    if source_hashes() != plan["source_sha256"]:
        raise RuntimeError("Source changed after plan freeze.")
    path = HERE / "capture.json"
    capture = {"plan_sha256": expected_hash, "started_at": datetime.now(timezone.utc).isoformat(),
               "dependencies": {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__},
               "status": "preflight", "calls": []}
    save(path, capture, exclusive=True)
    try:
        credentials = json.loads(subprocess.check_output(
            ["aws", "configure", "export-credentials", "--format", "process"], stderr=subprocess.DEVNULL,
        ))
        client = boto3.client(
            "bedrock-runtime", region_name="us-east-1", aws_access_key_id=credentials["AccessKeyId"],
            aws_secret_access_key=credentials["SecretAccessKey"], aws_session_token=credentials.get("SessionToken"),
            config=Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1}),
        )
        del credentials
        budget = ProviderCallBudget(2)
        capture["status"] = "running"
        with patch.dict(os.environ, plan["environment"]):
            for job in plan["jobs"]:
                print(f"Dispatch {job['index'] + 1}/2: {job['id']}", flush=True)
                metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
                adapted_raw = _generate_with_bedrock(
                    job["normalized_request"], Recorder(client, capture, path, job), MODEL,
                    contract=CONTRACT, call_budget=budget, request_metrics=metrics,
                )
                call = capture["calls"][-1]
                call.update(strict_native_adapter_valid=True, adapted_raw=adapted_raw,
                            metrics=metrics, analysis=inspect_items(json.loads(adapted_raw), job["normalized_request"]))
                save(path, capture)
                print(f"Completed {job['index'] + 1}/2: items={call['analysis']['item_count']}, sanitizer admitted={call['analysis']['sanitizer_admitted_count']}", flush=True)
        capture["status"] = "complete"
    except Exception as error:
        capture.update(status="stopped_after_failure", error_type=type(error).__name__)
        if capture["calls"]:
            capture["calls"][-1]["stage_error_type"] = type(error).__name__
    finally:
        capture["finished_at"] = datetime.now(timezone.utc).isoformat()
        save(path, capture)
    print(json.dumps({"capture": str(path), "status": capture["status"], "calls": len(capture["calls"])}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--prepare", action="store_true")
    action.add_argument("--execute", metavar="PLAN_SHA256")
    arguments = parser.parse_args()
    prepare() if arguments.prepare else execute(arguments.execute)
