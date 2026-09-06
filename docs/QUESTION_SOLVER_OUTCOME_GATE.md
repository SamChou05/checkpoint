# Enforcing the independent solver's outcome

Commit `de82f43` makes the stem-only solver's declared outcome an application-enforced condition for continuing to answer-choice review. Previously, the code checked `assumptionsRequired` but treated the solver's `answer` and `limitations` as advisory prose. A final reviewer could accept a positive answer after the solver had identified a decisive obstacle. The change adds no solver or reviewer call; it strengthens the existing two-stage contract.

The [pre-fix replay archive](evidence/solver-outcome-pre-fix-20260906.json) preserves the exact existing evidence and offline callback reproductions. Its SHA256 is `69784fc31d69613b993e6e81b71016fdd830907baa07c3a58375aa62e2482d62`, identical to the original `/tmp/checkpoint-solver-contract-audit-20260906.json`. Replay used the committed verifier at `8bd099047967b2438757dca3c2dc837c1d726025`, whose file SHA256 is `fab717a0a07a163f762841a4df44a8e18c0652f43416645097e16145b5e43f2f`; concurrent implementation edits were excluded. No model was called for this replay.

All eight historical acceptances reproduced, including four invalid and four valid case-arm observations. Two records in the [earlier evidence experiment](evidence/evidence-review-feasibility-20260906.json) demonstrate the gap particularly clearly:

- `results[4]`, `all_pairs_output_bound`: the solver gives an input with a quadratic number of matching index pairs and explains that enumerating them can exceed O(n). It nevertheless leaves `assumptionsRequired` empty. The final reviewer accepts an O(n) hash-map answer by excluding output enumeration from the promised total work.
- `results[1]`, `raw_highlight_recovery_unsupported_sequence`: the solver notes that fully clipped data cannot be restored and that nondestructive edit order is flexible. With empty required assumptions, the final reviewer accepts by reinterpreting the question's claimed maximizing sequence as a reasonable strategy.

These real solver summaries contain mixed recommendations and decisive caveats; they did not emit an explicit invalid outcome under the old schema. A separate fixed mock made the impossibility explicit in the answer and limitations while retaining empty assumptions. The exact archived accepting reviewer still passed the item. Changing only the required-assumptions list prevented the reviewer from being called. These mock observations establish control flow, not new measurements of model accuracy.

The new solver response requires one of five exact `outcome` values:

| Outcome | Enforced behavior |
| --- | --- |
| `resolved` | Continue to review only when no extra factual assumptions are required. Ordinary answers such as a count of zero or identification of a false statement remain possible. |
| `no_solution` | The authored key must be exactly `No solution exists under the stated conditions.` and that exact choice must occur once. |
| `underdetermined` | The authored key must be exactly `Cannot be determined from the information given.` and that exact choice must occur once. |
| `inconsistent_premises` | The authored key must be exactly `The stated premises are inconsistent.` and that exact choice must occur once. |
| `uncertain` | Abstain before review, including when a cannot-determine option is offered. The solver's uncertainty is not proof that the premises leave the answer undetermined. |

Required factual assumptions still block all otherwise eligible outcomes. The solver is instructed to list assumptions needed by its reported conclusion, rather than additional facts that would turn a proved negative conclusion into a positive result. Missing, unknown, or malformed outcomes have no default and fail closed as `invalid_solution`. They are not counted as successfully identifying a factual defect. An uncertain outcome records `solver_uncertain`; evaluation distinguishes abstention from a content rejection.

For the three exceptional outcomes, free solver prose cannot authorize a different key. Code also rejects a separately offered exact copy of the solver's answer when that would compete with the canonical negative choice. The author prompt now supplies the application-owned negative strings. The final reviewer can reject an eligible negative-answer question, but cannot replace the required negative key with a positive method or value. Existing index validation and reindexing preserve the association between each surviving question and its solution.

