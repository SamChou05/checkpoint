"""Four-call, fixed-control reviewer-core comparison; no inventory writes.

Invoke with --plan-only to freeze without dispatch. --run performs all four
predeclared calls, one SDK attempt each, and stops on any transport failure.
Existing captures are never overwritten by another run.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SERVICE = REPO / "backend" / "bedrock-question-service"
sys.path.insert(0, str(SERVICE))
sys.path.insert(0, str(SERVICE / "evals"))

import boto3  # noqa: E402
from botocore.config import Config  # noqa: E402
from checkpoint_choice_reliability_probe import controls  # noqa: E402
from question_quality import _strict_json_object  # noqa: E402
from question_verification import _REVIEW_CORE_PROMPT, verify_questions  # noqa: E402


ADDED_WORDING = """
Before approving, compare every pair of choices for meaning AS ANSWERS to this
exact question. Reject the item if any two options express the same answer,
including two wrong options. Different spelling, a numeric equivalent, or a
paraphrase of the same proposed answer does not make a distinct distractor.
Each wrong option should represent a different plausible error in the task.
Keep this judgment contextual: case, operators, units, accents, whitespace and
other literal symbols may distinguish answers when the question tests them.
Shared vocabulary or similar sentence structure alone is not duplication.
""".strip()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def plan():
    cases = [c for c in controls() if c["id"] not in {"exact_duplicate_wrong", "wrong_author_key"}]
    items = [{"index": i, "prompt": case["prompt"], "choices": case["choices"], "topic": "Literal reasoning"} for i, case in enumerate(cases)]
    context = {"goal": {"title": "Reason from literal facts and notation"}, "sourceDocuments": [], "existingQuestions": [], "items": items}
    user = "<question_review_json>\n" + json.dumps(context, ensure_ascii=False) + "\n</question_review_json>"
    jobs = []
    for i, arm in enumerate(["current_core", "explicit_diversity", "explicit_diversity", "current_core"]):
        system = _REVIEW_CORE_PROMPT
        if arm == "explicit_diversity":
            system += "\n\n" + ADDED_WORDING
        request = {
            "modelId": "us.anthropic.claude-sonnet-4-6",
            "system": [{"text": system}],
            "messages": [{"role": "user", "content": [{"text": user}]}],
            "inferenceConfig": {"maxTokens": 6000, "temperature": 0.2},
            "additionalModelRequestFields": {"thinking": {"type": "disabled"}},
        }
        jobs.append({"call_index": i, "arm": arm, "request": request, "request_sha256": digest(request)})
    return {
        "experiment": "reviewer-core-diversity-20260921",
        "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
        "source_sha256": {name: hashlib.sha256((SERVICE / name).read_bytes()).hexdigest() for name in ["question_verification.py", "request_contract.py", "question_quality.py", "evals/checkpoint_choice_reliability_probe.py"]},
        "settings": {"region": "us-east-1", "connect_timeout_seconds": 3, "read_timeout_seconds": 75, "sdk_total_max_attempts": 1, "maximum_calls": 4},
        "scope": "Isolated actual current reviewer core, omitting the production suffix that presumes independentSolutions. No solver outputs, authored keys, or assessments are supplied to the model. No author/solver/production release claim. Paired wording diagnostic only; 8 selected simple controls and 2 repetitions per arm do not qualify a prompt or measure population accuracy.",
        "format_scoring": "First require current strict whole-response parser. No recovery from surrounding prose. Save raw response and item declarations separately from current verification parser admission, which may reject invalid feedback. minimumDifficulty=1 avoids a difficulty confound.",
        "expected_cases": [{**c, "expected_valid": c["supported"] == [c["expectedAnswer"]] and not c["equivalent_pairs"]} for c in cases],
        "jobs": jobs,
    }


def score(text, cases):
    result = {}
    try:
        parsed = _strict_json_object(text)
        if set(parsed) != {"reviews"} or not isinstance(parsed["reviews"], list):
            raise ValueError("Invalid reviews envelope")
        reviews = parsed["reviews"]
        if len(reviews) != len(cases) or {r.get("index") for r in reviews} != set(range(len(cases))):
            raise ValueError("Invalid review coverage")
        result["strict_parse"] = True
        by_index = {r["index"]: r for r in reviews}
        result["rows"] = []
        for i, case in enumerate(cases):
            review = by_index[i]
            declared = review.get("valid") is True
            result["rows"].append({"case_id": case["id"], "expected_valid": case["expected_valid"], "declared_valid": declared,
                                   "declaration_agrees": declared == case["expected_valid"], "declared_answer": review.get("answer"),
                                   "equivalent_pairs": case["equivalent_pairs"]})
    except Exception as error:
        result.update({"strict_parse": False, "parse_error_type": type(error).__name__, "parse_error": str(error)})
    questions = [{"prompt": c["prompt"], "choices": c["choices"], "expectedAnswer": c["expectedAnswer"], "topic": "Literal reasoning", "explanation": "Fixture explanation hidden from reviewer.", "difficulty": 1} for c in cases]
    metrics = {}
    accepted = verify_questions(questions, {"minimumDifficulty": 1}, lambda *_: text, metrics)
    result["current_parser_accepted_case_ids"] = [c["id"] for c in cases if any(q["prompt"] == c["prompt"] and q["choices"] == c["choices"] for q in accepted)]
    result["current_parser_metrics"] = metrics
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--plan-only", action="store_true")
    args = parser.parse_args()
    frozen = plan()
    plan_path = HERE / "reviewer-plan.json"
    if plan_path.exists() and json.loads(plan_path.read_text()) != frozen:
        raise RuntimeError("Existing frozen plan differs; do not change a dispatched experiment.")
    save(plan_path, frozen)
    if not args.run or args.plan_only:
        print(f"Prepared {len(frozen['jobs'])} calls; no dispatch.")
        return
    output = HERE / "reviewer-capture.json"
    if output.exists():
        raise RuntimeError("Refusing to overwrite existing capture or repeat calls.")
    client = boto3.client("bedrock-runtime", region_name="us-east-1", config=Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1, "mode": "standard"}))
    capture = {"plan_sha256": digest(frozen), "started_at": datetime.now(timezone.utc).isoformat(), "status": "running", "calls": []}
    save(output, capture)
    for job in frozen["jobs"]:
        call = {"call_index": job["call_index"], "arm": job["arm"], "request_sha256": job["request_sha256"], "dispatch_attempted": True}
        capture["calls"].append(call)
        save(output, capture)
        start = time.monotonic()
        print(f"Dispatch {job['call_index'] + 1}/4: {job['arm']}", flush=True)
        try:
            response = client.converse(**job["request"])
            raw = "".join(block.get("text", "") for block in response["output"]["message"]["content"])
            call.update({"elapsed_seconds": round(time.monotonic() - start, 3), "stop_reason": response.get("stopReason"), "usage": response.get("usage"), "raw": raw, "score": score(raw, frozen["expected_cases"])})
            print(f"Complete {job['call_index'] + 1}/4: strict_parse={call['score']['strict_parse']}; accepted={call['score']['current_parser_accepted_case_ids']}", flush=True)
        except Exception as error:
            call.update({"elapsed_seconds": round(time.monotonic() - start, 3), "error_type": type(error).__name__, "error": str(error)})
            capture["status"] = "stopped_after_failure"
            save(output, capture)
            print(f"Stopped: {type(error).__name__}", flush=True)
            return
        save(output, capture)
    capture["status"] = "complete"
    capture["completed_at"] = datetime.now(timezone.utc).isoformat()
    save(output, capture)


if __name__ == "__main__":
    main()
