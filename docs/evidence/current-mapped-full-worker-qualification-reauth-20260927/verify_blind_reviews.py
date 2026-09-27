"""Verify locked answer-blind judgments against the private source map."""

import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
HASHES = {
    "capture.json": "5e05f1dcd05cb136b042828b89a3ddeeb8a83b8f7b986600e804f886a59cf2aa",
    "plan.json": "9b7803cf1587ec0833383b26e32c8a2bd97f0a06991d39a7eaa6daf9a76900eb",
    "blind-official/worksheet.json": "50012e6299b5507855559611772bd4c617a30c3e808d4c7781810d1e5939b4c6",
    "blind-official/RUBRIC.md": "0ab4d3c62d3a0212fea5bf80c2d64a31ad4281e235af17b2b5b56ab35aacebd2",
    "blind-private-returned_output.json": "13d4f64681477bcf56c9e539e8e6c5efd48f539589120e36a84e750878d85cc6",
    "blind-review-a.json": "4f2da7e03031ab05340e9a96a5e11f7dd7bac95cdcbb41eb7b8246f72ee4b502",
    "blind-review-b.json": "e3e413be7c16f603b05b1ce54f063af431df05db2ab98dec37289ae817336b57",
}
PAIRS = {"A-B", "A-C", "A-D", "B-C", "B-D", "C-D"}


def load(path):
    actual = hashlib.sha256((HERE / path).read_bytes()).hexdigest()
    if actual != HASHES[path]:
        raise ValueError(f"Frozen review source changed: {path}")
    return json.loads((HERE / path).read_text())


def check_hash(path):
    if hashlib.sha256((HERE / path).read_bytes()).hexdigest() != HASHES[path]:
        raise ValueError(f"Frozen review source changed: {path}")


def verify():
    capture = load("capture.json")
    plan = load("plan.json")
    worksheet = load("blind-official/worksheet.json")
    check_hash("blind-official/RUBRIC.md")
    private = load("blind-private-returned_output.json")
    a, b = load("blind-review-a.json"), load("blind-review-b.json")
    if (capture["plan"] != plan or capture["plan_sha256"] != HASHES["plan.json"]
            or private["capture_sha256"] != HASHES["capture.json"]
            or private["plan_sha256"] != HASHES["plan.json"]
            or private["worksheet_sha256"] != HASHES["blind-official/worksheet.json"]
            or a["worksheet_sha256"] != HASHES["blind-official/worksheet.json"]
            or b["input_sha256"]["worksheet.json"] != HASHES["blind-official/worksheet.json"]
            or a["rubric_sha256"] != HASHES["blind-official/RUBRIC.md"]
            or b["input_sha256"]["rubric.md"] != HASHES["blind-official/RUBRIC.md"]):
        raise ValueError("Review input or capture provenance mismatch")
    rows = worksheet["items"]
    ids = [row["id"] for row in rows]
    amap, bmap = ({row["id"]: row for row in review["items"]} for review in (a, b))
    if (len(ids) != len(set(ids)) or len(ids) != 5 or set(ids) != set(private["mapping"])
            or set(ids) != set(amap) or set(ids) != set(bmap)):
        raise ValueError("A worksheet row or review judgment is missing or duplicated")
    job = capture["jobs"][0]
    by_slot = dict(zip(job["returned_slot_ordinals"], job["returned"], strict=True))
    if len(by_slot) != 4:
        raise ValueError("Official returned-slot denominator changed")
    result_rows = []
    for row in rows:
        identity = row["id"]
        mapping = private["mapping"][identity]
        slot = mapping["original_slot"]
        ra, rb = amap[identity], bmap[identity]
        if row.get("unavailable"):
            if (slot in by_slot or mapping["status"] != "unavailable"
                    or ra["status"] != "unavailable_unfilled" or rb["status"] != "unavailable_placeholder"
                    or ra["correct_letter"] is not None or rb["answer"] is not None):
                raise ValueError("Unfilled source slot was treated as readable")
            result_rows.append({"worksheet_id": identity, "original_slot": slot,
                                "status": "unfilled", "both_reviews_mark_unfilled": True})
            continue
        question = by_slot[slot]
        indices = mapping["display_to_source_index"]
        if (sorted(indices) != [0, 1, 2, 3]
                or row["stem"] != question["prompt"]
                or row["choices"] != {label: question["choices"][index]
                                      for label, index in zip("ABCD", indices, strict=True)}):
            raise ValueError("Worksheet text does not match the exact returned question")
        key = mapping["correct_display_label"]
        if row["choices"][key] != question["expectedAnswer"]:
            raise ValueError("Private display key disagrees with the released literal key")
        if (ra["status"] != "readable" or rb["status"] != "readable"
                or ra["correct_letter"] != key or rb["answer"] != key
                or set(ra["pairwise_meaningful_distinctness"]) != PAIRS
                or set(rb["choice_pairs"]) != PAIRS
                or not all(ra["pairwise_meaningful_distinctness"].values())
                or not all(pair["meaningfully_distinct"] for pair in rb["choice_pairs"].values())
                or ra["self_contained"] is not True or rb["self_contained"] is not True
                or ra["difficulty_1_to_5"] != 2 or rb["estimated_difficulty_1_to_5"] != 2):
            raise ValueError("Locked answer or content judgments disagree with the source")
        result_rows.append({"worksheet_id": identity, "original_slot": slot,
                            "status": "returned", "correct_display_label": key,
                            "review_a_answer": ra["correct_letter"], "review_b_answer": rb["answer"],
                            "both_keys_correct": True, "choice_pairs_each_reviewer": 6,
                            "both_self_contained": True, "both_difficulty_2": True})
    if sorted(row["original_slot"] for row in result_rows) != list(range(5)):
        raise ValueError("Original slot identity disappeared")
    for row in result_rows:
        if row["original_slot"] in (3, 4):
            ra, rb = amap[row["worksheet_id"]], bmap[row["worksheet_id"]]
            if ("low" not in ra["within_batch_novelty"].lower()
                    or "limited" not in rb["within_batch_novelty"].lower()):
                raise ValueError("Grammar novelty concern was not independently recorded")
    return {"hashes": HASHES, "reviewers": ["blind_a", "blind_b"],
            "official_original_slots": 5, "readable_returned_slots": 4,
            "unfilled_slots": 1, "both_reviewers_correct_keys": 4,
            "meaningfully_distinct_choice_pairs_per_reviewer": 24,
            "both_reviewers_self_contained": 4, "both_reviewers_difficulty_2": 4,
            "both_reviewers_flag_grammar_format_overlap": True,
            "hidden_objective_alignment_assessed_by_reviewers": False,
            "rows": result_rows}


if __name__ == "__main__":
    record = verify()
    with (HERE / "blind-verification.json").open("x") as stream:
        json.dump(record, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps({key: value for key, value in record.items() if key not in {"hashes", "rows"}}, indent=2))
