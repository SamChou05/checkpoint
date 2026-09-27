"""Check that two locked blind reviews match the hidden synthetic bank keys."""

import hashlib
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
HASHES = {
    "worksheet.json": "2150bc0f199789e7a6a9345ea44912fb8c1d9b843c688f904e8f4f3dc5bedf85",
    "private.json": "d9e30f23237275b5ac1608110509c069d0e4cff8a1642588a0f0876c9980265c",
    "review-a.json": "3171efc7ee3fa5a3e169016018b6438630a6e14f5272cdbf9b0329d2f0b999ef",
    "review-b.json": "add45083dd8403c6c604d866e168b4032b6ad3d193891b4c331dadaa4d946525",
}


def load(name):
    content = (HERE / name).read_bytes()
    assert hashlib.sha256(content).hexdigest() == HASHES[name], name
    return json.loads(content)


def audit():
    worksheet = load("worksheet.json")
    private = load("private.json")["mapping"]
    reviews = [load("review-a.json"), load("review-b.json")]
    visible = {item["id"]: item for item in worksheet["items"]}
    assert len(visible) == len(private) == 15
    assert all("key" not in item and "expectedAnswer" not in item
               for item in worksheet["items"])
    strong = []
    difficulty_three = []
    for review in reviews:
        assert review["worksheet_sha256"] == HASHES["worksheet.json"]
        answers = {item["id"]: item["answer"] for item in review["items"]}
        assert len(answers) == 15 and set(answers) == set(visible)
        assert all(answers[item_id] == row["key"] for item_id, row in private.items())
        assert all(visible[item_id]["choices"][row["key"]] == row["row"]["expectedAnswer"]
                   for item_id, row in private.items())
        assert all(len(set(item["choices"].values())) == 4 for item in visible.values())
        strong.append({tuple(sorted(pair["ids"])) for pair in review["near_duplicates"]
                       if pair["strength"] == "strong"})
        difficulty_three.append({item["id"] for item in review["items"]
                                 if item["difficulty"] >= 3})
    consensus = sorted(strong[0] & strong[1])
    assert consensus == [("B01", "B07"), ("B01", "B12"),
                         ("B07", "B12"), ("B10", "B13")]
    assert difficulty_three[0] == {"B05", "B08", "B14"}
    assert difficulty_three[1] == {"B02", "B05", "B06", "B08", "B10", "B11", "B14", "B15"}
    return {"items": 15, "reviewer_key_matches": [15, 15],
            "consensus_strong_pairs": consensus,
            "above_requested_difficulty": [len(ids) for ids in difficulty_three],
            "provider_calls": 0}


if __name__ == "__main__":
    print(json.dumps(audit(), sort_keys=True))
