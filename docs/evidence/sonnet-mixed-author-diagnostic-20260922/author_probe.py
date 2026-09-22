"""Unfrozen author-only diagnostic; imports/draft/preflight make no provider calls."""

import argparse
import copy
from collections import Counter
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
BASELINE = HERE.parent / "quantitative-mixed-qualification-20260922"
_spec = importlib.util.spec_from_file_location("sonnet_author_baseline", BASELINE / "mixed_probe.py")
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
runtime, native, safe = base.runtime, base.native, base.safe
require, digest, file_hash, save = base.require, base.digest, base.file_hash, base.save
from quantitative_authoring import CompiledCandidate, prepare_mixed_rows  # noqa: E402
from question_quality import _normalized_question_skill_tag  # noqa: E402
from service_errors import ProviderError, SafetyInterventionError, ServiceConfigurationError  # noqa: E402

MODEL = "us.anthropic.claude-sonnet-4-6"
ENVIRONMENT = {**base.ENVIRONMENT, "BEDROCK_MODEL_ID": MODEL,
               "GENERATION_ATTEMPTS": "1", "MAX_PROVIDER_CALLS_PER_REQUEST": "1"}
LIMITS = {"jobs": 3, "requested_per_job": 5, "requested_total": 15,
          "maximum_dispatches": 3, "dispatches_per_job": 1,
          "read_timeout": 100, "connect_timeout": 3, "sdk_attempts": 1,
          "successful_call_elapsed_seconds_maximum": 100, "max_tokens": 16000}
PLAN, CAPTURE = HERE / "plan.json", HERE / "capture.json"


def original_plan():
    plan = safe.strict_json((BASELINE / "plan.json").read_text())
    require(plan["state"] == "frozen", "Original mixed plan is not frozen.")
    require(plan["source_root"] == str(base.SERVICE), "Runtime source selection changed.")
    for name, expected in plan["source_hashes"].items():
        require(file_hash(Path(name)) == expected, "Original source hash changed.")
    require([job["id"] for job in plan["jobs"]] == ["quantitative", "python", "mixed"], "Job order changed.")
    require(all(job["request"]["targetCount"] == 5 for job in plan["jobs"]), "Requested count changed.")
    require({p.name: file_hash(p) for p in base.SERVICE.glob("*.py")} == base.IMPORTED_SERVICE_HASHES,
            "Runtime bytes changed after import.")
    for path in base.SERVICE.glob("*.py"):
        loaded = sys.modules.get(path.stem)
        if loaded is not None:
            require(Path(getattr(loaded, "__file__", "")).resolve() == path, "Wrong runtime module imported.")
    return plan


