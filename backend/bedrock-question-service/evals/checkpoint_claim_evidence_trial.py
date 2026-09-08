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
import tempfile

SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR))

from evals import checkpoint_author_latency_probe as caller  # noqa: E402
from evals import claim_evidence_review as audit  # noqa: E402
from evals import grounding_transport as grounding  # noqa: E402
from evals.claim_evidence_schema import output_config  # noqa: E402
from source_acquisition import SourceAcquisitionLimits, acquire_source  # noqa: E402

shared = caller.shared
_hash = caller._hash
EXPERIMENT = "claim-directed-acquired-evidence-v1"
CITATION_EXPERIMENT = "frozen-claim-citation-discovery-v2"
SPLIT_EXPERIMENT = "frozen-source-split-review-v3"
SPLIT_CAPTURE = Path("/tmp/checkpoint-citation-discovery-live-20260908/capture.json")
SPLIT_CAPTURE_SHA256 = "f136a693f4fef8e72a6217924d1984021c0bbab1a46d3b4853fc60fe4d2f5a27"
SPLIT_SOURCE_REVISION = "cb41f487f8a9bc2beb6d93bd86ee23593b0b5da7"
CHALLENGE_CAPTURE = SERVICE_DIR.parents[1] / "docs/evidence/claim-evidence-interface-capture-20260908.json"
CHALLENGE_CAPTURE_SHA256 = "ade70260e2bbe9f9366783e70a4d4a2e359c93ffd44b391cf33ee71fff07676c"
STRUCTURED_REVIEW_SECONDS = 300
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


def structured_review_worker(connection, request, settings, cli_credentials, deadline):
    caller._worker(connection, request, {**SETTINGS, "BEDROCK_READ_TIMEOUT_SECONDS": "300"},
                   cli_credentials, deadline)


def review_request(system, user, *, structured=False):
    request = {"modelId": REVIEW_MODEL, "system": [{"text": system}],
            "messages": [{"role": "user", "content": [{"text": user}]}],
            "inferenceConfig": {"maxTokens": 6000, "temperature": 0.2},
            "additionalModelRequestFields": {"thinking": {"type": "disabled"}}}
    if structured:
        request["outputConfig"] = output_config()
    return request


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


