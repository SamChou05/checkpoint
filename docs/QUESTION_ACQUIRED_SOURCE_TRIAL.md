# Fresh questions with captured source evidence

September 8, 2026. This prospective evaluation tests the author and immutable
source reviewer together on three fresh learning goals. It uses the successful
records from the [four-reference acquisition](QUESTION_SOURCE_ACQUISITION.md).
The original failed W3C capture is not replaced or counted as a success.

| Goal | Acquired reference | Selected character interval |
| --- | --- | --- |
| Reason about Python loops and loop `else` | CPython 3.14 tutorial source | 4,800–8,080 |
| Apply the Declaration's argument about rights, consent and revolution | National Archives transcription | 1,953–4,001 |
| Explain seasons, axial tilt and opposite hemispheres | NASA Space Place | 430–5,782 |

Intervals are zero-based with an exclusive end in each exact captured text.
They were selected before any author call. Each goal requests minimum difficulty
3: applying relevant details to distinguish plausible conclusions. Subject
selection is for this evaluation; the code contains no topic-specific branches.

Each case permits one complete author response and one immutable evidence audit,
at most six model calls in total. The author and auditor receive the same exact
source spans and omission metadata. The auditor sees all teaching text but not
the explicit authored key or difficulty. It can reject content, not repair it.
No independent stem-only solver or production admission is part of this trial.

Requests use the existing evaluation model, Opus 4.6, adaptive thinking, high
effort and 16,000 output tokens. Each request has a 32,000-byte input allowance.
The existing process caller supplies a 300-second local deadline and read window,
with one SDK attempt and bounded cleanup. This evaluates evidence use, not a
production timeout or model change. Failed calls can have unknown remote
completion and usage. No retries, repairs, replacement goals or resumes are
allowed within the run.

The fixture and exact author requests are frozen before dispatch. Each dynamic
audit request is derived from the unchanged validated author result and recorded
before its call. Captured outputs and exact citations are replayed locally.
Operational, binding or persistence failures stop later calls; content/evidence
or difficulty rejection retains that outcome and ends the affected case.

Assessment must distinguish response completion, valid content shape, exact
citation coverage, independently correct key, all five accurate explanations,
plausible distinct choices and actual difficulty. Model approval is not the
correctness score. A three-item selected trial cannot estimate production error
rates or establish learning gains. Full captured reference text and request
packets remain in ignored local evidence files; published summaries retain their
hashes and limits without redistributing complete source pages.

## Results

The frozen run completed five calls normally and used 31,651 tokens (18,336
input, 13,315 output). All responses ended with `end_turn`; individual SDK
intervals were 26.2–44.1 seconds, and local worker/group cleanup was confirmed.
No response reached the output ceiling. The exact plan hash was
`2f4d7016677db398b89f15c56668852eb0086d71d2e3291bfdb3582f7801e99a`.
[Captured results](evidence/acquired-source-fresh-trial-20260908.json) preserve
every authored question, the contract outcomes, usage and request/source hashes.

| Fresh item | Pipeline outcome | Independent key / teaching assessment | Independent difficulty |
| --- | --- | --- | --- |
| Python loops | Accepted with exact citations | Unique correct key confirmed by execution; all five explanations sound for this code | 3, moderate confidence; closely resembles the source's worked example |
| Declaration argument | Author contract rejected; no audit call | Key supported; four explanations overstate the source's requirements | 2 |
| Seasons | Accepted with exact citations; model rated 3 | Key supported; explanations sound in ordinary school-level context, with three fields containing facts absent from the selected reference | 2 |

The Declaration rejection was caused by an optional objective label of 144
characters against the 140-character bound. The stem and choices fit their
limits. This is a format rejection, **not evidence that the audit detected the
teaching errors**. The original output remains unchanged, and the unspent audit
call was not used for a repair. Independent reading found that its feedback
turned one sufficient justification for revolution into an exclusive necessary
condition; some distractor explanations added qualifications the source did not
establish.

The seasons auditor returned valid exact quotations for every required field,
but those quotations did not cover every claim, including the additional Earth
diameter and orbital-speed facts. Their absence from the supplied source is not
proof of falsity. Independent assessment found no material error in the ordinary
daylight/seasons context, but rated the cognitive work below the requested level.
This is a concrete limitation of field-level citation coverage and model difficulty
ratings, not evidence that more output tokens are needed.

Each key/difficulty assessment was frozen before its assessor saw authored keys,
feedback or the model audit. Subsequent teaching assessments saw the exact
authored content but still did not see the audit verdict. These are assistant
assessments, not a human panel or calibrated psychometric measurement. The Python
code also ran once in isolated Python 3.12 after manual inspection; its output
exactly matched one choice. That is a check of one exact program, not automatic
execution support for arbitrary prose questions.

Only the Python item had support for complete teaching content at the requested
challenge, and its novelty was limited. The trial establishes that acquired
source text can reach both roles and yield replayable exact citations. It does
not establish a general correctness improvement over earlier configurations,
reliable difficulty progression, a production error rate or release readiness.

Offline replay verified frozen plan/source/request/decision bindings with no
new model calls. Full backend validation passes **826 tests with one existing
optional-runtime skip**. The new code and results are committed; none of this
experimental pipeline was deployed or admitted to learner inventory.

Independent evidence:

- [Python blind assessment](evidence/acquired-source-python-blind-assessment-20260908.json) and [exact native execution](evidence/acquired-source-python-native-20260908.json).
- [Declaration blind assessment](evidence/acquired-source-declaration-blind-assessment-20260908.json).
- [Python and Declaration teaching assessment](evidence/acquired-source-python-declaration-teaching-20260908.json).
- [Seasons blind assessment](evidence/acquired-source-seasons-blind-assessment-20260908.json) and [teaching assessment](evidence/acquired-source-seasons-teaching-20260908.json).

## Deployment snapshot, checked separately

A read-only check of the known TestFlight API and worker `$LATEST` packages found
policy revision 1. The inspected generation/verification/policy files match
revision `601d273`; both downloaded bundle hashes match Lambda's recorded code
hash. Policy-2 complete-choice integration is absent. This was a package/config
inspection, not a live request or an audit of every deployment or traffic alias.
[Sanitized deployment record](evidence/deployed-backend-correctness-20260908.json).

The deployed worker uses Kimi K2.5 and Sonnet 4.6 review with thinking disabled;
ordinary output is capped at 6,000 tokens. The API's author is Nova Lite. Existing
typed outcomes, required assumptions, nonempty resolved limitations and exact
alternative-answer vetoes are already deployed, so the old assumptions-only
description is stale even there. Impossibility stated only in non-choice answer
prose can still evade the legacy checks. The new repository checks and the Opus
evidence trial must not be described as the behavior current users receive.
