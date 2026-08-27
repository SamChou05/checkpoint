"""Stable question-bank limits, exceptions, and logger."""

from __future__ import annotations

import logging


LOGGER = logging.getLogger("question_bank")

MAX_DESIRED_COUNT = 100
MAX_CLAIM_COUNT = 20
DEFAULT_GENERATION_CHUNK_COUNT = 5
DEFAULT_BANK_TTL_SECONDS = 30 * 24 * 60 * 60
WORKER_LEASE_SECONDS = 180
DEFAULT_MAX_RECEIVE_COUNT = 5
DEFAULT_FAILURE_COOLDOWN_SECONDS = 5 * 60


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


class ProviderAttemptLimitError(RuntimeError):
    """The logical job has exhausted its provider-call allowance."""
