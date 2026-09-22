"""Project completed runtime returns without keys, teaching or model judgments."""

import hashlib
import json
from pathlib import Path


def main():
    directory = Path(__file__).resolve().parent
    capture_path = directory / "capture.json"
    capture = json.loads(capture_path.read_text())
    assert capture["status"] == "completed_pending_review"
    jobs = {job["id"]: job for job in capture["plan"]["jobs"]}
    items = []
    for job in capture["jobs"]:
        for index, question in enumerate(job["returned"]):
            identity = f'{job["id"]}:{index}'
            choices = question["choices"]
            assert len(choices) == 4 and all(isinstance(value, str) for value in choices)
            rotation = int(hashlib.sha256(identity.encode()).hexdigest(), 16) % 4
            reordered = choices[rotation:] + choices[:rotation]
            items.append({
                "id": identity,
                "prompt": question["prompt"],
                "choices": dict(zip("ABCD", reordered, strict=True)),
                "skillID": question.get("skillID"),
                "objectiveID": question.get("objectiveID"),
            })
    worksheet = {
        "capture_sha256": hashlib.sha256(capture_path.read_bytes()).hexdigest(),
        "planned_questions": 15,
        "returned_questions": len(items),
        "projection": "Returned stem and four choices only; rotation is derived solely from item ID. Keys, teaching, difficulty labels, provenance and model judgments are hidden.",
        "instructions": "Independently solve each item and assess uniqueness, distinct/plausible alternatives, sufficient premises, scope/assignment fit and difficulty. Lock judgments before opening the capture or explanations. Keep uncertainty explicit.",
        "jobs": [{"id": job["id"], "request": jobs[job["id"]]["request"],
                  "returned": len(job["returned"]), "within_deadline": job["within_deadline"]}
                 for job in capture["jobs"]],
        "items": items,
    }
    destination = directory / "blind-items.json"
    with destination.open("x") as stream:
        json.dump(worksheet, stream, ensure_ascii=True, indent=2, allow_nan=False)
        stream.write("\n")
    assert hashlib.sha256(capture_path.read_bytes()).hexdigest() == worksheet["capture_sha256"]
    print(json.dumps({"worksheet": str(destination), "items": len(items),
                      "worksheet_sha256": hashlib.sha256(destination.read_bytes()).hexdigest()}))


if __name__ == "__main__":
    main()
