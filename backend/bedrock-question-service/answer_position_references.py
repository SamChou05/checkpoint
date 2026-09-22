"""Shared shuffle-safe feedback validation; no subject text is rewritten."""

import re
from typing import Any


def _stem_subpart_labels(prompt: str, quoted: re.Pattern) -> set[str]:
    """Recognize named subparts or an explicit multi-part stem enumeration.

    A parenthesized variable or quoted string alone does not define a subpart.
    This intentionally recognizes a small set of cues, not arbitrary English.
    """
    subject = quoted.sub(lambda match: " " * len(match.group()), prompt)
    named = re.findall(
        r"\b(?:parts?|subparts?|statements?|claims?|cases?|conditions?|equations?)"
        r"\s+\(\s*([A-D1-4])\s*\)", subject, re.I,
    )
    enumerated = re.findall(
        r"(?:^|[\n:;.!?])\s*\(\s*([A-D1-4])\s*\)"
        r"(?=\s+[\w\"'`“‘]|\s*:\s*\S)", subject, re.I,
    )
    labels = {label.lower() for label in named}
    candidates = labels | {label.lower() for label in enumerated}
    return candidates if len(candidates) >= 2 else labels


def contains_answer_label_references(text: str, question: dict[str, Any]) -> bool:
    """Reject display positions while retaining exact quoted subject literals.

    A quoted reference is not safe merely because it has quotation marks. Its
    whole quoted content must be an offered literal or explicitly quoted in the
    stem. Parenthesized labels require a display or judgment cue; actual stem
    subparts remain usable. This is a bounded guard, not a language parser.
    No subject text, answer, or feedback is rewritten by this check.
    """
    quoted = re.compile(
        r'''"([^"\n]+)"|(?<!\w)'([^'\n]+)'(?!\w)|“([^”\n]+)”|‘([^’\n]+)’|`([^`\n]+)`'''
    )
    literals = set(question["choices"])
    prompt = question.get("prompt", "")
    if isinstance(prompt, str):
        literals.update(
            next(group for group in match.groups() if group is not None)
            for match in quoted.finditer(prompt)
        )
    bound_spans = [
        match.span()
        for match in quoted.finditer(text)
        if next(group for group in match.groups() if group is not None) in literals
    ]
    reference = re.compile(
        r"\b(?:choice|option|answer)\s+[A-D]\b"
        r"|\b(?:first|second|third|fourth|last|1st|2nd|3rd|4th)[\s-]+"
        r"(?:(?:two|three|four|[2-4])[\s-]+)?(?:choices?|options?|answers?)\b"
        # Bare numbers can name subject values, so only the four possible
        # display slots qualify. Preserve signed values and numeric continuations
        # such as 1,500, 2.5, 1/2 and 2% rather than reading a slot-number prefix.
        r"|\b(?:choices?|options?|answers?)\s+"
        r"(?:[1-4]|1st|2nd|3rd|4th|one|two|three|four|first|second|third|fourth|last)\b(?![.,][0-9]|/|%)"
        # An explicit display marker also makes an out-of-range index unsafe.
        r"|\b(?:choices?|options?|answers?)(?:[\s-]+(?:number|no\.)[\s-]+|[\s-]*#\s*)"
        r"(?:[0-9]+(?:st|nd|rd|th)?|one|two|three|four)\b",
        re.I,
    )
    def bound_literal(match):
        return any(start <= match.start() and match.end() <= end for start, end in bound_spans)

    if any(
        not bound_literal(match)
        for match in reference.finditer(text)
    ):
        return True

    # Explicit display nouns are unsafe even when a stem also has subparts.
    parenthesized_option = re.compile(r"\b(?:choices?|options?|answers?)\s*\(\s*[A-D1-4]\s*\)", re.I)
    if any(not bound_literal(match) for match in parenthesized_option.finditer(text)):
        return True

    subparts = _stem_subpart_labels(prompt, quoted) if isinstance(prompt, str) else set()
    location = re.compile(r"\b(?:in|for)\s+\(\s*([A-D1-4])\s*\)\s*[,;:]", re.I)
    if any(
        match.group(1).lower() not in subparts and not bound_literal(match)
        for match in location.finditer(text)
    ):
        return True

    judgment = re.compile(
        r"\(\s*([A-D1-4])\s*\)\s+(?:is|was)\s+(?:the\s+)?"
        r"(?:correct|incorrect|right|wrong|best)\b", re.I,
    )
    # A bare judgment must start a clause, optionally after a short connective.
    # Do not interpret f(b), f (b), or a larger expression's final (b) as a slot.
    clause_start = re.compile(r'''(?:^|[.!?;:]\s*|\b(?:so|thus|therefore|only)\s+)["'“‘`]*\s*$''', re.I)
    return any(
        clause_start.search(text[:match.start()])
        and match.group(1).lower() not in subparts
        and not bound_literal(match)
        for match in judgment.finditer(text)
    )
