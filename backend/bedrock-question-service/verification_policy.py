"""Server policy provenance, separate from the existing client wire contract.

Revision 1 identifies the historical stem-only solver gate and final review.
Revision 2 requires complete-choice judgments, unique exact key agreement, and
final review. Neither certifies factual correctness. Missing revisions remain
legacy/unknown; reading or claiming inventory must never assign a new revision.
Revision 3 additionally identifies the opt-in authored worked-explanation audit;
the final reviewer cannot replace learner-facing teaching. It is not yet the
default generation contract or required claim minimum.
Revision 4 solves only the topic, stem and choices displayed to the learner;
hidden goal/source/objective content cannot supply a missing task premise.
Revision 5 combines that boundary with the opt-in authored-teaching audit.
Revisions 4/5 were superseded because they reject valid source-based recall.
Revision 6 retains learned source facts, excludes goal/objective intent from
solving, and distinguishes reference rules from missing case data. Revision 7
adds the opt-in authored-teaching audit. Model judgments remain fallible.
"""

from typing import Any


VERIFICATION_VERSION = 1
LEGACY_VERIFICATION_POLICY_REVISION = 1
COMPLETE_CHOICE_VERIFICATION_POLICY_REVISION = 2
AUTHORED_SOLUTION_VERIFICATION_POLICY_REVISION = 3
DISPLAYED_QUESTION_VERIFICATION_POLICY_REVISION = 4
DISPLAYED_AUTHORED_SOLUTION_VERIFICATION_POLICY_REVISION = 5
SOURCE_SUPPORTED_VERIFICATION_POLICY_REVISION = 6
SOURCE_SUPPORTED_AUTHORED_VERIFICATION_POLICY_REVISION = 7
VERIFICATION_POLICY_REVISION = SOURCE_SUPPORTED_VERIFICATION_POLICY_REVISION


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
