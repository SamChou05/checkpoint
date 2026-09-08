# Artifact-first authoring: partial results, September 8, 2026

The [frozen four-question trial](QUESTION_ARTIFACT_AUTHORING_EXPERIMENT.md) did **not** pass. Python returned two structurally usable proposals; HTML timed out. The stopping rule ended the trial before any generated artifact was executed or observed in a browser. There is no fresh native-bound key, production change, deployment, or model promotion from this run.

This is a different construction mechanism from another solver/reviewer prompt: the application renders an exact supplied artifact and can select an answer by matching its native result to four typed alternatives. The code boundary is tested, but this incomplete trial does not establish useful live generation through that boundary, correctness across arbitrary goals, or a fix for the historical all-pairs question.

## Dispatch and capture

The author ran from source `04fc960d190a2dd1fb707f88489bbcc567811f01` with the exact archived requests and US Opus 4.6, adaptive thinking/high effort, 16,000 output tokens, one SDK attempt, and a 100-second read timeout. The local process ended with exit code 1. The [unaltered capture](evidence/artifact-author-capture-20260908.json) has byte SHA256 `aa701fa99b2ebd671816383d58ea9678248ded4e121dc1cbf2a9135bb3d1aaa5`.

| Author call | Outcome | Elapsed call interval | Known token usage |
| --- | --- | ---: | ---: |
| Python, two candidates | Completed with `end_turn` | 68.934 s | 1,295 input + 6,060 output = 7,355 |
| HTML, two candidates | `ReadTimeoutError` | 100.004 s | Unknown |

There were two dispatches and no retries, replacement candidates, model solvers, model reviewers, feedback rewrites, native Python sessions, or generated-HTML observations. A timed-out call does not imply zero provider usage or confirmed remote cancellation. The returned Python call did not exhaust the output allowance. The HTML response provides no output-token evidence, and this single timeout does not isolate batch size, model reasoning, network behavior, or service latency as its cause.

The [offline preparation](evidence/artifact-author-offline-preparation-20260908.json) was performed after the stop solely to inspect the returned proposals. It preserves the full source, invocation, proposed options/feedback, unkeyed display, and prepared-but-undispatched execution job. It does not authorize native dispatch or change the trial's stop rule. Both Python proposals fit the unchanged limits and the existing execution eligibility rules: their full rendered stems are 179 and 203 characters. The two unavailable HTML slots remain in the four-question denominator.

## Independent content assessment

Two assessors separately read the [answer-free packet](evidence/artifact-author-blind-packet-20260908.json), then froze their judgments before reading any authored explanation or difficulty label. They used the complete displayed source and invocation and official Python documentation, without executing the source. Their records are [independent assessment](evidence/artifact-author-blind-assessment-20260908.json) and [root assessment](evidence/artifact-author-root-blind-assessment-20260908.json). Ratings are provisional judgments, not calibrated difficulty or measured learning gains.

| Planned slot | Warranted answer on manual inspection | Difficulty judgments | Content finding |
| --- | --- | --- | --- |
| Python 1: shallow copy, mutation and rebinding | `[[1, 2, 9], [3, 4]]`, a list | Both 3 | Complete question; distinct, plausible distractors. One proposed distractor explanation needs clearer wording. |
| Python 2: accumulation with `break` and loop `else` | `5`, an integer | Both conservatively 2 | Complete question and supported feedback, but below the target. One assessor also found the `8` distractor weak; root considered it plausible. |
| HTML 1 | Unavailable | Unassessable | Author response did not return. |
| HTML 2 | Unavailable | Unassessable | Author response did not return. |

The Python 1 key follows because the outer slice preserves references to the existing inner lists: mutation of the first inner list remains visible through the copy, while replacing the second slot of the original outer list does not replace the copy's slot. Python 2 directly applies the rule that `break` skips the loop's `else`; its small accumulation does not, in either assessor's conservative reading, add enough challenge for level 3. See [Python copying](https://docs.python.org/3.12/library/copy.html) and [loop control](https://docs.python.org/3.12/tutorial/controlflow.html#else-clauses-on-loops).

Both assessors then examined all ten proposed feedback fields: two main explanations and eight choice explanations. Their complete records are [independent feedback assessment](evidence/artifact-author-feedback-assessment-20260908.json) and [root feedback assessment](evidence/artifact-author-root-feedback-assessment-20260908.json), joined to the [exact feedback packet](evidence/artifact-author-feedback-packet-20260908.json). Both main explanations and seven choice explanations were supported without reservation.

The remaining explanation attributes the `[[1, 2], [5]]` alternative partly to a shared-reference assumption about the second inner list, then calls that the opposite of what happens. This blurs two different relationships: sharing the original inner object and sharing an outer list slot. The original second inner object **is** shared immediately after the slice. The wrong `[5]` result would require replacement of the original outer slot to change the copy's slot too. Both assessors requested clarification; the independent record preserves the possibility of interpreting the wording charitably. This is a teaching-clarity concern, not a demonstrated wrong final value. No captured candidate was repaired.

Thus two of four planned proposals returned, two were structurally renderable, and two had uniquely warranted keys on manual inspection. Zero received a fresh native binding. Under the conservative feedback and difficulty criteria, neither returned proposal has an unqualified full content pass; treating the ambiguous wording as nonmaterial would leave one such candidate, without changing the missing native evidence or the failed four-question outcome.

## Implementation verification and next decision

The initial author/adapters milestone (`04fc960`) passed 42 focused tests, including controlled isolated browser smoke fixtures before author dispatch. The bounded browser-parent transport (`c41f52f`) subsequently passed nine fake-process tests, and observation-plan/lifecycle replay (`4331dc6`) passed 15 synthetic tests. These establish exact input/display/result joins, field limits, unique typed choices, stale-record rejection, cleanup requirements, and refusal to prepare a dispatch plan from an incomplete author capture. They are not 66 live correctness cases. No generated candidate was executed during these checks. Ruff, diff checks and independent read-only review passed for the final replay milestone.

The next evaluation should keep three questions separate: whether unchanged artifacts obtain a trustworthy native key; whether complete explanations accurately teach their mechanism; and whether authoring fits a usable latency budget. A separately frozen follow-up could observe the two saved artifacts without another author call, preserving this failed run and its four original slots. A future author comparison could test smaller request units, but the present timeout is insufficient evidence to claim that this will fix latency. Increasing output tokens is not supported as the next intervention by this run.

The remaining free-text solver contradiction path and all-pairs failure remain unresolved. This artifact mechanism is not integrated into production and does not replace the requirement to support arbitrary learning goals.