def _source_revision(source_revision):
    revision = source_revision or shared.source_revision()
    if (type(revision) is not str or re.fullmatch(r"[0-9a-f]{40}", revision) is None
            or subprocess.run(["git", "cat-file", "-e", revision + "^{commit}"], cwd=SERVICE_DIR,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode):
        raise ValueError("A resolvable full source commit is required.")
    return revision


def _source_hashes():
    sources = shared.source_hashes()
    for name in ("source_acquisition.py", "question_quality.py", "question_teaching.py",
                 "complete_question_solution.py", "evals/checkpoint_claim_evidence_trial.py",
                 "evals/claim_evidence_review.py", "evals/grounding_transport.py",
                 "evals/claim_evidence_schema.py",
                 "evals/acquired_source_review.py", "evals/question_immutable_review.py",
                 "evals/question_complete_author.py",
                 "evals/checkpoint_author_latency_probe.py", "evals/checkpoint_immutable_review_eval.py"):
        sources[name] = hashlib.sha256((SERVICE_DIR / name).read_bytes()).hexdigest()
    return sources


def _make_split_plan(fixture, revision):
    from evals import split_evidence_review as split

    if fixture != {"experiment": SPLIT_EXPERIMENT}:
        raise ValueError("The fixed split-review fixture has no configurable fields.")
    raw = SPLIT_CAPTURE.read_bytes()
    if hashlib.sha256(raw).hexdigest() != SPLIT_CAPTURE_SHA256:
        raise ValueError("The exact terminal v2 capture is required.")
    origin = json.loads(raw)
    if (origin["status"] != "completed" or origin["plan_sha256"] != _hash(origin["plan"])
            or origin["plan"]["experiment"] != CITATION_EXPERIMENT
            or origin["plan"]["source_revision"] != SPLIT_SOURCE_REVISION
            or len(origin["cases"]) != 4 or len(origin["calls"]) != 12
            or len(origin["plan"]["fixture"]["cases"]) != 4):
        raise ValueError("Unexpected terminal v2 origin.")
    cases, jobs = [], []
    for index, (case, result) in enumerate(zip(origin["plan"]["fixture"]["cases"], origin["cases"], strict=True)):
        if case["case_id"] != result["case_id"] or result["status"] != "completed":
            raise ValueError("Origin case binding changed.")
        records = []
        for fetched in result["fetches"]:
            record = fetched["capture"]
            if record["status"] == "acquired":
                locator = fetched["native_citation"]
                if (locator not in result["discovery"]["citation_urls"]
                        or record["requested_url"] != locator["url"]):
                    raise ValueError("Origin acquired source/native URL mismatch.")
                records.append(record)
        prepared = split.prepare(case["question"], case["context"], records, result["selections"])
        previous = [(i, c) for i, c in enumerate(origin["calls"])
                    if c["case_index"] == index and c["role"] == "with_sources"]
        if len(previous) != 1:
            raise ValueError("Exactly one old sourced review is required.")
        old_index, old = previous[0]
        expected = review_request(*audit.review_prompt(case["question"], case["context"],
                                  case["challenge"], records, result["selections"]), structured=True)
        if old["request"] != expected or old["request_sha256"] != _hash(expected):
            raise ValueError("Old sourced-review request changed.")
        call_text(old["observation"])
        requests = {"old_review": copy.deepcopy(old["request"])}
        for role in ("choices", "teaching"):
            requests[role] = review_request(*split.prompt(prepared, role))
            requests[role]["outputConfig"] = split.output_config(role)
        for request in requests.values():
            guard_request(request)
        cases.append({**copy.deepcopy(case), "records": copy.deepcopy(records),
                      "selections": copy.deepcopy(result["selections"])})
        jobs.append({"case_id": case["case_id"], "question_sha256": prepared["question_sha256"],
                     "source_packet_sha256": prepared["source_packet_sha256"],
                     "source_units": prepared["source_units"], "old_review_call_index": old_index,
                     "role_order": ["old_review", "choices", "teaching"] if index % 2 == 0
                     else ["choices", "teaching", "old_review"],
                     "requests": requests,
                     "request_sha256": {role: _hash(request) for role, request in requests.items()}})
    sources = _source_hashes()
    name = "evals/split_evidence_review.py"
    sources[name] = hashlib.sha256((SERVICE_DIR / name).read_bytes()).hexdigest()
    return {"experiment": SPLIT_EXPERIMENT, "fixture": copy.deepcopy(fixture),
            "fixture_sha256": _hash(fixture), "frozen_cases": cases, "jobs": jobs,
            "origin": {"capture_sha256": SPLIT_CAPTURE_SHA256,
                       "plan_sha256": origin["plan_sha256"], "source_revision": SPLIT_SOURCE_REVISION},
            "source_revision": revision, "source_sha256": sources, "dependencies": shared.dependencies(),
            "settings": SETTINGS, "maximum_calls": 12, "maximum_fetches": 0,
            "maximum_input_bytes_per_call": MAX_INPUT_BYTES,
            "maximum_input_bytes_total": MAX_INPUT_BYTES * 12,
            "review_worker_seconds": STRUCTURED_REVIEW_SECONDS, "review_sdk_read_seconds": 300,
            "diagnostic_minimum_difficulty": DIAGNOSTIC_MINIMUM_DIFFICULTY,
            "scope": "Four previously selected cases and unchanged acquired spans. Repeat each old sourced review and independently assess choices and main teaching. Candidate calls never receive one another's outputs; the choice solver receives no authored main, key or challenge. Reference binding is not entailment. No factual certification, production stamps or deployment.",
            "limits": "Twelve SDK attempts maximum, one per role and case; zero fetches. Read 300/connect 3, 300-second local worker deadline and bounded cleanup. Parent persistence is not hard real-time; local termination does not prove remote cancellation or zero usage.",
            "failure_policy": "Provider/unfinished-response/cleanup/persistence failure stops later calls. Both candidate roles run despite content or format vetoes. No retries, repairs, fallback or resume. Format rejection is not factual detection."}


def make_plan(fixture, *, source_revision=None):
    revision = _source_revision(source_revision)
    if type(fixture) is dict and fixture.get("experiment") == SPLIT_EXPERIMENT:
        return _make_split_plan(fixture, revision)
    if type(fixture) is not dict or set(fixture) != {"experiment", "cases"} or fixture["experiment"] not in (EXPERIMENT, CITATION_EXPERIMENT):
        raise ValueError("Unexpected fixture envelope.")
    citation_mode = fixture["experiment"] == CITATION_EXPERIMENT
    prior = None
    if citation_mode:
        raw_prior = CHALLENGE_CAPTURE.read_bytes()
        if hashlib.sha256(raw_prior).hexdigest() != CHALLENGE_CAPTURE_SHA256:
            raise ValueError("The exact terminal challenge capture is required.")
        prior = json.loads(raw_prior)
        if prior["status"] != "completed":
            raise ValueError("Prior challenge run must be terminal.")
    cases = fixture["cases"]
    if type(cases) is not list or not 1 <= len(cases) <= MAX_CASES:
        raise ValueError("One to four cases required.")
    jobs, seen = [], set()
    for case in cases:
        if (type(case) is not dict or set(case) != ({"case_id", "question", "context", "origin", "challenge"} if citation_mode
                                                       else {"case_id", "question", "context", "origin"})
                or type(case["case_id"]) is not str or not case["case_id"] or case["case_id"] in seen):
            raise ValueError("Distinct immutable cases with provenance required.")
        seen.add(case["case_id"])
        question = audit.freeze_question(case["question"])
        if citation_mode:
            matches = [(old, result) for old, result in zip(prior["plan"]["fixture"]["cases"], prior["cases"], strict=True)
                       if old["case_id"] == case["case_id"]]
            if len(matches) != 1:
                raise ValueError("Missing original challenge case.")
            old, result = matches[0]
            if (old != {k: v for k, v in case.items() if k != "challenge"}
                    or case["challenge"] != result["challenge"]):
                raise ValueError("Follow-up must preserve the exact original question, context and challenge.")
            system, user = audit.source_discovery_prompt(question, case["context"], case["challenge"])
        else:
            system, user = audit.discovery_prompt(question, case["context"])
        request = grounding.grounding_request(system, user)
        guard_request(request)
        jobs.append({"case_id": case["case_id"], "question_sha256": _hash(question),
                     "discovery_request": request, "discovery_request_sha256": _hash(request),
                     "review_order": ["without_sources", "with_sources"] if len(jobs) % 2 == 0
                     else ["with_sources", "without_sources"]})
    sources = _source_hashes()
    return {"experiment": fixture["experiment"], "fixture": copy.deepcopy(fixture), "jobs": jobs,
            "challenge_origin_sha256": CHALLENGE_CAPTURE_SHA256 if citation_mode else None,
            "review_output_config": output_config() if citation_mode else None,
            "review_worker_seconds": STRUCTURED_REVIEW_SECONDS if citation_mode else WORKER_SECONDS,
            "review_sdk_read_seconds": 300 if citation_mode else 75,
            "fixture_sha256": _hash(fixture), "source_sha256": sources,
            "source_revision": revision,
            "dependencies": shared.dependencies(), "settings": SETTINGS,
            "maximum_calls": 3 * len(cases), "maximum_fetches": MAX_FETCHES_PER_CASE * len(cases),
            "maximum_input_bytes_per_call": MAX_INPUT_BYTES,
            "maximum_input_bytes_total": MAX_INPUT_BYTES * MAX_CALLS,
            "worker_seconds": WORKER_SECONDS, "fetch_limits": asdict(FETCH_LIMITS),
            "span_characters_per_source": SPAN_CHARACTERS,
            "diagnostic_minimum_difficulty": DIAGNOSTIC_MINIMUM_DIFFICULTY,
            "scope": "Compare declared whole-question/main judgments on unchanged selected controls. v2 freezes prior selected challenges and uses prose discovery plus a static native review schema; it does not regenerate targets or reuse old reviewer verdicts. Same discovery challenge in both arms; only acquiredSources differs. A discovery hypothesis can reflect hidden search output, so this tests incremental actual passages, not independence of all information. Native citations locate pages, never prove claims. No generation/repair/retry/resume/stamp/deployment or general accuracy estimate.",
            "limits": "One SDK attempt per call. Discovery uses read 75/connect 3 and a 90-second local worker deadline. Review uses the explicit review_sdk_read_seconds/review_worker_seconds values; v2 allows 300 seconds for cold native-schema compilation and does not qualify the 75-second production window. Bounded cleanup. Native Nova nested search count is not enforceably capped. At most two cited URLs fetched per case; each fetch has a 20-second I/O budget, but blocking system DNS and parent persistence are not hard real-time. Failure never implies remote cancellation or zero usage.",
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
    citation_mode = plan["experiment"] == CITATION_EXPERIMENT
    split_mode = plan["experiment"] == SPLIT_EXPERIMENT
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
        size = len(shared.canonical(request).encode("utf-8"))
        if size + sum(c["input_utf8_bytes"] for c in report["calls"]) > plan["maximum_input_bytes_total"]:
            raise TrialFailure("Total input allowance exhausted.")
        call = {"case_index": case_index, "role": role, "request": copy.deepcopy(request),
                "request_sha256": _hash(request), "input_utf8_bytes": len(shared.canonical(request).encode("utf-8")),
                "status": "launch_intent"}
        report["calls"].append(call)
        persist()
        def progress(state):
            call["observation"] = state
            persist()
        worker = grounding.grounding_worker if role == "discovery" else (structured_review_worker if citation_mode or split_mode else review_worker)
        timeout = WORKER_SECONDS if role == "discovery" else plan["review_worker_seconds"]
        call["worker_timeout_seconds"] = timeout
        persist()
        call["observation"] = transport(request, cli_credentials=cli_credentials, on_progress=progress,
                                         worker=worker, timeout=timeout)
        call["status"] = "observed"
        persist()
        return call_text(call["observation"]), call["observation"]["response"]
    persist()
    try:
        cases = plan["frozen_cases"] if split_mode else plan["fixture"]["cases"]
        for index, (case, job) in enumerate(zip(cases, plan["jobs"], strict=True)):
            result = {"case_id": case["case_id"], "status": "discovering", "fetches": [], "reviews": {}}
            report["cases"].append(result)
            if split_mode:
                from evals import split_evidence_review as split

                result.update(status="reviewing", challenge=case["challenge"], selections=case["selections"])
                prepared = split.prepare(case["question"], case["context"], case["records"], case["selections"])
                for role in job["role_order"]:
                    raw, _ = invoke(job["requests"][role], role, index)
                    result["reviews"][role] = (
                        audit.observe_review(raw, case["question"], case["context"], case["challenge"],
                                             case["records"], case["selections"], minimum_difficulty=DIAGNOSTIC_MINIMUM_DIFFICULTY)
                        if role == "old_review" else split.observe(raw, prepared, role))
                    persist()
                result.update(status="completed", candidate=split.combine(
                    prepared, result["reviews"]["choices"], result["reviews"]["teaching"],
                    minimum_difficulty=DIAGNOSTIC_MINIMUM_DIFFICULTY))
                persist()
                continue
            _, response = invoke(job["discovery_request"], "discovery", index)
            try:
                discovery = grounding.decode_grounding_response(response)
                challenge = copy.deepcopy(case["challenge"]) if citation_mode else audit.validate_discovery(
                    discovery["generated_text"], case["question"])
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
                request = review_request(system, user, structured=citation_mode)
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


def replay_split_capture(report):
    """Re-derive terminal v3 observations through the same run, without clients."""
    if (report.get("status") not in ("completed", "operational_failure")
            or report["plan"]["experiment"] != SPLIT_EXPERIMENT
            or report["plan_sha256"] != _hash(report["plan"])):
        raise ValueError("A terminal hash-bound v3 capture is required.")
    calls = iter(report["calls"])
    def transport(request, **kwargs):
        recorded_call = next(calls)
        if (recorded_call["request"] != request
                or recorded_call["request_sha256"] != _hash(request)
                or recorded_call["worker_timeout_seconds"] != kwargs["timeout"]):
            raise ValueError("Recorded request or timeout mismatch.")
        return copy.deepcopy(recorded_call["observation"])
    with tempfile.TemporaryDirectory() as directory:
        derived = run(report["plan"], Path(directory) / "replay", transport=transport)
    if derived != report:
        raise ValueError("Replay differs; interrupted persistence captures cannot be promoted.")
    return derived


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
