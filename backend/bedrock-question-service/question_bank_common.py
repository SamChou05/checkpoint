"""Stable question-bank limits, exceptions, and logger."""

from __future__ import annotations

import logging
import re
import unicodedata
from typing import Any

from service_errors import (  # noqa: F401 - re-exported through question_bank
    ProviderAttemptLimitError,
    ProviderQuotaLimitError,
)


LOGGER = logging.getLogger("question_bank")

MAX_DESIRED_COUNT = 100
MAX_CLAIM_COUNT = 20
DEFAULT_GENERATION_CHUNK_COUNT = 5
DEFAULT_BANK_TTL_SECONDS = 30 * 24 * 60 * 60
WORKER_LEASE_SECONDS = 180
DEFAULT_MAX_RECEIVE_COUNT = 5
DEFAULT_FAILURE_COOLDOWN_SECONDS = 5 * 60
DEFAULT_MAX_FAILED_GENERATION_JOBS = 3
MAX_BLOCKED_STEM_FINGERPRINTS = 750
_PRESENTATION_PREFIXES = (
    re.compile(r"^(?:question|item)\s+\d+\s*[:.)-]\s*", re.IGNORECASE),
    re.compile(
        r"^(?:choose|select|identify|pick)\s+(?:the\s+)?(?:correct|best)\s+"
        r"(?:answer|choice|option)(?:\s+(?:to|for)\s+(?:this\s+)?"
        r"(?:question|item|example))?\s*[:-]\s*",
        re.IGNORECASE,
    ),
)
_MATH_OPERATOR_SPACING = re.compile(
    r"\s*(<=|>=|!=|==|[+\-\N{MINUS SIGN}\N{MULTIPLICATION SIGN}"
    r"\N{DIVISION SIGN}=<>\N{LESS-THAN OR EQUAL TO}\N{GREATER-THAN OR EQUAL TO}"
    r"\N{NOT EQUAL TO}\N{PLUS-MINUS SIGN}\N{MINUS-OR-PLUS SIGN}"
    r"\N{DOT OPERATOR}\N{MIDDLE DOT}*/^%])\s*"
)


def _normalized_stem_identity(value: Any) -> str:
    """Return an exact-question identity without erasing meaningful operators."""
    if value is None:
        return ""
    normalized = unicodedata.normalize("NFC", " ".join(str(value).split()))
    normalized = unicodedata.normalize("NFC", normalized.casefold())
    for prefix in _PRESENTATION_PREFIXES:
        normalized = prefix.sub("", normalized, count=1)
    normalized = re.sub(r"\s+([,.;:?!])", r"\1", normalized)
    normalized = _MATH_OPERATOR_SPACING.sub(r"\1", normalized)
    return normalized.rstrip(" .?!")


def _stem_fingerprint(value: Any) -> str:
    """Return the lowercase 64-bit FNV-1a fingerprint used by clients."""
    identity = _normalized_stem_identity(value)
    if not identity:
        return ""
    fingerprint = 14_695_981_039_346_656_037
    for byte in identity.encode("utf-8"):
        fingerprint ^= byte
        fingerprint = (fingerprint * 1_099_511_628_211) & 0xFFFF_FFFF_FFFF_FFFF
    return f"{fingerprint:016x}"


def _validated_blocked_stem_fingerprints(value: Any) -> list[str]:
    """Validate and deduplicate the bounded fingerprint wire representation."""
    field = "blockedStemFingerprints"
    if value is None:
        return []
    if not isinstance(value, list):
        raise ValueError(f"{field} must be an array.")
    if len(value) > MAX_BLOCKED_STEM_FINGERPRINTS:
        raise ValueError(
            f"{field} must contain at most {MAX_BLOCKED_STEM_FINGERPRINTS} items."
        )

    fingerprints = []
    seen = set()
    for index, fingerprint in enumerate(value):
        if not isinstance(fingerprint, str) or not re.fullmatch(
            r"[0-9a-f]{16}", fingerprint
        ):
            raise ValueError(
                f"{field}[{index}] must be a lowercase 16-character hexadecimal string."
            )
        if fingerprint not in seen:
            seen.add(fingerprint)
            fingerprints.append(fingerprint)
    return fingerprints


class QuestionBankError(RuntimeError):
    def __init__(self, status_code: int, message: str, code: str):
        super().__init__(message)
        self.status_code = status_code
        self.code = code


class NonRetryableGenerationError(RuntimeError):
    """A validated generation refusal that must remain terminal for this bank."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code
