"""Dry-by-default bounded qualification of the real three-stage generation path.

No deployment or learner-bank writes. Freeze source, requests and criteria first;
retain every attempt, including application top-ups and failed provider calls.
"""

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

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SERVICE = ROOT / "backend/bedrock-question-service"
sys.path.insert(0, str(SERVICE))

import boto3  # noqa: E402
import botocore  # noqa: E402
from botocore.config import Config  # noqa: E402
from native_output_contracts import contract_metadata  # noqa: E402
from question_generation import ProviderCallBudget, _generate_sanitized_questions  # noqa: E402
from request_contract import _normalize_request  # noqa: E402

ENVIRONMENT = {
    "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
    "BEDROCK_MODEL_ID": "moonshotai.kimi-k2.5",
    "BEDROCK_VERIFICATION_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
    "BEDROCK_FALLBACK_MODEL_ID": "", "BEDROCK_KIMI_THINKING": "disabled",
    "BEDROCK_CLAUDE_THINKING": "disabled", "BEDROCK_MAX_TOKENS": "6000",
    "BEDROCK_TEMPERATURE": "0.2", "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3",
    "BEDROCK_READ_TIMEOUT_SECONDS": "75", "BEDROCK_GUARDRAIL_IDENTIFIER": "",
    "BEDROCK_GUARDRAIL_VERSION": "", "QUESTION_FEEDBACK_CONTRACT": "reviewer_written",
    "CHECKPOINT_PROMPT_VARIANT": "balanced", "GENERATION_ATTEMPTS": "2",
    "MAX_PROVIDER_CALLS_PER_REQUEST": "6",
    "MIN_PROVIDER_REMAINING_MILLISECONDS": "0", "MAX_QUESTIONS_PER_BATCH": "20",
}
CONTRACTS = ("question_author_v3", "complete_choice_solver_v3", "default_reviewer_v1")


def sha(value):
    return hashlib.sha256(value).hexdigest()


def sources():
    files = [Path(__file__), *sorted(SERVICE.glob("*.py"))]
    return {str(path.relative_to(ROOT)): sha(path.read_bytes()) for path in files}


def save(path, value, *, exclusive=False):
    text = json.dumps(value, indent=2, ensure_ascii=False) + "\n"
    if exclusive:
        with path.open("x") as stream:
            stream.write(text)
    else:
        temporary = path.with_suffix(".partial")
        temporary.write_text(text)
        temporary.replace(path)


def prepare(path):
    specifications = [
        ("Arithmetic decisions", ["Ratios", "Percent change", "Unit rates"],
         "Use explicit numbers to test everyday costs, mixtures and rates. Include all necessary facts."),
        ("Python 3 expressions", ["Boolean expressions", "List indexing", "Conditionals"],
         "Use complete short Python 3 expressions or correctly indented code, with explicit values. Preserve case and literal syntax."),
        ("English usage", ["Subject-verb agreement", "Pronoun reference", "Sentence punctuation"],
         "Use standard written American English, supply complete sentences, and make the tested grammatical distinction explicit."),
        ("Interpreting quantitative evidence", ["Proportions", "Weighted averages", "Comparing measurements"],
         "Supply all measurements in the stem. Ask for a conclusion justified by those data; avoid unsupported causal inferences."),
        ("Applying fictional access rules", ["Conjunction", "Inclusive boundaries", "Conditional rules"],
         "State complete fictional access rules and concrete facts. Ask which single conclusion follows. Do not assume unstated real-world policies."),
        ("Physical quantities", ["Distance and speed", "Conservation of mass", "Density"],
         "Give explicit quantities and assumptions for simple physical applications. Use plain text units and complete conditions."),
    ]
    jobs = []
    for index, (title, topics, directive) in enumerate(specifications):
        with patch.dict(os.environ, ENVIRONMENT):
            request = _normalize_request({"goal": {
                "title": title, "contentTopics": topics, "needsSkillMap": False,
                "preferredQuestionStyle": "Multiple Choice",
                "questionDirective": directive + " Create five varied self-contained application questions at difficulty 2 or 3.",
            }, "targetCount": 5, "minimumDifficulty": 2})
        assert request["targetCount"] == 5
        jobs.append({"index": index, "request": request})
    plan = {
        "experiment": "Real native author, independent solver and final reviewer qualification",
        "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_sha256": sources(), "environment": ENVIRONMENT, "jobs": jobs,
        "dependencies": {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__},
        "limits": {"maximum_calls": 36, "maximum_calls_per_job": 6, "sdk_total_max_attempts": 1,
                   "job_deadline_seconds": 240, "read_timeout_seconds": 75,
                   "max_output_tokens_per_call": 6000, "region": "us-east-1"},
        "prospective_criteria": {
            "all_attempts_retained": True, "no_transport_schema_or_stage_coverage_failures": True,
            "minimum_admitted_per_job": 3, "minimum_total_admitted_of_30": 27,
            "every_admitted_item": "Exactly four distinct task-relevant proposed answers, exactly one correct answer matching the key; complete bounded prompt, explanation and per-choice feedback; no contradictory teaching or silent key repair. Independent human-agent adjudication records uncertainty as failure. All accepted bytes round-trip unchanged through application validation.",
        },
        "failure_policy": "Run each independent job once using the actual application with at most two passes and six calls. Preserve partial yields and all rejected drafts; no replacement jobs, out-of-band retries, follow-up judging calls or after-output criteria changes. Stop all dispatches after transport or non-end_turn failure. Never write a learner question bank or deploy.",
        "interpretation": "Six batches exercise the real route within the worker's count/token/time ceilings, not a population error-rate estimate or a proof of arbitrary factual correctness. The injected client keeps a fixed75s read timeout; unlike the real worker it cannot shrink the timeout late in a job, so deadline admission is conservative rather than byte-identical. The application may top up rejected items within its frozen budget. Independent review of all drafts and accepted outputs is retained.",
    }
    # Selecting contracts is a production-route decision, pinned by source hashes.
    plan["registered_contracts"] = {name: contract_metadata(name) for name in CONTRACTS}
    save(path, plan, exclusive=True)
    print(json.dumps({"plan_sha256": sha(path.read_bytes()), "maximum_calls": 36}))