def actual_request(job):
    """Build the real author request through an injected recorder, with zero I/O."""
    calls = []

    class Recorder:
        def converse(self, **request):
            calls.append(copy.deepcopy(request))
            return {"stopReason": "end_turn", "output": {"message": {"content": [{"text": '{"questions":[]}'}]}}}

    with patch.dict(os.environ, ENVIRONMENT, clear=True):
        runtime._generate_provider_payload(copy.deepcopy(job["request"]), Recorder(), runtime.ProviderCallBudget(1))
    require(len(calls) == 1, "Author construction did not use exactly one call.")
    request = calls[0]
    require(request["modelId"] == MODEL and request["inferenceConfig"] == {"maxTokens": 16000}, "Author settings changed.")
    require(request["additionalModelRequestFields"] == {"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}},
            "Adaptive request changed.")
    return request


def build_plan():
    prior = original_plan()
    calls = []
    for index, job in enumerate(prior["jobs"]):
        request = actual_request(job)
        require(request["system"] == [{"text": prior["initial_author_prompts"][index]["system"]}]
                and request["messages"] == [{"role": "user", "content": [{"text": prior["initial_author_prompts"][index]["user"]}]}]
                and request["outputConfig"] == prior["contracts"][base.MIXED_AUTHOR_CONTRACT],
                "Original prompt, input or mixed schema changed.")
        calls.append({"job_id": job["id"], "source_job_index": index, "requested_slots": 5,
                      "normalized_request_sha256": digest(job["request"]), "request": request,
                      "request_sha256": digest(request)})
    paths = [HERE / name for name in ("author_probe.py", "test_author_probe.py", "PLAN.md", "COMPATIBILITY.md")]
    return {"state": "draft", "experiment": "Sonnet adaptive mixed author only",
            "original_plan": str(BASELINE / "plan.json"), "original_plan_sha256": file_hash(BASELINE / "plan.json"),
            "runtime_source_hashes": prior["source_hashes"],
            "harness_source_hashes": {str(path): file_hash(path) for path in paths},
            "environment": ENVIRONMENT, "limits": LIMITS, "calls": calls,
            "dependencies": {"python": sys.version.split()[0], "boto3": base.boto3.__version__, "botocore": base.botocore.__version__},
            "criteria": {"normal_exact_five_row_calls": 3, "independently_usable_of_15": 14,
                         "usable_per_job": 4, "quantitative_job_compiled": 4, "mixed_job_compiled": 2,
                         "mixed_job_english_prose": 1, "independent_all_raw_content_review_required": True,
                         "main_explanation_runtime_maximum": 420, "prose_author_instruction_maximum": 320,
                         "instruction_deviation_alone_fails_usability": False},
            "claim_limits": "Author configuration diagnostic only; no solver/reviewer or runtime admission, no causal paired comparison or production qualification."}


def check_plan(plan, path=None, expected_hash=None):
    require(plan == {**build_plan(), "state": plan["state"]} and plan["state"] in {"draft", "frozen"}, "Plan/source drift.")
    if path is not None:
        require(file_hash(path) == expected_hash, "Frozen plan bytes changed.")


def content_lengths(content, kind):
    """Observe unmodified text against stated limits; never clip or approve it."""
    fields = {"prompt": (content["prompt"], 12, 320),
              "explanation": (content["explanation"], 12, 420),
              **{f"choice_{slot}": (choice, 1, 140)
                 for slot, choice in zip("abcd", content["choices"], strict=True)},
              **{f"feedback_{slot}": (content["choiceExplanations"][choice], 12, 280)
                 for slot, choice in zip("abcd", content["choices"], strict=True)
                 if "choiceExplanations" in content}}
    observed = {name: {"characters": len(text), "minimum": lower, "maximum": upper,
                       "within_bounds": lower <= len(text) <= upper and bool(text.strip())}
                for name, (text, lower, upper) in fields.items()}
    return {"fields": observed, "all_within_bounds": all(row["within_bounds"] for row in observed.values()),
            "bound_basis": "runtime_content_limits",
            "prose_author_instruction": {"explanation_maximum": 320,
                                         "explanation_within_maximum": len(content["explanation"]) <= 320}
            if kind == "prose" else None,
            "semantic_validity": "not_assessed"}


def assess_payload(payload, job_id, request):
    """No semantic approval: preserve and locally compile every source row."""
    records = []
    raw_skill_counts = Counter()
    for index, raw in enumerate(payload["questions"]):
        record = {"source": [job_id, index], "kind": raw["kind"], "raw_row_sha256": digest(raw)}
        metadata = raw["question"] if raw["kind"] == "prose" else raw
        assignment = _normalized_question_skill_tag(metadata, request)
        if assignment:
            raw_skill_counts[assignment["skillID"]] += 1
        record["assignment_diagnostic"] = {
            "required": bool(request.get("skillMap")), "resolved_metadata": assignment,
            "metadata_matches_known_assignment": assignment is not None if request.get("skillMap") else None,
            "actual_topic_fit": "pending_independent_review"}
        record["authored_difficulty"] = metadata["difficulty"]
        record["authored_difficulty_at_least_requested"] = metadata["difficulty"] >= request["minimumDifficulty"]
        if raw["kind"] == "quantitative":
            try:
                compiled = CompiledCandidate.from_task(raw["task"])
                record.update(compiler_status="valid", compiler_spec=json.loads(compiled.spec_json),
                              learner=compiled.content(), learner_sha256=digest(compiled.content()))
            except (ValueError, TypeError, KeyError) as error:
                record.update(compiler_status="rejected", compiler_failure=getattr(error, "code", "invalid_spec"))
        else:
            rows, provenance, failures = prepare_mixed_rows({"questions": [raw]})
            require(not provenance and not failures and len(rows) == 1, "Prose adapter identity failure.")
            record.update(compiler_status="not_applicable", prose_draft=rows[0], prose_draft_sha256=digest(rows[0]))
        content = record.get("learner", record.get("prose_draft"))
        record["length_diagnostic"] = content_lengths(content, raw["kind"]) if content else None
        record["independent_semantics"] = "pending"
        records.append(record)
    expected_allocation = request.get("requestedSkillAllocation", {})
    return {"exact_requested_row_count": len(records) == 5, "raw_rows": len(records), "rows": records,
            "kind_counts": dict(Counter(row["kind"] for row in records)),
            "length_failure_rows": sum(row["length_diagnostic"] is not None
                                       and not row["length_diagnostic"]["all_within_bounds"] for row in records),
            "length_unavailable_rows": sum(row["length_diagnostic"] is None for row in records),
            "prose_instruction_length_deviation_rows": sum(row["kind"] == "prose"
                and not row["length_diagnostic"]["prose_author_instruction"]["explanation_within_maximum"]
                for row in records),
            "allocation_diagnostic": {"requested": expected_allocation, "raw_matching_metadata_counts": dict(raw_skill_counts),
                                      "matches_requested_counts": dict(raw_skill_counts) == expected_allocation
                                      if request.get("skillMap") else None,
                                      "counts_include_uncompiled_raw_rows": True,
                                      "semantic_topic_fit": "pending_independent_review"},
            "independently_usable": None, "runtime_admission": False}


def run_jobs(plan, capture, path, client_factory, pin_check, *, secrets=(), clock=time.monotonic):
    require(not capture["calls"] and not capture["jobs"], "No resume/repeat.")
    prior = original_plan()
    for spec, job in zip(plan["calls"], prior["jobs"], strict=True):
        if capture.get("global_stop"):
            break
        row = {"id": job["id"], "status": "running", "requested_slots": 5}
        capture["jobs"].append(row)
        budget = runtime.ProviderCallBudget(1)

        def guard(condition, message):
            if not condition:
                capture["global_stop"] = "request_transport_or_budget_integrity"
                raise base.IntegrityError(message)

        def pins():
            try:
                pin_check()
            except Exception:
                capture["global_stop"] = "source_integrity"
                raise

        class Recorder:
            def __init__(self, client):
                self.client, self.meta = client, client.meta

            def converse(self, **request):
                pins()
                cfg = self.meta.config
                guard(request == spec["request"] and digest(request) == spec["request_sha256"], "Actual request drift.")
                guard(self.meta.endpoint_url == base.ENDPOINT and self.meta.region_name == "us-east-1"
                      and cfg.read_timeout == 100 and cfg.connect_timeout == 3
                      and cfg.retries.get("total_max_attempts") == 1, "Actual SDK transport drift.")
                guard(not capture.get("global_stop") and budget.calls == 1 and len(capture["calls"]) < 3
                      and not any(call["job_id"] == job["id"] for call in capture["calls"]), "Unplanned author dispatch.")
                call = {"job_id": job["id"], "request": copy.deepcopy(request), "request_sha256": digest(request),
                        "dispatch_attempted": True, "read_timeout": cfg.read_timeout,
                        "connect_timeout": cfg.connect_timeout, "sdk_attempts": 1}
                capture["calls"].append(call)
                save(path, capture)
                started = clock()
                try:
                    response = self.client.converse(**request)
                    call["response"], call["reasoning_blocks_omitted"] = safe.safe_response(response, secrets)
                    return response
                except Exception as error:
                    call["error"] = safe.safe_error(error, secrets)
                    if base.setup_failure(error) or isinstance(error, (base.IntegrityError, safe.CaptureBoundaryError)):
                        capture["global_stop"] = "provider_setup_or_capture_integrity"
                    raise
                finally:
                    call["elapsed_seconds"] = round(clock() - started, 6)
                    try:
                        pins()
                    except Exception:
                        capture["global_stop"] = "post_dispatch_source_drift"
                        raise
                    finally:
                        save(path, capture)

        def factory(*args, **kwargs):
            try:
                guard(args == ("bedrock-runtime",) and set(kwargs) == {"region_name", "config"}, "Unexpected SDK client factory.")
                return Recorder(client_factory(*args, **kwargs))
            except Exception:
                capture["global_stop"] = "sdk_factory_setup"
                raise

        try:
            pins()
            with patch.dict(os.environ, ENVIRONMENT, clear=True), patch.object(base.boto3, "client", factory):
                payload = runtime._generate_provider_payload(copy.deepcopy(job["request"]), None, budget)
            call = capture["calls"][-1]
            row.update(native_schema_valid=True, author_payload=payload, author_payload_sha256=digest(payload), assessment=assess_payload(payload, job["id"], job["request"]))
            row["normal_bounded_exact_count"] = (call["response"]["stopReason"] == "end_turn"
                and call["elapsed_seconds"] <= 100 and row["assessment"]["exact_requested_row_count"])
            row["status"] = "completed_pending_semantics" if row["normal_bounded_exact_count"] else "failed_count_or_completion_bound"
        except Exception as error:
            row.update(status="failed", error=safe.safe_error(error, secrets))
            if (isinstance(error, (base.IntegrityError, safe.CaptureBoundaryError, ServiceConfigurationError))
                    or base.setup_failure(error) or not isinstance(error, (ProviderError, SafetyInterventionError))):
                capture["global_stop"] = capture.get("global_stop", "setup_or_source_integrity")
        finally:
            row["provider_calls"] = budget.calls
            save(path, capture)
    pin_check()
    finish(capture)
    save(path, capture)


def finish(capture):
    capture["summary"] = {"planned_jobs": 3, "requested_slots": 15, "attempted_calls": len(capture["calls"]),
                          "unattempted_jobs": 3 - len(capture["jobs"]),
                          "normal_bounded_exact_count_jobs": sum(bool(row.get("normal_bounded_exact_count")) for row in capture["jobs"]),
                          "raw_rows_observed": sum(row.get("assessment", {}).get("raw_rows", 0) for row in capture["jobs"]),
                          "independent_content_review": "pending", "qualified": False}
    usage = [call.get("response", {}).get("usage", {}) for call in capture["calls"]]
    capture["summary"]["reported_usage"] = {"inputTokens": sum(row.get("inputTokens", 0) for row in usage),
        "outputTokens": sum(row.get("outputTokens", 0) for row in usage),
        "calls_without_usage": sum(not row for row in usage), "missing_usage_is_unknown": True}
    capture["status"] = "globally_aborted" if capture.get("global_stop") else "completed_pending_review"


def preflight():
    result = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", str(HERE),
                             "-p", "test_author_probe.py", "-q"], capture_output=True, text=True)
    require(result.returncode == 0, "Offline tests failed: " + result.stderr)
    return {"provider_calls": 0, "result": "passed", "output": result.stderr.strip()}


