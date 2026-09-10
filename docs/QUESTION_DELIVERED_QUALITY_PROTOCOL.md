# Compare delivered quality under the normal question-generation budget

Prospective protocol, September 9, 2026 (Pacific time). This is a new comparison
of two existing teaching contracts through the ordinary five-item generation
workflow. It changes no production default and does not require every raw draft
to be perfect. The primary objects of assessment are the exact questions the
runtime returns and the requests it can fill within its fixed budget.

## Why this is the next diagnostic

The [checked-example trial](QUESTION_AUTHOR_EXAMPLES_RESULTS.md) found more
supported raw keys in its example arm, but equal complete-content counts.
The [author-model comparison](QUESTION_AUTHOR_MODEL_COMPARISON_RESULTS.md)
also found raw-key gains without demonstrating sufficient useful inventory.
Both used one generation pass and two requested items. The
[current-worker qualification](QUESTION_RUNTIME_QUALIFICATION.md) exercised a
five-item batch, but only one fresh goal, and returned erroneous teaching.
The [authored-solution trial](QUESTION_AUTHORED_SOLUTION_FRESH_RESULTS.md)
preserved returned teaching through an audit but still returned a misleading
explanation. These observations leave an important comparison missing: whether
the existing stricter teaching contract improves what is actually delivered
under the normal replacement budget, and at what cost in usable inventory.

