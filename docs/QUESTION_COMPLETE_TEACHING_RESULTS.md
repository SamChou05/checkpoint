# Complete-teaching live qualification results

The September 10 frozen trial stopped on a reproducible software exception after
its first three model calls. It returned **0 of 15 requested questions**. The
first goal produced five readable drafts; the remaining two goals were never
attempted. All three responses were complete native JSON and ended normally.
This trial provides no evidence that increasing the 6,000-token output limit
would address the observed failure.

The immutable complete-teaching contract is **not qualified for promotion** by
this result. It also does not establish that the models cannot author MCQs:
independent execution confirmed all five authored answer keys. Correct keys,
correct teaching, suitable challenge and successful delivery are separate gates.

## Execution and actual delivery

The unchanged [prospective protocol](QUESTION_COMPLETE_TEACHING_QUALIFICATION.md)
and [original frozen plan](evidence/complete-teaching-preparation-20260910/frozen-plan/plan.json)
define the experiment. The source revision was
`a31a56c188d522dd40fb7ee45a49a7b1d6e20f74`; preparation HEAD was `94051df`.
The original plan was executed once after AWS authentication succeeded. Its
execution claim is preserved. No extra calls, retries of the plan, changed
limits, replacement fixture or post-result continuation occurred.

| Stage | Model | Output tokens | Input tokens | Stop reason |
| --- | --- | ---: | ---: | --- |
| Complete author | Kimi K2.5 | 1,438 | 2,879 | end_turn |
| Independent choice solver | Sonnet 4.6 | 1,428 | 2,403 | end_turn |
| Immutable complete auditor | Sonnet 4.6 | 744 | 5,844 | end_turn |

Thinking was disabled, temperature 0.2 and the per-call output cap 6,000.
All three native schemas were accepted and produced complete responses. Known
usage totals were 11,126 input and 3,610 output tokens, with zero unknown-usage
calls. Requests were 16,629, 9,270 and 21,389 serialized UTF-8 bytes. The observer
confirmed terminal workers and local process-group cleanup for all three calls.
Transport success is separate from factual correctness.

The [capture](evidence/complete-teaching-live-20260910/capture.json) exactly
replayed without network calls. The real offline bank preparation/claim path
returned zero items. Actual Swift decoding, sanitization, persistence and
feedback capture ran **one test, passed, with zero failures or skips**. It
observed zero retained items and zero composed displays. All three goal rows,
the explicit `authored_complete` selector and required policy revision 4 were
preserved. Client evidence is bound to the exact bank fixture hash; it is not a
reconstruction of hypothetical surviving questions.

| Goal | Requested | Raw drafts | Runtime returned | Bank | Client |
| --- | ---: | ---: | ---: | ---: | ---: |
| SQLite query results | 5 | 5 | 0 | 0 | 0 |
| Study design and inference | 5 | 0 (unattempted) | 0 | 0 | 0 |
| Spanish past-tense narrative | 5 | 0 (unattempted) | 0 | 0 | 0 |
| Total | 15 | 5 | 0 | 0 | 0 |

Delivery coverage is zero. Delivered-item precision is undefined, because no
items reached the client. The two unattempted goals cannot support cross-subject
quality conclusions. This finite-bank check does not exercise deployed queued
refill, adaptive learning or app blocking.

## Reproduced software failure

The reviewer reported `unsupported` choice feedback for raw item `q002`.
`complete_teaching_rejection_reason` correctly returned
`unsupported_choice_feedback`. However, `generation_diagnostics.record_quality`
did not allow that new reason and raised `ValueError: Unknown quality diagnostic`.
The exception escaped verification and discarded the entire batch, including
three provisional accepts. The frozen runner then stopped later goals as its
prospective unexpected-failure policy required.

The [exact replay diagnostic](evidence/complete-teaching-live-20260910/runtime-diagnostic.json)
locates the originating error at `generation_diagnostics.py:64`, called from
`question_verification.py:447`. The registry also omitted the other five new
unsupported/uncertain component reasons, invalid complete-teaching sanitization
and invalid complete-review format. Earlier direct rejection tests omitted a
metrics dictionary, which bypassed the registry check and hid this production
path. This is a general integration defect, independent of SQL content.

