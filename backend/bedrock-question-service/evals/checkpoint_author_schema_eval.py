#!/usr/bin/env python3
"""Four-call author-only comparison of provider-enforced JSON and ordinary text.

Two repetitions per arm on the exact same Python request. The only Converse
request difference is outputConfig. Both arms use a 300-second read deadline
to observe possible schema compilation; this is not a worker timeout change.
Stop on any provider failure. No repair calls, hidden retries or deployment.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import time
from unittest.mock import patch

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals.checkpoint_full_pipeline_smoke import (  # noqa: E402
    CapturingClient,
    MODEL,
    SETTINGS,
    load_cases,
    write_json,
)
from evals.checkpoint_prompt_ablation import (  # noqa: E402
    digest,
    use_aws_cli_credentials,
    write_outputs,
)
from question_generation import (  # noqa: E402
    ProviderCallBudget,
    _generate_with_bedrock,
    _system_prompt,
    _user_prompt,
)
from question_quality import _extract_json_object, _sanitize_questions  # noqa: E402
from request_contract import _normalize_request  # noqa: E402
from service_errors import ProviderError  # noqa: E402

REQUIRED_FIELDS = (
    "prompt",
    "expectedAnswer",
    "choices",
    "explanation",
    "topic",
    "difficulty",
    "format",
)
OPTIONAL_FIELDS = ("skillID", "objectiveID", "objective")
AUTHOR_SCHEMA = {
    "type": "object",
    "properties": {
        "questions": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    **{
                        key: {"type": "string"}
                        for key in (*REQUIRED_FIELDS, *OPTIONAL_FIELDS)
                        if key not in {"choices", "difficulty", "format"}
                    },
                    "choices": {"type": "array", "items": {"type": "string"}},
                    "difficulty": {"type": "integer", "enum": [1, 2, 3, 4, 5]},
                    "format": {"type": "string", "enum": ["Multiple Choice"]},
                },
                "required": list(REQUIRED_FIELDS),
                "additionalProperties": False,
            },
        },
    },
    "required": ["questions"],
    "additionalProperties": False,
}
OUTPUT_CONFIG = {
    "textFormat": {
        "type": "json_schema",
        "structure": {
            "jsonSchema": {
                "name": "checkpoint_questions_v1",
                "schema": json.dumps(AUTHOR_SCHEMA, separators=(",", ":")),
            }
        },
    }
}


class AuthorCapture(CapturingClient):
    def __init__(self, client, path, structured):
        super().__init__(client, path)
        self.structured = structured

    def converse(self, **request):
        if self.calls:
            raise RuntimeError("Each author arm permits exactly one provider call.")
        request = copy.deepcopy(request)
        if self.structured:
            request["outputConfig"] = copy.deepcopy(OUTPUT_CONFIG)
        return super().converse(**request)


def matches_schema(payload):
    """Validate this deliberately small schema without adding runtime deps."""
    if not isinstance(payload, dict) or set(payload) != {"questions"}:
        return False
    if not isinstance(payload["questions"], list):
        return False
    for item in payload["questions"]:
        if not isinstance(item, dict) or not set(REQUIRED_FIELDS) <= set(item):
            return False
        if set(item) - set(REQUIRED_FIELDS) - set(OPTIONAL_FIELDS):
            return False
        if any(
            not isinstance(value, str)
            for key, value in item.items()
            if key not in {"choices", "difficulty"}
        ):
            return False
        if (
            type(item["difficulty"]) is not int
            or item["difficulty"] not in range(1, 6)
            or item["format"] != "Multiple Choice"
            or not isinstance(item["choices"], list)
            or any(not isinstance(value, str) for value in item["choices"])
        ):
            return False
    return True


def make_plan(seed):
    case = load_cases()[0]
    request = _normalize_request(case["payload"])
    jobs = []
    for repetition in (1, 2):
        arms = ["ordinary", "structured"]
        random.Random(seed + repetition).shuffle(arms)
        for arm in arms:
            jobs.append(
                {
                    "case_id": case["case_id"],
                    "arm": arm,
                    "repetition": repetition,
                    "request": copy.deepcopy(request),
                    "contextSHA256": digest(json.dumps(request, sort_keys=True)),
                }
            )
    return jobs


def run_experiment(directory, client, seed=9062026):
    directory.mkdir(parents=True, exist_ok=False)
    results = []
    jobs = make_plan(seed)
    with patch.dict(os.environ, SETTINGS):
        system = _system_prompt()
        user = _user_prompt(jobs[0]["request"])
        write_json(
            directory / "plan.json",
            {
                "git_revision": subprocess.check_output(
                    ["git", "rev-parse", "HEAD"], cwd=SERVICE_DIR, text=True
                ).strip(),
                "model": MODEL,
                "maximum_calls": 4,
                "seed": seed,
                "read_timeout_seconds": 300,
                "hidden_sdk_retries": 0,
                "settings": SETTINGS,
                "runtime_read_timeout_note": "Client explicitly uses 300 seconds in both arms; deployed deadlines unchanged.",
                "schema": AUTHOR_SCHEMA,
                "system": system,
                "user": user,
                "jobs": jobs,
            },
        )
        for index, job in enumerate(jobs):
            metrics = {
                "ProviderCalls": 0,
                "BedrockInputTokens": 0,
                "BedrockOutputTokens": 0,
            }
            capture = AuthorCapture(
                client,
                directory / f"call{index + 1:02d}.json",
                job["arm"] == "structured",
            )
            result = {
                **job,
                "questions": [],
                "metrics": metrics,
                "strict_json": False,
                "runtime_parse": False,
                "schema_match": False,
                "structurally_retained": 0,
            }
            started = time.monotonic()
            try:
                raw = _generate_with_bedrock(
                    job["request"],
                    capture,
                    MODEL,
                    user_prompt=user,
                    system_prompt=system,
                    call_budget=ProviderCallBudget(1),
                    request_metrics=metrics,
                )
                result["raw"] = raw
                if capture.calls[0].get("response", {}).get("stopReason") != "end_turn":
                    raise ProviderError("Provider did not finish a normal answer.")
                try:
                    json.loads(raw)
                    result["strict_json"] = True
                except (ValueError, TypeError):
                    pass
                payload = _extract_json_object(raw)
                result["runtime_parse"] = True
                result["schema_match"] = matches_schema(payload)
                questions = payload.get("questions")
                if isinstance(questions, list):
                    result["questions"] = [q for q in questions if isinstance(q, dict)]
                    result["structurally_retained"] = len(
                        _sanitize_questions(
                            result["questions"], job["request"], metrics
                        )
                    )
            except (ProviderError, ValueError, TypeError) as error:
                result["error_type"] = type(error).__name__
            result["elapsed_seconds"] = round(time.monotonic() - started, 3)
            stop_reason = (
                capture.calls[0].get("response", {}).get("stopReason")
                if capture.calls
                else None
            )
            result["provider_failed"] = capture.failed
            result["stop_reason"] = stop_reason
            result["stopped_early"] = capture.failed or stop_reason != "end_turn"
            results.append(result)
            write_outputs(directory, results, MODEL, seed, len(jobs))
            print(
                json.dumps(
                    {
                        "completed": len(results),
                        "planned": 4,
                        "provider_failed": capture.failed,
                        "stopped_early": result["stopped_early"],
                        "elapsed_seconds": result["elapsed_seconds"],
                    }
                ),
                flush=True,
            )
            if result["stopped_early"]:
                break
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--aws-cli-credentials", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.dry_run:
        print(
            json.dumps(
                {
                    "calls": 4,
                    "model": MODEL,
                    "schema": AUTHOR_SCHEMA,
                    "read_timeout_seconds": 300,
                },
                indent=2,
            )
        )
        return 0
    if args.aws_cli_credentials:
        use_aws_cli_credentials()
    import boto3
    from botocore.config import Config
    from botocore.validate import validate_parameters

    client = boto3.client(
        "bedrock-runtime",
        region_name="us-east-1",
        config=Config(
            connect_timeout=3,
            read_timeout=300,
            retries={"total_max_attempts": 1, "mode": "standard"},
        ),
    )
    shape = client.meta.service_model.operation_model("Converse").input_shape
    validate_parameters(
        {"modelId": MODEL, "messages": [], "outputConfig": OUTPUT_CONFIG}, shape
    )
    results = run_experiment(args.output_dir, client)
    return 1 if results[-1]["stopped_early"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
