"""One-shot, three-call, synthetic-bank mapped refill qualification."""

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

import boto3
from botocore.config import Config
from botocore.validate import validate_parameters
from jsonschema import Draft202012Validator

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = ROOT / "backend/bedrock-question-service"
sys.path.insert(0, str(SERVICE))

import native_output_contracts as native  # noqa: E402
import question_bank  # noqa: E402
import question_generation as runtime  # noqa: E402
from question_bank_common import _stem_fingerprint  # noqa: E402
from evals import bounded_bedrock_capture as safe  # noqa: E402

SOURCE_COMMIT = "9105289100fdccec807a2d99c33878bfd276b6e0"
PRIOR = ROOT / "docs/evidence/mapped-quant-families-qualification-20260927"
PRIOR_PLAN_SHA = "4a26cee369744fd7f6aed2e60522608b40faa0d17a99d3f65a6f493e872ad6ce"
PRIOR_CAPTURE_SHA = "f9e81f34f19e4829b49587c3919d77bae2595784064e063631d3515b61e009fa"
PLAN = HERE / "plan.json"
CAPTURE = HERE / "capture.json"
BEDROCK_ENDPOINT = "https://bedrock-runtime.us-east-1.amazonaws.com"
STS_ENDPOINT = "https://sts.us-east-1.amazonaws.com"
ACCOUNT = "239342516379"
STAGES = ("question_author_constructed_mapped_families_v1_n5_56d4204a9b0238f6",
          "complete_choice_solver_v5_n2", "authored_solution_reviewer_v3_n5")
HISTORY_FIELDS = ("existingPrompts", "existingQuestionCoverage", "reportedPrompts",
                  "blockedStemFingerprints")


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_sha(path):
    return sha(path.read_bytes())


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True, allow_nan=False)


def write_new(path, value):
    with path.open("x", encoding="utf-8") as output:
        json.dump(value, output, indent=2, ensure_ascii=False)
        output.write("\n")


def update_capture(value):
    temporary = CAPTURE.with_suffix(".writing")
    with temporary.open("w", encoding="utf-8") as output:
        json.dump(value, output, indent=2, ensure_ascii=False)
        output.write("\n")
    temporary.replace(CAPTURE)


def checked_prior():
    require(file_sha(PRIOR / "plan.json") == PRIOR_PLAN_SHA, "Prior plan drift.")
    require(file_sha(PRIOR / "capture.json") == PRIOR_CAPTURE_SHA, "Prior capture drift.")
    old_plan = safe.strict_json((PRIOR / "plan.json").read_text())
    old_capture = safe.strict_json((PRIOR / "capture.json").read_text())
    require(old_capture["plan_sha256"] == PRIOR_PLAN_SHA
            and old_capture["summary"]["returned_questions"] == 5
            and old_capture["summary"]["attempted_calls"] == 3
            and old_capture["jobs"][0]["returned_slot_ordinals"] == list(range(5)),
            "Prior pass is not the reviewed five-slot bank seed.")
    return old_plan, old_capture


def stored_items(questions):
    return [{"state": {"S": "ready"},
             "questionJSON": {"S": json.dumps(question, ensure_ascii=False)},
             "createdAt": {"N": str(index)},
             "sk": {"S": f"QUESTION#{index:03d}"}}
            for index, question in enumerate(questions)]


def worker_request(base, stored):
    request = copy.deepcopy(base)
    request["targetCount"] = 5
    request["requestedSkillAllocation"] = question_bank._worker_skill_allocation(
        request, stored, desired_count=11, low_watermark=0, target_count=5)
    request["requestedObjectiveAllocation"] = question_bank._worker_objective_allocation(
        request, stored, desired_count=11, low_watermark=0,
        requested_skill_allocation=request["requestedSkillAllocation"])
    recent = [question_bank._question_from_item(item)
              for item in question_bank._recent_question_items(stored, 30)]
    request["existingPrompts"] = list(dict.fromkeys(
        request["existingPrompts"] + [item.get("prompt", "") for item in recent]))[-30:]
    request["existingQuestionCoverage"] = (
        request["existingQuestionCoverage"] + [
            {"topic": item.get("topic", ""), "skillID": item.get("skillID", ""),
             "objectiveID": item.get("objectiveID", ""),
             "objective": item.get("objective", ""), "prompt": item.get("prompt", ""),
             "expectedAnswer": item.get("expectedAnswer", ""),
             "choices": item.get("choices", []), "difficulty": item.get("difficulty", 1)}
            for item in recent])[-30:]
    request["_agreementVariantIdentities"] = question_bank._agreement_variant_history(stored)
    return request


