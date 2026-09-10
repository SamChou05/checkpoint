"""Aggregate frozen independent assessments under the prospective joint rules."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("capture", type=Path)
parser.add_argument("assessment", type=Path)
args = parser.parse_args()
capture = json.loads(args.capture.read_text())
directory = args.assessment
mapping = json.loads((directory / "private-mapping.json").read_text())["items"]
ids = {row["id"] for row in mapping}
assessments = {}
for phase in ["first", "teaching"]:
    for assessor in ["a", "b"]:
        data = json.loads((directory / f"{phase}-assessment-{assessor}.json").read_text())
        assert len(data["items"]) == len(ids)
        indexed = {row["id"]: row for row in data["items"]}
        assert set(indexed) == ids
        assessments[phase, assessor] = indexed

def score(row, assessor):
    first = assessments["first", assessor][row["id"]]
    teaching = assessments["teaching", assessor][row["id"]]
    question = row["question"]
    key = (first["premise_status"] == "valid" and first["uniquely_answerable"] is True
           and first["supported_choices"] == [question["expectedAnswer"]])
    taught = all(teaching[field] is True for field in [
        "all_displayed_feedback_supported", "worked_solution_complete", "shuffle_safe"])
    useful = (key and taught and first["goal_fit"] is True
              and first["distractors_adequate"] is True and first["shuffle_safe"] is True
              and type(first["assessed_difficulty"]) is int
              and first["assessed_difficulty"] >= 3)
    return {"supported_key": key, "complete_teaching": taught, "useful": useful}

items = []
for row in mapping:
    scores = {assessor: score(row, assessor) for assessor in ["a", "b"]}
    items.append({"id": row["id"], "operation_index": row["operation_index"],
                  "arm": row["arm"], "case_id": row["case_id"], "assessors": scores,
                  "joint": {field: all(scores[a][field] for a in ["a", "b"])
                            for field in scores["a"]}})

operations = []
for index, operation in enumerate(capture["operations"]):
    rows = [item for item in items if item["operation_index"] == index]
    assert len(rows) == len(operation["questions"])
    calls = [call for call in capture["calls"] if call["operation_index"] == index]
    tokens = {key: sum(((c.get("observation") or {}).get("response") or {}).get("usage", {}).get(key, 0)
                      for c in calls if (((c.get("observation") or {}).get("response") or {}).get("usage")) is not None)
              for key in ["inputTokens", "outputTokens"]}
    operations.append({"operation_index": index, "arm": operation["arm"],
        "case_id": operation["case_id"], "status": operation["status"],
        "result_category": operation.get("result_category"), "requested_count": 5,
        "returned_count": len(rows), "joint": {field: sum(row["joint"][field] for row in rows)
                                               for field in ["supported_key", "complete_teaching", "useful"]},
        "prepared_calls": len(calls), "known_tokens": tokens,
        "runtime_metrics": operation.get("metrics"),
        "delivery_observation": operation.get("delivery_observation")})

arms = {}
for arm in ["reviewer_written", "authored_solution"]:
    rows = [row for row in items if row["arm"] == arm]
    jobs = [job for job in operations if job["arm"] == arm]
    useful = sum(row["joint"]["useful"] for row in rows)
    calls = sum(job["prepared_calls"] for job in jobs)
    tokens = {key: sum(job["known_tokens"][key] for job in jobs) for key in ["inputTokens", "outputTokens"]}
    arms[arm] = {"planned_requests": 3, "requested_slots": 15,
        "attempted_requests": sum(job["status"] != "unattempted" for job in jobs),
        "runtime_returned": len(rows), "joint": {field: sum(row["joint"][field] for row in rows)
                                                for field in ["supported_key", "complete_teaching", "useful"]},
        "individual": {a: {field: sum(row["assessors"][a][field] for row in rows)
                           for field in ["supported_key", "complete_teaching", "useful"]} for a in ["a", "b"]},
        "precision_denominator": len(rows) if rows else None,
        "requests_with_five_returned": sum(job["returned_count"] == 5 for job in jobs),
        "requests_with_five_joint_useful": sum(job["joint"]["useful"] == 5 for job in jobs),
        "prepared_calls": calls, "known_tokens": tokens,
        "prepared_calls_per_joint_useful": calls / useful if useful else None,
        "known_tokens_per_joint_useful": {key: value / useful if useful else None for key, value in tokens.items()}}

result = {"capture_byte_sha256": hashlib.sha256(args.capture.read_bytes()).hexdigest(),
          "items": items, "operations": operations, "arms": arms,
          "scope": "Small selected comparison; all captured runtime returns retained. Unattempted requests remain explicit. Joint credits require both independent assessments; no root upgrades. Known token subtotals are not total usage when any call has unknown usage."}
(directory / "summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
print(json.dumps(arms, indent=2))
