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
