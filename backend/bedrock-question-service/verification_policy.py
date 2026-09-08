"""Server policy provenance, separate from the existing client wire contract.

Revision 1 means the current independent-solver gate and final review ran. It is
not a factual-correctness certificate. Missing revisions remain legacy/unknown;
inventory must never acquire a revision merely by being read or claimed.
"""

from typing import Any


VERIFICATION_VERSION = 1
VERIFICATION_POLICY_REVISION = 1


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
