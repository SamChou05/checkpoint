# Question generation: two reproduced rejection bugs

The pipeline does discard good questions for reasons unrelated to their
correctness. This audit fixes two concrete bugs by removing faulty shortcuts.
It does not introduce another prompt variant, reviewer, model, or quality gate.

The search covered current author/provider orchestration, sanitization, solver
and reviewer inputs and correlation, bank storage, iOS decoding/shuffling/grading,
historical experiments, open PR #7, and the actual deployed API/worker packages.
The isolated baseline was `d0a96dd`; unrelated edits in the main checkout were
left untouched.

## 1. Answer vocabulary was incorrectly treated as question identity

Both the backend and iOS rejected a new question if its four choices matched
another question's choices, irrespective of its stem or correct answer. They
also rejected a repeated answer within a topic when the answer had at least
16 characters. These checks applied within a batch and against history.

For example, identifying `fox` and identifying `runs` in “The fox runs” test
different words and have different correct answers. Both legitimately offer
`noun / verb / adjective / adverb`. The old backend keeps only the first.
Likewise, identifying rusting and burning as “A chemical change” legitimately
reuses a classification in different scenarios; the topic/answer veto drops
the second even with a different set of distractors.

This prevents valid, parallel alternatives from being reused, even if the
author is perfectly accurate. The fix removes those two cross-question vetoes
in [backend admission](../backend/bedrock-question-service/question_quality.py)
and [iOS admission](../Checkpoint/Services/QuestionBatchSanitizer.swift).
Duplicate choices **within** one question, missing keys, exact repeated stems,
blocked stem fingerprints, allocations, and difficulty checks still apply.
The existing solver and reviewer still check each candidate.

A three-call live diagnostic generated four new beginner grammar questions
using Kimi K2.5 plus Sonnet 4.6, disabled thinking, temperature 0.2, and the
existing 6,000-token ceiling. No prompt or model setting changed.

| Same four raw authored questions | Retained |
| --- | ---: |
| Original `d0a96dd` sanitizer, offline replay | 1/4 |
| Downloaded deployed sanitizer, isolated offline replay | 1/4 |
| Fixed sanitizer | 4/4 |
| Fixed complete pipeline after live solving and review | 4/4 |

The original sanitizer reports three `duplicate_choices` rejections. The four
keys are adjective (`quick`), adverb (`beautifully`), verb (`won`), and noun
(`cat`), supported by their respective sentences. The
[evidence](evidence/question-generation-bug-audit-20260911.json) preserves the
unchanged raw questions, final questions, model observations, and replay counts.
This is one selected beginner batch, not a production accuracy or advanced
distractor-quality estimate. Its final noun explanation overstates subject
position as the defining role of a noun; sound keys do not establish wholly
sound teaching. No new baseline model calls were used for the replay comparison.

## 2. Explanation fragments were mistaken for final-answer verdicts

The deterministic explanation filter rejects this correct item:

> Compute -(2 - 5). What is the sign of the final result?
> Key: positive.
> Explanation: The intermediate result is negative: 2 - 5 = -3. Negating -3 gives 3.

It takes “result is negative” as endorsement of the negative choice. Changing
the key to the *wrong* answer `negative` makes this particular prefilter pass;
the downstream solver must then catch the wrong key. The filter also searches
for `correct` inside `incorrect`, so a sentence explicitly refuting a long
distractor can be interpreted as endorsing it. A separate blanket match on
“provided choices” rejects otherwise correct unit-conversion teaching.

The fix removes these prose-fragment vetoes from generation. The deterministic
eval scorer used the same contradiction heuristic, so that failure criterion
was removed there too. Historical helper exports remain available for replay
compatibility and are explicitly marked unsuitable for admission/scoring.
Historical scores require their original source revision.

New tests preserve valid explanations in both feedback modes, require rejection
when the independent solver reports a different key, and require rejection of
unsupported authored teaching. Default review still writes its own explanation;
the opt-in authored-solution path still audits the author's complete explanation.
These tests establish enforcement of reported judgments, not model infallibility.

## Deployment and remaining correctness issue

Read-only AWS inspection on September 11 found both deployed functions last
updated at `2026-09-08T07:07:54Z`. All five inspected runtime modules match
`601d273`, including the policy-1 verifier. They do not match current main.
Recent complete-choice solving and subject-context fixes therefore are not
deployed behavior. Replaying the downloaded sanitizer confirms the answer-set
failure there too, using current shared dependencies; this was not a Lambda
invocation. The seven-day worker log query returned no matching `QuestionQuality`
events, so this audit does not estimate production incidence.

The [prior author examples](QUESTION_AUTHOR_EXAMPLES_RESULTS.md) independently
show wrong keys and inconsistent premises already present in raw model output.
The [solution-construction](QUESTION_SOLUTION_CONSTRUCTION_RESULTS.md) and
[reasoning](QUESTION_REASONING_RECHECK.md) trials also document remaining model
errors. This audit found no new verified-question shuffle/index bug: current
grading uses exact answer text, and tests preserve keys through decoding,
shuffling, persistence, and grading. Legacy unverified grading heuristics were
not changed.

The external search included the [distractor-generation survey](https://aclanthology.org/2024.emnlp-main.799/)
and [math distractor-generation study](https://aclanthology.org/2024.findings-naacl.193/).
They examine plausible incorrect alternatives and their assessment. They do not
establish these runtime bugs or qualify another intervention for this app; the
counterexamples and exact-output replay are the evidence for these changes.

Removing the shortcuts means cosmetic paraphrases and genuine explanation
contradictions depend on semantic assessment; shared answer vocabulary and
prose substring matches cannot establish those properties. The author's existing
history guidance and exact-stem controls remain. This patch fixes demonstrated
false rejections, not arbitrary-subject model reasoning.

## Verification

- Baseline: 1,042 backend tests passed.
- Answer-vocabulary milestone `18b0201`: 1,047 backend tests and 52 iOS question
  validation tests passed, including shared before/after fixtures and exact-key grading.
- Explanation milestone `f199595`: 1,050 backend tests, whole-service Ruff,
  Python compilation, and `git diff --check` passed. Its new counterexample tests
  failed against the previous code before passing with the fix.
- iOS integration follow-up: 122 additional tests passed across backend transport,
  asynchronous bank flow, refill, and checkpoint sessions, for 174 selected iOS
  tests with zero failures in total.
- Live diagnostic: one author call, one solver call, one reviewer call; all
  ended normally, using 5,315 input and 1,797 output tokens in total.

Both fixes are committed on `codex/question-generation-root-cause`. No backend
deployment, bank mutation, learner-data migration, or model promotion occurred.
