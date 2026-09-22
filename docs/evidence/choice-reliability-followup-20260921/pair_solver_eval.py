"""Dry-by-default frozen native comparison of choice truth and pair equivalence.

Experimental contracts live only in this evidence directory. No production
modules are edited. Four requests maximum, one SDK attempt each, no repair or
retry. Execution requires --run and refuses to replace a previous capture.
"""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
from itertools import combinations
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SERVICE = REPO / "backend" / "bedrock-question-service"
sys.path.insert(0, str(SERVICE))

import boto3  # noqa: E402
from botocore.config import Config  # noqa: E402
import jsonschema  # noqa: E402
from complete_question_solution import (  # noqa: E402
    COMPLETE_SOLUTION_SYSTEM_PROMPT, build_solver_prompt,
    rejection_reason, validate_batch,
)
from native_output_contracts import (  # noqa: E402
    _reject_constant, _reject_duplicate_pairs, adapt_native_response,
    native_prompt,
)
from question_generation import _generate_with_bedrock, ProviderCallBudget  # noqa: E402


SETTINGS = {
    "BEDROCK_STRUCTURED_OUTPUT_MODE": "native",
    "BEDROCK_MAX_TOKENS": "6000",
    "BEDROCK_TEMPERATURE": "0.2",
    "BEDROCK_CLAUDE_THINKING": "disabled",
    "BEDROCK_GUARDRAIL_IDENTIFIER": "",
    "BEDROCK_GUARDRAIL_VERSION": "",
}

PAIR_INSTRUCTIONS = """
Also compare the proposed answer meaning of every unordered pair of choices.
This is a separate task from deciding which choices are correct. Two wrong
answers can propose the same thing, and two different answers can both be wrong.
Do not equate options merely because both are false in the stated scenario or
both receive the same supported/refuted judgment.

Judge meaning AS AN ANSWER IN THE FORM THE STEM REQUESTS:
- equivalent: they propose the same value, claim, condition or action, or the
  same literal representation when representation is what the question tests.
  Equivalent numerical forms, unit conversions and paraphrases can duplicate
  wrong answers. A label saying only one is correct cannot cure that duplication.
- distinct: they propose different values, claims, conditions or actions, or
  different literal representations that this stem asks the learner to distinguish.
- uncertain: a material interpretation prevents establishing either relation.

Respect requested representation. If a stem asks about the written notation,
spelling, spaces, operators, unit word or syntax itself, preserve that distinction;
do not collapse representations solely because they have equal numerical values.
For claims or actions, superficial wording changes alone do not create a new
meaning. Preserve quantifiers, negation, bounds and whether equality is included.
For expressions evaluated mathematically, compare the functions under the stated
domain, rather than assuming a special input. Do not rewrite the choices.

For each pair give a short reason identifying its shared proposed content or the
specific distinction, not merely saying both answers are right or wrong. Reasons
are at most 240 characters. There is no overall validity flag for you to choose:
the application separately computes correctness and duplicate-choice vetoes.

Return only {"solutions":[{"index":0,"choices":[{"choice":"exact offered text",
"judgment":"supported|refuted|uncertain","reason":"concise decisive reason"}],
"choicePairs":[{"leftChoice":"exact offered text","rightChoice":"exact other text",
"relation":"equivalent|distinct|uncertain","reason":"specific shared meaning or distinction"}]}]}.
Return exactly one solution for every input index, exactly four choice rows and
exactly six pair rows per solution. Cover each unordered pair once, with no self
pairs or extra pairs. Preserve exact choice text in every row. Choice reasons
remain nonempty and at most 600 characters. Do not include any other fields.
""".strip()


