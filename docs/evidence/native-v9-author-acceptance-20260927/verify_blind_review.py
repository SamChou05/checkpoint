"""Bind the locked author-only review to the withheld display map and source."""

import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
HASHES = {
    "plan.json": "fdaf5ba1558c578aec177ba289f894577d65ddc57de1e86177fa5550d7d2d9ab",
    "capture.json": "17575d5a62b1fde235c3d43c7c9bc1d9e40385466e30b973fde1ca9cf1bbc9aa",
    "offline-replay.json": "00e3d6638a6095bc0edddf668388f76ca893c1d51be23606d2f64a6254c99722",
    "blind-official/worksheet.json": "f1cf83c7ea68e7b1796572316f09e408940b0e880f5297b39e1adeaac39d55b7",
    "blind-official/RUBRIC.md": "5d247f82c0a8dc62ad4cb2f0c557617ee6545909f75fdf10ddf5c3ed2ad9b9ee",
    "blind-private.json": "3392b07bad490ded6a3ed0bbd1a488c376939aa7c5a3c73fe7dcf042886ed431",
    "blind-review.json": "d2d7c28fd0366e2aed68ffbca30498179fb7ccf1805312f9cc0779e0ddf8be36",
}
PAIRS = {"A-B", "A-C", "A-D", "B-C", "B-D", "C-D"}


def load(name):
    raw = (HERE / name).read_bytes()
    if hashlib.sha256(raw).hexdigest() != HASHES[name]:
        raise ValueError(f"Frozen blind-review input changed: {name}")
    return raw.decode() if name.endswith(".md") else json.loads(raw)


def verify():
    plan, capture, replay = load("plan.json"), load("capture.json"), load("offline-replay.json")
    worksheet, private, review = (load("blind-official/worksheet.json"),
                                  load("blind-private.json"), load("blind-review.json"))
    load("blind-official/RUBRIC.md")
    if (capture["plan_sha256"] != HASHES["plan.json"] or capture["status"] != "failed"
            or capture["error"]["type"] != "TypeError"
            or capture["sts_calls"] != 1 or capture["converse_calls"] != 1
            or replay["plan_sha256"] != HASHES["plan.json"]
            or replay["capture_sha256"] != HASHES["capture.json"]
            or private["capture_sha256"] != HASHES["capture.json"]
            or private["replay_sha256"] != HASHES["offline-replay.json"]
            or private["worksheet_sha256"] != HASHES["blind-official/worksheet.json"]
            or plan["current_schema_bytes"] != 2156):
        raise ValueError("Author-only provenance changed")
    rows = worksheet["items"]
    ids = [row["id"] for row in rows]
    reviewed = {row["id"]: row for row in review["items"]}
    if (worksheet["candidate_count"] != 5 or len(ids) != len(set(ids)) or len(ids) != 5
            or len(reviewed) != 5
            or not (set(ids) == set(private["mapping"]) == set(reviewed))):
        raise ValueError("Worksheet or review lost a candidate")
    bound = []
    for row in rows:
        identity = row["id"]
        mapping = private["mapping"][identity]
        slot = mapping["original_author_slot"]
        question = replay["candidate_questions"][slot]
        indices = mapping["display_to_source_index"]
        if (sorted(indices) != [0, 1, 2, 3] or row["stem"] != question["prompt"]
                or row["choices"] != {letter: question["choices"][index]
                                      for letter, index in zip("ABCD", indices, strict=True)}):
            raise ValueError("A displayed candidate differs from offline replay")
        key = mapping["correct_display_label"]
        if row["choices"][key] != question["expectedAnswer"]:
            raise ValueError("Private display key differs from the candidate key")
        judged = reviewed[identity]
        pairs = judged["choice_pairs"]
        if (judged["correct_choice"] != key or judged["self_contained"] is not True
                or judged["objective_visible"] is not True
                or judged["difficulty_1_to_5"] not in (2, 3)
                or len(pairs) != 6 or {pair["pair"] for pair in pairs} != PAIRS
                or not all(pair["meaningfully_distinct"] for pair in pairs)):
            raise ValueError("Locked answer, stem, difficulty or choice-pair judgment failed")
        bound.append({"worksheet_id": identity, "original_author_slot": slot,
                      "source_key_display_label": key,
                      "review_selected_source_key": True,
                      "meaningfully_distinct_pairs": 6,
                      "difficulty": judged["difficulty_1_to_5"]})
    if sorted(row["original_author_slot"] for row in bound) != list(range(5)):
        raise ValueError("Original author slots are not represented once each")
    if (review["summary"]["strong_within_batch_near_duplicates"] is not False
            or review["summary"]["semantically_distinct_choice_pairs"] != 30):
        raise ValueError("Locked batch-level judgment changed")
    return {
        "frozen_source_sha256": HASHES,
        "reviewer_count": 1,
        "author_only_compiled_candidates": 5,
        "full_worker_returned_questions_in_this_trial": 0,
        "all_reviewed_display_keys_match_exact_source": True,
        "correct_reviewed_keys": 5,
        "meaningfully_distinct_pairs_reviewed": 30,
        "self_contained_stems_reviewed": 5,
        "difficulty_2_or_3_reviewed": 5,
        "strong_within_batch_near_duplicates_reported": False,
        "review_files_embed_worksheet_digest": False,
        "capture_status_remains_failed": True,
        "rows": bound,
    }


if __name__ == "__main__":
    result = verify()
    with (HERE / "post-lock-verification.json").open("x") as stream:
        json.dump(result, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps({key: value for key, value in result.items() if key not in {"frozen_source_sha256", "rows"}}, indent=2))
