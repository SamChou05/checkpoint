"""Server policy provenance, separate from the existing client wire contract.

Revision 1 identifies the historical stem-only solver gate and final review.
Revision 2 requires complete-choice judgments, unique exact key agreement, and
final review. Neither certifies factual correctness. Missing revisions remain
legacy/unknown; reading or claiming inventory must never assign a new revision.
Revision 3 additionally identifies the opt-in authored worked-explanation audit;
the final reviewer cannot replace learner-facing teaching. This remains a
separate mode from the current native generation contract.
Revision 4 identifies the complete-choice solver with key-independent choice
slots, all six semantic pair comparisons, and reviewer-written final teaching.
It builds on revision 2, not the separate authored-teaching mode in revision 3.
Revisions are freshness thresholds, not a claim that all earlier optional modes
ran. Model judgments remain fallible even with a strictly enforced shape.
Revision 6 identifies the opt-in compiled quantitative route: complete-choice
solver/reviewer vetoes remain, but all five learner fields come from revalidated
bounded compiler data. Mathematical guarantees apply only to that closed subset;
scope, difficulty, novelty and distractor usefulness remain model assessments.
Revision 7 identifies native complete-pair, count-bound solving followed by an
immutable authored-main audit. It returns no choice-specific teaching. It does
not imply compiled provenance from revision 6; require exact revision 6 for that
mode. Policy minimums are freshness thresholds, not cumulative capabilities.
"""

from typing import Any


VERIFICATION_VERSION = 1
LEGACY_VERIFICATION_POLICY_REVISION = 1
COMPLETE_CHOICE_VERIFICATION_POLICY_REVISION = 2
AUTHORED_SOLUTION_VERIFICATION_POLICY_REVISION = 3
DISTINCT_CHOICE_VERIFICATION_POLICY_REVISION = 4
VERIFICATION_POLICY_REVISION = DISTINCT_CHOICE_VERIFICATION_POLICY_REVISION
COMPILED_QUANTITATIVE_VERIFICATION_POLICY_REVISION = 6
AUTHORED_PAIR_VERIFICATION_POLICY_REVISION = 7
MAX_SUPPORTED_VERIFICATION_POLICY_REVISION = AUTHORED_PAIR_VERIFICATION_POLICY_REVISION


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
