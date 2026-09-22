# Correct-answer transport, grading, and highlighting investigation

Investigation baseline: `origin/main` at `7d9cc6ad93128893fb52f1a0183fea620b3b00ac`.

## Proven client defect

The Swift legacy path (`verificationVersion == 0`) inferred an answer from explanation prose and let that inference override the structured `expectedAnswer`. Its cue test was `contains("correct")`, `contains("best answer")`, or `contains("right answer")`, followed by finding exactly one choice of at least 12 characters anywhere in the explanation. It did not check negation, sentence ownership, or whether the explanation was discussing a distractor.

A deterministic reproduction uses a stack question:

- Key: `Remove the most recently added element`.
- Distractor: `Remove the earliest added element`.
- Explanation: `Remove the earliest added element is incorrect because a stack uses last-in-first-out ordering.`

Before the fix, the correct choice graded incorrect and the distractor graded correct. The same failure occurs with `is not correct`, an unrelated sentence mentioning the correct rule, and `It is false that … is correct`. The defect is application logic, not a model failing to understand this question.

Both `AnswerGrader.evaluateMultipleChoice` and `QuestionBatchSanitizer.sanitizedChoices` had this behavior. A further legacy sanitizer veto inferred contradictions from phrases describing signed values, which could confuse intermediate and final results. Backend commit `f199595` had already removed analogous backend vetoes, but did not change these Swift paths.

## End-to-end behavior

1. `GeneratedQuestionPayload` decodes `expectedAnswer`, `choices`, the explanation, keyed choice feedback, and verification metadata. `makeQuestion` preserves the answer text. There is no persisted correct-answer index.
2. `QuestionBatchSanitizer` resolves legacy answer labels before shuffling. Reviewed version 1 items keep their exact choice text and answer. Choices shuffle together as strings; keyed feedback stays bound to its choice text.
3. `CheckpointQuestion` persists the answer text and offered choices. `AnswerGrader` uses the same choice identity as the sanitizer. Case, punctuation, internal whitespace, and literal Unicode bytes are meaningful; cosmetic normalization must not collapse programming/math alternatives.
4. `CheckpointAttemptView.choiceState` marks a button correct by calling `AnswerGrader` for its actual choice text after submission. The correct state renders a teal background/check and VoiceOver value `Correct answer`. A chosen wrong option has a coral background/X. The UI therefore faithfully displayed the legacy grader's wrong result.
5. Noncorrect inline and terminal feedback displays a `Correct answer` reference resolved by that same grader. Correct submissions already show the chosen answer with the correct status, so no redundant reference answer is displayed.
6. Attempt snapshots persist the reference answer and feedback for history. Existing snapshots remain authoritative. This change does not rewrite recorded outcomes or historic snapshots.

No wrong-index or shuffle defect was found in the reviewed version 1 path. Fresh member practice requires current backend verification; nonmember/local questions and retained legacy content can still encounter the defective legacy path. This is a concrete client bug, not evidence that it accounts for every reported modern-generation quality issue.

## Fix

Remove explanation-based answer inference and prose contradiction vetoes from the Swift legacy path. Preserve exact structured answer keys and existing deterministic legacy label/contained-answer adapters. A malformed key cannot be repaired by prose. The reviewed version 1 contract remains unchanged.

This deliberately stops attempting to infer factual correctness locally. Semantics belong to backend full-choice review; the client's structural validation and grading must not silently replace the review/key with a substring heuristic. An incorrect structured key is still incorrect content and requires regeneration or reporting.

## Verification

On the iOS 26.4 `Checkpoint Question Integrity QA` simulator:

- Before the fix: the first seven tests in `AnswerHighlightingReliabilityTests` produced **33 assertion failures in three tests**. The reviewed-answer transport, history, and duplicate-choice tests already passed. Result bundle: `/tmp/checkpoint-answer-highlighting-current-before.xcresult`.
- After the fix: **138 tests passed, zero failures**: 9 answer-highlighting reliability tests, 52 question-validation tests, 29 backend wire-contract tests, 29 practice-history presentation tests, and 19 checkpoint-attempt rendering tests. Result bundle: `/tmp/checkpoint-answer-highlighting-after.xcresult`.
- After strengthening the permutation test to force each persisted/displayed order, its focused suite passed again: **9 tests, zero failures**. Result bundle: `/tmp/checkpoint-answer-highlighting-permutations.xcresult`.
- The new reliability suite covers negation, unrelated correctness language, counterfactual distractor explanations, malformed keys, legacy labels, all 24 persisted choice orders for four answer types, feedback identity, question/attempt persistence, reference-answer presentation, and visible duplicate rejection. Reviewed cases include numeric answer text, case-sensitive literals, and arithmetic operators.
- `git diff --check` passed. No migration or stored-history rewrite was performed.

The focused verification command is:

```sh
xcodebuild test -project Checkpoint.xcodeproj -scheme Checkpoint \
  -destination 'platform=iOS Simulator,name=Checkpoint Question Integrity QA' \
  -derivedDataPath /tmp/checkpoint-answer-highlighting-current-derived \
  -only-testing:CheckpointTests/AnswerHighlightingReliabilityTests \
  -only-testing:CheckpointTests/QuestionValidationTests \
  -only-testing:CheckpointTests/PracticeHistoryReviewPresentationTests \
  -only-testing:CheckpointTests/CheckpointAttemptRenderingTests \
  -only-testing:CheckpointTests/BackendQuestionEngineContractTests \
  CODE_SIGNING_ALLOWED=NO
```

The tests establish structural identity and deterministic grading/highlighting. They do not establish that arbitrary generated distractors are semantically distinct or that the model's structured key is factually correct; those are separate backend experiments.
