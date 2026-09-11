"""Immutable complete-teaching boundary; no provider calls or trust assignment.

This module preserves content and enforces declared review outcomes. Neither
well-formed content nor unanimous supported judgments prove semantic truth.
The caller owns request binding, provenance, difficulty admission and delivery.
"""

import copy
import re
import unicodedata
from typing import Any, Literal

from complete_question_solution import CompleteSolutionFormatError, _items_by_index
from question_difficulty import DIFFICULTY_RUBRIC
from question_quality import _strict_json_object
from question_source_guidance import SOURCE_EVIDENCE_GUIDANCE
from request_contract import _has_unambiguous_choices
from service_errors import ProviderError


COMPLETE_TEACHING_REVIEW_SYSTEM_PROMPT = ("""
Audit the complete unchanged educational question and every learner-facing
teaching claim, including the exact composed feedback displays.
""" + SOURCE_EVIDENCE_GUIDANCE + """

This audit is not answer-blind: teaching can reveal the intended answer. Treat
that intention as a claim to check, never evidence that an answer exists or is
correct. The explicit author key, author difficulty and prior solver/reviewer
judgments are not supplied. Independently assess the actual unchanged stem and
all four exact choices, allowing zero or multiple warranted answers. A true
statement need not answer the question; a false statement can correctly answer
a task asking which statement is false. Weak alternatives cannot establish an
otherwise unsupported answer. Preserve negation, quantifiers, units, exceptions,
comparison scope, output costs and conditions of every applied rule.

There must be enough information to support the actual answer. Missing values
can establish a warranted cannot-determine answer; do not confuse that result
with your uncertainty about the subject. Established knowledge cannot supply
missing case observations, causal evidence or an unstated special condition.
Do not silently repair the task, reinterpret a guarantee as a typical result,
or infer a cause just because it is a familiar possible explanation.

Audit every material claim in the exact main explanation, each choice-specific
feedback field, and EACH supplied feedbackDisplays display. A display contains
the choice feedback followed by the main, except that the client shows only the
main when the feedback equals it under Unicode canonical equivalence. Assess
the actual supplied display; do not assume supported components guarantee a
supported composition. Check contradictions, changed referents, scope shifts
and missing qualifications across the combined text as well as within fields.
Judge choice feedback against the answer warranted by the task, not the answer
suggested by the teaching. Do not invent the learner's thought process.

For explanationSupport, feedbackSupport and displaySupport:
- supported: the entire field accurately teaches its associated result or error,
  with every material claim and required qualification warranted;
- unsupported: a material claim is false, contradicts the task or other teaching,
  invents an observation or cause, omits a necessary qualifier, or lacks the
  reasoning needed to establish its conclusion;
- uncertain: you cannot establish the field's support or adequacy. Absence of
  evidence alone need not prove a claim false.
A correct answer name alone is not a sufficient worked explanation. The main
must connect the actual facts and justified rules to the result. Check goal fit
and distinct, plausible alternatives. Rate difficulty independently using the
rubric below; a correct easy item can be valid even if it misses a caller target.

Return only {"reviews":[{"index":0,"valid":true,"answer":"exact offered choice",
"difficulty":3,"explanationSupport":"supported","choiceFeedbackSupport":[
{"choice":"each exact offered choice","feedbackSupport":"supported",
"displaySupport":"supported"}],"issues":[]}]}.
Use exactly these fields. Return exactly one review for every supplied index
and exactly one choiceFeedbackSupport row for every offered choice, even when
valid is false. Preserve exact choice text. All three support fields use only
supported, unsupported or uncertain. valid is Boolean; difficulty is an integer
from 1 through 5. answer is the exact unique warranted choice, or "" if no unique
answer is established; a known answer may coexist with invalid teaching.
issues contains at most eight nonblank diagnostic strings, each at most 600
characters; aim for 240. Report material defects or unresolved obstacles, not
praise or replacement wording.

Return valid:true only when exactly one unchanged answer is warranted, goal fit
and alternatives are adequate, and ALL main, choice-feedback and display claims
are supported. Any unsupported/uncertain declaration or reported issue vetoes
admission independently of valid and key agreement. Never rewrite, shorten or
add learner-facing content, propose replacement fields, or assign verification
metadata. These are fallible review declarations, not a correctness certificate.

Difficulty rubric:
""" + DIFFICULTY_RUBRIC).strip()

