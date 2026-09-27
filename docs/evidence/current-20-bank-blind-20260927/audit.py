"""Verify the locked blind review against the post-lock archived answer map."""

from __future__ import annotations

from collections import Counter
import hashlib
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
HASHES = {
    "worksheet.json": "ab3d3ab1b73c0bf6268a6c4cd5cc13d753ba804c77a1ca1e8e3635edbd960ab4",
    "review-a.json": "63c833dcf02aea88f4ee8343b308e9b1203a841744f467eec41ee9d9d8579c74",
    "post-lock-answer-map.json": "40be5690f5f5733a986f85c0a3bf87703466a225bedb728ac0f68c3582f303c2",
    "seed.json": "97311ad795e7936ffd0c79b338762770a27336d86d3200c24afc21bb0bad05f5",
}


def audit() -> dict:
    for name, expected in HASHES.items():
        actual = hashlib.sha256((HERE / name).read_bytes()).hexdigest()
        if actual != expected:
            raise AssertionError(f"Frozen {name} SHA-256 changed")
    worksheet = json.loads((HERE / "worksheet.json").read_text())
    review = json.loads((HERE / "review-a.json").read_text())
    private = json.loads((HERE / "post-lock-answer-map.json").read_text())
    expected_ids = [f"Q{number:02d}" for number in range(1, 21)]
    if ([item["id"] for item in worksheet["items"]] != expected_ids
            or [item["id"] for item in review["items"]] != expected_ids
            or set(private["mapping"]) != set(expected_ids)
            or private["worksheetSha256"] != HASHES["worksheet.json"]
            or review["worksheet_sha256_as_stated_in_rubric"] != HASHES["worksheet.json"]
            or review["items_reviewed"] != 20
            or review["source_scope"] != ["worksheet.json", "RUBRIC.md"]):
        raise AssertionError("Blind worksheet, review, or answer map differs")

    mismatches = []
    below_target = []
    for displayed, judgment in zip(worksheet["items"], review["items"], strict=True):
        identity = displayed["id"]
        hidden = private["mapping"][identity]
        row = hidden["row"]
        if (displayed["prompt"] != row["prompt"]
                or set(displayed["choices"]) != set("ABCD")
                or set(displayed["choices"].values()) != set(row["choices"])
                or displayed["choices"][hidden["key"]] != row["expectedAnswer"]
                or len(set(row["choices"])) != 4
                or row["choices"].count(row["expectedAnswer"]) != 1
                or set(row["choiceExplanations"]) != set(row["choices"])):
            raise AssertionError(f"Frozen prompt, choices, or code-owned key changed: {identity}")
        distinct = judgment["choice_distinctness"]
        if (distinct["pairs_checked"] != 6
                or distinct["all_pairs_meaningfully_distinct"] is not True
                or distinct["equivalent_or_format_only_pairs"] != []
                or judgment["self_contained"] is not True
                or judgment["objective_clear"] is not True):
            raise AssertionError(f"Review coverage or item judgment changed: {identity}")
        difficulty = judgment["difficulty_1_to_5"]
        if type(difficulty) is not int or difficulty not in range(1, 6):
            raise AssertionError(f"Review difficulty changed: {identity}")
        if judgment["target_difficulty_2_to_3_met"] != (difficulty in (2, 3)):
            raise AssertionError(f"Review difficulty flag differs: {identity}")
        if difficulty not in (2, 3):
            below_target.append({"id": identity, "difficulty": difficulty,
                                 "slot": hidden["slot"], "family": hidden["family"]})
        selected = judgment["selected_answer"]
        if type(selected) is not str or selected not in {"A", "B", "C", "D"}:
            raise AssertionError(f"Review lacked one selected choice: {identity}")
        if selected != hidden["key"]:
            mismatches.append({
                "id": identity, "reviewSelected": selected,
                "reviewSelectedText": displayed["choices"][selected],
                "codeOwnedKey": hidden["key"],
                "codeOwnedText": displayed["choices"][hidden["key"]],
                "slot": hidden["slot"], "family": hidden["family"],
            })

    comparisons = review["cross_item_comparison"]
    flagged = comparisons["near_duplicate_pairs"]
    pair_counts = Counter()
    seen_pairs = set()
    strong_pairs = []
    by_slots = Counter()
    for pair in flagged:
        ids = pair["ids"]
        if (len(ids) != 2 or ids[0] not in expected_ids or ids[1] not in expected_ids
                or ids[0] >= ids[1] or tuple(ids) in seen_pairs
                or pair["strength"] not in {"strong", "moderate"}
                or not pair["reason"].strip()):
            raise AssertionError("Flagged pair is duplicate, reversed, or incomplete")
        seen_pairs.add(tuple(ids))
        pair_counts[pair["strength"]] += 1
        first, second = (private["mapping"][identity] for identity in ids)
        slot_pair = sorted((first["slot"], second["slot"]))
        by_slots[f'{pair["strength"]}:{slot_pair[0]}-{slot_pair[1]}'] += 1
        if pair["strength"] == "strong":
            strong_pairs.append({
                "ids": ids,
                "batchById": {identity: private["mapping"][identity]["batch"]
                              for identity in ids},
                "slotById": {identity: private["mapping"][identity]["slot"]
                             for identity in ids},
                "familyById": {identity: private["mapping"][identity]["family"]
                               for identity in ids},
            })
    possible_pairs = 20 * 19 // 2
    if (comparisons["total_pairs_checked"] != possible_pairs
            or comparisons["unflagged_pairs_distinct"] != possible_pairs - len(flagged)
            or comparisons["strong_count"] != pair_counts["strong"]
            or comparisons["moderate_count"] != pair_counts["moderate"]):
        raise AssertionError("Cross-item pair arithmetic differs")

    return {
        "worksheetSha256": HASHES["worksheet.json"],
        "lockedReviewSha256": HASHES["review-a.json"],
        "postLockAnswerMapSha256": HASHES["post-lock-answer-map.json"],
        "items": 20,
        "codeOwnedSingleKeyAndFourLiteralDistinctChoices": 20,
        "reviewSelectedKeysMatchingCodeOwned": 20 - len(mismatches),
        "reviewSelectedKeyMismatches": mismatches,
        "reviewAllSixChoicePairsDistinctItems": 20,
        "reviewSelfContainedAndObjectiveClearItems": 20,
        "reviewTargetDifficultyItems": 20 - len(below_target),
        "reviewBelowTarget": below_target,
        "crossItemPairsArithmeticVerified": possible_pairs,
        "reviewStrongNearDuplicatePairs": strong_pairs,
        "reviewModerateNearDuplicatePairs": pair_counts["moderate"],
        "reviewUnflaggedPairs": comparisons["unflagged_pairs_distinct"],
        "flaggedPairCountsByOriginalSlots": dict(sorted(by_slots.items())),
        "semanticJudgmentsIndependentlyRecheckedByScript": False,
    }


if __name__ == "__main__":
    result = audit()
    rendered = json.dumps(result, sort_keys=True, indent=2, ensure_ascii=False) + "\n"
    path = HERE / "post-lock-audit.json"
    if path.exists():
        if path.read_text() != rendered:
            raise AssertionError("Post-lock audit changed")
    else:
        path.write_text(rendered)
    print(rendered)
