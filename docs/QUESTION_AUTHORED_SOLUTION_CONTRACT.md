# Authored worked explanations — September 8, 2026

## Status and purpose

Implemented behind the server environment setting `QUESTION_FEEDBACK_CONTRACT=authored_solution`; the default remains `reviewer_written`. No deployment or live qualification of this path is claimed at this milestone. The [reasoning comparison](QUESTION_REASONING_RECHECK.md) showed that the final reviewer could introduce incorrect teaching while approving correct keys. This change removes that unchecked content-writing step, without assuming that author text or model agreement is necessarily true.

## Runtime contract

1. The author creates the question, four choices, key and a complete main worked explanation. It must apply the stated facts and explain the decisive reasoning within the existing 420-character main limit. Choice explanations are not requested in this construction mode.
2. Sanitization rejects malformed or oversized main explanations instead of cleaning or clipping them. A supplied nonempty or malformed `choiceExplanations` value is a rejection, never permission to discard existing teaching. Normal stem and choice sanitization still occurs before the candidate is frozen.
3. The existing complete-choice solver receives the exact candidate stem and choices without the author key, explanation or difficulty. Zero or multiple supported choices, uncertainty and exact key disagreement block final review. These are enforced declarations, not proof that each model judgment is true.
4. The final audit receives the frozen candidate and main explanation, plus goal, skill and supplied source context. It receives neither the explicit author key/difficulty nor solver judgments/reasons. Historical answers and teaching are omitted. The explanation may reveal the intended key, so this audit is not answer-blind.
5. A strict response contains only an indexed verdict, exact answer, assessed difficulty, explanation support and issues. Unsupported or uncertain teaching, any issue, disagreement, malformed output or insufficient difficulty blocks acceptance. Replacement text and verification metadata are forbidden response fields.
6. Acceptance preserves the frozen main exactly, returns an empty choice-feedback map and assigns policy revision 3. The audit cannot write learner-facing content. The normal three-call generation path, deadline, quota and provider-call limits remain in force.

The iOS client already displays the main when choice-specific feedback is absent, and JSON bank storage retains the complete question. No storage migration or UI change is required for this opt-in shape.

## Provenance and limits

Revision 3 identifies execution of this particular contract. It does not certify semantic correctness. The default generation contract and current request/claim policy remain revision 2; requesting a revision-3-only bank is not yet supported. Existing revision-2 inventory and claim replays remain eligible, so enabling the environment flag alone does not guarantee that every delivered bank question used this path. Old content is never relabeled.

The application can enforce unchanged teaching and blocking review outcomes. It cannot establish that a model's `supported` label accurately describes its reasoning. Tests deliberately preserve an example where two falsely supportive model responses still admit incorrect teaching. Neither this path nor more output tokens replaces subject evidence or independent assessment.

A fresh, prospective trial across non-math goals is required before considering a default change. Inspect every raw candidate as well as returned content, measure usable yield and difficulty, and retain malformed output and rejected questions in the denominator. Passing a small trial would establish feasibility, not arbitrary-subject accuracy or full-bank release readiness.

## Verification

- Twelve pure contract tests and eight integration tests cover exact preservation, malformed and replacement feedback, answer/issue/support vetoes, solver prerequisites, configuration ownership, index reconciliation and policy provenance.
- The full backend suite passed **884 tests** with no skips on September 8 using the live-review Python environment; Ruff and `git diff --check` passed.
- Independent read-only review found no material integration blocker and confirmed that the default author, solver and reviewer prompts retain their archived bytes.
