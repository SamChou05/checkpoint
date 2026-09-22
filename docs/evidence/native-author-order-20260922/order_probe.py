"""Prepare a four-call paired author experiment; execute only a reviewed hash.

The only treatment is the property order serialized inside the v2 author JSON
schema. Production schema serialization and all earlier evidence are untouched.
"""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
PRIOR = HERE.parent / "native-author-release-20260922"
spec = importlib.util.spec_from_file_location("fixed_slot_author_probe", PRIOR / "author_probe.py")
author = importlib.util.module_from_spec(spec)
spec.loader.exec_module(author)

import boto3  # noqa: E402
import botocore  # noqa: E402
from botocore.config import Config  # noqa: E402
from jsonschema import Draft202012Validator  # noqa: E402
from question_generation import ProviderCallBudget, _generate_with_bedrock  # noqa: E402


PROPERTY_ORDER = [
    "prompt", "choices", "explanation", "correctChoice", "topic", "difficulty",
    "format", "skillID", "objectiveID", "objective",
]


def sha(value):
    return hashlib.sha256(value).hexdigest()


def hashes():
    return author.source_hashes() | {str(Path(__file__).relative_to(ROOT)): sha(Path(__file__).read_bytes())}


def ordered_request(request):
    changed = copy.deepcopy(request)
    config = changed["outputConfig"]["textFormat"]["structure"]["jsonSchema"]
    original = json.loads(config["schema"])
    schema = copy.deepcopy(original)
    question = schema["properties"]["questions"]["items"]
    if set(question["properties"]) != set(PROPERTY_ORDER):
        raise ValueError("Author schema properties changed.")
    question["properties"] = {key: question["properties"][key] for key in PROPERTY_ORDER}
    # Keep every other mapping's order, all required arrays and all schema
    # semantics unchanged. Only question property ordering is the treatment.
    config["schema"] = json.dumps(schema, separators=(",", ":"))
    assert json.loads(config["schema"]) == original
    assert changed != request
    normalized = copy.deepcopy(changed)
    normalized["outputConfig"] = copy.deepcopy(request["outputConfig"])
    assert normalized == request
    return changed


def prepare():
    prior_bytes = (PRIOR / "plan.json").read_bytes()
    prior = json.loads(prior_bytes)
    jobs = []
    with patch.dict(os.environ, prior["environment"]):
        for goal_index, previous_job in enumerate(prior["jobs"]):
            dry = author.DryClient()
            _generate_with_bedrock(previous_job["normalized_request"], dry, author.MODEL,
                                   contract=author.CONTRACT, call_budget=ProviderCallBudget(1))
            if dry.request != previous_job["provider_request"]:
                raise RuntimeError("Current actual author request differs from the prior frozen prompt/settings.")
            treatment = ordered_request(dry.request)
            arms = ("sorted", "ordered") if goal_index == 0 else ("ordered", "sorted")
            for arm in arms:
                request = dry.request if arm == "sorted" else treatment
                jobs.append({
                    "index": len(jobs), "goal_index": goal_index, "goal_id": previous_job["id"], "arm": arm,
                    "normalized_request": previous_job["normalized_request"],
                    "logical_request": dry.request, "provider_request": request,
                    "provider_request_sha256": author.digest(request),
                })
    plan = {
        "experiment": "Paired fixed-slot author schema property ordering",
        "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_sha256": hashes(), "prior_plan_sha256": sha(prior_bytes),
        "prior_capture_sha256": sha((PRIOR / "capture.json").read_bytes()),
        "environment": prior["environment"],
        "limits": {**prior["limits"], "maximum_calls": 4, "calls_per_arm": 2},
        "treatment": "Only the question item's properties mapping order in the serialized JSON Schema changes. Sorted baseline is the exact previous native v2 request. Ordered treatment uses prompt, choices, explanation, correctChoice, topic, difficulty, format, skillID, objectiveID, objective. Required-field array order, property types, enum, schema name, system/user prompts, model/settings and application adapter/sanitizer are identical. Production serialization is unchanged.",
        "prospective_criteria": {
            "all_four_calls_end_turn_and_strict_valid": True,
            "exactly_five_items_each": True,
            "ordered_items_follow_prompt_choices_explanation_correctChoice_order": 10,
            "ordered_items_within_original_display_bounds": 10,
            "ordered_items_difficulty_2_or_3": 10,
            "ordered_items_four_distinct_visible_choices_and_mapped_key": 10,
            "ordered_items_retained_without_choice_or_answer_text_change": 10,
            "manual_adjudication": "For both arms, inspect every unchanged item for a unique supported exact key, distinct answer meanings under the stem, and a coherent explanation of that final stem without abandoned drafting. Record any uncertainty; do not repair or exclude failures. Compare arms using the frozen criteria, not only chosen examples.",
        },
        "failure_policy": "Stop every remaining dispatch on provider, non-end_turn, strict JSON/schema or adapter failure. Count/bounds/semantic failures remain in results without repair; independent remaining jobs may still run. Maximum four calls, one SDK attempt each, no fallback, repair, replacement capture or additional judge calls.",
        "interpretation": "Two paired prompts, counterbalanced arm order, are a bounded causal probe rather than a deterministic guarantee or population estimate. Content can differ at temperature0.2. Baseline grammar may be warm from prior calls while ordered grammar may be cold; provider cache state is unobservable. No solver/final reviewer, question-bank write, deployment or production serializer change occurs. Sanitizer admission is not factual verification.",
        "jobs": jobs,
    }
    path = HERE / "plan.json"
    author.save(path, plan, exclusive=True)
    print(json.dumps({"plan": str(path), "plan_sha256": sha(path.read_bytes()), "maximum_calls": 4,
                      "arms": [job["arm"] for job in jobs], "source_sha256": plan["source_sha256"]}))


