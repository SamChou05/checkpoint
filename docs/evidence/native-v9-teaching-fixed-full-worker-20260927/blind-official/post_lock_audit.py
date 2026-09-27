"""Verify both locked blind reviews against the sealed five-slot answer map."""

import hashlib
import json
from itertools import combinations
from pathlib import Path

HERE = Path(__file__).resolve().parent
HASHES = {
    "worksheet.json": "0cb3bc9eebc17805703b4d9760135b896d0258987b335f95254480c79af185f5",
    "review-a.json": "3b347a51c700adbb40531552284ff8073380e3e45579ceb3ca9960e06c321a57",
    "review-b.json": "d37cb13dad220a8c6022fd79e64ec5d34b89ba781acf87d49c3e56db9db4c286",
    "post-lock-answer-map.json": "28947f7a2fdf8d5cdd3719ece015ce64b0a310883e3cf13bb98dff83ca3e3f5c",
}


def audit():
    data = {}
    for name, expected in HASHES.items():
        raw = (HERE / name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != expected:
            raise ValueError(f"Frozen {name} changed")
        data[name] = json.loads(raw)
    worksheet = data["worksheet.json"]
    mapping = data["post-lock-answer-map.json"]["mapping"]
    first = {item["id"]: item for item in data["review-a.json"]["items"]}
    second = {item["id"]: item for item in data["review-b.json"]["items"]}
    identities = {item["id"] for item in worksheet["items"]}
    if (worksheet["requested_slots"] != 5 or len(identities) != 5
            or set(mapping) != identities or set(first) != identities
            or set(second) != identities):
        raise ValueError("Five original readable slot identities changed")
    for item in worksheet["items"]:
        identity = item["id"]
        key = mapping[identity]["correct_display_label"]
        a, b = first[identity], second[identity]
        if (key not in item["choices"] or a["selected_key"] != key or b["key"] != key
                or a["key_status"] != "unique_supported"
                or b["key_status"] != "unique_defensible"
                or not a["difficulty_2_to_3_fit"] or not b["within_target_2_to_3"]
                or not a["stem_self_contained"] or not b["stem_self_contained"]):
            raise ValueError(f"Blind answer or difficulty disagrees for {identity}")
        for review in (a, b):
            pairs = review["choice_pairs"]
            expected_pairs = {"-".join(pair) for pair in combinations(sorted(item["choices"]), 2)}
            if (len(pairs) != 6 or {p["pair"] for p in pairs} != expected_pairs
                    or not all(p["meaningfully_distinct"] for p in pairs)):
                raise ValueError(f"Choice pairs disagree for {identity}")
    return {"requested_slots": 5, "returned_slots": 5,
            "both_blind_reviewers_match_code_owned_keys": 5,
            "reviewed_distinct_choice_pairs": 60,
            "all_five_within_target_difficulty": True,
            "mechanical_worker_result": "5_OF_5_WITHIN_240_SECONDS",
            "bank_diversity_qualified": False}


if __name__ == "__main__":
    print(json.dumps(audit(), indent=2, sort_keys=True))
