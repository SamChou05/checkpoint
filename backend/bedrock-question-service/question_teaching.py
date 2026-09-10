"""Immutable authored worked-solution boundary; no provider or trust assignment.

The application can enforce unchanged content and declared review outcomes.
Neither a supported verdict nor this validation proves factual correctness.
"""

import copy
import re
from typing import Any, Literal

from complete_question_solution import CompleteSolutionFormatError, _items_by_index
from question_difficulty import DIFFICULTY_RUBRIC
from question_quality import _strict_json_object
from question_source_guidance import SOURCE_EVIDENCE_GUIDANCE
from request_contract import _has_unambiguous_choices
from service_errors import ProviderError


AUTHORED_SOLUTION_REVIEW_SYSTEM_PROMPT = ("""
Audit the complete educational multiple-choice question and its unchanged main
worked explanation.
""" + SOURCE_EVIDENCE_GUIDANCE + """

Do not silently substitute a familiar textbook scenario.

The author key and difficulty and the independent solver's judgments/reasons are
not supplied. The main explanation can reveal the author's intended answer;
treat that intention as a claim to check, never evidence that the key is right.
Evaluate the exact stem, all four exact choices, and every material claim in the
worked explanation. Allow zero or multiple warranted answers. Weak alternatives
cannot make an unsupported choice correct. A possible explanation is not an
established or likely cause merely because it is familiar. Preserve negation,
quantifiers, units, comparison scope, probability conditions and output costs.
Do not interpret lack of knowledge as proof of nonexistence or insufficiency.
An exact negative or zero answer may be correct for the actual task.

The main explanation must teach a sufficient worked solution from the supplied
facts and justified rules, connecting them to the result. A correct answer alone
is not enough: circular assertions, invented causal facts, false calculations,
unjustified counterfactuals, deleted qualifications or missing essential reasoning
make its teaching unsupported. If you cannot establish its support, mark uncertain.
Check whether wrong alternatives are distinct and plausibly tempting for this
task. No choice-specific teaching is supplied or requested in this contract.

Return valid:true only if exactly one unchanged choice is warranted, the entire
main explanation is supported, the task fits the goal, and the distractors are
adequate. Otherwise return valid:false; retain an exact answer if it is established
despite another defect, or use the empty string if no unique answer is established.
Independently rate the cognitive work using the rubric below, not the author's
intention or the length of the wording. Report material defects or unresolved
obstacles as concise issues. Aim for at most 240 characters per issue; the hard
limit is 600, with at most 8 issues. Do not add issues merely to praise an item.

Return only {"reviews":[{"index":0,"valid":true,"answer":"exact offered choice",
"difficulty":3,"explanationSupport":"supported|unsupported|uncertain","issues":[]}]}.
Return exactly one record for every supplied index, with those exact fields and
no others. Never rewrite the stem, choices or explanation, produce replacement
teaching, or assign verification metadata. This is a fallible review declaration,
not a correctness certificate. The application rejects any unsupported/uncertain
explanation or reported issue even if valid is true.

Difficulty rubric:
""" + DIFFICULTY_RUBRIC).strip()

RejectionReason = Literal[
    "unsupported_authored_explanation", "uncertain_authored_explanation",
    "reported_issues", "rejected_by_model", "answer_disagreement",
]


class AuthoredTeachingFormatError(ValueError):
    """Malformed content, response structure or exact-item correlation."""


def _bounded_subject(value: Any, maximum: int) -> bool:
    # Count the exact stored text; never hide excess characters by trimming.
    return type(value) is str and len(value.strip()) >= 12 and len(value) <= maximum


def _validate_content(question: Any) -> None:
    if type(question) is not dict:
        raise AuthoredTeachingFormatError("Question must be an object.")
    if not _bounded_subject(question.get("prompt"), 320):
        raise AuthoredTeachingFormatError("Prompt must contain 12..320 characters.")
    if not _bounded_subject(question.get("explanation"), 420):
        raise AuthoredTeachingFormatError("Worked explanation must contain 12..420 characters.")
    choices = question.get("choices")
    if (type(choices) is not list or len(choices) != 4
            or any(type(c) is not str or not 1 <= len(c) <= 140 for c in choices)
            or not _has_unambiguous_choices(choices)):
        raise AuthoredTeachingFormatError("Four exact unambiguous choices are required.")
    if "choiceExplanations" in question and (
        type(question["choiceExplanations"]) is not dict or question["choiceExplanations"]
    ):
        raise AuthoredTeachingFormatError("Existing choice teaching cannot be removed by this mode.")
    if re.search(r"\b(?:choice|option|answer)\s+[A-D]\b", question["explanation"], re.I):
        raise AuthoredTeachingFormatError("Teaching cannot reference shuffled answer labels.")


