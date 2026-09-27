"""Recheck frozen worker return, two blind selections, and the sealed key map."""

import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
HASHES = {
    "worksheet.json": "8b6a40d007d174408e48e9bb535f81ea0dac90877c65d716a92c8bbc56e4224f",
    "review-a.json": "00f293a6b299425076f2e7f558cf8d1e0d91252d65a5a156c919404695e6ea19",
    "review-b.json": "8095ba73c8352c9f1cc36c8a8471de72eb67ce3baf69a2384a2a79c51b8fdbd0",
    "post-lock-answer-map.json": "f64df733b6ab1dc3ec96b981670d2d900eae33b0a806be9652b0199900d54866",
}


def audit():
    data = {}
    for name, expected in HASHES.items():
        raw = (HERE / name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != expected:
            raise ValueError(f"Frozen {name} changed")
        data[name] = json.loads(raw)
    worksheet = data["worksheet.json"]
    review_a = data["review-a.json"]
    review_b = data["review-b.json"]
    mapping = data["post-lock-answer-map.json"]["mapping"]
    if (worksheet["requested_slots"] != 5 or len(worksheet["items"]) != 5
            or len(review_a["items"]) != 5 or len(review_b["items"]) != 5
            or set(mapping) != {item["id"] for item in worksheet["items"]}):
        raise ValueError("Original slot or review cardinality changed")
    a_by_id = {item["id"]: item for item in review_a["items"]}
    b_by_id = {item["id"]: item for item in review_b["items"]}
    if len(a_by_id) != 5 or len(b_by_id) != 5:
        raise ValueError("Review IDs are duplicated")
    matches = 0
    missing = 0
    for item in worksheet["items"]:
        identity = item["id"]
        source = mapping[identity]
        a, b = a_by_id[identity], b_by_id[identity]
        if source.get("status") == "unavailable":
            if (a["status"] != "unavailable_placeholder"
                    or b["status"] != "unavailable_placeholder"):
                raise ValueError("Missing slot was relabeled")
            missing += 1
            continue
        key = source["correct_display_label"]
        if (a["status"] != "readable" or b["status"] != "readable"
                or key not in item["choices"]
                or a["single_correct_letter"] != key
                or b["unique_correct_letter"] != key
                or not a["all_six_pairs_distinct"]
                or not b["answer_unique"]
                or not all(pair["meaningfully_distinct"] for pair in b["choice_pairs"].values())):
            raise ValueError(f"Blind key or choice review disagrees for {identity}")
        matches += 1
    if (matches, missing) != (4, 1):
        raise ValueError("Official worker return count changed")
    return {"requested_slots": 5, "returned_slots": matches, "unfilled_slots": missing,
            "both_blind_reviewers_match_code_owned_keys": matches,
            "reviewed_distinct_choice_pairs": 2 * matches * 6,
            "official_qualification": "FAIL_4_OF_5"}


if __name__ == "__main__":
    print(json.dumps(audit(), indent=2, sort_keys=True))
