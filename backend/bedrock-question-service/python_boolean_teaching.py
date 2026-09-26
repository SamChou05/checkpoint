"""Veto two specific incomplete Python Boolean-operator teaching rules.

This recognizes a narrow unqualified generic claim, not general English truth.
Correct evaluation of the shown expression does not make that claim a complete
rule: ``or`` returns its last operand when none are truthy, and ``and`` returns
its last operand when none are falsy.
"""

import re


_RULE = re.compile(
    r"(?:^|(?<=[.!?])\s+)\s*(?:the\s+)?(?:Python(?:'s)?\s+)?"
    r"[`\"']?(or|and)[`\"']?(?:\s+operator)?\s+"
    r"(?:evaluates\s+left\s+to\s+right\s+and\s+)?"
    r"returns?\s+(?:the\s+)?first\s+(truthy|falsy)\s+operand\b",
    re.I,
)
_CASE_SCOPE = re.compile(
    r"\b(?:in|for)\s+(?:this|that|the)\s+(?:expression|case|example|code)\b|\bhere\b",
    re.I,
)
_FINAL_OPERAND = re.compile(r"\b(?:last|final)\s+(?:evaluated\s+)?operand\b", re.I)
_LOCAL_CONDITION = re.compile(r"\b(?:if|when|provided|assuming)\b", re.I)
_NEGATED_CLAIM = re.compile(r"\b(?:incomplete|incorrect|not always|false as a rule)\b", re.I)


def has_incomplete_python_boolean_rule(prompt: str, topic: str, explanation: str) -> bool:
    """Find only unqualified first-truthy/first-falsy universal assertions.

    The check is deliberately silent outside explicit Python context. It skips
    case-local wording and any possible last-operand fallback wording. That may
    miss some bad explanations, but avoids rejecting a correct concise rule.
    Other false claims remain the model auditor's responsibility.
    """
    if not all(type(value) is str for value in (prompt, topic, explanation)):
        return False
    if not re.search(r"\bpython\b", prompt + " " + topic, re.I):
        return False
    for match in _RULE.finditer(explanation):
        operator, named_truth = match.group(1).lower(), match.group(2).lower()
        if (operator, named_truth) not in {("or", "truthy"), ("and", "falsy")}:
            continue
        # The rule matcher starts at a sentence boundary. A qualifier in that
        # sentence limits the claim to the displayed case or a stated condition.
        sentence_end = re.search(r"[.!?]", explanation[match.end():])
        end = match.end() + sentence_end.start() if sentence_end else len(explanation)
        sentence = explanation[match.start():end]
        if (_CASE_SCOPE.search(sentence) or _LOCAL_CONDITION.search(sentence)
                or _NEGATED_CLAIM.search(sentence)):
            continue
        if _FINAL_OPERAND.search(explanation):
            continue
        return True
    return False