class Deadline:
    def __init__(self):
        self.start = time.monotonic()

    def get_remaining_time_in_millis(self):
        return max(0, int((240 - (time.monotonic() - self.start)) * 1000))


class Recorder:
    def __init__(self, client, capture, job, path):
        self.client, self.capture, self.job, self.path = client, capture, job, path

    def converse(self, **request):
        if self.capture.get("stop_dispatching"):
            raise RuntimeError("Dispatch stopped after provider failure.")
        if len(self.capture["calls"]) >= 36 or sum(c["job"] == self.job for c in self.capture["calls"]) >= 6:
            raise RuntimeError("Frozen dispatch ceiling reached.")
        if request["modelId"] not in (ENVIRONMENT["BEDROCK_MODEL_ID"], ENVIRONMENT["BEDROCK_VERIFICATION_MODEL_ID"]):
            raise RuntimeError("Unplanned model.")
        if request["inferenceConfig"] != {"maxTokens": 6000, "temperature": 0.2}:
            raise RuntimeError("Unplanned sampling or token settings.")
        contract = request["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"]
        if contract not in CONTRACTS:
            raise RuntimeError("Unplanned stage contract.")
        call = {"job": self.job, "request": copy.deepcopy(request), "dispatch_attempted": True,
                "started_at": datetime.now(timezone.utc).isoformat()}
        self.capture["calls"].append(call)
        save(self.path, self.capture)
        started = time.monotonic()
        try:
            response = self.client.converse(**request)
            call["response"] = response
            if response.get("stopReason") != "end_turn":
                self.capture["stop_dispatching"] = True
            return response
        except Exception as error:
            call["provider_error_type"] = type(error).__name__
            self.capture["stop_dispatching"] = True
            raise
        finally:
            call["elapsed_seconds"] = round(time.monotonic() - started, 3)
            save(self.path, self.capture)


def execute(expected_hash, plan_path):
    encoded = plan_path.read_bytes()
    plan = json.loads(encoded)
    if sha(encoded) != expected_hash or sources() != plan["source_sha256"]:
        raise RuntimeError("Frozen plan or source changed.")
    if plan["dependencies"] != {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__}:
        raise RuntimeError("Frozen dependency versions changed.")
    capture = {"plan_sha256": expected_hash, "started_at": datetime.now(timezone.utc).isoformat(),
               "calls": [], "jobs": [], "status": "preflight"}
    path = plan_path.with_name(plan_path.name.replace("plan", "capture", 1))
    if path == plan_path:
        raise RuntimeError("Plan filename must include 'plan'.")
    save(path, capture, exclusive=True)
    credentials = json.loads(subprocess.check_output(
        ["aws", "configure", "export-credentials", "--format", "process"], stderr=subprocess.DEVNULL))
    client = boto3.client("bedrock-runtime", region_name="us-east-1",
                         aws_access_key_id=credentials["AccessKeyId"],
                         aws_secret_access_key=credentials["SecretAccessKey"],
                         aws_session_token=credentials.get("SessionToken"),
                         config=Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1}))
    del credentials
    capture["status"] = "running"
    with patch.dict(os.environ, plan["environment"]):
        for job in plan["jobs"]:
            if capture.get("stop_dispatching"):
                break
            row = {"index": job["index"], "metrics": {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}}
            capture["jobs"].append(row)
            started = time.monotonic()
            print(f"Job {job['index'] + 1}/6: {job['request']['goal']['title']}", flush=True)
            try:
                row["accepted"] = _generate_sanitized_questions(
                    copy.deepcopy(job["request"]), Recorder(client, capture, job["index"], path),
                    ProviderCallBudget(6, context=Deadline()), row["metrics"])
            except Exception as error:
                row["error_type"] = type(error).__name__
            row["elapsed_seconds"] = round(time.monotonic() - started, 3)
            save(path, capture)
            print(f"Accepted {len(row.get('accepted', []))}/5; calls={row['metrics']['ProviderCalls']}", flush=True)
    capture["status"] = "stopped_after_failure" if capture.get("stop_dispatching") else "complete"
    capture["finished_at"] = datetime.now(timezone.utc).isoformat()
    save(path, capture)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--prepare", action="store_true")
    action.add_argument("--execute", metavar="PLAN_SHA256")
    parser.add_argument("--plan", type=Path, default=HERE / "pipeline-plan.json")
    args = parser.parse_args()
    prepare(args.plan) if args.prepare else execute(args.execute, args.plan)
