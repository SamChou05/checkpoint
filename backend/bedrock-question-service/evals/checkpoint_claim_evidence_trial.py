#!/usr/bin/env python3
"""One bounded claim-directed discovery/fetch/paired-review diagnostic.

Dry by default. Reuses the existing disposable model worker and public HTTPS
capture. No retries, repairs, resume, production stamps or model agreements.
"""
from __future__ import annotations

import argparse
import copy
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals import checkpoint_author_latency_probe as caller  # noqa: E402
from evals import claim_evidence_review as audit  # noqa: E402
from evals import grounding_transport as grounding  # noqa: E402
from source_acquisition import SourceAcquisitionLimits, acquire_source  # noqa: E402

shared = caller.shared
_hash = caller._hash
EXPERIMENT = "claim-directed-acquired-evidence-v1"
REVIEW_MODEL = "us.anthropic.claude-sonnet-4-6"
MAX_CASES, MAX_CALLS, MAX_FETCHES_PER_CASE = 4, 12, 2
MAX_INPUT_BYTES, WORKER_SECONDS = 65536, 90
SPAN_CHARACTERS = 8000
DIAGNOSTIC_MINIMUM_DIFFICULTY = 2
FETCH_LIMITS = SourceAcquisitionLimits(text_characters=60000, io_seconds=20)
SETTINGS = {"BEDROCK_REGION": "us-east-1", "BEDROCK_READ_TIMEOUT_SECONDS": "75",
            "BEDROCK_CONNECT_TIMEOUT_SECONDS": "3"}


class TrialFailure(RuntimeError):
    pass


def review_worker(connection, request, settings, cli_credentials, deadline):
    caller._worker(connection, request, SETTINGS, cli_credentials, deadline)


def review_request(system, user):
    return {"modelId": REVIEW_MODEL, "system": [{"text": system}],
            "messages": [{"role": "user", "content": [{"text": user}]}],
            "inferenceConfig": {"maxTokens": 6000, "temperature": 0.2},
            "additionalModelRequestFields": {"thinking": {"type": "disabled"}}}


def guard_request(request):
    if len(shared.canonical(request).encode("utf-8")) > MAX_INPUT_BYTES:
        raise ValueError("Request input allowance exceeded.")
    shared.canonical(request)