def build_plan():
    require(subprocess.check_output(("git", "rev-parse", "HEAD"), cwd=ROOT, text=True).strip()
            == SOURCE_COMMIT, "Source commit changed.")
    old_plan, old_capture = checked_prior()
    previous = old_capture["jobs"][0]["returned"]
    initial = worker_request(old_plan["jobs"][0]["request"], [])
    refill = worker_request(old_plan["jobs"][0]["request"], stored_items(previous))
    # Model a client report accompanying the refill. Worker-derived bank history
    # remains the five real prior returned rows above.
    refill["reportedPrompts"] = [previous[1]["prompt"]]
    refill["blockedStemFingerprints"] = [
        _stem_fingerprint(previous[index]["prompt"], version=1) for index in (0, 3)]
    require(initial["requestedSkillAllocation"] == refill["requestedSkillAllocation"]
            == {"11111111-1111-4111-8111-111111111111": 3,
                "22222222-2222-4222-8222-222222222222": 2},
            "Worker changed the required 3:2 allocation.")
    require(initial["requestedObjectiveAllocation"] == refill["requestedObjectiveAllocation"]
            and len(refill["existingPrompts"]) == 5
            and len(refill["existingQuestionCoverage"]) == 5
            and len(refill["_agreementVariantIdentities"]) == 2,
            "Synthetic bank history or objective allocation changed.")
    scope = runtime._mapped_author_refill_scope_sha256(initial)
    require(runtime._mapped_author_refill_scope_sha256(refill) == scope
            and runtime._mapped_author_scope_sha256(initial)
            != runtime._mapped_author_scope_sha256(refill),
            "Refill scope does not distinguish static from evolving history.")
    environment = copy.deepcopy(old_plan["environment"])
    environment.update({
        "QUESTION_MAPPED_FIXED_FIVE_SCOPE_MODE": "refill_history",
        "QUESTION_MAPPED_FIXED_FIVE_SCOPE_SHA256": scope,
        "MAX_PROVIDER_CALLS_PER_REQUEST": "3",
        "GENERATION_ATTEMPTS": "1",
        "BEDROCK_READ_TIMEOUT_SECONDS": "70",
    })
    with patch.dict(os.environ, environment, clear=True):
        assignments = runtime._mapped_fixed_slot_assignments(
            refill, "constructed_quantitative", "array")
        require(assignments is not None
                and runtime._mapped_agreement_route(refill, assignments)
                and runtime._mapped_quantitative_family_route(refill, assignments, True),
                "Refill did not select both closed-family routes.")
        contract = runtime._mapped_author_contract(refill, assignments, True, True)
        author_config = native.native_output_config(contract)
        schema = author_config["textFormat"]["structure"]["jsonSchema"]["schema"]
        Draft202012Validator.check_schema(json.loads(schema))
        user = runtime._user_prompt(refill)
        system = native.native_prompt(runtime._system_prompt(), contract)
        wire = {"modelId": environment["BEDROCK_MODEL_ID"],
                "system": [{"text": system}],
                "messages": [{"role": "user", "content": [{"text": user}]}],
                "outputConfig": author_config,
                "inferenceConfig": {"maxTokens": 16000},
                "additionalModelRequestFields": {"thinking": {"type": "adaptive"},
                                                 "output_config": {"effort": "high"}}}
        offline = boto3.Session(aws_access_key_id="offline", aws_secret_access_key="offline",
                                region_name="us-east-1").client(
            "bedrock-runtime", endpoint_url=BEDROCK_ENDPOINT)
        validate_parameters(wire, offline.meta.service_model.operation_model("Converse").input_shape)
    sources = {str(path.relative_to(ROOT)): file_sha(path) for path in sorted(SERVICE.glob("*.py"))}
    sources[str((SERVICE / "evals/bounded_bedrock_capture.py").relative_to(ROOT))] = file_sha(
        SERVICE / "evals/bounded_bedrock_capture.py")
    return {"state": "frozen", "source_commit": SOURCE_COMMIT,
            "source_hashes": sources, "harness_sha256": file_sha(Path(__file__)),
            "prior_plan_sha256": PRIOR_PLAN_SHA, "prior_capture_sha256": PRIOR_CAPTURE_SHA,
            "bank": {"desired_count": 11, "low_watermark": 0, "history_rows": 5,
                     "initial_request": initial, "refill_request": refill,
                     "static_scope_sha256": scope,
                     "full_initial_scope_sha256": runtime._mapped_author_scope_sha256(initial),
                     "full_refill_scope_sha256": runtime._mapped_author_scope_sha256(refill)},
            "environment": environment,
            "author": {"contract_name": native.contract_metadata(contract)["name"],
                       "schema_sha256": sha(schema.encode()),
                       "system_sha256": sha(system.encode()),
                       "user_sha256": sha(user.encode()),
                       "wire_sha256": sha(canonical(wire).encode())},
            "limits": {"new_provider_calls": 3, "sdk_attempts_per_call": 1,
                       "generation_attempts": 1, "fallback_model": "",
                       "connect_timeout_seconds": 3, "read_timeout_seconds": 70,
                       "execute_deadline_seconds": 240, "sts_identity_requests": 1,
                       "resume_or_top_up": False},
            "expected_stages": list(STAGES),
            "criteria": {"returned_original_slots": [0, 1, 2, 3, 4],
                         "quantitative_policy_8": 3, "agreement_policy_10": 2,
                         "exact_keys_choices_feedback": True,
                         "cross_bank_stem_reuse": 0,
                         "blind_minimum_difficulty": 2,
                         "near_duplicates_reported_separately": True}}


