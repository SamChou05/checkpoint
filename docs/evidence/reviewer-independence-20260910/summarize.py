"""Derive paired observations from frozen evidence; no provider or storage API."""
import collections
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def read(name):
    return json.loads((ROOT / name).read_text())


def summarize():
    capture = read("capture.json")
    first = {(x["archive"], x["call_index"], x["item_index"]): x["id"]
             for x in read("mapping.json")}
    feedback = {(x["position"], x["item_index"]): x["id"]
                for x in read("feedback-mapping.json")}
    independent = {x["id"]: x for x in read("independent-feedback.json")["items"]}
    root = {x["id"]: x for x in read("root-feedback-notes.json")["assessments"]}
    controls = set(read("root-pre-response-notes.json")["uncontested_valid_controls"])
    calls = {x["position"]: x for x in capture["calls"]}
    results = {x["position"]: x for x in capture["results"]}
    rows, arms = [], collections.defaultdict(collections.Counter)
    for job in capture["plan"]["jobs"]:
        arm = job["arm"]
        result, call = results[job["position"]], calls[job["position"]]
        reviews = {}
        if result["stage_validation"] == "passed":
            reviews = {x["index"]: x for x in json.loads(call["observation"]["response"]["text"])["reviews"]}
        returned = {x["prompt"]: x for x in result.get("simulated_returned_questions", [])}
        arms[arm]["calls"] += 1
        for field in ("inputTokens", "outputTokens"):
            arms[arm][field] += call["observation"]["response"]["usage"][field]
        arms[arm]["adaptation_pass_calls"] += result["adaptation"] == "passed"
        for item in job["subject"]["items"]:
            subject_id = first[(job["origin_path"], job["archived_call_index"], item["index"])]
            opaque_id = feedback[(job["position"], item["index"])]
            review, admitted = reviews.get(item["index"]), returned.get(item["prompt"])
            if independent[opaque_id]["prior_subject_id"] != subject_id:
                raise ValueError("Independent assessment subject join changed.")
            row = {"subject_id": subject_id, "arm": arm, "position": job["position"],
                   "opaque_review_id": opaque_id, "correlated_review_available": review is not None,
                   "declared_valid": review["valid"] if review else None,
                   "declared_answer": review["answer"] if review else None,
                   "model_difficulty": review["difficulty"] if review else None,
                   "local_policy_return": admitted is not None,
                   "independent_verdict_assessment": independent[opaque_id]["verdict_assessment"],
                   "independent_main_support": independent[opaque_id]["main_support"]["status"],
                   "independent_choice_support_counts": dict(collections.Counter(
                       x["status"] for x in independent[opaque_id]["choice_feedback_support"])),
                   "root_feedback_assessment": root[opaque_id]["assessment"],
                   "root_feedback_issues": root[opaque_id]["issues"]}
            rows.append(row)
            arms[arm]["planned_item_occurrences"] += 1
            arms[arm]["correlated_reviews"] += review is not None
            arms[arm]["local_policy_returns"] += admitted is not None
            arms[arm]["uncontested_control_returns"] += admitted is not None and subject_id in controls
            arms[arm]["clear_spreadsheet_defect_approvals"] += bool(review and review["valid"] and subject_id == "item04")
            arms[arm]["clear_spreadsheet_defect_returns"] += admitted is not None and subject_id == "item04"
            arms[arm]["independent_supported_complete_feedback"] += (
                independent[opaque_id]["verdict_assessment"] == "approved_valid_item_with_supported_feedback")
            arms[arm]["root_supported_complete_feedback"] += (
                root[opaque_id]["assessment"] == "supported_under_predeclared_interpretation")
    pairs = []
    for subject_id in sorted(set(x["subject_id"] for x in rows)):
        pair = {x["arm"]: x for x in rows if x["subject_id"] == subject_id}
        if set(pair) != {"solver_context", "withheld_solver_context"}:
            raise ValueError("Each fixed subject needs exactly both arms.")
        available = all(x["correlated_review_available"] for x in pair.values())
        pairs.append({"subject_id": subject_id, "both_correlated": available,
                      "same_declared_answer": available and len({x["declared_answer"] for x in pair.values()}) == 1,
                      "arms": pair})
    return {
        "scope": "Selected paired diagnostic, not a production accuracy estimate. All12 subjects remain in each arm. Five unavailable treatment slots are format losses, not semantic catches. Independent and root interpretation differences are preserved; complete-feedback counts are descriptive and not new success thresholds.",
        "plan_sha256": capture["plan_sha256"],
        "capture_byte_sha256": hashlib.sha256((ROOT / "capture.json").read_bytes()).hexdigest(),
        "arms": {k: dict(v) for k, v in arms.items()},
        "paired_correlated_subjects": sum(p["both_correlated"] for p in pairs),
        "paired_same_declared_answer": sum(p["same_declared_answer"] for p in pairs),
        "pairs": pairs,
        "prospective_result": "Does not qualify withholding: both arms return the unequivocally defective spreadsheet item; treatment loses five subjects to malformed review records and supplies additional incorrect ecology arithmetic. No production intervention follows.",
    }


if __name__ == "__main__":
    result = summarize()
    (ROOT / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: result[k] for k in ("arms", "paired_correlated_subjects", "paired_same_declared_answer")}))
