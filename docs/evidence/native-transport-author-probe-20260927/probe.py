"""One-call, read-only native author schema acceptance probe.

The request is the prior synthetic mapped first refill, reconstructed against
current source. It makes no bank, queue, deployment, or GitHub writes.
"""

import argparse
import copy
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

ROOT = Path(__file__).resolve().parents[3]
SERVICE = ROOT / "backend/bedrock-question-service"
sys.path.insert(0, str(SERVICE))

import native_output_contracts as native  # noqa: E402
import question_bank  # noqa: E402
import question_generation as generation  # noqa: E402
from evals import bounded_bedrock_capture as safe  # noqa: E402
from agreement_task_constructor import prepare_mapped_agreement_rows  # noqa: E402

HERE = Path(__file__).resolve().parent
PLAN = HERE / "plan.json"
CAPTURE = HERE / "capture.json"
PRIOR_PLAN = ROOT / "docs/evidence/mapped-refill-qualification-20260927/plan.json"
PRIOR_CAPTURE = ROOT / "docs/evidence/mapped-refill-qualification-20260927/capture.json"
SOURCE_COMMIT = "811ec0af4759c40731750165c3c5f0043a034e70"
ACCOUNT = "239342516379"
BEDROCK_ENDPOINT = "https://bedrock-runtime.us-east-1.amazonaws.com"
STS_ENDPOINT = "https://sts.us-east-1.amazonaws.com"
MODEL = "us.anthropic.claude-sonnet-4-6"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    return digest(path.read_bytes())


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True, allow_nan=False)


def write_new(path, value):
    with path.open("x", encoding="utf-8") as output:
        json.dump(value, output, indent=2, ensure_ascii=False)
        output.write("\n")


def update_capture(value):
    temporary = CAPTURE.with_suffix(".writing")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    temporary.replace(CAPTURE)


def current_source():
    return subprocess.check_output(("git", "rev-parse", "HEAD"), cwd=ROOT,
                                   text=True).strip() == SOURCE_COMMIT


def build():
    require(current_source(), "Source commit changed.")
    prior = safe.strict_json(PRIOR_PLAN.read_text())
    prior_capture = safe.strict_json(PRIOR_CAPTURE.read_text())
    previous = prior_capture["calls"]
    # The five reviewed seed questions are in the successful prior capture,
    # rather than the failed refill capture.
    seed = safe.strict_json((ROOT / "docs/evidence/mapped-quant-families-qualification-20260927/capture.json").read_text())
    questions = seed["jobs"][0]["returned"]
    require(len(questions) == 5 and len(previous) == 3, "Prior evidence changed.")
    request = copy.deepcopy(prior["bank"]["refill_request"])
    stored = [{"questionJSON": {"S": json.dumps(question)}} for question in questions]
    request["_mappedQuantitativeVariantIdentities"] = (
        question_bank._mapped_quantitative_variant_history(stored)
    )
    require(len(request["_mappedQuantitativeVariantIdentities"]) == 3,
            "Numeric bank projection changed.")
    environment = copy.deepcopy(prior["environment"])
    environment["BEDROCK_MODEL_ID"] = MODEL
    with patch.dict(os.environ, environment, clear=True):
        assignments = generation._mapped_fixed_slot_assignments(
            request, "constructed_quantitative", "array",
        )
        require(assignments is not None, "Five-slot assignment changed.")
        require(generation._mapped_agreement_route(request, assignments)
                and generation._mapped_quantitative_family_route(request, assignments, True),
                "Mapped route is not selected.")
        contract = generation._mapped_author_contract(request, assignments, True, True)
        config = native.native_output_config(contract)
        schema = config["textFormat"]["structure"]["jsonSchema"]["schema"]
        Draft202012Validator.check_schema(json.loads(schema))
        system = native.native_prompt(generation._system_prompt(), contract)
        user = generation._user_prompt(request)
        wire = {
            "modelId": MODEL,
            "system": [{"text": system}],
            "messages": [{"role": "user", "content": [{"text": user}]}],
            "outputConfig": config,
            "inferenceConfig": {"maxTokens": 16000},
            "additionalModelRequestFields": {
                "thinking": {"type": "adaptive"},
                "output_config": {"effort": "high"},
            },
        }
    offline = boto3.Session(aws_access_key_id="offline", aws_secret_access_key="offline",
                            region_name="us-east-1").client("bedrock-runtime", endpoint_url=BEDROCK_ENDPOINT)
    validate_parameters(wire, offline.meta.service_model.operation_model("Converse").input_shape)
    sources = {str(path.relative_to(ROOT)): file_digest(path)
               for path in sorted(SERVICE.glob("*.py"))}
    return {
        "source_commit": SOURCE_COMMIT,
        "source_hashes": sources,
        "harness_sha256": file_digest(Path(__file__)),
        "prior_plan_sha256": file_digest(PRIOR_PLAN),
        "prior_capture_sha256": file_digest(PRIOR_CAPTURE),
        "author_contract": contract.name,
        "transport_schema_name": contract.transport_name,
        "schema_bytes": len(schema.encode()),
        "schema_sha256": digest(schema.encode()),
        "wire_sha256": digest(canonical(wire).encode()),
        "request_sha256": digest(canonical(request).encode()),
        "limits": {"sts_calls": 1, "converse_calls": 1, "sdk_attempts": 1,
                   "read_timeout_seconds": 70, "connect_timeout_seconds": 3,
                   "deadline_seconds": 120, "no_fallback_or_retry": True},
    }, wire, contract, request