def freeze_authored_question(question: dict[str, Any]) -> dict[str, Any]:
    """Validate and deep-copy exact content; do not normalize or mint approval.

    Extra metadata remains data. The caller owns provenance and admission; this
    helper does not interpret or assign verification fields. Existing per-choice
    teaching is rejected, never silently deleted or replaced.
    """
    _validate_content(question)
    answer = question.get("expectedAnswer")
    if type(answer) is not str or answer not in question["choices"]:
        raise AuthoredTeachingFormatError("The key must be an exact offered choice.")
    return copy.deepcopy(question)


def _validated_review(record: Any, choices: list[str]) -> dict[str, Any]:
    if (type(record) is not dict
            or set(record) != {"index", "valid", "answer", "difficulty", "explanationSupport", "issues"}
            or type(record["index"]) is not int or record["index"] < 0
            or type(record["valid"]) is not bool
            or type(record["difficulty"]) is not int or not 1 <= record["difficulty"] <= 5
            or type(record["explanationSupport"]) is not str
            or record["explanationSupport"] not in {"supported", "unsupported", "uncertain"}
            or type(record["answer"]) is not str
            or record["answer"] not in choices and (record["valid"] or record["answer"] != "")
            or type(record["issues"]) is not list or len(record["issues"]) > 8
            or any(type(issue) is not str or not issue.strip() or len(issue) > 600
                   for issue in record["issues"])):
        raise AuthoredTeachingFormatError("Malformed immutable teaching review.")
    return copy.deepcopy(record)


def validate_authored_reviews(raw: str, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Require dense index/choice coverage; reorder records without text changes.

    Items are the exact audit payload (no author key is needed here). The caller
    must omit keys, author difficulty and solver records when constructing that
    payload; a parser cannot undo information already disclosed to the reviewer.
    """
    try:
        offered = _items_by_index(items)
    except CompleteSolutionFormatError as error:
        raise AuthoredTeachingFormatError("Invalid indexed audit items.") from error
    for item in offered.values():
        _validate_content(item)
    if type(raw) is not str:
        raise AuthoredTeachingFormatError("Review response must be text.")
    try:
        parsed = _strict_json_object(raw)
    except ProviderError as error:
        raise AuthoredTeachingFormatError("Malformed review JSON.") from error
    if (type(parsed) is not dict or set(parsed) != {"reviews"}
            or type(parsed["reviews"]) is not list or len(parsed["reviews"]) != len(items)):
        raise AuthoredTeachingFormatError("Complete review envelope required.")
    by_index = {}
    for record in parsed["reviews"]:
        if type(record) is not dict or type(record.get("index")) is not int:
            raise AuthoredTeachingFormatError("Invalid review index.")
        index = record["index"]
        if index not in offered or index in by_index:
            raise AuthoredTeachingFormatError("Missing, duplicate or unexpected review index.")
        by_index[index] = _validated_review(record, offered[index]["choices"])
    return [by_index[i] for i in range(len(items))]


def authored_review_rejection_reason(
    review: dict[str, Any], question: dict[str, Any],
) -> RejectionReason | None:
    """Enforce declared support/issues/key agreement, not semantic truth.

    Difficulty admission belongs to the caller. A false supported declaration
    with no issues can still pass; there is no natural-language truth oracle.
    """
    question = freeze_authored_question(question)
    review = _validated_review(review, question["choices"])
    if review["explanationSupport"] == "unsupported":
        return "unsupported_authored_explanation"
    if review["explanationSupport"] == "uncertain":
        return "uncertain_authored_explanation"
    if review["issues"]:
        return "reported_issues"
    if not review["valid"]:
        return "rejected_by_model"
    if review["answer"] != question["expectedAnswer"]:
        return "answer_disagreement"
    return None
