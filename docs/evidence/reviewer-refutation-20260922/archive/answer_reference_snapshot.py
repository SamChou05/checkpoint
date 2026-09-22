"""Verbatim pure answer-reference predicate from the documented runtime snapshot."""
import re
from typing import Any

def _contains_answer_label_references(text: str, question: dict[str, Any]) -> bool:
    """Reject display positions while retaining exact quoted subject literals.

    A quoted reference is not safe merely because it has quotation marks. Its
    whole quoted content must be an offered literal or explicitly quoted in the
    stem. No subject text, answer, or feedback is rewritten by this check.
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
    return any(
        not any(start <= match.start() and match.end() <= end for start, end in bound_spans)
        for match in reference.finditer(text)
    )
