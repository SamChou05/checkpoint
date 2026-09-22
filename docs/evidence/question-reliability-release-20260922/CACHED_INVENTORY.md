# Cached question inventory safety

The iOS selector and generation requests now require current verification for both members and Starter users. Cached wire-version-zero questions and stale policy revisions remain stored, but cannot enter new practice after launch, membership downgrade, or refill. This milestone keeps the current required policy revision at **2**, so verified wire-version-one/policy-two questions from the deployed worker remain eligible.

An earlier sanitizer could already have rewritten a legacy stored key from explanation prose. Such a key cannot be repaired reliably after the fact. The remediation excludes obsolete inventory from new practice instead of guessing a replacement answer or changing historic results.

For an unused Starter allowance, obsolete inventory triggers a verified replacement request. Replacement appends usable questions without deleting or retiring the quarantined questions. Canonicalization skips those obsolete rows, preserving their stored key and metadata across replacement and relaunch. Existing attempt records and historical snapshots retain their content. Stored attempts, `timesAsked`, and retired inventory still determine Starter consumption; quarantine cannot reset that allowance. An active, unfinished Starter run blocks replacement and explicit retry while it remains active.

Ten new `CachedQuestionSafetyTests` cover persisted legacy/stale inventory, membership downgrade, historical snapshot/key preservation, fresh verified replacement and relaunch, rejection of unverified replacement output, durable claim policy requirements, consumed local-template history, retired consumption without retained attempts, exhausted allowance plus explicit retry, and an active unfinished run. The existing local-template launch test now checks preservation during replacement. The dashboard readiness fixture now explicitly supplies verified multiple-choice questions, as production readiness requires.

Verification:

- Final focused run: **80 tests, 0 failures** across cached safety (10), goal creation (25), durable bank flows (22), skill-map migration (16), and verification freshness (7). Result bundle: `/tmp/checkpoint-cache-safety-focused-final.xcresult`.
- A first full run exposed one stale dashboard readiness fixture; after correcting that fixture, its focused rendering test passed. Result bundle: `/tmp/checkpoint-cache-safety-rendering.xcresult`.
- Final full simulator run: **1,054 total tests; 1,051 passed, 3 skipped, 0 failures**, with `xcodebuild` exit 0. Result bundle: `/tmp/checkpoint-cache-safety-full-final.xcresult`; log: `/tmp/checkpoint-cache-safety-full-final.log`.
- The three skips are the existing opt-in native interaction walkthrough and two App Group file-container tests in this unsigned simulator environment. No new test skips were introduced by this milestone.

The full run used the Checkpoint scheme, iPhone 17 Pro simulator on iOS 26.4.1, parallel testing disabled, and `CODE_SIGNING_ALLOWED=NO`. This validates client selection, persistence, refill, and allowance behavior; it does not qualify model semantic quality or retroactively correct historical answers.
