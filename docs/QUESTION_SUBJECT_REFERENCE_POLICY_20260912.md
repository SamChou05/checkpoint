# Preserve learned facts across subject-reference fields

The source-only correction in policy 6/7 still discarded legitimate subject facts
when they appeared in goal or curriculum prose. This is a second form of the same
information-loss mistake, not a new reason to suppress another input field. The
request contract deliberately preserves literal subject content in these fields.

The final three calls of the existing 48-call continuation compared eight fixed
questions across arithmetic, programming, language and handbook facts. Their four
reference texts moved verbatim from source attachments into `goal.focusAreas`.
Four questions legitimately recall those facts; four omit essential case data.
Both arms used the same request/items, Sonnet and native schema. Only reference
visibility and the responsibility to use subject-reference facts differed.

- Source-only solving rejected all four valid recalls because their facts were absent.
- Restoring subject references recovered three valid recalls, with supported final teaching. Both arms blocked all four missing-case items.
- The fourth valid recall was wrongly rejected: the solver supported Friday for the Vale museum using a fact about the Fern museum. This is an observed subject mismatch, not proof of a particular batch-contamination cause.

[Exact plan](evidence/correctness-continuation-20260912/goal-reference/plan.json),
[all three calls](evidence/correctness-continuation-20260912/goal-reference/trace.json),
and [item-level assessment](evidence/correctness-continuation-20260912/goal-reference/assessment.json)
preserve the failure as well as the successes. The experimental final returns
retain historical policy 2; they are not relabeled as new production inference.
The matched stage costs one solver call per arm; candidate survivors then use the
existing reviewer. Total continuation inference is now **48/48**, combined **150**
with the earlier 102-call investigation. No failed or timed-out call was retried.

## Current responsibility and provenance

Policy 8 sends exact topic, stem and choices plus normalized goal, skill-map and
source references to independent solving. It omits the author's key, explanation,
difficulty, answer history, and generated item objective/tags. User-provided prose
can itself contain learned facts and answers; it remains untrusted subject data.
The model must distinguish those facts from lesson intent or missing case data.
This distinction is semantic; field deletion cannot enforce it reliably.

Policy 9 adds the existing optional authored-teaching audit. Historical reference
1/2/3, displayed 4/5 and source-only 6/7 paths preserve their original stamps.
The prompt builder takes one explicit context contract rather than overlapping
boolean flags. The production subject prompt and payload match the qualified
candidate bytes; offline replay uses the actual saved solver/reviewer responses
through current orchestration and owns policy 8 without changing old trace stamps.

The client requires 8 for fresh verified practice. Release API claim support and
all generating workers before distributing that client. Existing content and
attempt history keep their original bytes, wire version, key and policy revision.
Nothing was deployed or written to learner inventory.

The prior 21-call fresh-author matrix used the source-only intermediate, so it is
contextual evidence rather than fresh semantic qualification of this final
reference-preserving prompt. Exact literal-carrier tests, current-runtime replay,
and the four-domain reference comparison establish the omission correction;
they do not establish general correctness or eliminate false model reasoning.

All 1,071 backend tests, seven focused iOS policy/history tests, Ruff, and
`git diff --check` pass for this milestone.
