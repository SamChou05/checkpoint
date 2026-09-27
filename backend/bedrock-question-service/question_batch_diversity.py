"""Narrow code-owned format signatures for the opt-in generic reserve."""

import re
from typing import Any

from generation_diagnostics import record_quality


_BARE_DOLLAR_AMOUNT = re.compile(
    r"[-−]?\$(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?"
)
_DIRECT_EXPECTED_MONEY_TARGET = re.compile(
    r"(?:(?:what|which)(?:\s+(?:is|are|would\s+be|will\s+be))?"
    r"|how\s+much(?:\s+(?:is|would\s+be))?"
    r"|(?:calculate|find|determine|compute))"
    r"\s+(?:the\s+)?expected\s+(?:(?:net|gross)\s+)?"
    r"(?:value|gain|profit|winnings?|payout|prize|earnings|amount won)\b",
    re.IGNORECASE,
)
_CHANCE_CONTEXT = re.compile(
    r"\b(?:probability|chance|random(?:ly)?|coin|die|dice|lottery|raffle|"
    r"ticket|spinner|spin|roll|game|draw|prize)\b",
    re.IGNORECASE,
)
_TARGET_CUE = re.compile(
    r"\b(?:what|which|how much|calculate|find|determine|compute)\b",
    re.IGNORECASE,
)


def _reserve_mechanism_signature(question: dict[str, Any]) -> str | None:
    """Identify only a high-confidence repeated money expectation format.

    This is intentionally incomplete. It must not treat shared probability
    topics or fraction response formats as proof of the same solving decision.
    """
    prompt = question.get("prompt")
    choices = question.get("choices")
    final_sentence = re.split(r"[.!?]\s+", prompt.strip())[-1] if type(prompt) is str else ""
    cues = list(_TARGET_CUE.finditer(final_sentence))
    target_clause = final_sentence[cues[-1].start():] if cues else ""
    if (type(prompt) is not str or type(choices) is not list or len(choices) != 4
            or _DIRECT_EXPECTED_MONEY_TARGET.match(target_clause) is None
            or not _CHANCE_CONTEXT.search(prompt)
            or any(type(choice) is not str
                   or _BARE_DOLLAR_AMOUNT.fullmatch(choice.strip()) is None
                   for choice in choices)):
        return None
    return "expected_monetary_value:bare_dollars"


def keep_varied_reserve_questions(
    questions: list[dict[str, Any]], metrics: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """Retain the earliest independently verified item per known mechanism."""
    seen = set()
    retained = []
    for question in questions:
        signature = _reserve_mechanism_signature(question)
        if signature is not None and signature in seen:
            record_quality(metrics, "reserve", "repeated_expected_money")
            continue
        if signature is not None:
            seen.add(signature)
        retained.append(question)
    return retained