def freeze(reviewed_digest):
    draft = build_plan()
    require(digest(draft) == reviewed_digest, "Draft changed after review.")
    preflight()
    require(build_plan() == draft, "Source changed during preflight.")
    save(PLAN, {**draft, "state": "frozen"}, exclusive=True)
    return {"plan_sha256": file_hash(PLAN), "provider_calls": 0}


def execute(expected_hash):
    require(PLAN.stat().st_size <= 1024 * 1024 and file_hash(PLAN) == expected_hash, "Frozen plan bound/hash failed.")
    plan = safe.strict_json(PLAN.read_text())
    require(plan["state"] == "frozen", "Draft cannot authorize dispatch.")
    check_plan(plan, PLAN, expected_hash)
    capture = {"plan_sha256": expected_hash, "calls": [], "jobs": [], "status": "setup",
               "started_at": datetime.now(timezone.utc).isoformat()}
    finish(capture)
    capture["status"] = "setup"
    save(CAPTURE, capture, exclusive=True)
    try:
        session, secrets = safe.credential_session()
        run_jobs(plan, capture, CAPTURE, session.client, lambda: check_plan(plan, PLAN, expected_hash), secrets=secrets)
    except BaseException as error:
        capture.update(status="globally_aborted", global_stop="setup_or_interruption",
                       error=safe.safe_error(error, locals().get("secrets", ())))
        finish(capture)
        save(CAPTURE, capture)
        if isinstance(error, (SystemExit, KeyboardInterrupt)):
            raise
    return {"capture": str(CAPTURE), "status": capture["status"], "summary": capture.get("summary")}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--draft", action="store_true")
    group.add_argument("--preflight", action="store_true")
    group.add_argument("--freeze")
    group.add_argument("--execute")
    args = parser.parse_args()
    result = ({"draft_digest": digest(build_plan()), "plan": build_plan()} if args.draft else preflight() if args.preflight
              else freeze(args.freeze) if args.freeze else execute(args.execute))
    print(json.dumps(result, ensure_ascii=True, indent=2))
