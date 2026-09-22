# Client answer highlighting review

No reproducible explicit-key loss or incorrect key-based highlight was found for admitted valid payloads. This was a read-only audit of source `c38f19a`; reporting checkout `3472f5f` has only evidence changes. The accompanying JSON pins23 inspected/executed boundary files and confirms no app, test or backend source difference between those commits.

The bank client decodes with `QuestionContentJSONDecoder` and copies the explicit key into the question (`BackendQuestionBankClient.swift:188`, `BackendPayloads.swift:489–528`). Verified admission requires four unique choices and key membership, then shuffles the choice array while retaining the key and reviewed teaching (`QuestionBatchSanitizer.swift:48–89`). Cache serialization preserves these fields; metadata canonicalization changes only topic/skill/objective metadata.

`AnswerGrader.swift:164` grades the offered explicit key without inferring from explanation prose. After submission, `CheckpointAttemptView.swift:2371` uses that result for each choice; its correct state produces a checkmark, teal styling and “Correct answer” accessibility value. Noncorrect results also display the reference answer. Empty choice feedback returns the unchanged main explanation (`QuestionModels.swift:193`), which inline/terminal feedback and persisted attempt reviews use. Saved history honors its review snapshot.

Verification completed without new tests or source edits:

| Executed checks | Result |
|---|---|
| Initial focused simulator invocation |19passed,0failed,0skipped|
| Corrected feedback-test selectors, same build |2passed,0failed,0skipped|
| Python compiler → bank write → claim/idempotent replay |2passed,0failed|

The initial command mistakenly named two methods under `QuestionValidationTests`; they belong to `ReviewedFeedbackPreservationTests` and were not selected. A `test-without-building` invocation ran those two methods afterward. The total is21distinct iOS tests, not23. Exact commands, selected test names, complete `xcresulttool` summaries and log hashes are retained in `CLIENT_HIGHLIGHTING_REVIEW.json`.

The selected highlighting tests cover96verified display orders (four fixtures ×24),72compiled display orders (three ×24), actual random admission shuffling, exact teaching persistence, legacy explanation/key conflicts, Unicode collisions, cache reuse and persisted reviews. The feedback test explicitly admits maps of sizes0,1,4 without backfill.

These are XCTest model/presentation checks and fake-Dynamo/queue storage tests. They do not constitute a real HTTP-bank-to-tapped-UI run, screenshot/color measurement, VoiceOver interaction or live provider qualification. UI state/color/accessibility wiring was inspected in source. No separate policy7 empty-feedback UI automation was run; existing tests and code cover its constituent transformations. Synthetic trusted compiler carrier metadata is not a provenance-approval test.

The client floor remains2. Unverified/stale inventory is excluded, but previously accepted policy2+ questions can retain semantic mistakes in a stored key or explanation. Highlighting cannot determine a different true answer; this is the existing semantic/freshness limitation, not a newly introduced client regression. No inventory/history changes, policy bump, deployment or provider calls were performed.