Primary research supports measuring that tradeoff, without supplying a ready
automatic correctness oracle. A 2026 study of 429 filtered Eedi math questions
found that modern models already use solution, misconception and selection
strategies. Imposing that sequence changed reference-distractor matching from
0.52 to 0.55 without statistical significance. Matching an existing bank is
also an incomplete quality measure: another plausible wrong alternative can
be useful. This study concerns distractors for supplied questions, not complete
arbitrary-goal authorship or learner gains.
[Zengaffinen et al.](https://arxiv.org/html/2603.15547v1)

Bitew and colleagues supplied existing questions and answers, generated ten
distractor candidates per question and obtained teacher assessments. Retrieved
question-relevant examples helped modestly in their language setting; roughly
half of candidates were useful. That supports distinguishing candidate supply
from selected-set quality. It does not establish an automated selector or that
three static cross-domain examples make a complete MCQ correct.
[Bitew et al.](https://arxiv.org/html/2307.16338v1)

MMLU-Redux manually reannotated 5,700 questions across 57 subjects and found
meaningful errors in benchmark questions and weak automated error detection.
Consequently, model rejection counts or agreement alone cannot certify the
accepted set. Unclear questions/options, wrong keys, no correct option and
multiple correct options are useful categories for our natural failures.
[Gema et al.](https://aclanthology.org/2025.naacl-long.262/)

## Fixed inputs and execution

Experiment identifier: `worker-delivery-feedback-comparison-v1`.
The existing `evals/checkpoint_runtime_qualification.py` runner is reused, with
an additive mode and its existing isolated transport and replay. No new worker
supervisor or production verifier is introduced.

Reuse the three exact goal/source payloads from
`evals/fixtures/question_author_examples.json`: Excel copying, map scale and
food-web energy. Change only `targetCount` from two to five. Keep the raw goals,
minimum difficulty 3, source text and truncation markers unchanged. The origin
fixture's byte SHA-256 is
`82fb6ca25666ab4d00c0780cae9f1d41e0ff9fecd33555e99b0d50e57f393bc8`.
Its demonstrations, assessment notes, previous outputs and known failure
descriptions are excluded from every provider request. These are reused,
selected goals with fresh generated outputs, not unseen subject holdouts.

Each goal has two independent operations: `reviewer_written` and
`authored_solution`. Reverse their order for the middle goal. The settings
within a pair differ only in `QUESTION_FEEDBACK_CONTRACT`; that selector changes
the existing author/review contracts and admission behavior as designed.
Downstream requests depend on each operation's newly generated candidates.
This is a comparison of complete existing workflows, not the same drafts
reviewed twice or an isolated test of one sentence in a prompt.

Both use Kimi K2.5 authoring, Sonnet 4.6 solving/review, disabled thinking,
6,000 output tokens, temperature 0.2, three generation attempts and at most six
provider calls per operation. There are six operations, at most 36 calls and
30 requested returned slots. Each operation has a 240-second clock; transport
uses read75/connect3 and one SDK attempt. The existing runner's conservative
fixed-read admission is not an exact simulation of the deployed client's
late-operation timeout shortening. Serialized requests are limited to 32 KiB
each and 36 times that allowance in total. Bytes are not tokens or a spend cap.

Normal author JSON repair and content replacement are allowed only as performed
by the unchanged runtime, within the same call and attempt budgets. Preserve all
raw responses and retry feedback. No manual edits, post-hoc selection,
replacement operation, fallback model, resumed failed capture or extra inference
is allowed. No native execution or example suffix enters this comparison.
Freeze the complete inputs, source, dependencies, settings, initial requests
and operation order before dispatch; record each later actual request before
its provider call.

A completed usable textual response with a recognized question-content failure,
or a request that exhausts its ordinary content/call budget, is a per-operation
coverage outcome. It must
not be relabeled as a provider outage or prevent the other independently
budgeted operations from being evaluated. The new mode distinguishes these
recognized runtime outcomes only when the transport has not latched a failure.
Actual provider, unfinished-response, transport, cleanup, persistence or unknown
failures still stop later dispatch. Preserve partial results and unattempted
operations; do not infer zero usage from a missing response.
An observer record with `content_valid == false` is an operational failure even
if the model's stop reason is `end_turn`. Propagated deadline failures also stop
the comparison. The unchanged runtime can return an earlier partial batch after
declining a late top-off; this comparison adds no new deadline supervisor or
global latch for a deadline exception already handled by that runtime.

Source preparation occurs in an isolated worktree starting at `aa2db49`, so
concurrent native-schema implementation in the shared checkout cannot alter
this comparison midway. The final committed experiment revision, rather than
this starting revision, must bind the executable plan. Native structured output
is outside this fixed comparison.

## Assess the returned set, then account for coverage

Keep every raw author occurrence for diagnostic purposes, including discarded,
malformed, oversized and replacement candidates. The primary quality denominator
is every returned item, not a favorable sample of those items. Empty returned
sets have undefined precision and zero useful coverage, not perfect precision.
No human or assistant assessor may select a better draft for delivery afterward.

Two fresh independent assistant assessors receive opaque shuffled IDs, exact
returned stems and choices, raw goals and supplied source summaries. Initially
withhold the authored/returned keys, all feedback, arm, model difficulty and
runtime outcomes. Freeze both first passes before revealing the exact returned
main, every returned choice explanation, and the composed feedback shown for
each selected choice. Freeze both teaching passes before
unmasking arms, keys or operational counts. Disclose that explanations reveal
intended answers, that the goals have appeared in prior experiments and that
assistant assessments are not expert or learner calibration.

Assess complete premises, exactly one warranted key, three plausible distinct
wrong choices, goal fit, actual cognitive demand and wholly supported worked
teaching. Evaluate all feedback the app can display, including why a wrong
choice is wrong. Empty choice feedback in authored-solution mode is intentional;
the main must still teach a complete solution. Preserve ambiguity and
disagreement instead of repairing the question's intended meaning.

The app shuffles choices while preserving their text identity. Assess whether
the stem and feedback remain valid under that shuffle: references such as
"the first option" must not acquire a different meaning. For each offered
choice, assess the displayed composition of its distinct feedback followed by
the main (or the main alone when choice feedback is absent or identical).
Individually supported strings do not excuse a contradictory composed display.

Freeze each assessor's supported choice set, premise validity, goal fit,
distractor adequacy, assessed difficulty, whole-feedback support, worked-solution
completeness and shuffle safety as separate fields. Joint supported-key credit
requires both assessors independently selecting exactly the returned keyed
choice with valid premises. Joint complete-teaching credit requires both to
support all displayed feedback and mark the worked solution complete and
shuffle-safe. A jointly useful item must receive both of those credits, and
both assessors must find goal fit, adequate distractors and difficulty at least
3. Uncertain or disputed criteria receive no joint credit; report each
assessor's counts and the disagreements separately. Later root checks may
document additional defects or counterexamples but cannot upgrade a disputed
item into joint credit. This rule is fixed before the live run.

Report per arm and per goal:

- Supported-key precision and complete-teaching precision among all returns.
- Complete useful-question precision, combining correctness, premises,
  distractors, goal fit, assessed difficulty at least 3 and complete teaching.
- Returned count and independently complete useful count per five requested
  slots; requests with all five returned and requests with all five useful.
- Raw generation counts, ordinary rejection categories, repairs/replacements,
  content-budget outcomes, operational failures and unattempted work separately.
- Provider calls, known tokens, observed time and calls/tokens per useful return;
  leave the latter undefined if no useful question was returned.

Keep any format, length or provenance exclusions distinct from factual error
detection. Do not change the existing stem320/choice140/main420 admission limits
or main320 author guidance after observing results. Do not present this small
selected run as a population accuracy estimate or a learning-outcome study.

## Delivery boundary and decision

After content assessment, verify the exact returned content through the existing
bank/claim serialization and app decoding/feedback-selection contracts using
isolated synthetic state and envelopes around unchanged returned content. Run
each complete returned operation batch together, starting from a fresh bank and
empty local history under the same goal/source context, target five and minimum
difficulty three. Record runtime-returned, bank-claimable and client-retained
counts separately; losses at later boundaries remain in the original runtime
quality denominator. Bind the Swift sources used for these checks.
The local storage check uses a completed finite bank sized to the returned
batch, so it exercises claim and idempotent replay without enqueueing refills.
That synthetic bank size does not change the original five-item generation or
client request. Worker scheduling and production refill behavior are outside
this storage/decoding check.
Compare complete question text, choice identity,
key and every displayed explanation. Choice order may change through the actual
app sanitizer; compare identity mappings and composed feedback for every choice,
not array order. Keep local contract checks separate from
an actual deployed bank/claim operation; no production bank write is authorized
by this experiment plan. A model return does not by itself prove client delivery.

Prefer a workflow only on evidence about both useful delivered precision and
coverage. A stricter mode that merely empties requests has not fulfilled the
product goal. A fuller bank containing incorrect teaching has not fulfilled it
either. Partial benefits remain evidence without making a small zero-error set
proof of general reliability. Any subsequent production default or external
capability integration needs its own review and verification of the final state.
This comparison does not establish adaptive progression, learner retention or
the full arbitrary-goal correctness objective.

## Preparation verification

The additive evaluation mode pins the batch maximum to five and rejects a
normalized request that changes the five-item target, difficulty three or source
documents. A hostile ambient batch limit of two is covered by a regression.
Fifteen new tests exercise the actual generation loop with controlled provider
observations, including both contracts, rejection/top-offs, malformed JSON and
bounded repair, partial results, transport failure, deadline behavior, frozen
input tampering and exact replay with client creation forbidden.

The full backend suite passed 1,007 tests in 31.063 seconds with no skips.
Focused Ruff, Python compilation and `git diff --check` passed. These are local
contract and harness checks; the controlled responses do not provide evidence
of live question correctness. The separate local delivery helper and app check
will be verified before their eventual results are reported.
