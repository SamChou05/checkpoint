#!/usr/bin/env python3
"""Paired reviewer context diagnostic; dry by default, no production mutation.

Both arms use the same conditional reviewer instructions. Only the complete
independentSolutions field is withheld in the treatment. Historical solver
survivors remain fixed; this cannot rescue a solver-rejected question.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
from unittest.mock import patch

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals import checkpoint_native_stage_probe as native_probe  # noqa: E402
from question_verification import COMPLETE_REVIEW_SYSTEM_PROMPT, verify_questions  # noqa: E402
import question_generation as generation  # noqa: E402
from generation_diagnostics import quality_summary  # noqa: E402
from service_errors import ProviderError  # noqa: E402

shared = native_probe.shared
_hash, _same = native_probe._hash, native_probe._same
EXPERIMENT = "paired-reviewer-solver-context-v1"
MAX_CALLS = 10
ASSESSMENT_DIR = SERVICE_DIR.parents[1] / "docs/evidence/reviewer-independence-20260910"
ASSESSMENT_FREEZE_SHA256 = "a044e81af5014c2c263f1380247ff25f0405c82ba1ef2abdfa09c0fac8980b50"
ORIGINS = (
    ("delivery-feedback-20260909/capture.json",
     "b2b4d385fcde8143d8d43ea34cb17d6e4963fb816793cb5feed9a776c02b3049", (2, 5, 23)),
    ("runtime-qualification-capture-20260908.json",
     "6b4e90c111164618d042fe7b920d15bf0bd878dbd4b1a397b8de694c95bb3c5d", (1, 4)),
)
ARMS = ("solver_context", "withheld_solver_context")
_ENVELOPE_ADDITION = """Do not add fields to the envelope or review items. A rejected item may contain
only index, valid:false, and answer:\"\"; never add a competing verdict or repair.

