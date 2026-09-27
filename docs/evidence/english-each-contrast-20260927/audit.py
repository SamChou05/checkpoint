"""Verify two locked blind reviews against the post-lock 20-item answer map."""

from __future__ import annotations

from collections import Counter
from itertools import combinations
import hashlib
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
HASHES = {
    "worksheet.json": "636811004c5b9d3e99a275a432222f2af51fcd6748a453805b27088264146b18",
    "summary.json": "3b8669a3c1b46832eb77b3654eeb2e8231e150c8dc8147cfe51ff7af7286f5dc",
    "blind-review-a.json": "46ed9c44a4c988dda8ee81ebae42e569fece7c3fdfbca02eb507fe7fc3fe2b01",
    "blind-review-b.json": "1c1a72cc93ccf1cf9f18da23866e19c6b9666fde2cbaf018c03f06f61bccf4cc",
    "post-lock-answer-map.json": "f33733e1d451ca3d77cd7cd9ac5caafc9a538645ecc642fd549c88daa2a384eb",
}


def _loaded(name: str) -> dict:
    path = HERE / name
    if hashlib.sha256(path.read_bytes()).hexdigest() != HASHES[name]:
        raise AssertionError(f"Frozen {name} changed")
    return json.loads(path.read_text())


def audit() -> dict:
    worksheet = _loaded("worksheet.json")
    summary = _loaded("summary.json")
    review_a = _loaded("blind-review-a.json")
    review_b = _loaded("blind-review-b.json")
    answer_map = _loaded("post-lock-answer-map.json")
    assert (summary["worksheetSha256"] == review_a["worksheet_sha256"]
            == review_b["source_sha256"] == answer_map["worksheetSha256"]
            == HASHES["worksheet.json"])
    assert review_a["frozen_before_answer_map"] is True
    ids = [item["id"] for item in worksheet["items"]]
    assert len(ids) == 20 and len(set(ids)) == 20
    assert ids == [item["id"] for item in review_a["items"]]
    assert ids == [item["id"] for item in review_b["items"]]
    expected_choice_pairs = {"-".join(pair) for pair in combinations("ABCD", 2)}
    for item, a, b in zip(worksheet["items"], review_a["items"],
                          review_b["items"], strict=True):
        locked = answer_map["mapping"][item["id"]]
        assert item["prompt"] == locked["row"]["prompt"]
        assert item["choices"][locked["key"]] == locked["row"]["expectedAnswer"]
        assert a["selected_key"] == b["selected_key"] == locked["key"]
        assert b["selected_text"] == locked["row"]["expectedAnswer"]
        assert a["unique_supported_key"] is True and b["ambiguity"] == "none"
        assert a["difficulty_target_2_to_3_met"] is True and b["target_2_to_3"] == "within"
        assert {pair["pair"] for pair in a["all_six_within_item_pairs"]} == expected_choice_pairs
        assert {"-".join(pair["choices"]) for pair in b["six_within_item_option_pair_reviews"]} == expected_choice_pairs
        assert all(pair["judgment"].startswith("distinct") for pair in a["all_six_within_item_pairs"])
        assert all(pair["judgment"].startswith("distinct")
                   for pair in b["six_within_item_option_pair_reviews"])
    all_pairs = set(combinations(ids, 2))
    pairs_a = review_a["all_190_cross_item_pairs"]
    pairs_b = review_b["all_190_cross_item_pair_reviews"]
    assert {tuple(pair["pair"]) for pair in pairs_a} == all_pairs
    assert {tuple(pair["items"]) for pair in pairs_b} == all_pairs
    counts_a = Counter(pair["strength"] for pair in pairs_a)
    counts_b = Counter(pair["overlap"] for pair in pairs_b)
    assert counts_a == {"none": 169, "moderate": 19, "strong": 2}
    assert counts_b == {"none": 128, "low": 39, "moderate": 21, "high": 2}
    top_a = {tuple(pair["pair"]) for pair in pairs_a if pair["strength"] == "strong"}
    top_b = {tuple(pair["items"]) for pair in pairs_b if pair["overlap"] == "high"}
    top_expected = {("Q05", "Q06"), ("Q11", "Q16")}
    assert top_a == top_b == top_expected
    q08_a = next(item for item in review_a["items"] if item["id"] == "Q08")
    q08_b = next(item for item in review_b["items"] if item["id"] == "Q08")
    assert q08_a["selected_key"] == q08_b["selected_key"] == "D"
    assert q08_a["difficulty_level_estimate"] in (2, 3)
    assert q08_b["difficulty_estimate_1_to_5"] in (2, 3)
    return {
        "worksheetSha256": HASHES["worksheet.json"],
        "reviewSha256": [HASHES["blind-review-a.json"], HASHES["blind-review-b.json"]],
        "answerMapSha256": HASHES["post-lock-answer-map.json"],
        "eachRoleItem": {"id": "Q08", "key": "D", "difficultyA": q08_a["difficulty_level_estimate"],
                         "difficultyB": q08_b["difficulty_estimate_1_to_5"]},
        "keysMatchedByBothReviewers": 20,
        "distinctWithinItemChoicePairsPerReviewer": 120,
        "crossItemPairsA": dict(sorted(counts_a.items())),
        "crossItemPairsB": dict(sorted(counts_b.items())),
        "topOverlapConsensus": [list(pair) for pair in sorted(top_expected)],
        "fullBankQualified": False,
    }


if __name__ == "__main__":
    result = audit()
    rendered = json.dumps(result, sort_keys=True, indent=2) + "\n"
    output = HERE / "post-lock-audit.json"
    if output.exists() and output.read_text() != rendered:
        raise AssertionError("Frozen post-lock audit changed")
    output.write_text(rendered)
    print(json.dumps(result, sort_keys=True))