RejectionReason = Literal[
    "unsupported_main_explanation", "uncertain_main_explanation",
    "unsupported_choice_feedback", "uncertain_choice_feedback",
    "unsupported_feedback_display", "uncertain_feedback_display",
    "reported_issues", "rejected_by_model", "answer_disagreement",
]

_SUPPORT = frozenset({"supported", "unsupported", "uncertain"})
_REVIEW_FIELDS = {
    "index", "valid", "answer", "difficulty", "explanationSupport",
    "choiceFeedbackSupport", "issues",
}
_SUPPORT_FIELDS = {"choice", "feedbackSupport", "displaySupport"}
_ANSWER_LABEL = re.compile(r"\b(?:choice|option|answer)\s+[A-D]\b", re.I)


class CompleteTeachingFormatError(ValueError):
    """Malformed content, response structure or exact-item correspondence."""


def _bounded_text(value: Any, minimum: int, maximum: int) -> bool:
    # Match the client's nonblank minimum; the maximum counts every stored
    # character. Trimming is only a predicate and never changes retained text.
    if type(value) is not str or len(value.strip()) < minimum or len(value) > maximum:
        return False
    try:
        value.encode("utf-8")
    except UnicodeEncodeError:
        return False
    return True


def _composed_displays(question: dict[str, Any]) -> list[dict[str, str]]:
    main = question["explanation"]
    displays = []
    for choice in question["choices"]:
        feedback = question["choiceExplanations"][choice]
        # Swift String equality selects the main-only branch for canonical
        # equivalents. This comparison never normalizes either stored/output text.
        same = unicodedata.normalize("NFC", feedback) == unicodedata.normalize("NFC", main)
        displays.append({"choice": choice, "display": main if same else feedback + "\n\n" + main})
    return displays


def _validate_content(question: Any, *, require_displays: bool = False) -> None:
    if type(question) is not dict:
        raise CompleteTeachingFormatError("Question must be an object.")
    if not _bounded_text(question.get("prompt"), 12, 320):
        raise CompleteTeachingFormatError("Prompt must contain 12..320 nonblank UTF-8 characters.")
    if not _bounded_text(question.get("explanation"), 12, 420):
        raise CompleteTeachingFormatError("Main explanation must contain 12..420 characters.")
    choices = question.get("choices")
    if (type(choices) is not list or len(choices) != 4
            or any(not _bounded_text(choice, 1, 140) for choice in choices)
            or not _has_unambiguous_choices(choices)):
        raise CompleteTeachingFormatError("Four exact unambiguous choices are required.")
    feedback = question.get("choiceExplanations")
    if (type(feedback) is not dict or any(type(key) is not str for key in feedback)
            or set(feedback) != set(choices)
            or any(not _bounded_text(value, 12, 280) for value in feedback.values())):
        raise CompleteTeachingFormatError("Complete exact choice feedback within 12..280 characters required.")
    if any(_ANSWER_LABEL.search(text) for text in [question["explanation"], *feedback.values()]):
        raise CompleteTeachingFormatError("Teaching cannot reference shuffled answer labels.")
    if require_displays or "feedbackDisplays" in question:
        displays = question.get("feedbackDisplays")
        expected = _composed_displays(question)
        if (type(displays) is not list or len(displays) != 4
                or any(type(row) is not dict or set(row) != {"choice", "display"}
                       or type(row["choice"]) is not str or type(row["display"]) is not str
                       or row != wanted for row, wanted in zip(displays, expected))):
            raise CompleteTeachingFormatError("Feedback displays must match exact client composition and order.")


def freeze_complete_question(question: dict[str, Any]) -> dict[str, Any]:
    """Validate and deep-copy exact content and metadata, without trust stamps.

    Existing metadata is retained as data; it cannot establish admission. No
    field is normalized, clipped, removed, inferred or semantically repaired.
    """
    _validate_content(question)
    answer = question.get("expectedAnswer")
    if type(answer) is not str or answer not in question["choices"]:
        raise CompleteTeachingFormatError("The key must be an exact offered choice.")
    return copy.deepcopy(question)


def compose_feedback_displays(question: dict[str, Any]) -> list[dict[str, str]]:
    """Return exact Swift feedback displays in question choice order.

    A key is not needed: this also accepts key-free audit items. Complete
    nonblank feedback is required, so the missing-feedback fallback cannot occur.
    """
    _validate_content(question)
    return _composed_displays(question)