def controls():
    # These ten stems were not among the prior eight reviewer controls. The
    # paired notation/value contexts deliberately reuse exact option strings.
    return [
        {"id": "fraction_value_duplicate", "prompt": "A bottle is half full. What fraction of its capacity is filled?", "choices": ["1/2", "1/4", "0.25", "3/4"], "expectedAnswer": "1/2", "equivalentPairs": [["1/4", "0.25"]], "oracle": "One half is filled. One quarter equals 0.25; the two wrong proposals denote the same amount."},
        {"id": "unit_notation_distinct", "prompt": "Which exact written choice uses 'seconds' as its unit word?", "choices": ["2 minutes", "60 seconds", "1 minute", "3 minutes"], "expectedAnswer": "60 seconds", "equivalentPairs": [], "oracle": "The task tests written unit words. The equal durations 60 seconds and 1 minute have different requested written representations."},
        {"id": "turn_action_duplicate", "prompt": "A fictional road sign says only a left turn reaches the library. Which direction should you take?", "choices": ["Turn left.", "Turn right.", "Make a right turn.", "Continue straight."], "expectedAnswer": "Turn left.", "equivalentPairs": [["Turn right.", "Make a right turn."]], "oracle": "Only a left turn meets the rule. Two other choices propose the same right-turn action."},
        {"id": "inequality_boundary_distinct", "prompt": "Which relation describes all real x less than 3 while excluding x = 3?", "choices": ["x < 3", "x <= 3", "x > 3", "x >= 3"], "expectedAnswer": "x < 3", "equivalentPairs": [], "oracle": "Only strict less-than has the requested set. Direction and inclusion of the boundary distinguish all four relations."},
        {"id": "lamp_negation_duplicate", "prompt": "Two lamps are each either on or off. Exactly one is on. Which statement is true?", "choices": ["Some lamps are on.", "No lamps are on.", "Every lamp is off.", "All lamps are on."], "expectedAnswer": "Some lamps are on.", "equivalentPairs": [["No lamps are on.", "Every lamp is off."]], "oracle": "Some lamps are on is true. With only on/off states, no lamps on and every lamp off propose the same all-off condition."},
        {"id": "fraction_notation_distinct", "prompt": "Which written choice is a decimal numeral rather than a fraction written with '/'?", "choices": ["1/2", "1/4", "0.25", "3/4"], "expectedAnswer": "0.25", "equivalentPairs": [], "oracle": "The requested distinction is notation. Only 0.25 is written as a decimal numeral; 1/4 is a different required representation despite equal value."},
        {"id": "duration_unit_duplicate", "prompt": "A process lasts 120 seconds. What is its duration? Use 60 seconds = 1 minute.", "choices": ["2 minutes", "60 seconds", "1 minute", "3 minutes"], "expectedAnswer": "2 minutes", "equivalentPairs": [["60 seconds", "1 minute"]], "oracle": "120 seconds is 2 minutes. The two 60-second proposals are equal wrong durations under the supplied conversion."},
        {"id": "literal_spaces_distinct", "prompt": "Which quoted string contains exactly two spaces between a and b? Treat every written space as part of the string.", "choices": ['"ab"', '"a b"', '"a  b"', '"a   b"'], "expectedAnswer": '"a  b"', "equivalentPairs": [], "oracle": "The four literal strings contain zero, one, two and three spaces. All are distinct; only the two-space string answers the stem."},
        {"id": "algebra_function_duplicate", "prompt": "For every real x, which mathematical expression equals x + x?", "choices": ["2*x", "x+1", "1+x", "x-1"], "expectedAnswer": "2*x", "equivalentPairs": [["x+1", "1+x"]], "oracle": "x+x is 2*x. Commutativity makes x+1 and 1+x equal for every real x, but neither equals 2*x for every real x."},
        {"id": "quantifier_boundary_distinct", "prompt": "Which condition allows zero items or one item but excludes two or more items?", "choices": ["At most one item.", "At least one item.", "Exactly one item.", "More than one item."], "expectedAnswer": "At most one item.", "equivalentPairs": [], "oracle": "The allowed counts are {0,1}; other choices allow {1,2,...}, {1}, or {2,3,...}. The four proposed sets differ."},
    ]


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


class DryClient:
    def converse(self, **request):
        self.request = request
        return {"stopReason": "end_turn", "output": {"message": {"content": [{"text": '{"solutions":[]}'}]}}}


def candidate_schema(base):
    schema = copy.deepcopy(base)
    record = schema["properties"]["solutions"]["items"]
    record["properties"]["choicePairs"] = {
        "type": "array", "items": {
            "type": "object", "additionalProperties": False,
            "required": ["leftChoice", "rightChoice", "relation", "reason"],
            "properties": {
                "leftChoice": {"type": "string"}, "rightChoice": {"type": "string"},
                "relation": {"type": "string", "enum": ["equivalent", "distinct", "uncertain"]},
                "reason": {"type": "string"},
            },
        },
    }
    record["required"].append("choicePairs")
    return schema