The earlier hidden-marble unit fixture supplies an important distinction: both red and blue satisfy its premises, so a cannot-determine answer is justified. Its exact older choice, `Cannot be determined`, is outside the new canonical wording. This is an unsupported representation under the new contract, not evidence that the answer is factually wrong. Other paraphrases and localized negative answers have the same limitation. They are not automatically rewritten or treated as equivalent. The new fixed tests separately exercise canonical valid negative answers, uncertain answers, missing assumptions, invalid outcomes, contradictory records, and mixed batches.

This gate binds review to the solver's declared outcome; it does not independently prove that declaration. A solver can still incorrectly return `resolved`, including when its prose contains a contradiction. Semantic uniqueness, synonyms among distractors, explanation correctness, choice feedback, and difficulty still require review. Exact text checks do not establish these properties. Historical Python samples contain no generated exception-answer MCQ, so those samples do not establish retention of legitimate error-answer questions.

Validation for `de82f43`: the backend suite reported `Ran 450 tests` and `OK (skipped=1)`. The existing client wire contract and `verificationVersion: 1` remain unchanged. No historical question-bank re-verification or deployment occurred in this milestone. Already stored questions are not retroactively certified by the new gate.

## Live diagnostic: the enforcement fix is insufficient for correctness

The [live smoke archive](evidence/solver-outcome-smoke-20260906.json) preserves the frozen plan, exact requests and final response text, usage, runner source, and adjudication. The final plan hash is `05cf7081bfcb179885494bcfadab2d26ee7f2dccbcba196a090de7bbd194bf6d`. The source was isolated at `de82f43`; the model was the already enabled `us.anthropic.claude-opus-4-6-v1`, with adaptive thinking, high effort, and 16,000 output tokens per call. No agreement was activated. The earlier zero-dispatch plan is retained with its local preflight corrections described in the archive.

All eight calls completed normally with no retries, using 8,771 input and 5,280 output tokens in total. Every response reported a reasoning block; only its presence was recorded. The largest output used 1,312 tokens, so truncation did not cause these failures.

| Case | Solver outcome | Runtime result | Independent assessment |
| --- | --- | --- | --- |
| Original all-pairs question | `resolved` | Accepted | Still defective: an allowed interpretation requires quadratic output, but both calls repeat a linear-time matching procedure without qualification. |
| Explicit all-index-pairs question with canonical negative answer | `no_solution` | Accepted | Correct key and main explanation: quadratic output rules out the promised linear total work. Sorting-choice feedback needs a comparison-sorting qualification. |
| RAW recovery sequence | `resolved` | Accepted | Still defective: the facts do not establish recoverable sensor data or a uniquely optimal order, yet both calls assert a required sequence. |
| Mira conditional inference | `resolved` | Accepted | Correct key, main explanation, and all four choice explanations. |

Neither invalid item was rejected. Both valid keys were retained, but that does not certify every explanatory assertion: the negative control's sorting feedback gives an unqualified O(n log n) cost without specifying comparison sorting. Its quadratic-output argument remains sound and sufficient.

No pre-review veto occurred in this live run. The regression tests establish that an explicit exceptional outcome cannot be overridden by an approving reviewer; the live run exercised ordinary `resolved` and eligible `no_solution` paths only. In the two failures, the solver omitted the earlier decisive caveats and incorrectly declared `resolved`, with empty assumptions and limitations. This is a model reasoning failure outside the new gate's guarantee.

These are selected historical stress cases plus a synthetic counterpart, not a fresh holdout or a production error-rate estimate. The counterpart changes the stem and choices; its success cannot isolate the effect of additional context. This run did not test authoring, bank filling, external evidence, adaptive learning, deployment, or existing inventory. It supplies no reason to promote the system as reliably correct or to increase the output cap. Further work must address incorrect solver conclusions and independently check feedback where possible.

The separate paired-model plan frozen at revision `1377b28` uses the prior contract; historical results or a future execution of that unchanged plan cannot validate the new outcome gate.
