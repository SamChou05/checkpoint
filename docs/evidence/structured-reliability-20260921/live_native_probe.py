"""Bounded local native author/solver/reviewer qualification on synthetic content.

Prepare an immutable plan, then execute that plan once using its SHA256. No bank,
configuration, deployment, or IAM writes occur. Credentials stay in memory.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
SERVICE = ROOT / "backend/bedrock-question-service"
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(SERVICE))

import boto3  # noqa: E402
import botocore  # noqa: E402
from botocore.config import Config  # noqa: E402

from native_output_contracts import contract_metadata  # noqa: E402
from question_generation import ProviderCallBudget, _generate_sanitized_questions  # noqa: E402
from request_contract import _normalize_request  # noqa: E402


def sha(value):
    return hashlib.sha256(value).hexdigest()


def write_new(path, value):
    with path.open("x") as stream:
        stream.write(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def save(path, value):
    temporary = path.with_suffix(".partial")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    temporary.replace(path)


def source_hashes():
    return {str(path.relative_to(ROOT)): sha(path.read_bytes()) for path in [
        Path(__file__),
        *[SERVICE / name for name in (
            "native_output_contracts.py", "question_generation.py", "question_quality.py",
            "question_verification.py", "complete_question_solution.py", "request_contract.py",
        )],
    ]}


def prepare():
    plan = {
        "kind": "Two local synthetic native generation passes; at most six Bedrock dispatches",
        "source_revision": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
        ).strip(),
        "source_sha256": source_hashes(),
        "deployment_observation": "Parent freshly read TestFlight worker 2026-09-21: same models, thinking, output and timeout settings; native transport is the only treatment.",
        "environment": {
            "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
            "BEDROCK_MODEL_ID": "moonshotai.kimi-k2.5",
            "BEDROCK_VERIFICATION_MODEL_ID": "us.anthropic.claude-sonnet-4-6",
            "BEDROCK_FALLBACK_MODEL_ID": "",
            "BEDROCK_KIMI_THINKING": "disabled",
            "BEDROCK_CLAUDE_THINKING": "disabled",
            "BEDROCK_MAX_TOKENS": "6000",
            "BEDROCK_THINKING_MAX_TOKENS": "16000",
            "BEDROCK_TEMPERATURE": "0.2",
            "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3",
            "BEDROCK_READ_TIMEOUT_SECONDS": "75",
            "BEDROCK_GUARDRAIL_IDENTIFIER": "",
            "BEDROCK_GUARDRAIL_VERSION": "",
            "BEDROCK_REASONING_EFFORT": "",
            "QUESTION_FEEDBACK_CONTRACT": "reviewer_written",
            "CHECKPOINT_PROMPT_VARIANT": "balanced",
            "GENERATION_ATTEMPTS": "1",
        },
        "request": _normalize_request({
            "goal": {"title": "Practice adding and subtracting whole numbers from 0 through 20"},
            "targetCount": 1,
            "minimumDifficulty": 1,
        }),
        "contracts": [contract_metadata(name) for name in (
            "question_author_v1", "complete_choice_solver_v1", "default_reviewer_v1",
        )],
        "limits": {
            "passes": 2, "maximum_dispatches_per_pass": 3, "maximum_dispatches_total": 6,
            "sdk_total_max_attempts": 1, "region": "us-east-1",
            "read_timeout_seconds": 75, "connect_timeout_seconds": 3,
            "no_fallback_or_repair_retry": True,
        },
        "interpretation": [
            "Each pass uses the actual production author, sanitizer, independent solver and reviewer.",
            "Second-pass author receives the same request; downstream inputs depend on generated content.",
            "First/repeated refer to schema use; actual provider grammar cache state is unobservable.",
            "This does not qualify other schemas, skill maps, optional feedback, sync Nova Lite, or deployed execution.",
            "No general semantic error rate, answer diversity rate, or repeatability guarantee can be inferred.",
        ],
    }
    path = HERE / "live-native-plan.json"
    write_new(path, plan)
    print(json.dumps({"plan": str(path), "sha256": sha(path.read_bytes()), "maximum_dispatches": 6}))


class Recorder:
    def __init__(self, client, result, path):
        self.client, self.result, self.path = client, result, path
        self.meta = client.meta

    def converse(self, **request):
        if len(self.result["calls"]) >= 6:
            raise RuntimeError("Six-dispatch probe ceiling reached")
        record = {
            "dispatch": len(self.result["calls"]) + 1,
            "request": request,
            "started_at": datetime.now(timezone.utc).isoformat(),
            "outcome": "dispatching",
        }
        self.result["calls"].append(record)
        save(self.path, self.result)
        started = time.monotonic()
        try:
            response = self.client.converse(**request)
        except Exception as error:
            record.update(
                outcome="provider_failed", exception_type=type(error).__name__,
                provider_error_code=getattr(error, "response", {}).get("Error", {}).get("Code"),
            )
            raise
        else:
            record.update(
                outcome="returned",
                response={
                    "stopReason": response.get("stopReason"),
                    "usage": response.get("usage"),
                    "metrics": response.get("metrics"),
                    "content": [block for block in response.get("output", {}).get("message", {}).get("content", [])
                                if "reasoningContent" not in block],
                },
            )
            return response
        finally:
            record["elapsed_seconds"] = round(time.monotonic() - started, 3)
            save(self.path, self.result)


def execute(expected_sha):
    plan_path = HERE / "live-native-plan.json"
    raw = plan_path.read_bytes()
    if sha(raw) != expected_sha:
        raise SystemExit("Plan checksum mismatch")
    plan = json.loads(raw)
    if plan["source_sha256"] != source_hashes():
        raise SystemExit("Probe or production source changed after plan freeze")
    output = HERE / "live-native-capture.json"
    result = {
        "plan_sha256": expected_sha, "started_at": datetime.now(timezone.utc).isoformat(),
        "dependencies": {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__},
        "status": "preflight", "calls": [], "passes": [],
    }
    write_new(output, result)
    try:
        credentials = json.loads(subprocess.check_output(
            ["aws", "configure", "export-credentials", "--format", "process"],
            stderr=subprocess.DEVNULL,
        ))
        client = boto3.client(
            "bedrock-runtime", region_name="us-east-1",
            aws_access_key_id=credentials["AccessKeyId"],
            aws_secret_access_key=credentials["SecretAccessKey"],
            aws_session_token=credentials.get("SessionToken"),
            config=Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1}),
        )
        del credentials
        recording_client = Recorder(client, result, output)
        result["status"] = "running"
        with patch.dict(os.environ, plan["environment"]):
            for iteration in range(2):
                metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
                budget = ProviderCallBudget(3)
                run = {"iteration": iteration + 1, "metrics": metrics, "questions": []}
                result["passes"].append(run)
                try:
                    run["questions"] = _generate_sanitized_questions(
                        plan["request"], recording_client, budget, metrics,
                    )
                    run["outcome"] = "completed"
                except Exception as error:
                    run.update(outcome="failed", exception_type=type(error).__name__)
                run["provider_calls"] = budget.calls
                save(output, result)
        result["status"] = "completed"
    except Exception as error:
        result.update(status="preflight_failed", exception_type=type(error).__name__)
    finally:
        result["finished_at"] = datetime.now(timezone.utc).isoformat()
        save(output, result)
    print(json.dumps({
        "capture": str(output), "status": result["status"], "calls": len(result["calls"]),
        "passes": [{"iteration": item["iteration"], "outcome": item["outcome"],
                    "accepted": len(item["questions"]), "calls": item["provider_calls"]}
                   for item in result["passes"]],
    }))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--prepare", action="store_true")
    action.add_argument("--execute", metavar="PLAN_SHA256")
    arguments = parser.parse_args()
    prepare() if arguments.prepare else execute(arguments.execute)