class Recorder:
    def __init__(self, client, capture, path, job):
        self.client, self.capture, self.path, self.job = client, capture, path, job

    def converse(self, **logical_request):
        if logical_request != self.job["logical_request"]:
            raise RuntimeError("Current logical author request differs from frozen plan.")
        request = ordered_request(logical_request) if self.job["arm"] == "ordered" else copy.deepcopy(logical_request)
        if request != self.job["provider_request"] or author.digest(request) != self.job["provider_request_sha256"]:
            raise RuntimeError("Dispatch request differs from frozen plan.")
        if len(self.capture["calls"]) >= 4:
            raise RuntimeError("Four-dispatch ceiling reached.")
        call = {"index": self.job["index"], "goal_id": self.job["goal_id"], "arm": self.job["arm"],
                "request": request, "started_at": datetime.now(timezone.utc).isoformat(), "dispatch_attempted": True}
        self.capture["calls"].append(call)
        author.save(self.path, self.capture)
        started = time.monotonic()
        try:
            response = self.client.converse(**request)
            call["response"] = response
            if response.get("stopReason") != "end_turn":
                raise ValueError("Provider did not end normally.")
            return response
        except Exception as error:
            call["provider_error_type"] = type(error).__name__
            call["provider_error_code"] = getattr(error, "response", {}).get("Error", {}).get("Code")
            raise
        finally:
            call["elapsed_seconds"] = round(time.monotonic() - started, 3)
            author.save(self.path, self.capture)


def execute(expected_hash):
    encoded = (HERE / "plan.json").read_bytes()
    if sha(encoded) != expected_hash:
        raise RuntimeError("Plan checksum mismatch.")
    plan = json.loads(encoded)
    if hashes() != plan["source_sha256"]:
        raise RuntimeError("Source changed after plan freeze.")
    if sha((PRIOR / "plan.json").read_bytes()) != plan["prior_plan_sha256"] or sha((PRIOR / "capture.json").read_bytes()) != plan["prior_capture_sha256"]:
        raise RuntimeError("Prior frozen evidence changed.")
    path = HERE / "capture.json"
    capture = {"plan_sha256": expected_hash, "started_at": datetime.now(timezone.utc).isoformat(),
               "dependencies": {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__},
               "status": "preflight", "calls": []}
    author.save(path, capture, exclusive=True)
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
        budget = ProviderCallBudget(4)
        capture["status"] = "running"
        with patch.dict(os.environ, plan["environment"]):
            for job in plan["jobs"]:
                print(f"Dispatch {job['index'] + 1}/4: {job['goal_id']} {job['arm']}", flush=True)
                metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
                result = _generate_with_bedrock(
                    job["normalized_request"], Recorder(client, capture, path, job), author.MODEL,
                    contract=author.CONTRACT, call_budget=budget, request_metrics=metrics,
                )
                call = capture["calls"][-1]
                raw = "\n".join(block["text"] for block in call["response"]["output"]["message"]["content"] if "text" in block)
                schema = json.loads(call["request"]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
                parsed = json.loads(raw)
                Draft202012Validator(schema).validate(parsed)
                analysis = author.inspect_items(json.loads(result), job["normalized_request"])
                for row, provider_item in zip(analysis["rows"], parsed["questions"], strict=True):
                    row["provider_field_order"] = list(provider_item)
                    row["prompt_choices_explanation_key_order"] = [key for key in provider_item if key in {"prompt", "choices", "explanation", "correctChoice"}] == ["prompt", "choices", "explanation", "correctChoice"]
                # Runtime observations describe the logical production schema;
                # request plus this hash records the actual ordered treatment.
                call.update(strict_native_adapter_valid=True, adapted_raw=result, metrics=metrics,
                            dispatched_schema_sha256=sha(call["request"]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"].encode()), analysis=analysis)
                author.save(path, capture)
                print(f"Completed {job['index'] + 1}/4: items={analysis['item_count']}, admitted={analysis['sanitizer_admitted_count']}", flush=True)
        capture["status"] = "complete"
    except Exception as error:
        capture.update(status="stopped_after_failure", error_type=type(error).__name__)
        if capture["calls"]:
            capture["calls"][-1]["stage_error_type"] = type(error).__name__
    finally:
        capture["finished_at"] = datetime.now(timezone.utc).isoformat()
        author.save(path, capture)
    print(json.dumps({"capture": str(path), "status": capture["status"], "calls": len(capture["calls"])}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--prepare", action="store_true")
    action.add_argument("--execute", metavar="PLAN_SHA256")
    arguments = parser.parse_args()
    prepare() if arguments.prepare else execute(arguments.execute)
