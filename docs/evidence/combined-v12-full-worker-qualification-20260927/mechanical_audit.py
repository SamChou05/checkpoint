"""Independently check the frozen v12 worker's five code-owned candidates."""

from __future__ import annotations

from fractions import Fraction
import hashlib
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
CAPTURE_SHA256 = "fe66f66fe9bc1b8eefa62c167447e73a62d41cf362850a3db8cbc912298af31d"
PLAN_SHA256 = "bbac67ed6255db66c20404f37470a5c92a53e86d1a49a0ca41c90015f8f5217b"
LEARNER_FIELDS = ("prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations")


def _hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _value(node: dict, x: int | None = None) -> Fraction:
    if "value" in node:
        return Fraction(node["value"])
    if node.get("variable") == "x":
        if x is None:
            raise ValueError("Variable has no assignment")
        return Fraction(x)
    left, right = _value(node["left"], x), _value(node["right"], x)
    if node["op"] == "add":
        return left + right
    if node["op"] == "sub":
        return left - right
    if node["op"] == "mul":
        return left * right
    if node["op"] == "div":
        return left / right
    raise ValueError("Unknown exact operator")


def _condition(spec: dict, x: int) -> bool:
    condition = spec["condition"]
    left = _value(condition["left"], x)
    right = _value(condition["right"], x)
    return {
        "eq": lambda: left == right, "ne": lambda: left != right,
        "lt": lambda: left < right, "le": lambda: left <= right,
        "gt": lambda: left > right, "ge": lambda: left >= right,
    }[condition["relation"]]()


def _numeric_proof(spec: dict, question: dict) -> dict:
    key = Fraction(question["expectedAnswer"])
    choices = [Fraction(choice) for choice in question["choices"]]
    if len(set(choices)) != 4 or choices.count(key) != 1:
        raise ValueError("Numeric choices are equivalent or incorrectly keyed")
    if spec["kind"] == "exact_value":
        answer = _value(spec["expression"])
        if key != answer:
            raise ValueError("Exact expression answer differs from key")
        return {"kind": "exact_value", "independentAnswer": str(answer)}
    if spec["kind"] != "scalar_condition":
        raise ValueError("Unsupported numeric proof kind")
    domain = spec["domain"]
    satisfying = [x for x in range(domain["lower"], domain["upper"] + 1)
                  if _condition(spec, x)]
    selection = spec["selection"]
    if selection == "count_satisfying":
        answer = len(satisfying)
    elif selection == "minimum":
        answer = min(satisfying)
    elif selection == "maximum":
        answer = max(satisfying)
    elif selection == "any_satisfying":
        supported_choices = [int(choice) for choice in choices
                             if choice.denominator == 1 and _condition(spec, int(choice))]
        if supported_choices != [int(key)] or int(key) not in satisfying:
            raise ValueError("Offered scalar condition has another viable answer")
        answer = int(key)
    else:
        raise ValueError("Unsupported scalar selection")
    if key != answer:
        raise ValueError("Scalar selection differs from key")
    return {"kind": "scalar_condition", "selection": selection,
            "satisfyingDomainValues": satisfying, "independentAnswer": str(answer)}


def audit() -> dict:
    capture_path, plan_path = HERE / "capture.json", HERE / "plan.json"
    if _hash(capture_path) != CAPTURE_SHA256 or _hash(plan_path) != PLAN_SHA256:
        raise ValueError("Frozen capture or plan changed")
    capture = json.loads(capture_path.read_text())
    plan = json.loads(plan_path.read_text())
    if capture["plan"] != plan or capture["plan_sha256"] != PLAN_SHA256:
        raise ValueError("Capture detached from frozen plan")
    if capture["summary"]["returned_questions"] != 4 or len(capture["calls"]) != 3:
        raise ValueError("Official call or return count changed")
    job = capture["jobs"][0]
    if job["returned_slot_ordinals"] != [0, 1, 2, 3]:
        raise ValueError("Returned original slot sequence changed")
    statuses = [slot["status"] for slot in capture["original_jobs"][0]["slots"]]
    if statuses != ["returned", "returned", "returned", "returned", "unfilled"]:
        raise ValueError("Original slot provenance changed")
    sanitized = job["passes"][0]["sanitized"]
    if len(sanitized) != 5:
        raise ValueError("Sanitizer did not accept five candidates")

    rows = []
    for ordinal, entry in enumerate(sanitized):
        question = entry["question"]
        if entry["original_slot_ordinals"] != [ordinal]:
            raise ValueError("Sanitized source ordinal changed")
        source = entry.get("compiled_source") or entry.get("agreement_source")
        if any(question[field] != source["learner"][field] for field in LEARNER_FIELDS):
            raise ValueError("Code-owned learner content changed")
        choices = question["choices"]
        if (len(choices) != 4
                or len({choice.strip().casefold() for choice in choices}) != 4
                or choices.count(question["expectedAnswer"]) != 1
                or set(question["choiceExplanations"]) != set(choices)):
            raise ValueError("Candidate choices or key changed")
        row = {"originalSlot": ordinal, "workerStatus": statuses[ordinal],
               "codeOwnedLearnerFieldsMatch": True, "literalDistinctChoicePairs": 6}
        if entry.get("compiled_source"):
            row["numericProof"] = _numeric_proof(source["spec"], question)
        else:
            row["englishProof"] = "closed_agreement_constructor"
        rows.append(row)
    for i, ordinal in enumerate(job["returned_slot_ordinals"]):
        if any(job["returned"][i][field] != sanitized[ordinal]["question"][field]
               for field in LEARNER_FIELDS):
            raise ValueError("Released learner content differs from sanitized source")

    reviewer = json.loads(capture["calls"][2]["response"]["output"]["message"]
                          ["content"][0]["text"])["reviews"]
    if (set(reviewer) != set("01234")
            or any(review["valid"] is not True or review["explanationSupport"] != "supported"
                   or any(review["issueFlags"].values()) for review in reviewer.values())
            or reviewer["4"]["difficulty"] != 4):
        raise ValueError("Reviewer result does not match the recorded veto")
    solver = json.loads(capture["calls"][1]["response"]["output"]["message"]
                        ["content"][0]["text"])["solutions"]
    if set(solver) != {"0", "1"}:
        raise ValueError("Answer-blind solver scope changed")
    for solution in solver.values():
        if (sum(choice["judgment"] == "supported" for choice in solution["choices"].values()) != 1
                or len(solution["choicePairs"]) != 6
                or any(pair["relation"] != "distinct"
                       for pair in solution["choicePairs"].values())):
            raise ValueError("Solver key or choice-pair result changed")
    return {"captureSha256": CAPTURE_SHA256, "planSha256": PLAN_SHA256,
            "candidateCount": 5, "returnedOriginalSlots": [0, 1, 2, 3],
            "unfilledOriginalSlots": [4], "providerCalls": 3,
            "numericExactProofs": 3, "englishSolverOneKeyAndSixDistinctPairs": 2,
            "allCandidateLearnerFieldsMatchCodeProvenance": True,
            "reviewerMarkedAllFiveValidAndExplanationsSupported": True,
            "reviewerSlotFourDifficulty": 4,
            "independentBlindContentReview": "pending", "rows": rows}


if __name__ == "__main__":
    result = audit()
    output = HERE / "mechanical-audit.json"
    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if output.exists():
        if output.read_text() != rendered:
            raise ValueError("Frozen mechanical audit changed")
    else:
        output.write_text(rendered)
    print(json.dumps({key: value for key, value in result.items() if key != "rows"}, indent=2))