"""
_BEFORE = """An independent solver assessed every exact offered choice against the complete
question. Its independentSolutions records contain a judgment and concise reason
for each choice."""
_AFTER = """An independent solver assessed every exact offered choice against the complete
question. When independentSolutions is supplied, its records contain a judgment
and concise reason for each choice. When it is absent, independently assess the
item from its unchanged stem, choices and relevant facts."""


def shared_system_prompt():
    if COMPLETE_REVIEW_SYSTEM_PROMPT.count(_BEFORE) != 1:
        raise ValueError("Current complete-choice review instructions changed.")
    return COMPLETE_REVIEW_SYSTEM_PROMPT.replace(_BEFORE, _AFTER)


def _current_request(original):
    expected = copy.deepcopy(original)
    old_system = expected["system"][0]["text"]
    if old_system == COMPLETE_REVIEW_SYSTEM_PROMPT.replace(_ENVELOPE_ADDITION, ""):
        expected["system"] = [{"text": COMPLETE_REVIEW_SYSTEM_PROMPT}]
    return expected


def _user(subject):
    return ("<question_review_json>\n" + json.dumps(subject, ensure_ascii=False)
            + "\n</question_review_json>")


class _ReviewReached(BaseException):
    pass


def reconstruct_policy_input(capture, review_index):
    """Recover actual candidates through exact historical generation calls.

    The client is a local replay stub. Reaching any request absent from the
    frozen prefix is an error, never permission to contact a provider.
    """
    target = capture["calls"][review_index]
    operation = capture["plan"]["operations"][target["operation_index"]]
    indexes = [i for i, call in enumerate(capture["calls"])
               if call["operation_index"] == target["operation_index"] and i <= review_index]
    cursor, active, recovered, matched = 0, {}, {}, []

    def verification(candidates, request, reviewer, *args, **kwargs):
        active.clear()
        active.update(candidates=copy.deepcopy(candidates), request=copy.deepcopy(request))
        return verify_questions(candidates, request, reviewer, *args, **kwargs)

    class Client:
        def converse(self, **request):
            nonlocal cursor
            if cursor >= len(indexes):
                raise ValueError("Unexpected historical replay request.")
            index = indexes[cursor]
            old = capture["calls"][index]
            expected = _current_request(old["request"])
            if not _same(request, expected):
                raise ValueError("Historical generation prefix changed.")
            cursor += 1
            matched.append({"call_index": index, "request_sha256": _hash(request),
                            "archived_request_sha256": _hash(old["request"]),
                            "shared_envelope_instruction_migration": request != old["request"]})
            if index == review_index:
                recovered.update(copy.deepcopy(active))
                raise _ReviewReached()
            if not native_probe.runtime._usable_observation(old["observation"]):
                raise ValueError("Historical prefix response is not usable.")
            return native_probe.runtime._provider_response(old["observation"])

    settings = operation.get("settings", capture["plan"]["settings"])
    with patch.dict(os.environ, {**settings, "BEDROCK_STRUCTURED_OUTPUT_MODE": "legacy"}), patch.object(
        generation, "verify_questions", side_effect=verification,
    ):
        try:
            request = copy.deepcopy(operation["request"])
            client = Client()
            budget = generation.ProviderCallBudget(operation["maximum_calls"])
            metrics = {"ProviderCalls": 0, "BedrockInputTokens": 0, "BedrockOutputTokens": 0}
            if operation["kind"] == "fixed":
                def invoke(system, user):
                    return generation._generate_legacy_with_bedrock(
                        request, client, generation._verification_model_id(), user, system, budget, metrics,
                    )
                verification(copy.deepcopy(operation["questions"]), request, invoke,
                             solve=invoke, solver_contract="complete_choices")
            else:
                generation._generate_sanitized_questions(request, client, budget, metrics)
        except _ReviewReached:
            pass
    if not recovered or cursor != len(indexes):
        raise ValueError("The exact historical reviewer was not reached.")
    solver_index = next(i for i in reversed(indexes[:-1]) if capture["calls"][i]["role"] == "solver")
    solver = capture["calls"][solver_index]
    return {**recovered, "prefix_request_matches": matched, "solver_call_index": solver_index,
            "solver_request": copy.deepcopy(solver["request"]),
            "solver_text": solver["observation"]["response"]["text"]}


def make_plan(*, source_revision=None):
    snapshot = native_probe._source_snapshot(source_revision)
    freeze_bytes = (ASSESSMENT_DIR / "first-pass-freeze.json").read_bytes()
    if hashlib.sha256(freeze_bytes).hexdigest() != ASSESSMENT_FREEZE_SHA256:
        raise ValueError("The prospective independent assessment freeze changed.")
    assessment = json.loads(freeze_bytes)
    for name, expected in assessment["files"].items():
        if hashlib.sha256((ASSESSMENT_DIR / name).read_bytes()).hexdigest() != expected:
            raise ValueError("The prospective assessment or exact subjects changed.")
    jobs, origins, pair_index = [], [], 0
    for relative, expected_hash, indexes in ORIGINS:
        path = SERVICE_DIR.parents[1] / "docs/evidence" / relative
        raw = path.read_bytes()
        if hashlib.sha256(raw).hexdigest() != expected_hash:
            raise ValueError("Exact historical capture bytes required.")
        capture = json.loads(raw)
        if capture["plan_sha256"] != _hash(capture["plan"]):
            raise ValueError("Historical capture plan binding changed.")
        origins.append({"path": relative, "byte_sha256": expected_hash,
                        "canonical_sha256": _hash(capture), "call_indexes": list(indexes)})
        for index in indexes:
            old = capture["calls"][index]
            original = old["request"]
            subject = native_probe._subject(original, "reviewer")
            operation = capture["plan"]["operations"][old["operation_index"]]
            if (old["role"] != "reviewer" or old["request_sha256"] != _hash(original)
                    or _current_request(original)["system"] != [{"text": COMPLETE_REVIEW_SYSTEM_PROMPT}]
                    or original["modelId"] != "us.anthropic.claude-sonnet-4-6"
                    or original["inferenceConfig"] != {"maxTokens": 6000, "temperature": .2}
                    or original.get("additionalModelRequestFields") != {"thinking": {"type": "disabled"}}
                    or not native_probe.runtime._usable_observation(old["observation"])
                    or not subject.get("independentSolutions")
                    or _user(subject) != original["messages"][0]["content"][0]["text"]):
                raise ValueError("Exact current reviewer context and provider settings required.")
            policy_input = reconstruct_policy_input(capture, index)
            for arm in ARMS if pair_index % 2 == 0 else tuple(reversed(ARMS)):
                payload = copy.deepcopy(subject)
                if arm == "withheld_solver_context":
                    del payload["independentSolutions"]
                treatment = copy.deepcopy(original)
                treatment["system"] = [{"text": shared_system_prompt()}]
                treatment["messages"][0]["content"][0]["text"] = _user(payload)
                job = {
                    "position": len(jobs), "pair_index": pair_index, "arm": arm,
                    "origin_path": relative, "archived_call_index": index,
                    "archived_operation_index": old["operation_index"],
                    "role": "reviewer", "contract": "default_reviewer_v1",
                    "source_request": copy.deepcopy(original),
                    # Native adapter consumes this frozen legacy-shaped input.
                    "archived_request": treatment,
                    "normalized_operation_request": copy.deepcopy(operation["request"]),
                    "subject": payload,
                    "policy_input": copy.deepcopy(policy_input),
                }
                job["request"] = native_probe._native_request(job)
                job["request_sha256"] = _hash(job["request"])
                job["input_utf8_bytes"] = len(shared.canonical(job["request"]).encode())
                job["contract_metadata"] = native_probe.native.contract_metadata(job["contract"])
                jobs.append(job)
            pair_index += 1
    if len(jobs) != MAX_CALLS or pair_index != 5:
        raise ValueError("Exactly five historical batches and ten fixed calls required.")
    return {
        "experiment": EXPERIMENT, **snapshot, "origins": origins, "jobs": jobs,
        "pre_response_assessment": {"freeze_byte_sha256": ASSESSMENT_FREEZE_SHA256,
                                    "frozen_record": assessment},
        "settings": copy.deepcopy(native_probe.SETTINGS), "maximum_calls": MAX_CALLS,
        "maximum_input_utf8_bytes_per_call": native_probe.MAX_INPUT_BYTES,
        "maximum_input_utf8_bytes_total": MAX_CALLS * native_probe.MAX_INPUT_BYTES,
        "planned_input_utf8_bytes": sum(j["input_utf8_bytes"] for j in jobs),
        "per_worker_deadline_seconds": native_probe.WORKER_SECONDS,
        "sdk_total_max_attempts": 1,
        "maximum_worker_capture_bytes": native_probe.caller.MAX_CAPTURE_BYTES,
        "shared_prompt_change": {"before": _BEFORE, "after": _AFTER},
        "shared_historical_prompt_migration": "The two older runtime batches predate the three-line rejected-envelope instruction. Both arms use the current instruction; only that exact known historical omission is accepted during reconstruction. All other prefix request fields must match.",
        "scope": "Five fixed historical reviewer batches, twelve distinct questions, two fresh arms. Both arms share a minimally conditional system prompt and native schema. Only independentSolutions presence varies. Current archived solver survivors, sources, history, exact choices and item order remain fixed. Neither arm is an untouched production baseline. No fresh author/solver, repair, additional evidence, production setting change or delivery.",
        "failure_policy": "Stop on provider, nonterminal response, cleanup, observation or persistence failure. Usable completed textual schema/adaptation/correlation failures remain content evidence; continue only the fixed jobs, never retry or replace them.",
        "assessment": "Freeze independent exact-subject assessments before dispatch. Assess both arms' unchanged decisions, keys, main and all choice feedback with arm and solver records hidden. Report semantic quality, difficulty and application eligibility separately. A format or difficulty rejection is not a correct defect detection. Preserve false rejection of valid controls and unsupported teaching. No general accuracy or learning-gain claim from this selected set.",
        "decision_rule": "A promising diagnostic requires fewer semantically admitted defective items without a new rejection of a supported control or newly unsupported teaching. A mixed or null result does not qualify removal. Even improvement requires a fresh normal-runtime evaluation before promotion; no trial-until-pass repeats.",
        "timing_scope": "Ten serial disposable workers, each at most 240 seconds before bounded cleanup; connect3/read75/SDK1. Parent disk operations are not hard real-time. Unobserved remote completion and usage remain unknown, never inferred from local cleanup.",
    }


def load_frozen_plan(path, expected_hash):
    plan = json.loads(path.read_text())
    if _hash(plan) != expected_hash or not _same(
        plan, make_plan(source_revision=plan.get("source_revision")),
    ):
        raise ValueError("Exact frozen plan, source, dependencies and origin bytes required.")
    return plan


def run_probe(plan_path, expected_hash, directory, *, cli_credentials=False, observer=None):
    plan = load_frozen_plan(plan_path, expected_hash)
    return native_probe.run_frozen_jobs(plan, directory, cli_credentials=cli_credentials,
                                       observer=observer, content_observer=content_observation)


def content_observation(job, state):
    result = native_probe.content_observation(job, state)
    if native_probe.runtime._usable_observation(state):
        result["response_text_sha256"] = hashlib.sha256(state["response"]["text"].encode()).hexdigest()
    if result["adaptation"] != "passed":
        return result
    policy = job["policy_input"]
    callbacks, metrics = [], {}

    def solve(system, user):
        original = policy["solver_request"]
        if (system != original["system"][0]["text"]
                or user != original["messages"][0]["content"][0]["text"]):
            raise ValueError("Actual solver callback binding changed.")
        callbacks.append("solver")
        return policy["solver_text"]

    def review(system, user):
        original = _current_request(job["source_request"])
        if (system != original["system"][0]["text"]
                or user != original["messages"][0]["content"][0]["text"]):
            raise ValueError("Actual reviewer callback binding changed.")
        callbacks.append("reviewer")

        class Client:
            def converse(self, **request):
                if not _same(request, job["request"]):
                    raise ValueError("Native paired request binding changed.")
                callbacks.append("native_transport")
                return native_probe.runtime._provider_response(state)

        # Reuse the prospective shared prompt and payload intervention exactly.
        return native_probe._invoke(job, Client())

    try:
        with patch.dict(os.environ, native_probe.SETTINGS):
            returned = verify_questions(
                copy.deepcopy(policy["candidates"]), copy.deepcopy(policy["request"]),
                review, request_metrics=metrics, solve=solve,
                solver_contract="complete_choices", feedback_contract="reviewer_written",
                preserve_reviewed_text=True,
            )
    except ProviderError:
        result["full_production_acceptance"] = "offline_adapter_rejection"
        return result
    if callbacks != ["solver", "reviewer", "native_transport"]:
        raise ValueError("Actual verification callbacks did not execute exactly once.")
    result.update(full_production_acceptance="offline_policy_replay_only",
                  policy_callbacks=callbacks, policy_metrics=quality_summary(metrics),
                  simulated_returned_questions=returned,
                  simulated_return_count=len(returned),
                  policy_scope="Actual unchanged application vetoes over historical candidates/solver and this fresh reviewer response, with only the prospective reviewer context intervention. No fresh author/solver, storage or production delivery. Semantic accuracy remains separately assessed.")
    return result


def export_assessment(report, directory):
    """Export every planned item, with fresh feedback but no arm or solver data."""
    if report["status"] not in {"completed", "operational_failure"}:
        raise ValueError("Only a terminal capture can be assessed.")
    if report["plan_sha256"] != _hash(report["plan"]):
        raise ValueError("Capture plan binding changed.")
    positions = [j["position"] for j in report["plan"]["jobs"]]
    result_positions = [r["position"] for r in report["results"]]
    call_positions = [c["position"] for c in report["calls"]]
    if (positions != list(range(len(positions))) or result_positions != positions
            or call_positions != positions[:len(call_positions)]):
        raise ValueError("Exact unique planned/result/call positions required.")
    calls = {c["position"]: c for c in report["calls"]}
    results = {r["position"]: r for r in report["results"]}
    rows, mapping = [], []
    for job in report["plan"]["jobs"]:
        result = results[job["position"]]
        call = calls.get(job["position"])
        if call and call.get("observation") is not None:
            if call["request_sha256"] != job["request_sha256"]:
                raise ValueError("Observed request binding changed.")
            reproduced = content_observation(job, call["observation"])
            if not _same(reproduced, {k: v for k, v in result.items() if k not in {"position", "status"}}):
                raise ValueError("Stored content outcome does not match the exact response.")
        reviews = {}
        if result.get("stage_validation") == "passed":
            call = calls[job["position"]]
            if call["request_sha256"] != job["request_sha256"]:
                raise ValueError("Observed request binding changed.")
            raw = json.loads(call["observation"]["response"]["text"])
            reviews = {r["index"]: r for r in raw["reviews"]}
        for item in job["subject"]["items"]:
            identifier = _hash({"mask": "reviewer-context-v1", "position": job["position"],
                                "index": item["index"]})[:12]
            review = copy.deepcopy(reviews.get(item["index"]))
            if review is not None:
                del review["index"]
            rows.append({"id": identifier, "goal": job["subject"].get("goal"),
                         "sourceDocuments": job["subject"].get("sourceDocuments"),
                         "question": {k: item[k] for k in ("prompt", "choices", "topic")},
                         "review": review,
                         "content_status": "review_available" if review else "no_correlated_review"})
            mapping.append({"id": identifier, "position": job["position"],
                            "item_index": item["index"], "arm": job["arm"],
                            "origin_path": job["origin_path"], "call_index": job["archived_call_index"]})
    directory.mkdir(parents=True, exist_ok=False, mode=0o700)
    shared.write_json(directory / "reviews.json", {
        "instructions": "Assess the exact question and each available fresh review. No arm, solver, authored key or runtime result is supplied. Determine whether a positive review's answer, entire main and all four choice explanations are sound. Preserve ambiguity and ordinary textbook conventions. A bare negative review has no defect rationale, so record rejection without proven detection reason. Null review is unavailable format/operational evidence, not a semantic rejection. Do not rewrite content.",
        "required_assessment_fields": ["id", "verdict_assessment", "key_support", "main_support",
                                       "choice_feedback_support", "issues", "difficulty", "notes"],
        "reviews": sorted(rows, key=lambda row: row["id"]),
    })
    shared.write_json(directory / "private-mapping.json", sorted(mapping, key=lambda row: row["id"]))
    shared.write_json(directory / "binding.json", {
        "capture_canonical_sha256": _hash(report), "plan_sha256": report["plan_sha256"],
        "planned_item_occurrences": len(rows),
        "files": {name: hashlib.sha256((directory / name).read_bytes()).hexdigest()
                  for name in ("reviews.json", "private-mapping.json")},
    })
    return len(rows)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--plan-sha256")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args(argv)
    if args.execute:
        if args.plan is None or args.plan_sha256 is None:
            parser.error("Execution requires --plan and --plan-sha256.")
        report = run_probe(args.plan, args.plan_sha256, args.directory,
                           cli_credentials=args.aws_cli_credentials)
        return 0 if report["status"] == "completed" else 1
    if args.plan is not None or args.plan_sha256 is not None or args.aws_cli_credentials:
        parser.error("Dry preparation accepts only a new --directory.")
    plan = make_plan()
    args.directory.mkdir(parents=True, exist_ok=False, mode=0o700)
    shared.write_json(args.directory / "plan.json", plan)
    print(json.dumps({"plan_sha256": _hash(plan), "maximum_calls": MAX_CALLS, "execute": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
