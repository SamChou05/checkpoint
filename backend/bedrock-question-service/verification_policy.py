"""Server policy provenance, separate from the existing client wire contract.

Revision 1 identifies the historical stem-only solver gate and final review.
Revision 2 requires complete-choice judgments, unique exact key agreement, and
final review. Neither certifies factual correctness. Missing revisions remain
legacy/unknown; reading or claiming inventory must never assign a new revision.
"""

from typing import Any


VERIFICATION_VERSION = 1
LEGACY_VERIFICATION_POLICY_REVISION = 1
COMPLETE_CHOICE_VERIFICATION_POLICY_REVISION = 2
VERIFICATION_POLICY_REVISION = COMPLETE_CHOICE_VERIFICATION_POLICY_REVISION


def meets_verification_policy(question: dict[str, Any], minimum: int) -> bool:
    """Zero preserves legacy claims; a positive minimum requires typed stamps."""
    if minimum == 0:
        return True
    wire_version = question.get("verificationVersion")
    revision = question.get("verificationPolicyRevision")
    return (
        type(wire_version) is int
        and wire_version == VERIFICATION_VERSION
        and type(revision) is int
        and revision >= minimum
    )
