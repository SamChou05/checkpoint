"""Offline semantic boundary probes and reproducible saved-output accounting.

No model calls, network requests, writes, or changes to production behavior.
Synthetic judgments are truthful controls except the explicitly named correlated
error. They demonstrate what the application enforces, not model error rates.
Historical assessments are fallible, selected-sample judgments from the saved
evidence; replaying them is not a new independent adjudication.
"""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import sys

SERVICE = Path(__file__).resolve().parents[1]
REPO = SERVICE.parents[1]
sys.path.insert(0, str(SERVICE))

from complete_question_solution import rejection_reason, validate_batch  # noqa: E402
from question_quality import _normalized_choices, _sanitize_questions  # noqa: E402
from request_contract import _has_unambiguous_choices  # noqa: E402


def controls():
    """Hand-checkable controls; equivalent pairs are scoped to each exact stem."""
    return [
        {
            "id": "valid_arithmetic",
            "prompt": "What is 2 + 2?",
            "choices": ["4", "5", "6", "7"],
            "expectedAnswer": "4", "supported": ["4"], "equivalent_pairs": [],
        },
        {
            "id": "exact_duplicate_wrong",
            "prompt": "What is 2 + 2?",
            "choices": ["4", "5", "5", "6"],
            "expectedAnswer": "4", "supported": ["4"],
            "equivalent_pairs": [["5", "5"]],
        },
        {
            "id": "equivalent_numeric_wrong",
            "prompt": "What is 2 + 2?",
            "choices": ["4", "5", "5.0", "6"],
            "expectedAnswer": "4", "supported": ["4"],
            "equivalent_pairs": [["5", "5.0"]],
        },
        {
            "id": "equivalent_verbal_wrong",
            "prompt": "A fictional quiz defines the allowed answer as exactly two. Which option gives that number?",
            "choices": ["Two", "Three", "The number three", "Four"],
            "expectedAnswer": "Two", "supported": ["Two"],
            "equivalent_pairs": [["Three", "The number three"]],
        },
        {
            "id": "equivalent_correct",
            "prompt": "What is one half expressed as a number?",
            "choices": ["0.5", "1/2", "2", "3"],
            "expectedAnswer": "0.5", "supported": ["0.5", "1/2"],
            "equivalent_pairs": [["0.5", "1/2"]],
        },
        {
            "id": "multiple_correct_properties",
            "prompt": "Every valid report has a date and a signature. Which property must a valid report have?",
            "choices": ["It has a date.", "It has a signature.", "It has a photograph.", "It has a serial number."],
            "expectedAnswer": "It has a date.",
            "supported": ["It has a date.", "It has a signature."],
            "equivalent_pairs": [],
        },
        {
            "id": "zero_correct",
            "prompt": "What is 2 + 2?",
            "choices": ["1", "2", "3", "5"],
            "expectedAnswer": "1", "supported": [], "equivalent_pairs": [],
        },
        {
            "id": "wrong_author_key",
            "prompt": "What is 2 + 2?",
            "choices": ["3", "4", "5", "6"],
            "expectedAnswer": "3", "supported": ["4"], "equivalent_pairs": [],
        },
        {
            "id": "case_sensitive_valid",
            "prompt": "Which Python literal denotes the Boolean true value?",
            "choices": ["True", "true", "TRUE", "False"],
            "expectedAnswer": "True", "supported": ["True"], "equivalent_pairs": [],
        },
        {
            "id": "operator_sensitive_valid",
            "prompt": "Which Python expression adds one to n?",
            "choices": ["n + 1", "n - 1", "n * 1", "n / 1"],
            "expectedAnswer": "n + 1", "supported": ["n + 1"], "equivalent_pairs": [],
        },
    ]


def declared_solution(question, supported):
    return {
        "index": 0,
        "choices": [
            {"choice": choice,
             "judgment": "supported" if choice in supported else "refuted",
             "reason": "Controlled fixture declaration; see the explicit ground truth."}
            for choice in question["choices"]
        ],
    }


def synthetic_probe():
    rows = []
    for control in controls():
        identity_pass = _has_unambiguous_choices(control["choices"])
        gate = None
        if identity_pass:
            gate = rejection_reason(
                declared_solution(control, control["supported"]), control
            )
        rows.append({
            **control,
            "identity_pass": identity_pass,
            "normalized_choices_pass": bool(_normalized_choices(
                control["choices"], control["expectedAnswer"])),
            "truthful_solver_gate": gate if identity_pass else "invalid_choices",
            "unique_correct_authored_key": control["supported"] == [control["expectedAnswer"]],
            "diverse_options": not control["equivalent_pairs"],
        })
    wrong = next(q for q in controls() if q["id"] == "wrong_author_key")
    correlated = rejection_reason(declared_solution(wrong, [wrong["expectedAnswer"]]), wrong)
    return {
        "scope": "Synthetic declarations isolate deterministic boundaries; these are not observed model successes or failures.",
        "rows": rows,
        "counts": {
            "controls": len(rows),
            "truthful_solver_eligible": sum(r["truthful_solver_gate"] is None for r in rows),
            "equivalent_wrong_options_eligible": sum(
                r["truthful_solver_gate"] is None and not r["diverse_options"] for r in rows),
            "bad_key_controls_blocked_with_truthful_solver": sum(
                not r["unique_correct_authored_key"] and r["truthful_solver_gate"] is not None for r in rows),
        },
        "correlated_wrong_declaration": {
            "case": wrong["id"], "factual_answer": "4", "declared_answer": "3",
            "solver_gate": correlated,
            "meaning": "Shape and declaration agreement cannot prove arithmetic truth.",
        },
    }


