"""Verify both answer-blind reviews against their post-lock private mappings."""

import hashlib
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
WORKSHEET_HASHES = {
    "": "73415d0a33dd50412a7cc2d112cd4251e1c3502cb42292cd00bd7615e531b021",
    "cross-": "94c6cedbd4d7e877fad16b6ca8012ff2b4a76ef0a7287a65438474c5d96aec6a",
}


def audit() -> dict[str, int]:
    results = {}
    for prefix, expected_hash in WORKSHEET_HASHES.items():
        worksheet_path = HERE / f"{prefix}worksheet.json"
        actual_hash = hashlib.sha256(worksheet_path.read_bytes()).hexdigest()
        if actual_hash != expected_hash:
            raise ValueError(f"{prefix}worksheet changed after the review lock")
        worksheet = json.loads(worksheet_path.read_text())
        private = json.loads((HERE / f"{prefix}private.json").read_text())
        review = json.loads((HERE / f"{prefix}review.json").read_text())
        if review["sourceSha256"] != actual_hash:
            raise ValueError(f"{prefix}review references a different worksheet")
        expected = {item["id"]: item["displayKey"] for item in private}
        answers = {item["id"]: item["answer"] for item in private}
        offered = {item["id"]: item["choices"] for item in worksheet["items"]}
        returned = {item["id"]: item["soleCorrectLabel"] for item in review["items"]}
        if set(expected) != set(offered) or expected != returned:
            raise ValueError(f"{prefix}reviewer key mismatch")
        if any(offered[ident][label] != answers[ident] for ident, label in expected.items()):
            raise ValueError(f"{prefix}private key is absent from the displayed choices")
        results[prefix or "within_family"] = len(expected)
    return results


if __name__ == "__main__":
    print(json.dumps(audit(), sort_keys=True))
