"""One-shot English repertoire native author probe; no worker or bank writes."""

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from unittest.mock import patch

import boto3
import botocore
from botocore.config import Config
from botocore.validate import validate_parameters
from jsonschema import Draft202012Validator

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = ROOT / "backend/bedrock-question-service"
sys.path.insert(0, str(SERVICE))

import native_output_contracts as native  # noqa: E402
import question_generation as generation  # noqa: E402
from agreement_task_constructor import prepare_mapped_agreement_rows  # noqa: E402
from evals import bounded_bedrock_capture as safe  # noqa: E402

SOURCE_COMMIT = "3456177f1f18cb6658ab1fdf78aaadc5df04b202"
PREVIOUS_PLAN = ROOT / "docs/evidence/mapped-full-worker-next-prep-20260927/plan.json"
PREVIOUS_CAPTURE = ROOT / "docs/evidence/mapped-full-worker-next-prep-20260927/capture.json"
PREVIOUS_CAPTURE_SHA256 = "1ab308db5ea2aeedea0655a7886886c4851fbfa9278b22b5c9413cacaf45af4a"
REQUEST = HERE / "request.json"
PLAN = HERE / "plan.json"
CAPTURE = HERE / "capture.json"
REVIEW_LOCK = HERE / "review-approval.json"
ACCOUNT = "239342516379"
MODEL = "us.anthropic.claude-sonnet-4-6"
BEDROCK_ENDPOINT = "https://bedrock-runtime.us-east-1.amazonaws.com"
STS_ENDPOINT = "https://sts.us-east-1.amazonaws.com"
MAX_SECONDS = 120


class DeadlineExceeded(BaseException):
    """Escape SDK reads when the whole execution wall-clock bound expires."""


def deadline_alarm(_signal, _frame):
    raise DeadlineExceeded("Whole author probe deadline expired.")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def file_sha(path):
    return sha(path.read_bytes())


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=True, allow_nan=False,
                      separators=(",", ":")).encode()


def write_new(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2, ensure_ascii=True, allow_nan=False)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())


def update_capture(value):
    temporary = CAPTURE.with_suffix(".partial")
    write_new(temporary, value)
    os.replace(temporary, CAPTURE)


def source_guard():
    require(subprocess.run(("git", "merge-base", "--is-ancestor", SOURCE_COMMIT, "HEAD"),
                           cwd=ROOT, check=False, capture_output=True).returncode == 0,
            "The pinned source commit is not an ancestor.")
    require(Path(generation.__file__).resolve().parent == SERVICE.resolve(),
            "Wrong service checkout imported.")
    require(file_sha(PREVIOUS_CAPTURE) == PREVIOUS_CAPTURE_SHA256,
            "Predecessor 5/5 capture changed.")


