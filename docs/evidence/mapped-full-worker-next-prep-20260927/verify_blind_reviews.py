"""Bind the two locked answer-blind reviews to the exact five returned questions."""

import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
HASHES = {
    "plan.json": "7be1e0b7079d4007623d39481189db48de016c459af89766d49367ae1a5d0bdb",
    "capture.json": "1ab308db5ea2aeedea0655a7886886c4851fbfa9278b22b5c9413cacaf45af4a",
    "blind-official/worksheet.json": "e3ef5bc39766b81bd0ed7655f68e246b635e769bab13cfdf883ff4c38e51a8d5",
    "blind-official/RUBRIC.md": "0ab4d3c62d3a0212fea5bf80c2d64a31ad4281e235af17b2b5b56ab35aacebd2",
    "blind-private-returned_output.json": "1ec235e7ea4ac922c6ac595fec26ad33e794a048be4f1c9d9eec91374e673bdc",
    "blind-review-a.json": "0ede220154a8bce51f02e89e57aff12184e80fec607b0063f0e2634a1b792175",
    "blind-review-b.json": "68ce3f66abf50d8bca2c0969b219b6438249a0c782b219061408ab1b63243dcb",
}
PAIRS = {"A-B", "A-C", "A-D", "B-C", "B-D", "C-D"}


def load(name):
    raw = (HERE / name).read_bytes()
    if hashlib.sha256(raw).hexdigest() != HASHES[name]:
        raise ValueError(f"Frozen source changed: {name}")
    if name.endswith(".md"):
        return raw.decode()
    return json.loads(raw)


def verify():
    plan, capture = load("plan.json"), load("capture.json")
    worksheet = load("blind-official/worksheet.json")
    load("blind-official/RUBRIC.md")
    private = load("blind-private-returned_output.json")
    review_a, review_b = load("blind-review-a.json"), load("blind-review-b.json")
    if (capture["plan"] != plan or capture["plan_sha256"] != HASHES["plan.json"]
            or private["plan_sha256"] != HASHES["plan.json"]
            or private["capture_sha256"] != HASHES["capture.json"]
            or private["worksheet_sha256"] != HASHES["blind-official/worksheet.json"]
            or capture["summary"]["returned_questions"] != 5
            or len(capture["calls"]) != 3):
        raise ValueError("Plan, capture, or private-map provenance changed")
    job = capture["jobs"][0]
    by_slot = dict(zip(job["returned_slot_ordinals"], job["returned"], strict=True))
    if (set(by_slot) != set(range(5)) or worksheet["requested_slots"] != 5
            or len(worksheet["items"]) != 5):
        raise ValueError("An originally requested slot is missing")
    rows = worksheet["items"]
    ids = [row["id"] for row in rows]
    a_rows = {row["id"]: row for row in review_a["items"]}
    b_rows = {row["id"]: row for row in review_b["items"]}
    if (len(set(ids)) != 5 or len(a_rows) != 5 or len(b_rows) != 5
            or not (set(ids) == set(private["mapping"]) == set(a_rows) == set(b_rows))):
        raise ValueError("Worksheet and review IDs differ")

    bound_rows = []
    for row in rows:
        identity = row["id"]
        mapping = private["mapping"][identity]
        slot = mapping["original_slot"]
        question = by_slot[slot]
        indices = mapping["display_to_source_index"]
        if (sorted(indices) != [0, 1, 2, 3]
                or row.get("unavailable") is True
                or row["stem"] != question["prompt"]
                or row["choices"] != {letter: question["choices"][index]
                                       for letter, index in zip("ABCD", indices, strict=True)}):
            raise ValueError("Displayed question differs from returned source")
        key = mapping["correct_display_label"]
        if row["choices"][key] != question["expectedAnswer"]:
            raise ValueError("Private key differs from captured key")
        a, b = a_rows[identity], b_rows[identity]
        if (a["answer"] != key or b["selected_answer"] != key
                or a["answer_status"] != "single_correct"
                or b["answer_status"] != "single_supported_answer"
                or set(a["choice_pairs"]) != PAIRS
                or set(b["choice_pair_meaningfully_distinct"]) != PAIRS
                or not all(pair["meaningfully_distinct"] for pair in a["choice_pairs"].values())
                or not all(b["choice_pair_meaningfully_distinct"].values())
                or a["stem_self_contained"] is not True
                or b["stem_self_contained"] is not True):
            raise ValueError("A locked answer or choice-pair judgment did not pass")
        bound_rows.append({
            "worksheet_id": identity, "original_slot": slot,
            "correct_display_label": key, "both_reviews_choose_key": True,
            "both_reviews_say_single_answer": True,
            "both_reviews_say_six_meaningfully_distinct_pairs": True,
            "both_reviews_say_self_contained": True,
            "review_a_difficulty": a["difficulty"],
            "review_b_difficulty": b["difficulty_1_to_5"],
            "skill_id": question["skillID"], "objective_id": question["objectiveID"],
        })
    if sorted(row["original_slot"] for row in bound_rows) != list(range(5)):
        raise ValueError("Worksheet did not cover each original slot once")
    near_a = {frozenset(pair["ids"]) for pair in review_a["batch"]["strong_near_duplicate_pairs"]}
    near_b = {frozenset(pair["ids"]) for pair in review_b["strong_near_duplicate_question_pairs"]}
    grammar_ids = frozenset(row["worksheet_id"] for row in bound_rows if row["original_slot"] in (3, 4))
    if grammar_ids not in near_a or grammar_ids not in near_b:
        raise ValueError("Locked novelty concerns were not preserved")
    return {
        "source_sha256": HASHES,
        "review_input_binding": "IDs, displayed labels, and external locked file hashes; reviews do not embed worksheet SHA-256",
        "original_requested_slots": 5,
        "returned_slots": 5,
        "both_reviewers_correct_single_keys": 5,
        "meaningfully_distinct_pairs_per_reviewer": 30,
        "both_reviewers_self_contained": 5,
        "difficulty_review_a": [row["review_a_difficulty"] for row in sorted(bound_rows, key=lambda row: row["original_slot"])],
        "difficulty_review_b": [row["review_b_difficulty"] for row in sorted(bound_rows, key=lambda row: row["original_slot"])],
        "both_reviewers_flag_grammar_near_duplicate": True,
        "reviewers_saw_authored_teaching": False,
        "reviewers_saw_hidden_objective_assignments": False,
        "rows": bound_rows,
    }


if __name__ == "__main__":
    record = verify()
    with (HERE / "blind-verification.json").open("x") as stream:
        json.dump(record, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps({key: value for key, value in record.items() if key not in {"source_sha256", "rows"}}, indent=2))