def freeze():
    require(not PLAN.exists() and not CAPTURE.exists(), "Probe already frozen or executed.")
    plan, _, _, _ = build()
    write_new(PLAN, plan)
    return {"plan_sha256": file_digest(PLAN), "contract": plan["author_contract"],
            "schema_sha256": plan["schema_sha256"], "schema_bytes": plan["schema_bytes"],
            "transport_schema_name": plan["transport_schema_name"], "max_converse_calls": 1}


def checked_plan(expected):
    require(PLAN.exists() and file_digest(PLAN) == expected, "Frozen plan hash mismatch.")
    plan, wire, contract, request = build()
    require(safe.strict_json(PLAN.read_text()) == plan, "Frozen source or request drifted.")
    return plan, wire, contract, request


def execute(expected):
    require(not CAPTURE.exists(), "No probe resume or second call permitted.")
    plan, wire, contract, request = checked_plan(expected)
    started = time.monotonic()
    capture = {"plan_sha256": expected, "status": "setup", "sts_calls": 0,
               "converse_calls": 0, "author_response": None}
    write_new(CAPTURE, capture)
    secrets = ()
    try:
        require(not any(os.environ.get(key) for key in
                        ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN")),
                "Inherited credential override present.")
        session, secrets = safe.credential_session()
        sts = session.client("sts", endpoint_url=STS_ENDPOINT,
                             config=Config(connect_timeout=3, read_timeout=10,
                                           retries={"total_max_attempts": 1, "mode": "standard"}))
        capture["sts_calls"] = 1
        update_capture(capture)
        require(sts.get_caller_identity()["Account"] == ACCOUNT, "Wrong AWS account.")
        require(time.monotonic() - started < 20, "Identity setup exhausted deadline.")
        bedrock = session.client("bedrock-runtime", endpoint_url=BEDROCK_ENDPOINT,
                                 config=Config(connect_timeout=3, read_timeout=70,
                                               retries={"total_max_attempts": 1, "mode": "standard"}))
        require(bedrock.meta.endpoint_url == BEDROCK_ENDPOINT
                and bedrock.meta.config.retries.get("total_max_attempts") == 1,
                "Bedrock transport drifted.")
        validate_parameters(wire, bedrock.meta.service_model.operation_model("Converse").input_shape)
        require(digest(canonical(wire).encode()) == plan["wire_sha256"], "Author wire drifted.")
        capture["converse_calls"] = 1
        capture["status"] = "dispatched"
        update_capture(capture)
        response = bedrock.converse(**wire)
        retained, omitted = safe.safe_response(response, secrets)
        capture["author_response"] = retained
        capture["reasoning_blocks_omitted"] = omitted
        content = retained["output"]["message"]["content"]
        require(len(content) == 1, "Author text cardinality changed.")
        adapted = json.loads(native.adapt_native_response(content[0]["text"], contract))
        rows, math_proof, agreement_proof, failures = prepare_mapped_agreement_rows(
            adapted, contract,
            existing_prompts=tuple(request["existingPrompts"]),
            blocked_variant_identities=tuple(request["_agreementVariantIdentities"]),
            blocked_quantitative_variant_identities=tuple(request["_mappedQuantitativeVariantIdentities"]),
            blocked_stem_fingerprints=tuple(request["blockedStemFingerprints"]),
            stem_fingerprint_version=request["stemFingerprintVersion"],
        )
        capture["offline_compilation"] = {
            "rows": len(rows), "numeric_proofs": len(math_proof),
            "english_proofs": len(agreement_proof), "failures": failures,
        }
        capture["status"] = "completed"
    except Exception as error:
        capture["status"] = "failed"
        capture["error"] = safe.safe_error(error, secrets)
    finally:
        capture["elapsed_seconds"] = round(time.monotonic() - started, 3)
        capture["within_deadline"] = capture["elapsed_seconds"] <= 120
        update_capture(capture)
    return {"status": capture["status"], "sts_calls": capture["sts_calls"],
            "converse_calls": capture["converse_calls"],
            "elapsed_seconds": capture["elapsed_seconds"],
            "offline_compilation": capture.get("offline_compilation"),
            "capture_sha256": file_digest(CAPTURE)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("freeze", "check", "execute"))
    parser.add_argument("--plan-sha256")
    args = parser.parse_args()
    if args.mode == "freeze":
        result = freeze()
    else:
        require(args.plan_sha256, "Exact plan SHA required.")
        checked_plan(args.plan_sha256)
        result = ({"status": "ready", "plan_sha256": args.plan_sha256}
                  if args.mode == "check" else execute(args.plan_sha256))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