def make_plan():
    os.environ.update(SETTINGS)
    cases = controls()
    jobs = []
    for batch_index in range(2):
        selected = cases[batch_index * 5:(batch_index + 1) * 5]
        items = []
        for index, case in enumerate(selected):
            # Stable rotation breaks the usual authored-key-first arrangement
            # without changing exact choice content or carrying the key.
            offset = (index + batch_index + 1) % 4
            options = case["choices"][offset:] + case["choices"][:offset]
            items.append({"index": index, "prompt": case["prompt"], "choices": options, "topic": "Self-contained literal reasoning"})
        system, user = build_solver_prompt(items, {"goal": {"title": "Solve self-contained questions exactly as written"}})
        dry = DryClient()
        _generate_with_bedrock({}, dry, "us.anthropic.claude-sonnet-4-6", system_prompt=system, user_prompt=user, call_budget=ProviderCallBudget(1), contract="complete_choice_solver_v1")
        baseline = dry.request
        base_schema = json.loads(baseline["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
        candidate = copy.deepcopy(baseline)
        candidate_prompt = COMPLETE_SOLUTION_SYSTEM_PROMPT.rsplit("\nReturn only", 1)[0] + "\n\n" + PAIR_INSTRUCTIONS
        candidate["system"] = [{"text": native_prompt(candidate_prompt, "complete_choice_solver_v2")}]
        candidate["outputConfig"]["textFormat"]["structure"]["jsonSchema"] = {
            "name": "complete_choice_solver_v2",
            "schema": json.dumps(candidate_schema(base_schema), sort_keys=True, separators=(",", ":")),
        }
        order = ["baseline", "pairwise"] if batch_index == 0 else ["pairwise", "baseline"]
        for arm in order:
            request = baseline if arm == "baseline" else candidate
            jobs.append({"call_index": len(jobs), "batch_index": batch_index, "arm": arm, "case_ids": [c["id"] for c in selected], "items": items, "request": request, "request_sha256": digest(request)})
    return {
        "experiment": "complete-choice-pairwise-equivalence-heldout-20260921",
        "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
        "source_sha256": {name: hashlib.sha256((SERVICE / name).read_bytes()).hexdigest() for name in ["complete_question_solution.py", "question_generation.py", "native_output_contracts.py", "request_contract.py", "question_quality.py"]},
        "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "settings": {"env": SETTINGS, "model": "us.anthropic.claude-sonnet-4-6", "region": "us-east-1", "maximum_calls": 4, "sdk_total_max_attempts": 1, "connect_timeout_seconds": 3, "read_timeout_seconds": 75},
        "scope": "Existing answer-blind complete-choice solver versus local experimental extension requiring every pair relation; no new production stage, author, reviewer, bank mutation, or production module edit. Ten new selected self-contained controls, five duplicate and five distinct, all uniquely keyed. Each arm sees two batches of five; this is feasibility, not population qualification or a repeated stability estimate.",
        "production_budget": "The candidate replaces the solver contract in the existing author/solver/reviewer pass: still 3 calls, allowing at most two complete passes under max6. Five items add 30 pair rows. The current 6000-token cap/read75 remain fixed to expose overhead failures; no extra calls, retries, or truncation repair.",
        "failure_policy": "Stop immediately on transport error, non-end_turn completion, invalid JSON/schema, missing/excess choice or pair coverage, exact-text mismatch, or invalid reason length. Preserve raw output and usage even on local validation failure. No retry or replacement; unattempted jobs remain in the denominator.",
        "prospective_criteria": {"all_calls_format_and_coverage_valid": True, "baseline_correct_unique_authored_keys": 10, "candidate_correct_unique_authored_keys": 10, "candidate_equivalent_pairs_correct": 5, "candidate_distinct_pairs_correct": 55, "candidate_duplicate_items_rejected": 5, "candidate_valid_items_retained": 5, "uncertain_pair_rows": 0, "tokens_per_call_max": 6000, "no_additional_provider_stage": True},
        "controls": cases, "jobs": jobs,
    }


def validate_and_score(raw, job, cases):
    schema = json.loads(job["request"]["outputConfig"]["textFormat"]["structure"]["jsonSchema"]["schema"])
    parsed = json.loads(raw, object_pairs_hook=_reject_duplicate_pairs, parse_constant=_reject_constant)
    jsonschema.Draft202012Validator(schema).validate(parsed)
    if job["arm"] == "baseline":
        records = validate_batch(adapt_native_response(raw, "complete_choice_solver_v1"), job["items"])
    else:
        projected = {"solutions": [{key: value for key, value in row.items() if key != "choicePairs"} for row in parsed["solutions"]]}
        records = validate_batch(json.dumps(projected, ensure_ascii=False), job["items"])
    raw_by_index = {row["index"]: row for row in parsed["solutions"]}
    rows = []
    for item, record, case_id in zip(job["items"], records, job["case_ids"], strict=True):
        case = cases[case_id]
        question = {**item, "expectedAnswer": case["expectedAnswer"]}
        base_veto = rejection_reason(record, question)
        row = {"case_id": case_id, "expected_eligible": not case["equivalentPairs"], "baseline_rejection": base_veto,
               "supported_choices": [r["choice"] for r in record["choices"] if r["judgment"] == "supported"]}
        pair_veto = None
        if job["arm"] == "pairwise":
            pairs = raw_by_index[item["index"]]["choicePairs"]
            wanted = {frozenset(pair) for pair in combinations(item["choices"], 2)}
            equivalent = {frozenset(pair) for pair in case["equivalentPairs"]}
            seen, pair_scores = set(), []
            if len(pairs) != 6:
                raise ValueError("Expected exactly six unordered pairs.")
            for pair in pairs:
                identity = frozenset((pair["leftChoice"], pair["rightChoice"]))
                if len(identity) != 2 or identity not in wanted or identity in seen:
                    raise ValueError("Unknown, duplicate, self, or content-mutated pair.")
                if not pair["reason"].strip() or len(pair["reason"]) > 240:
                    raise ValueError("Invalid pair-reason length.")
                seen.add(identity)
                expected = "equivalent" if identity in equivalent else "distinct"
                pair_scores.append({**pair, "expected_relation": expected, "relation_agrees": pair["relation"] == expected})
            if seen != wanted:
                raise ValueError("Missing unordered pair coverage.")
            relations = [p["relation"] for p in pairs]
            if "equivalent" in relations:
                pair_veto = "equivalent_choices"
            elif "uncertain" in relations:
                pair_veto = "uncertain_choice_distinctness"
            row["pairs"] = pair_scores
        row.update({"pair_rejection": pair_veto, "eligible": base_veto is None and pair_veto is None})
        row["eligibility_agrees"] = row["eligible"] == row["expected_eligible"]
        rows.append(row)
    return {"strict_schema_and_coverage_valid": True, "rows": rows}


def self_check(plan):
    """Offline oracle/validator controls; never interpreted as model outcomes."""
    cases = {c["id"]: c for c in plan["controls"]}
    assert len(cases) == 10 and sum(bool(c["equivalentPairs"]) for c in cases.values()) == 5
    for job in plan["jobs"]:
        rows = []
        for item, case_id in zip(job["items"], job["case_ids"], strict=True):
            case = cases[case_id]
            row = {"index": item["index"], "choices": [{"choice": choice, "judgment": "supported" if choice == case["expectedAnswer"] else "refuted", "reason": "Explicit synthetic oracle fixture, not a model response."} for choice in item["choices"]]}
            if job["arm"] == "pairwise":
                equivalent = {frozenset(p) for p in case["equivalentPairs"]}
                row["choicePairs"] = [{"leftChoice": a, "rightChoice": b, "relation": "equivalent" if frozenset((a, b)) in equivalent else "distinct", "reason": "Explicit synthetic oracle fixture, not a model response."} for a, b in combinations(item["choices"], 2)]
            rows.append(row)
        result = validate_and_score(json.dumps({"solutions": rows}), job, cases)
        if job["arm"] == "pairwise":
            assert all(row["eligibility_agrees"] for row in result["rows"])
            broken = copy.deepcopy(rows)
            broken[0]["choicePairs"][1] = copy.deepcopy(broken[0]["choicePairs"][0])
            try:
                validate_and_score(json.dumps({"solutions": broken}), job, cases)
            except ValueError:
                pass
            else:
                raise AssertionError("Duplicate pair was accepted.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    plan = make_plan()
    self_check(plan)
    path = HERE / "plan.json"
    if path.exists() and json.loads(path.read_text()) != plan:
        raise RuntimeError("Existing frozen plan changed; do not mutate or rerun.")
    save(path, plan)
    if not args.run:
        print("Frozen 4 native calls, 10 held-out controls, 60 candidate pairs; offline validator self-check passed. No provider calls.")
        return
    output = HERE / "capture.json"
    if output.exists():
        raise RuntimeError("Refusing to replace an existing capture or repeat calls.")
    cases = {c["id"]: c for c in plan["controls"]}
    client = boto3.client("bedrock-runtime", region_name="us-east-1", config=Config(connect_timeout=3, read_timeout=75, retries={"total_max_attempts": 1, "mode": "standard"}))
    capture = {"plan_sha256": digest(plan), "started_at": datetime.now(timezone.utc).isoformat(), "status": "running", "calls": []}
    save(output, capture)
    for job in plan["jobs"]:
        call = {"call_index": job["call_index"], "arm": job["arm"], "batch_index": job["batch_index"], "request_sha256": job["request_sha256"], "dispatch_attempted": True}
        capture["calls"].append(call)
        save(output, capture)
        print(f"Dispatch {job['call_index'] + 1}/4: {job['arm']} batch {job['batch_index']}", flush=True)
        start = time.monotonic()
        try:
            response = client.converse(**job["request"])
            raw = "\n".join(block["text"] for block in response["output"]["message"]["content"] if "text" in block)
            call.update({"elapsed_seconds": round(time.monotonic() - start, 3), "raw": raw, "usage": response.get("usage"), "stop_reason": response.get("stopReason")})
            save(output, capture)
            if response.get("stopReason") != "end_turn":
                raise ValueError("Provider did not end normally; no repair or retry.")
            call["score"] = validate_and_score(raw, job, cases)
            print(f"Complete {job['call_index'] + 1}/4: eligible={[r['case_id'] for r in call['score']['rows'] if r['eligible']]}", flush=True)
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
