"""Prepare every runtime return for two-stage masked assessment, without selection."""
import argparse
import hashlib
import json
from pathlib import Path
import random


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


parser = argparse.ArgumentParser()
parser.add_argument("capture", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
capture = json.loads(args.capture.read_text())
assert capture["plan"]["experiment"] == "worker-delivery-feedback-comparison-v1"
assert capture["status"] in {"completed", "operational_failure"}
cases = {case["case_id"]: case["payload"] for case in capture["plan"]["origin"]["cases"]}
rows = []
for operation_index, operation in enumerate(capture["operations"]):
    for question_index, question in enumerate(operation["questions"]):
        rows.append((operation_index, question_index, operation, question))
random.SystemRandom().shuffle(rows)
first, teaching, mapping = [], [], []
for index, (operation_index, question_index, operation, question) in enumerate(rows, 1):
    item_id = f"q{index:02d}"
    context = cases[operation["case_id"]]
    first.append({"id": item_id, "goal": context["goal"],
                  "sourceDocuments": context.get("sourceDocuments", []),
                  "prompt": question["prompt"], "choices": question["choices"]})
    main = question["explanation"]
    by_choice = question.get("choiceExplanations", {})
    composed = []
    for choice in question["choices"]:
        feedback = by_choice.get(choice, "")
        display = feedback + "\n\n" + main if feedback.strip() and feedback != main else main
        composed.append({"selectedChoice": choice, "displayedFeedback": display})
    teaching.append({"id": item_id, "explanation": main,
                     "choiceExplanations": by_choice, "composedFeedback": composed})
    mapping.append({"id": item_id, "operation_index": operation_index,
                    "question_index": question_index, "arm": operation["arm"],
                    "case_id": operation["case_id"], "question": question})

args.output.mkdir(parents=True, exist_ok=False)
write(args.output / "stems-and-choices.json", {"items": first})
write(args.output / "teaching.json", {"items": teaching})
write(args.output / "private-mapping.json", {"items": mapping})
write(args.output / "packet-manifest.json", {
    "capture_byte_sha256": digest(args.capture), "plan_sha256": capture["plan_sha256"],
    "returned_item_count": len(rows), "requested_slots": 30,
    "selection": "Every captured operation question, including any partial result from an operational failure; no rejected raw draft substituted.",
    "shuffle": "SystemRandom once, opaque IDs retained across both assessment phases.",
    "feedback_scope": "Compositions use exact returned choice keys and text; separately checked against actual Swift feedback selection after app admission.",
    "files": {name: digest(args.output / name) for name in
              ["stems-and-choices.json", "teaching.json", "private-mapping.json"]},
})
print(json.dumps({"items": len(rows), "output": str(args.output)}))