def checked_plan(expected_sha):
    require(PLAN.is_file() and file_sha(PLAN) == expected_sha, "Frozen plan SHA mismatch.")
    plan = safe.strict_json(PLAN.read_text())
    require(plan == build_plan(), "Source, harness, or refill scope drifted.")
    for relative, expected in plan["source_hashes"].items():
        require(file_sha(ROOT / relative) == expected, "Runtime file changed.")
    return plan


def freeze():
    require(not PLAN.exists() and not CAPTURE.exists(), "Trial already frozen or executed.")
    plan = build_plan()
    write_new(PLAN, plan)
    return {"plan_sha256": file_sha(PLAN), "source_commit": SOURCE_COMMIT,
            "static_scope_sha256": plan["bank"]["static_scope_sha256"],
            "author_wire_sha256": plan["author"]["wire_sha256"],
            "max_new_provider_calls": 3, "sdk_attempts_per_call": 1,
            "ready": True}


class Deadline:
    def __init__(self):
        self.started = time.monotonic()

    def get_remaining_time_in_millis(self):
        return max(0, int((240 - (time.monotonic() - self.started)) * 1000))


def credentials():
    require(not any(key.upper().startswith("AWS_ENDPOINT_URL") and value
                    for key, value in os.environ.items()), "AWS endpoint override present.")
    for key in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"):
        require(not os.environ.get(key), "Inherited AWS credential override present.")
    safe.CREDENTIAL_COMMAND = ("aws", "configure", "export-credentials", "--profile", "default",
                               "--format", "process")
    data = safe.strict_json(safe.export_credentials().decode("utf-8"))
    expiry = datetime.fromisoformat(data["Expiration"].replace("Z", "+00:00"))
    require((expiry - datetime.now(timezone.utc)).total_seconds() >= 300,
            "Credential snapshot expires before trial deadline.")
    secrets = tuple(data[key] for key in ("AccessKeyId", "SecretAccessKey", "SessionToken")
                    if data.get(key))
    session = boto3.Session(aws_access_key_id=data["AccessKeyId"],
                            aws_secret_access_key=data["SecretAccessKey"],
                            aws_session_token=data.get("SessionToken"), region_name="us-east-1")
    return session, secrets