def select_spans(records, challenge):
    """One unchanged lexical-match window per page; no model-written excerpts.

    Rank overlapping windows by distinct query/target words, then occurrences;
    ties choose the earliest window. This is retrieval relevance, not entailment.
    """
    target = challenge["challenge"]
    terms = set(re.findall(r"[^\W\d_]{3,}", target["searchQuery"].casefold()
                          + " " + target["quote"].casefold()))
    selections = []
    for index, record in enumerate(records):
        text = record["source_text"]
        last = max(0, len(text) - SPAN_CHARACTERS)
        starts = sorted(set(range(0, last + 1, SPAN_CHARACTERS // 2)) | {last})
        def rank(start):
            words = re.findall(r"[^\W\d_]{3,}", text[start:start + SPAN_CHARACTERS].casefold())
            return len(terms.intersection(words)), sum(word in terms for word in words), -start
        start = max(starts, key=rank)
        selections.append({"record_index": index, "start": start,
                           "end": min(len(text), start + SPAN_CHARACTERS)})
    return selections


def make_plan(fixture, *, source_revision=None):
    revision = source_revision or shared.source_revision()
    if (type(revision) is not str or re.fullmatch(r"[0-9a-f]{40}", revision) is None
            or subprocess.run(["git", "cat-file", "-e", revision + "^{commit}"], cwd=SERVICE_DIR,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode):
        raise ValueError("A resolvable full source commit is required.")
    if type(fixture) is not dict or set(fixture) != {"experiment", "cases"} or fixture["experiment"] != EXPERIMENT:
        raise ValueError("Unexpected fixture envelope.")
    cases = fixture["cases"]
    if type(cases) is not list or not 1 <= len(cases) <= MAX_CASES:
        raise ValueError("One to four cases required.")
    jobs, seen = [], set()
    for case in cases:
        if (type(case) is not dict or set(case) != {"case_id", "question", "context", "origin"}
                or type(case["case_id"]) is not str or not case["case_id"] or case["case_id"] in seen):
            raise ValueError("Distinct immutable cases with provenance required.")
        seen.add(case["case_id"])
        question = audit.freeze_question(case["question"])
        system, user = audit.discovery_prompt(question, case["context"])
        request = grounding.grounding_request(system, user)
        guard_request(request)
        jobs.append({"case_id": case["case_id"], "question_sha256": _hash(question),
                     "discovery_request": request, "discovery_request_sha256": _hash(request),
                     "review_order": ["without_sources", "with_sources"] if len(jobs) % 2 == 0
                     else ["with_sources", "without_sources"]})
    sources = shared.source_hashes()
    for name in ("source_acquisition.py", "question_quality.py", "question_teaching.py",
                 "complete_question_solution.py", "evals/checkpoint_claim_evidence_trial.py",
                 "evals/claim_evidence_review.py", "evals/grounding_transport.py",
                 "evals/acquired_source_review.py", "evals/question_immutable_review.py",
                 "evals/question_complete_author.py",
                 "evals/checkpoint_author_latency_probe.py", "evals/checkpoint_immutable_review_eval.py"):
        sources[name] = hashlib.sha256((SERVICE_DIR / name).read_bytes()).hexdigest()
    return {"experiment": EXPERIMENT, "fixture": copy.deepcopy(fixture), "jobs": jobs,
            "fixture_sha256": _hash(fixture), "source_sha256": sources,
            "source_revision": revision,
            "dependencies": shared.dependencies(), "settings": SETTINGS,
            "maximum_calls": 3 * len(cases), "maximum_fetches": MAX_FETCHES_PER_CASE * len(cases),
            "maximum_input_bytes_per_call": MAX_INPUT_BYTES,
            "maximum_input_bytes_total": MAX_INPUT_BYTES * MAX_CALLS,
            "worker_seconds": WORKER_SECONDS, "fetch_limits": asdict(FETCH_LIMITS),
            "span_characters_per_source": SPAN_CHARACTERS,
            "diagnostic_minimum_difficulty": DIAGNOSTIC_MINIMUM_DIFFICULTY,
            "scope": "Compare declared whole-question/main judgments on unchanged selected controls. Same discovery challenge in both arms; only acquiredSources differs. A discovery hypothesis can reflect hidden search output, so this tests incremental actual passages, not independence of all information. Native citations locate pages, never prove claims. No generation/repair/retry/resume/stamp/deployment or general accuracy estimate.",
            "limits": "One SDK attempt per call, read75/connect3,90-second local worker plus bounded cleanup. Native Nova nested search count is not enforceably capped. At most two cited URLs fetched per case; each fetch has20-second I/O budget, but blocking system DNS and parent persistence are not hard real-time. Failure never implies remote cancellation or zero usage.",
            "failure_policy": "Provider/unfinished-response/cleanup/persistence failure stops all later dispatch. Malformed discovery ends its case. Failed fetches remain recorded; no acquired page skips the evidence arm. Review format rejection remains a format observation, not a factual detection."}


def load_plan(path, approved_hash):
    plan = json.loads(Path(path).read_text())
    if _hash(plan) != approved_hash or plan != make_plan(plan["fixture"], source_revision=plan["source_revision"]):
        raise ValueError("Frozen fixture, source, dependencies or requests changed.")
    return plan


def call_text(observation):
    response = observation.get("response", {})
    if (observation.get("status") != "completed" or observation.get("provider_dispatch_attempted") is not True
            or observation.get("local_worker_reaped") is not True
            or observation.get("local_process_group_cleanup_confirmed") is not True
            or observation.get("worker_exitcode") != 0 or observation.get("termination_attempted") is not False
            or response.get("stopReason") != "end_turn" or response.get("content_valid") is not True):
        raise TrialFailure("Incomplete provider or cleanup observation.")
    caller.recorded._validate_response_record(response)
    return response["text"]


def run(plan, directory, *, cli_credentials=False, transport=caller.observe_request, fetch=acquire_source):
    # Rebuild before creating output or admitting a worker. The caller must have
    # loaded the hash-bound plan; direct test callers receive the same check.
    if plan != make_plan(plan["fixture"], source_revision=plan["source_revision"]):
        raise ValueError("Plan no longer matches current sources.")
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=False)
    report = {"plan": plan, "plan_sha256": _hash(plan), "status": "running",
              "calls": [], "cases": []}
    def persist():
        shared.write_json(directory / "capture.json", report)
    def invoke(request, role, case_index):
        guard_request(request)
        if len(report["calls"]) >= plan["maximum_calls"]:
            raise TrialFailure("Call allowance exhausted.")
        call = {"case_index": case_index, "role": role, "request": copy.deepcopy(request),
                "request_sha256": _hash(request), "input_utf8_bytes": len(shared.canonical(request).encode("utf-8")),
                "status": "launch_intent"}
        report["calls"].append(call)
        persist()
        def progress(state):
            call["observation"] = state
            persist()
        worker = grounding.grounding_worker if role == "discovery" else review_worker
        call["observation"] = transport(request, cli_credentials=cli_credentials, on_progress=progress,
                                         worker=worker, timeout=WORKER_SECONDS)
        call["status"] = "observed"
        persist()
        return call_text(call["observation"]), call["observation"]["response"]
    persist()
    try:
        for index, (case, job) in enumerate(zip(plan["fixture"]["cases"], plan["jobs"], strict=True)):
            result = {"case_id": case["case_id"], "status": "discovering", "fetches": [], "reviews": {}}
            report["cases"].append(result)
            _, response = invoke(job["discovery_request"], "discovery", index)
            try:
                discovery = grounding.decode_grounding_response(response)
                challenge = audit.validate_discovery(discovery["generated_text"], case["question"])
            except ValueError as error:
                result.update(status="invalid_discovery", error_type=type(error).__name__)
                persist()
                continue
            result.update(challenge=challenge, discovery=discovery, status="fetching")
            persist()
            records = []
            unique_urls = {}
            for locator in discovery["citation_urls"]:
                unique_urls.setdefault(locator["url"].partition("#")[0], locator)
            for locator in list(unique_urls.values())[:MAX_FETCHES_PER_CASE]:
                url = locator["url"]
                fetched = {"native_citation": locator, "status": "fetch_intent"}
                result["fetches"].append(fetched)
                persist()
                captured = fetch(url, limits=FETCH_LIMITS)
                fetched.update(status="observed", capture=captured)
                if captured["status"] == "acquired":
                    if captured.get("requested_url") != url:
                        raise TrialFailure("Acquired source does not match dispatched native URL.")
                    records.append(captured)
                persist()
            selections = select_spans(records, challenge)
            result.update(selections=selections, status="reviewing")
            prompts = {arm: audit.review_prompt(case["question"], case["context"], challenge,
                       records if arm == "with_sources" else [],
                       selections if arm == "with_sources" else [])
                       for arm in job["review_order"]}
            left, right = (prompts[arm] for arm in ("without_sources", "with_sources"))
            left_data, right_data = (json.loads(p[1])
                                     for p in (left, right))
            left_data.pop("acquiredSources")
            right_data.pop("acquiredSources")
            if left[0] != right[0] or left_data != right_data:
                raise TrialFailure("Paired prompts differ beyond acquired sources.")
            for arm in job["review_order"]:
                if arm == "with_sources" and not records:
                    result["reviews"][arm] = {"status": "no_acquired_evidence"}
                    continue
                selected_records, selected_spans = (records, selections) if arm == "with_sources" else ([], [])
                system, user = prompts[arm]
                request = review_request(system, user)
                try:
                    guard_request(request)
                except ValueError:
                    result["reviews"][arm] = {"status": "input_budget_rejected"}
                    continue
                raw, _ = invoke(request, arm, index)
                result["reviews"][arm] = audit.observe_review(raw, case["question"], case["context"], challenge,
                                                              selected_records, selected_spans, minimum_difficulty=DIAGNOSTIC_MINIMUM_DIFFICULTY)
                persist()
            result["status"] = "completed"
            persist()
        report["status"] = "completed"
    except Exception as error:
        report.update(status="operational_failure", error_type=type(error).__name__)
    finally:
        persist()
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--execute", metavar="CANONICAL_PLAN_SHA256")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--aws-cli-credentials", action="store_true")
    args = parser.parse_args()
    if not args.execute:
        if not args.fixture or args.plan.exists():
            raise SystemExit("Provide a fixture and a new plan path.")
        plan = make_plan(json.loads(args.fixture.read_text()))
        shared.write_json(args.plan, plan)
        print(json.dumps({"plan": str(args.plan), "sha256": _hash(plan), "maximum_calls": plan["maximum_calls"]}))
        return
    if args.output is None:
        raise SystemExit("An exclusive output directory is required.")
    plan = load_plan(args.plan, args.execute)
    result = run(plan, args.output, cli_credentials=args.aws_cli_credentials)
    print(json.dumps({"status": result["status"], "calls": len(result["calls"]), "cases": len(result["cases"])}))
    if result["status"] != "completed":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