The correction is committed and pushed separately as `a71d8db` on
`codex/complete-teaching-diagnostics-fix`, preserving the original trial source.
It adds the eight bounded diagnostic names and enables metrics in the existing
integration tests. New regressions exercise all six component rejection states
through the actual HTTP/native orchestration, preserving a valid neighboring
item and emitting content-free metrics. They also cover malformed complete
teaching and malformed audits. Before the fix the six HTTP cases returned 502;
afterward all 1,150 backend tests passed, along with Ruff and diff checks.
There were no additional live calls, model/prompt changes or deployment.

## Independent assessment

Two assessors independently solved every raw stem and all 20 choices before
seeing keys, explanations or runtime verdicts. Their phase-one files were frozen
and hashed before phase two. They separately froze the empty client packet
before inspecting client teaching. All five raw occurrences and every native
feedback row remain in the assessment evidence, including rejected items.

Both assessors and literal SQLite execution confirmed five unique keyed
answers, sufficient premises and goal relevance. Both rated `q001` and `q003`
as difficulty 2; both found `q003` distractors weak. They disagreed on `q004`
difficulty (3 versus 2), which remains a disagreement rather than a factual
error. Both rated `q002` and `q005` as difficulty 3.

Both assessors supported 4/5 main explanations and 19/20 native choice-feedback
rows, with the same two defective items. Thus **3/5 raw drafts had fully
supported teaching**. Assessor A considered `q004` useful; assessor B rated it
below the difficulty target. Under the predeclared agreement rule, **0/5 raw
drafts met every usefulness criterion for both assessors**. This does not make
`q004` factually wrong. Actual useful delivery remains 0/15 because the runtime
returned no items.

The [assessment summary](evidence/complete-teaching-live-20260910/assessment-summary.json)
and separate frozen assessor files preserve all initial judgments and the
difficulty disagreement. No runtime verdict is treated as the factual ground
truth.

## Concrete semantic findings

The following defects have independent executable evidence, beyond a model's
support declaration:

- **Missed false explanation, `q005`:** the main explanation says the excluded
  NULL-extended row has `L.ID=20`. The literal join produces `(10,NULL)` and
  `(20,'a')`; the excluded row has ID 10. The author keyed the correct final
  result, but the main teaching describes a nonexistent intermediate row.
  The auditor marked the main and all displays supported and provisionally
  accepted it. The later software exception prevented actual delivery.
- **Correct rejection, `q002`:** feedback says `1=NULL` is false. SQLite evaluates
  that expression to NULL; a join predicate that evaluates to NULL does not
  match. The main explanation states the NULL result correctly, so the fields
  also contradict one another. The auditor caught this defect. Logging that
  rejection triggered the software failure.
- **Solver reasoning error, `q003`:** the blind solver repeatedly describes two
  surviving `V=2` rows, although the stated input has only one. Its chosen
  answer remains correct. The auditor rated the item below the requested
  difficulty, appropriately excluding it, but agreement on the key did not
  establish correct reasoning.

The [literal SQLite checks](evidence/complete-teaching-live-20260910/sqlite-checks.json)
retain setup statements, exact queries and observed rows; no missing case facts,
constraints or repaired queries were substituted. They agree with SQLite's
[expression rules](https://www.sqlite.org/lang_expr.html) and
[join/filter processing](https://www.sqlite.org/lang_select.html).
The [occurrence lineage](evidence/complete-teaching-live-20260910/occurrence-lineage.json)
separates raw drafting, solving, audit declarations, provisional admission and
actual zero delivery.

## Implication for the architecture

The deterministic rejection/metrics integration is now fixed and verified with
metrics enabled in real orchestration tests. This preserves the rejection; it
does not make the auditor's other factual judgments correct.

Immutable authorship prevents the reviewer from introducing new teaching, but
this trial shows it can still approve an author's false explanation. More
serial approval calls, schema compliance or unanimous key agreement should not
be presented as proof of correctness. For claims that can be executed, checking
intermediate steps as well as the answer would have exposed these examples.
For other subjects, source support or explicit premises must play the analogous
role; a SQL-specific rule would not be a generalized fix.

Further model/prompt changes need a fresh bounded evaluation after the plumbing
fix, with answer correctness, teaching correctness, challenge and delivered
coverage measured separately. These five selected drafts neither estimate a
production error rate nor establish generalized reliability. Production defaults
and deployment were not changed by this trial.