def fake_english_repertoire(contract, wire, request):
    """Run the real adapter/compiler against a fake Converse result, without sockets."""
    tasks = {"questions": {
        "0": {"family": "fraction_product_complement", "a": 4, "b": 6},
        "1": {"family": "bounded_rational_equation", "a": 4, "b": 7},
        "2": {"family": "bounded_solution_count", "a": 5, "b": 8},
        "3": {"kind": "agreement_pair_v1", "scene": "partitive_paint", "order": "plural_first"},
        "4": {"kind": "agreement_pair_v1", "scene": "compound_guides", "order": "singular_first"},
    }}
    schema = json.loads(wire["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
    Draft202012Validator(schema).validate(tasks)

    class FakeProvider:
        def __init__(self):
            self.calls = 0
            self.response = None

        def converse(self, **received):
            require(received == wire, "Fake provider did not receive the frozen author wire.")
            self.calls += 1
            self.response = {"stopReason": "end_turn", "output": {"message": {"content": [
                {"text": json.dumps(tasks, separators=(",", ":"))}
            ]}}}
            return self.response

    provider = FakeProvider()
    # Exercise the production wire builder, not merely this probe's duplicate.
    generated = generation._generate_with_bedrock(
        normalized_request=request, bedrock_client=provider, model_id=MODEL,
        contract=contract)
    require(safe.strict_json(generated) == safe.strict_json(
        native.adapt_native_response(json.dumps(tasks, separators=(",", ":")), contract)),
        "Production native adapter disagreed with the probe adapter.")
    require(provider.calls == 1, "Production author made more than one fake-provider call.")
    result = compile_author_response(provider.response, contract)
    require(result["offline_compilation"] == {
        "rows": 5, "numeric_proofs": 3, "english_proofs": 2, "failures": []},
        "Offline fake provider English repertoire compile failed.")
    require(result["chosen_scenes"] == {"3": "partitive_paint", "4": "compound_guides"},
            "Fake provider did not exercise both target English constructions.")
    return {"source": "fake_provider_socket_free_not_live", **result}


def compile_author_response(response, contract):
    """Shared live/fake parser; adapter yields a list, indexed by integers."""
    require(response["stopReason"] in {"end_turn", "stop_sequence"},
            "Author response did not end normally.")
    content = response["output"]["message"]["content"]
    require(len(content) == 1 and set(content[0]) == {"text"},
            "Author text cardinality changed.")
    raw = safe.strict_json(content[0]["text"])
    schema = json.loads(native.native_output_config(contract)["textFormat"]["structure"]["jsonSchema"]["schema"])
    Draft202012Validator(schema).validate(raw)
    adapted = safe.strict_json(native.adapt_native_response(content[0]["text"], contract))
    tasks = adapted["questions"]
    require(type(tasks) is list and len(tasks) == 5,
            "Native adapter did not return the exact five-slot list.")
    rows, numerical, english, failures = prepare_mapped_agreement_rows(adapted, contract)
    return {"chosen_families": {str(i): raw["questions"][str(i)]["family"] for i in range(3)},
            "chosen_scenes": {str(i): raw["questions"][str(i)]["scene"] for i in (3, 4)},
            "offline_compilation": {"rows": len(rows), "numeric_proofs": len(numerical),
                                    "english_proofs": len(english), "failures": failures}}


def build():
    source_guard()
    previous = safe.strict_json(PREVIOUS_PLAN.read_text())
    request = safe.strict_json(REQUEST.read_text())
    require(request["targetCount"] == 5 and request["requestedSkillAllocation"] == {
        "11111111-1111-4111-8111-111111111111": 3,
        "22222222-2222-4222-8222-222222222222": 2},
        "Synthetic original 3:2 request changed.")
    environment = copy.deepcopy(previous["environment"])
    require(environment["BEDROCK_MODEL_ID"] == MODEL
            and environment["BEDROCK_FALLBACK_MODEL_ID"] == ""
            and environment["QUESTION_AUTHOR_CARDINALITY_CONTRACT"] == "array",
            "Author environment changed.")
    with patch.dict(os.environ, environment, clear=True):
        assignments = generation._mapped_fixed_slot_assignments(
            request, "constructed_quantitative", "array")
        require(assignments is not None
                and generation._mapped_agreement_route(request, assignments)
                and generation._mapped_quantitative_family_route(request, assignments, True),
                "Expected mapped route was not selected.")
        contract = generation._mapped_author_contract(request, assignments, True, True)
        config = native.native_output_config(contract)
        schema = config["textFormat"]["structure"]["jsonSchema"]["schema"]
        Draft202012Validator.check_schema(json.loads(schema))
        require(contract.name.startswith("question_author_constructed_mapped_families_v10_n5_"),
                "Mapped author contract version changed.")
        properties = json.loads(schema)["properties"]["questions"]["properties"]
        require("fraction_product_complement" in properties["0"]["properties"]["family"]["enum"]
                and "bounded_solution_count" in properties["2"]["properties"]["family"]["enum"],
                "Numeric family labels are absent from the native schema.")
        require("partitive_paint" in properties["3"]["properties"]["scene"]["enum"]
                and "compound_guides" in properties["4"]["properties"]["scene"]["enum"],
                "English partitive/each scenes are absent from the pinned slots.")
        system = native.native_prompt(generation._system_prompt(), contract)
        user = generation._user_prompt(request)
        wire = {"modelId": MODEL, "system": [{"text": system}],
                "messages": [{"role": "user", "content": [{"text": user}]}],
                "outputConfig": config, "inferenceConfig": {"maxTokens": 16000},
                "additionalModelRequestFields": {"thinking": {"type": "adaptive"},
                                                  "output_config": {"effort": "high"}}}
        scripted = fake_english_repertoire(contract, wire, request)
    offline = boto3.Session(aws_access_key_id="offline", aws_secret_access_key="offline",
                            region_name="us-east-1").client(
        "bedrock-runtime", endpoint_url=BEDROCK_ENDPOINT)
    validate_parameters(wire, offline.meta.service_model.operation_model("Converse").input_shape)
    source_paths = [*sorted(SERVICE.glob("*.py")), SERVICE / "requirements.txt",
                    SERVICE / "evals/bounded_bedrock_capture.py"]
    plan = {
        "state": "frozen", "trial_id": "english-partitive-each-native-author-20260927-01",
        "source_commit": SOURCE_COMMIT,
        "source_hashes": {str(path.relative_to(ROOT)): file_sha(path) for path in source_paths},
        "harness_sha256": file_sha(Path(__file__)),
        "request_sha256": file_sha(REQUEST),
        "normalized_request_sha256": sha(canonical(request)),
        "previous_successful_worker_plan_sha256": file_sha(PREVIOUS_PLAN),
        "previous_successful_worker_capture_sha256": PREVIOUS_CAPTURE_SHA256,
        "current_schema_bytes": len(schema.encode()),
        "current_schema_sha256": sha(schema.encode()),
        "author_contract": contract.name,
        "system_prompt_sha256": sha(system.encode()),
        "user_prompt_sha256": sha(user.encode()),
        "wire_sha256": sha(canonical(wire)),
        "environment": environment,
        "model": MODEL,
        "account": ACCOUNT,
        "endpoints": {"bedrock": BEDROCK_ENDPOINT, "sts": STS_ENDPOINT},
        "runtime": {"python": sys.version.split()[0], "boto3": boto3.__version__,
                    "botocore": botocore.__version__},
        "limits": {"original_jobs": 1, "original_slots": 5, "sts_calls": 1,
                   "converse_calls": 1, "sdk_attempts_per_call": 1,
                   "seconds_from_before_credential_export": MAX_SECONDS,
                   "hard_deadline_enforcement": "SIGALRM_ITIMER_REAL_one_shot",
                   "connect_timeout_seconds": 3, "read_timeout_seconds": 90,
                   "retry_fallback_topup": False,
                   "queue_bank_deploy_github_writes": False},
        "live_prompt_english_selection": "permitted_not_forced_exact_production_wire",
        "fake_provider_english_repertoire_result": scripted,
    }
    return plan, wire, contract, request


def checked(expected):
    require(PLAN.exists() and file_sha(PLAN) == expected, "Frozen plan SHA mismatch.")
    plan, wire, contract, request = build()
    require(safe.strict_json(PLAN.read_text()) == plan,
            "Source, schema, request, wire or harness drifted after freeze.")
    return plan, wire, contract, request


def freeze():
    require(not PLAN.exists() and not CAPTURE.exists(), "Trial already frozen or attempted.")
    plan, _, _, _ = build()
    write_new(PLAN, plan)
    return {"status": "frozen_offline", "plan_sha256": file_sha(PLAN),
            "harness_sha256": plan["harness_sha256"],
            "schema_sha256": plan["current_schema_sha256"],
            "schema_bytes": plan["current_schema_bytes"]}


def execute(expected):
    require(not CAPTURE.exists(), "This one-call trial cannot be resumed or retried.")
    plan, wire, contract, request = checked(expected)
    lock = safe.strict_json(REVIEW_LOCK.read_text())
    require(lock == {"plan_sha256": expected,
                     "harness_sha256": plan["harness_sha256"],
                     "root_go": True, "independent_go": True},
            "Exact-hash root and independent review is required before AWS.")
    started = time.monotonic()
    capture = {"plan_sha256": expected, "status": "setup", "sts_calls": 0,
               "converse_calls": 0, "author_response": None}
    write_new(CAPTURE, capture)
    secrets = ()
    old_alarm = signal.getsignal(signal.SIGALRM)
    signal.signal(signal.SIGALRM, deadline_alarm)
    try:
        remaining = MAX_SECONDS - (time.monotonic() - started)
        require(remaining > 0, "Execution deadline expired before credential export.")
        signal.setitimer(signal.ITIMER_REAL, remaining)
        require(not any(os.environ.get(key) for key in
                        ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN")),
                "Inherited credential override is present.")
        session, secrets = safe.credential_session()
        require(time.monotonic() - started < 20, "Credential setup exceeded the bound.")
        sts = session.client("sts", endpoint_url=STS_ENDPOINT,
                             config=Config(connect_timeout=3, read_timeout=10,
                                           retries={"total_max_attempts": 1, "mode": "standard"}))
        capture["sts_calls"] = 1
        update_capture(capture)
        require(sts.get_caller_identity()["Account"] == ACCOUNT, "Wrong AWS account.")
        bedrock = session.client("bedrock-runtime", endpoint_url=BEDROCK_ENDPOINT,
                                 config=Config(connect_timeout=3, read_timeout=90,
                                               retries={"total_max_attempts": 1, "mode": "standard"}))
        require(bedrock.meta.endpoint_url == BEDROCK_ENDPOINT
                and bedrock.meta.config.retries.get("total_max_attempts") == 1
                and sha(canonical(wire)) == plan["wire_sha256"],
                "Pinned transport or wire changed.")
        validate_parameters(wire, bedrock.meta.service_model.operation_model("Converse").input_shape)
        require(time.monotonic() - started < 30, "Identity setup exhausted dispatch budget.")
        capture["converse_calls"] = 1
        capture["status"] = "dispatched"
        update_capture(capture)
        response = bedrock.converse(**wire)
        require(time.monotonic() - started < MAX_SECONDS,
                "Author call exceeded the whole execution deadline.")
        retained, omitted = safe.safe_response(response, secrets)
        capture["author_response"] = retained
        capture["reasoning_blocks_omitted"] = omitted
        compiled = compile_author_response(retained, contract)
        capture.update(compiled)
        require(time.monotonic() - started < MAX_SECONDS,
                "Post-response compilation exceeded the whole execution deadline.")
        result = compiled["offline_compilation"]
        capture["status"] = ("completed" if result["rows"] == 5 and not result["failures"]
                             else "compile_failed")
    except DeadlineExceeded:
        capture["status"] = "deadline_exceeded"
        capture["error"] = {"type": "DeadlineExceeded", "code": "whole_execution_deadline"}
    except Exception as error:
        capture["status"] = "failed"
        capture["error"] = safe.safe_error(error, secrets)
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, old_alarm)
        elapsed = time.monotonic() - started
        capture["elapsed_seconds"] = round(elapsed, 3)
        capture["within_deadline"] = elapsed <= MAX_SECONDS and capture["status"] != "deadline_exceeded"
        update_capture(capture)
    return {"status": capture["status"], "sts_calls": capture["sts_calls"],
            "converse_calls": capture["converse_calls"],
            "elapsed_seconds": capture["elapsed_seconds"],
            "chosen_families": capture.get("chosen_families"),
            "chosen_scenes": capture.get("chosen_scenes"),
            "offline_compilation": capture.get("offline_compilation"),
            "capture_sha256": file_sha(CAPTURE)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("freeze", "check", "execute"))
    parser.add_argument("--plan-sha256")
    args = parser.parse_args()
    if args.mode == "freeze":
        result = freeze()
    else:
        require(args.plan_sha256, "Exact plan SHA required.")
        checked(args.plan_sha256)
        result = ({"status": "offline_ready", "plan_sha256": args.plan_sha256}
                  if args.mode == "check" else execute(args.plan_sha256))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