def load_evidence(name):
    path = REPO / "docs" / "evidence" / name
    raw = path.read_bytes()
    return json.loads(raw), {"path": str(path.relative_to(REPO)), "sha256": hashlib.sha256(raw).hexdigest()}


def historical_author_replay():
    saved, provenance = load_evidence("question-prompt-experiment-20260906.json")
    rows, counts = [], {}
    for batch in saved["batches"]:
        count = counts.setdefault(batch["arm"], Counter())
        for item in batch["items"]:
            request = {**saved["contexts"][batch["case_id"]], "targetCount": 1}
            metrics = {}
            accepted = bool(_sanitize_questions([item["question"]], request, metrics))
            valid = item["authored_key_matches_sole_blind_choice"]
            count.update({"total": 1, "historically_valid": int(valid), "accepted": int(accepted)})
            count[("true_" if accepted == valid else "false_") + ("accept" if accepted else "reject")] += 1
            rows.append({
                "arm": batch["arm"], "case_id": batch["case_id"], "key": item["key"],
                "prompt": item["question"]["prompt"],
                "historical_unique_key_assessment": valid,
                "historical_assessment": item["blind_review"],
                "current_sanitizer_accepted": accepted,
                "current_sanitizer_metrics": metrics,
            })
    return {
        "provenance": provenance,
        "scope": "Current deterministic sanitizer only, replaying all 60 saved author candidates. Historical blind assessments are reused, not recertified. Sanitizer acceptance is not production release approval.",
        "counts": counts, "rows": rows,
    }


def historical_pipeline_assessment():
    assessment, assessment_source = load_evidence("author-model-comparison-stem-assessment-a-20260908.json")
    mapping, mapping_source = load_evidence("author-model-comparison-mapping-20260908.json")
    capture, capture_source = load_evidence("author-model-comparison-capture-20260908.json")
    by_id = {entry["candidate_id"]: entry for entry in mapping["items"]}
    rows, counts = [], Counter()
    for item in assessment["candidates"]:
        link = by_id[item["candidate_id"]]
        operation = capture["operations"][link["operation_index"]]
        # Production puts the authored key first; match the exact choice multiset,
        # not an order-sensitive list, without normalizing any choice content.
        returned = any(q["prompt"] == item["prompt"] and sorted(q["choices"]) == sorted(item["choices"]) for q in operation["questions"])
        valid = item["exact_unique_supported_key"]
        counts.update({"raw_candidates": 1, "historically_unique_keys": int(valid), "returned": int(returned)})
        if returned:
            counts["returned_unique_keys" if valid else "returned_unsupported_keys"] += 1
            counts["returned_three_plausible_distinct_distractors"] += int(item["three_plausible_distinct_distractors"])
        rows.append({
            "candidate_id": item["candidate_id"], "arm": link["arm"], "case_id": link["case_id"],
            "prompt": item["prompt"], "historical_returned": returned,
            "historical_unique_key_assessment": valid,
            "historical_distractor_quality": item["three_plausible_distinct_distractors"],
            "material_concerns": item["material_concerns"],
        })
    return {
        "provenance": [assessment_source, mapping_source, capture_source],
        "scope": "Join saved author/solver/teaching-auditor capture to its answer-hidden assessment. This trial used the authored_solution feedback contract, not a claim about current deployment or population accuracy.",
        "counts": counts, "rows": rows,
    }


def historical_solver_replay():
    capture, provenance = load_evidence("runtime-qualification-capture-20260908.json")
    call = capture["calls"][0]
    text = call["request"]["messages"][0]["content"][0]["text"]
    items = json.loads(text.split("\n", 1)[1].rsplit("\n", 1)[0])["items"]
    records = validate_batch(call["observation"]["response"]["text"], items)
    cardinalities = [1, 0, 0, 2, 1]
    rows = []
    for item, record, expected in zip(items, records, cardinalities, strict=True):
        supported = [r["choice"] for r in record["choices"] if r["judgment"] == "supported"]
        rows.append({"index": item["index"], "prompt": item["prompt"],
                     "expected_supported_count": expected, "declared_supported": supported,
                     "cardinality_agrees": len(supported) == expected})
    return {"provenance": provenance, "scope": "One actual saved Sonnet solver call on five fixed simple controls, revalidated with today's exact complete-choice parser.",
            "counts": {"items": len(rows), "correct_cardinality": sum(r["cardinality_agrees"] for r in rows)}, "rows": rows}


def run():
    return {
        "experiment": "choice-reliability-20260921-offline",
        "network_calls": 0,
        "source_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
        "runtime_source_sha256": {
            name: hashlib.sha256((SERVICE / name).read_bytes()).hexdigest()
            for name in ("question_quality.py", "request_contract.py", "complete_question_solution.py")
        },
        "synthetic": synthetic_probe(),
        "historical_author_sanitizer": historical_author_replay(),
        "historical_pipeline": historical_pipeline_assessment(),
        "historical_solver": historical_solver_replay(),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = run()
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: value.get("counts") for key, value in report.items() if isinstance(value, dict)}, indent=2))
