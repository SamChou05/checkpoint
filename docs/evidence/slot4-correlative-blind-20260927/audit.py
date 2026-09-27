"""Verify two locked correlative-grammar reviews against the hidden keys."""

import hashlib
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
HASHES = {
    "worksheet.json": "0a4d6417329fb1924d797dbd846bb0511478812f6bcbc58afe28aafc9d775ca6",
    "private.json": "3adfb9a6fbb4a31148a05750e99a9d9cf4cc1eabbcab22dcacee1ebb274e4571",
    "review-a.json": "256d0ddfa3952aae84e83ed112551912b5d46f209ccffdfa976c9ab7fa2095f3",
    "review-b.json": "cc42114c410d1b9acc3655778d8069cf466a187fc56912db1e457886c8d0797d",
}


def load(name):
    data = (HERE / name).read_bytes()
    assert hashlib.sha256(data).hexdigest() == HASHES[name], name
    return json.loads(data)


def audit():
    worksheet = load("worksheet.json")
    private = load("private.json")["mapping"]
    reviews = [load("review-a.json"), load("review-b.json")]
    shown = {item["id"]: item for item in worksheet["items"]}
    assert len(shown) == len(private) == 8
    assert all("key" not in item and "expectedAnswer" not in item
               for item in worksheet["items"])
    naturalness = []
    for review, key_field in zip(reviews, ("correct_choice", "selected"), strict=True):
        assert review["worksheet_sha256"] == HASHES["worksheet.json"]
        items = {item["id"]: item for item in review["items"]}
        assert len(items) == 8 and set(items) == set(shown)
        assert all(items[id_][key_field] == private[id_]["key"] for id_ in items)
        assert all(shown[id_]["choices"][private[id_]["key"]] == private[id_]["row"]["expectedAnswer"]
                   for id_ in items)
        assert all(len(set(item["choices"].values())) == 4 for item in shown.values())
        naturalness.append([items[id_]["naturalness_1_to_5"] for id_ in sorted(items)])
    assert naturalness == [[3, 3, 3, 3, 4, 4, 4, 4], [3] * 8]
    return {"items": 8, "reviewer_key_matches": [8, 8],
            "naturalness_ranges": [
                [min(scores), max(scores)] for scores in naturalness],
            "provider_calls": 0}


if __name__ == "__main__":
    print(json.dumps(audit(), sort_keys=True))
