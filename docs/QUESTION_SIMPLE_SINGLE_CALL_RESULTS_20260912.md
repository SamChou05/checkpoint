# Simpler questions in one call: faster, still unreliable

The requested prototype uses **one author call per two-question batch**, a
**144-word system prompt** (previous author: 975 words), and **one worked
explanation**. There is no solver, reviewer, model repair or replacement. All
reference facts remain available. The exact prompt is in
[the implementation](../backend/bedrock-question-service/evals/checkpoint_simple_single_call.py)
and the [frozen plan](evidence/simple-single-call-20260912/plan.json).

It is much cheaper in calls and observed time, but this sample does **not** show
better correctness. The prototype is committed for evaluation; production still
uses its existing verification contract. No new questions were stamped verified,
written to learner inventory or deployed.

## Same four requests and two authors

The eight candidate calls repeated the previous mixture, Python, relative-clause
and private-transit requests with the same Nova/Kimi author models and settings.
The comparison uses saved baseline calls; it is not a randomized concurrent A/B.
The questions themselves are newly generated, so this compares designs on matched
requests, not identical authored items.

| Measure across 16 requested questions | Previous complete pipeline | Simple one-call candidate |
| --- | ---: | ---: |
| Actual provider calls | 22 | 8 |
| Summed local pipeline time | 138.578 s | 31.590 s |
| Input tokens | 42,957 | 3,542 |
| Output tokens | 10,858 | 3,914 |
| Items retained by each path | 5 verified returns | 10 format-compatible, unverified candidates |
| Retained items with supported key and main explanation | 5 | 4 |
| Retained items with supported key, main and all per-choice feedback | 3 | Not applicable: per-choice feedback omitted |

Calls fell **64%**, observed time **77%**, and total tokens **86%**. These are
single-run local measurements, not production latency distributions or dollar
cost estimates. The reduced feedback feature contributes to the savings.

The common comparison is key plus main explanation after actual content
transformations. Comparing the previous three full-feedback successes directly
with the candidate's four main-only successes would overstate the result. The
candidate produces more material, including several wrong questions that pass
format checks. Its four supported retained items are Kimi's two Python questions,
one wolf relative-clause interpretation and one transit-day question. Distractor
clarity and awkward singular/plural wording remain qualitative reservations in
the latter two; these are not four expert-certified items.

## What improved, and what failed

- **Python:** Kimi's two closure/default questions are correct on execution, with
  supported explanations. Nova gets the value sequences right but writes false
  explanations about which variables or calls are captured; its comma-separated
  choices also do not literally reproduce the printed line breaks.
- **Math:** Kimi reaches 26.25 liters of acid in 60 liters, then incorrectly calls
  that 35%; the exact answer is 43.75%, absent from the choices. This bad question
  passes format admission. Another stem requires both 30% and an incompatible
  final 42%; the main notices the contradiction but keeps the intended key.
  Nova's dilution questions also have incorrect or incomplete cases and long,
  contradictory explanations. Short instructions did not resolve these failures.
- **Language:** Both authors still offer restrictive `that` and restrictive `which`
  as competing correct answers. One otherwise correct Nova explanation refers to
  “the second sentence”; existing choice normalization moves that sentence to
  first position, making the explanation unreliable even before iOS shuffling.
  The source-example question is also below the requested level.
- **Transit:** Kimi correctly gives Monday and Friday for Harbor→Ridge, but its next
  item calculates Friday and still keys Wednesday. Nova invents travel times and
  a nonexistent line connection, and omits mapped IDs. All supplied route/day facts
  were present. Format rejection is recorded separately from these semantic errors.

## Fresh cases, fixed before results

Four further single-call Kimi requests cover new price changes, Python dictionaries,
English past-modal deductions and a fictional reserve handbook. These produced
**eight drafts, six format-compatible candidates, and four clearly supported
key/main items**: both dictionary questions and both handbook questions. One modal
item remains qualified under competing readings, rather than counted as plainly
wrong or fully sound. Both price questions fail: their mains calculate the correct
amounts ($351 and $212.70), then rationalize incorrect offered keys. Oversized
explanations cause their separate format rejection.

Fresh calls total **40.405 seconds**, including a 27.414-second price response that
spends its output repeatedly defending an inconsistent answer. Thus one call is
not automatically short in every case. The worker model was selected for these
fresh requests before any candidate results were inspected.

Total trial: **12/12 calls, 24 drafts**. There were no retries or transport errors.
Four responses were bare JSON; eight used a sole JSON fence allowed by the existing
whole-response parser. No surrounding model prose was discarded. Six mains exceed
420 characters; two additional items fail mapped-ID admission. Their raw text is
preserved and assessed. No field was shortened to manufacture a passing result.

## Evidence and checks

The [24-item assessment](evidence/simple-single-call-20260912/assessment.json)
records key/main support, exact output lengths, admission, difficulty, ambiguity,
and distractor reservations for every raw draft. All actual prompts and responses
are saved in the same directory. [Boundary checks](evidence/simple-single-call-20260912/boundary-checks.json)
confirm exact frozen prompts, reference preservation, one call per job, unchanged
main teaching through admission, and absence of verification stamps. A positional
explanation can become wrong even when its bytes are preserved; that failure is
included in the assessment.

[Independent checks](evidence/simple-single-call-20260912/independent-checks.json)
use exact arithmetic, execution of the displayed Python code spans and the
stipulated handbook facts. The record specifies where prose labels/fences and
terminal sentence punctuation were excluded from code spans. Grammar checks use
the provided notes and [Cambridge Grammar](https://dictionary.cambridge.org/grammar/british-grammar/relative-clauses-defining-and-non-defining)
and [British Council](https://learnenglish.britishcouncil.org/free-resources/grammar/b1-b2/modals-deductions-about-past?page=1).
The modal ambiguity concerns whether the story supports the speaker's judgment,
not whether `cannot have` can express a strong negative deduction. Assessment is
by the assistant, not a blinded human expert panel.

The new one-call/provenance tests and existing trace/budget tests pass (seven tests),
as do Ruff, dry-run normalization, saved-source hash comparisons and diff checks.
The [manifest](evidence/simple-single-call-20260912/manifest.json) preserves the
captures and assessment sidecars. Earlier evidence is unchanged.

The useful result is a small, reusable baseline with measurable call savings.
This particular prompt/model combination does not justify replacing production
verification. A next comparison can keep this one-call design fixed while changing
the author configuration; another stack of reviewer prompts is not supported by
these results. No further calls are part of this completed 12-call trial.
