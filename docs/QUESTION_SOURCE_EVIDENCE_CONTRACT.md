# Backend source instructions now distinguish learned knowledge from case data

The default reviewer previously said supplied sources could **only** establish
subject/scope and outside knowledge could supply definitions. The author and
solvers were allowed to use substantive source facts. The backend therefore
gave different stages conflicting instructions about the same question.

`question_source_guidance.py` now supplies one shared instruction block to
authoring, complete-choice solving, current reviewer-written feedback and
authored-solution review. The author’s repeated constraints in
balanced, focused-application, checklist and authored-teaching prompts now refer
to case-specific premises instead of requiring every learned fact in the stem.

The contract permits ordinary established subject knowledge and relevant
substantive supplied text. A topic-only outline, title or unfetched URL does not
establish unseen facts; substantive content inside a document called an outline
is still usable. Explicit fictional rules and relevant source qualifications
must be preserved. Embedded behavioral commands remain untrusted data.

The distinction matters because
[`CheckpointAttemptView.questionPanel`](../Checkpoint/Views/CheckpointAttemptView.swift)
shows the topic, question and choices, with no accompanying source-document
panel. A question can test a fact or rule learned from study material without
restating its answer. A question asking the learner to inspect a particular
passage, table, diagram or code sample needs that stimulus in the displayed
stem or choices. Choices may carry objects, samples or hypotheticals when those
are what the task asks the learner to assess; an option cannot introduce a new
condition that repairs the common scenario. Private case details cannot repair an absent stimulus, and the
explanation cannot be the first place essential case premises appear.

Examples of intended behavior, not observed provider results:

| Task | Intended source use |
| --- | --- |
| Recall a studied vocabulary meaning or established historical fact | Use learned knowledge; the stem need not give away the answer. |
| Apply a learned fictional rule to a person whose relevant state is stated | Use the studied rule and the displayed case facts. |
| “Using the table below…” without a table, even though one exists in private source text | Do not silently borrow the table to approve the incomplete question. |
| Source text is truncated before an exception or necessary case value | Do not invent the omitted text or assume the excerpt proves its absence. |

No response schema, answer-key hiding, text-normalization limit, solver veto,
review admission rule, model setting or source import behavior changes. This is
an instruction-consistency fix; it does not make model declarations factual
proof, add retrieval, or recover discarded source text.

The existing provider-boundary integration test now includes mixed complete and
truncated documents, literal whitespace and delimiter-like text. It checks exact
source delivery and the shared instruction block through native/legacy author,
solver and both review modes while retaining the prior key-hiding and objective
checks. Scripted responses test these interfaces, not model obedience or quiz
correctness. No extra model experiment was created for this change.

Work is isolated in `/tmp/checkpoint-source-evidence-contract-20260910`, branch
`codex/source-evidence-contract`. The prepared ordering comparison remains in
its original clean checkout and binds its original prompts. Do not run that
comparison from this changed source or attribute later source-guidance behavior
to output order. AWS renewal is still pending; no inference or deployment has
occurred for this slice.

Scope remains backend-only. Local iOS prompt text in `QuestionContext.swift` and
`AppleFoundationQuestionEngine.swift` still has broader self-contained wording;
this change does not claim app-wide prompt consistency or learning gains. Live
question-quality evaluation and full-workflow qualification remain required.

Legacy revision-one solver/reviewer prompt bytes remain frozen for historical
evaluation compatibility; the active production generation path uses the
complete-choice contract. Historical diagnostic tests must explicitly load
their frozen prompt contracts rather than reinterpret old evidence using the
new source instructions.

Verification completed: all 1,134 backend tests pass, including the source-bearing
provider-boundary integration and two checks refusing historical plans under new
production prompt identities. Historical diagnostics use a test-only fixture
bound to immutable capture bytes and explicit prompt hashes; production guards
and archived evidence were not loosened or edited. Both revision-one prompt
hashes remain exact. Ruff and diff checks pass, and independent review found no
remaining instruction conflict after clarifying choice-contained stimuli.
The original 32-call ordering plan was revalidated in its unchanged checkout.