def _is_support(value: Any) -> bool:
    return type(value) is str and value in _SUPPORT


def _validated_review(record: Any, choices: list[str]) -> dict[str, Any]:
    if (type(record) is not dict or set(record) != _REVIEW_FIELDS
            or type(record["index"]) is not int or record["index"] < 0
            or type(record["valid"]) is not bool
            or type(record["difficulty"]) is not int or not 1 <= record["difficulty"] <= 5
            or not _is_support(record["explanationSupport"])
            or type(record["answer"]) is not str
            or record["answer"] not in choices and (record["valid"] or record["answer"] != "")
            or type(record["issues"]) is not list or len(record["issues"]) > 8
            or any(not _bounded_text(issue, 1, 600) for issue in record["issues"])):
        raise CompleteTeachingFormatError("Malformed complete-teaching review.")
    rows = record["choiceFeedbackSupport"]
    if type(rows) is not list or len(rows) != 4:
        raise CompleteTeachingFormatError("Four exact choice-support rows are required.")
    by_choice = {}
    for row in rows:
        if (type(row) is not dict or set(row) != _SUPPORT_FIELDS
                or type(row["choice"]) is not str or row["choice"] not in choices
                or row["choice"] in by_choice
                or not _is_support(row["feedbackSupport"])
                or not _is_support(row["displaySupport"])):
            raise CompleteTeachingFormatError("Invalid, missing or duplicate choice support.")
        by_choice[row["choice"]] = row
    validated = copy.deepcopy(record)
    validated["choiceFeedbackSupport"] = [copy.deepcopy(by_choice[choice]) for choice in choices]
    return validated


def validate_complete_teaching_reviews(
    raw: str, items: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Validate dense exact coverage against the caller's frozen audit payload.

    Items omit expectedAnswer and contain all teaching and exact displays.
    The caller also keeps author difficulty and prior verdicts out of the
    request; this parser cannot remove information already shown to a reviewer.
    Returned rows are independent copies in item-index/choice order.
    """
    if type(items) is not list:
        raise CompleteTeachingFormatError("Expected an indexed audit item list.")
    try:
        offered = _items_by_index(items)
    except CompleteSolutionFormatError as error:
        raise CompleteTeachingFormatError("Invalid indexed audit items.") from error
    for item in offered.values():
        _validate_content(item, require_displays=True)
        if "expectedAnswer" in item:
            raise CompleteTeachingFormatError("The explicit author key must be absent from audit items.")
    try:
        parsed = _strict_json_object(raw)
    except ProviderError as error:
        raise CompleteTeachingFormatError("Malformed complete-teaching review JSON.") from error
    if (set(parsed) != {"reviews"} or type(parsed["reviews"]) is not list
            or len(parsed["reviews"]) != len(items)):
        raise CompleteTeachingFormatError("Complete review envelope required.")
    by_index = {}
    for record in parsed["reviews"]:
        if type(record) is not dict or type(record.get("index")) is not int:
            raise CompleteTeachingFormatError("Invalid review index.")
        index = record["index"]
        if index not in offered or index in by_index:
            raise CompleteTeachingFormatError("Missing, duplicate or unexpected review index.")
        by_index[index] = _validated_review(record, offered[index]["choices"])
    return [by_index[index] for index in range(len(items))]


def complete_teaching_rejection_reason(
    review: dict[str, Any], question: dict[str, Any],
) -> RejectionReason | None:
    """Enforce every declared veto; the caller owns factual and policy judgment.

    A false supported declaration without reported issues can still pass.
    Direct callers receive the same format validation as parsed responses.
    """
    question = freeze_complete_question(question)
    review = _validated_review(review, question["choices"])
    declarations = [(review["explanationSupport"], "main_explanation")]
    declarations.extend((row["feedbackSupport"], "choice_feedback")
                        for row in review["choiceFeedbackSupport"])
    declarations.extend((row["displaySupport"], "feedback_display")
                        for row in review["choiceFeedbackSupport"])
    for status in ("unsupported", "uncertain"):
        for support, component in declarations:
            if support == status:
                return f"{status}_{component}"
    if review["issues"]:
        return "reported_issues"
    if not review["valid"]:
        return "rejected_by_model"
    if review["answer"] != question["expectedAnswer"]:
        return "answer_disagreement"
    return None