def execute(expected_sha):
    require(not CAPTURE.exists(), "No resume or second execution permitted.")
    plan = checked_plan(expected_sha)
    deadline = Deadline()
    capture = {"plan_sha256": expected_sha, "source_commit": SOURCE_COMMIT,
               "status": "setup", "attempted_calls": 0, "reserved_calls": 0,
               "calls": [], "returned": [], "metrics": {},
               "identity": {"status": "unattempted", "account": ACCOUNT}}
    write_new(CAPTURE, capture)
    secrets = ()
    try:
        session, secrets = credentials()
        sts = session.client("sts", endpoint_url=STS_ENDPOINT,
                             config=Config(connect_timeout=3, read_timeout=10,
                                           retries={"total_max_attempts": 1, "mode": "standard"}))
        require(sts.meta.endpoint_url == STS_ENDPOINT
                and sts.meta.config.retries.get("total_max_attempts") == 1,
                "STS transport drift.")
        capture["identity"]["status"] = "attempted"
        update_capture(capture)
        identity = sts.get_caller_identity()
        require(identity["Account"] == ACCOUNT, "Wrong AWS account.")
        capture["identity"]["status"] = "verified"
        update_capture(capture)
        require(deadline.get_remaining_time_in_millis() >= 220_000,
                "Credential or identity setup exhausted trial budget.")
        bedrock = session.client("bedrock-runtime", endpoint_url=BEDROCK_ENDPOINT,
                                 config=Config(connect_timeout=3, read_timeout=70,
                                               retries={"total_max_attempts": 1, "mode": "standard"}))
        require(bedrock.meta.endpoint_url == BEDROCK_ENDPOINT
                and bedrock.meta.config.retries.get("total_max_attempts") == 1
                and bedrock.meta.config.read_timeout == 70,
                "Bedrock transport drift.")
        class Recorder:
            meta = bedrock.meta

            def converse(self, **wire):
                require(capture["reserved_calls"] == len(capture["calls"]) + 1
                        and len(capture["calls"]) < 3, "Unreserved provider dispatch.")
                index = len(capture["calls"])
                stage = wire["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["name"]
                require(stage == STAGES[index], "Unexpected provider stage.")
                validate_parameters(wire, bedrock.meta.service_model.operation_model("Converse").input_shape)
                if index == 0:
                    require(sha(canonical(wire).encode()) == plan["author"]["wire_sha256"],
                            "Author wire differs from frozen plan.")
                entry = {"stage": stage, "request": wire, "attempted": True,
                         "sdk_attempts": 1, "response": None}
                capture["calls"].append(entry)
                capture["attempted_calls"] += 1
                update_capture(capture)
                try:
                    response = bedrock.converse(**wire)
                    retained, omitted = safe.safe_response(response, secrets)
                    require(not any(secret and secret in json.dumps(retained, ensure_ascii=False)
                                    for secret in secrets), "Credential appeared in visible response.")
                    entry["response"] = retained
                    entry["reasoning_blocks_omitted"] = omitted
                    update_capture(capture)
                    return response
                except Exception as error:
                    entry["error"] = safe.safe_error(error, secrets)
                    update_capture(capture)
                    raise
        def reserve():
            require(capture["reserved_calls"] < 3, "Provider reservation ceiling reached.")
            capture["reserved_calls"] += 1
            update_capture(capture)
        metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
        with patch.dict(os.environ, plan["environment"], clear=True):
            result = runtime._generate_sanitized_questions(
                copy.deepcopy(plan["bank"]["refill_request"]), Recorder(),
                runtime.ProviderCallBudget(3, context=deadline, reserve_call=reserve), metrics)
        capture["returned"] = result
        capture["metrics"] = metrics
        capture["status"] = "completed_pending_review"
    except Exception as error:
        capture["status"] = "failed"
        capture["error"] = safe.safe_error(error, secrets)
    finally:
        capture["elapsed_seconds"] = round(time.monotonic() - deadline.started, 6)
        capture["within_deadline"] = capture["elapsed_seconds"] <= 240
        capture["token_usage"] = {
            "input_tokens": sum(call.get("response", {}).get("usage", {}).get("inputTokens", 0)
                                for call in capture["calls"]),
            "output_tokens": sum(call.get("response", {}).get("usage", {}).get("outputTokens", 0)
                                 for call in capture["calls"])}
        update_capture(capture)
    return {"status": capture["status"], "attempted_calls": capture["attempted_calls"],
            "returned_questions": len(capture["returned"]),
            "elapsed_seconds": capture["elapsed_seconds"],
            "token_usage": capture["token_usage"],
            "capture_sha256": file_sha(CAPTURE)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("freeze", "check", "execute"))
    parser.add_argument("--plan-sha256")
    args = parser.parse_args()
    if args.mode == "freeze":
        print(json.dumps(freeze(), indent=2))
    else:
        require(bool(args.plan_sha256), "Exact plan SHA required.")
        plan = checked_plan(args.plan_sha256)
        if args.mode == "check":
            print(json.dumps({"status": "ready", "plan_sha256": file_sha(PLAN),
                              "history_rows": plan["bank"]["history_rows"],
                              "scope_sha256": plan["bank"]["static_scope_sha256"],
                              "max_new_provider_calls": 3,
                              "sdk_attempts_per_call": 1}, indent=2))
        else:
            print(json.dumps(execute(args.plan_sha256), indent=2))


if __name__ == "__main__":
    main()
