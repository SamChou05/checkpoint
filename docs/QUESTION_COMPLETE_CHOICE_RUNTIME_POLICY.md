# Complete-choice solver gate, policy revision 2

September 8, 2026. Generation now explicitly requests an independent judgment for
every offered choice. The solver sees the complete question and relevant subject
context, with the author's key, feedback, difficulty label and answer history
withheld. The application requires exactly one supported choice, three refuted
choices and exact agreement with the authored key before final review can run.

This is a general contract for multiple-choice questions on arbitrary subjects.
There are no exam-specific branches, topic lists or checks for the wording of the
observed CSS example. A correct response can be a natural-language negative,
zero, an insufficient-information conclusion, or a false statement in a task
asking for one. Support is judged relative to the actual question, not whether a
choice is a true sentence in isolation.

## Enforced behavior

- Missing, duplicate, rewritten or extra choice judgments fail validation, as do
  missing or duplicate question indexes. Malformed responses never fall back to
  the legacy solver.
- Zero supported choices, multiple supported choices, any uncertainty or a
  different supported key exclude an item before final review. An approving
  reviewer cannot restore it.
- Reordered responses are joined to their original questions before filtering
  and renumbering survivors. Identical stems with different choices keep their
  distinct records and exact reason text.
- Final review still independently checks the answer, actual difficulty,
  skill/objective fit and teaching feedback. Its prompt describes complete-choice
  judgments accurately and treats their reasons as fallible claims.

The change replaces arbitrary free-prose answer matching with an explicit mapping
to every option. It does **not** detect every semantic contradiction: a solver can
label an option supported while giving a wrong or contradictory reason, and a
fallible reviewer can still agree. Tests preserve that known limitation. Policy
revision 2 records the checks performed; it is not a truth certificate.

The [fresh immutable-auditor failure](QUESTION_FRESH_AUTHOR_IMMUTABLE_RESULTS.md)
provides separate evidence that even full-field model review can share an author's
false explanation. The current production review continues writing feedback;
this milestone does not integrate the experimental immutable auditor, external
retrieval or execution. The fixed WebKit counterexample remains evaluation evidence.

## Stored inventory and compatibility

Wire version remains 1, preserving historical grading and presentation behavior.
Only the complete-choice path followed by successful final review stamps policy
revision 2. The preserved legacy entry point always stamps revision 1; review-only
helpers cannot mint either solver provenance. Caller-supplied stamps are discarded.

The client now requires revision 2 for fresh verified practice. Existing policy-
aware claims, candidate admission, selection and bank context rotation use that
requirement. Old cached questions and attempt history retain their original text,
grades and revisions. A captured policy-1 app snapshot exercises the real migration:
the old bank and claim context are replaced, blocked/retry state is cleared, and
the full historical question and attempt survive persistence unchanged.

For a future release, deploy API support and generation workers for revision 2
before distributing the client that requests it. A revision-1 API rejects a
minimum-2 claim; an old worker only generates revision-1 stock. Older clients can
continue requesting their prior minimum but do not acquire a newer guarantee.
This work does not deploy either component.

Historical solver prompts, parser and default evaluation entry point are retained
unchanged. Frozen experiments remain replayable from their recorded source
revisions. The explicit model-comparison source manifest now includes the newly
imported adapter so future plans record that dependency as well.

## Verification and practical limits

The backend suite passes 761 tests with one existing optional-runtime skip,
including production path selection, budget/deadline behavior, batch correlation,
non-overridable vetoes, natural negative answers, both claim replay paths and
revision provenance. Legacy prompt hashes are unchanged. Ruff and whitespace
checks pass; independent backend review found no blocking defect within the
declared structural guarantees.

The client passes 29 focused freshness and bank-flow tests. A full isolated app
run passes all 995 tests, using base `df5f4d9` plus the exact three changed Swift
files and captured fixture. The earlier shared-checkout run exercised 1,018 tests
and encountered ten assertions in three in-progress learning-map visual tests;
its one skip and failures are not reported as a full-suite pass. Isolating this
policy change avoids conflating those separate edits with its validation.
The migration fixture
was exported by the actual older app using a mock bank, rather than synthesizing
its context hash: [snapshot](../CheckpointTests/Fixtures/policy-one-bank-snapshot.json),
[capture provenance](evidence/policy-one-context-provenance-20260908.json),
[temporary export test](evidence/policy-one-context-export-test-20260908.swift).

No model, output-token allowance, timeout or batch setting changed. Four reasons
per item can increase output pressure: at every field's ceiling, five items need
about 16,020 ASCII JSON characters. That is not a token-fit or latency guarantee,
especially when reasoning shares the allowance. Existing truncation handling
fails closed. The usual bank chunk is five, while larger configured/direct
batches need live operational qualification before rollout. Local tests establish
control flow and compatibility, not model accuracy, fill rate or learning gains.
