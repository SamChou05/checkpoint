# Immutable authored-feedback audit: first-request timeout

The qualification failed before any model output was returned. The first six-item audit request raised `ReadTimeoutError` after **75.167173 seconds**. The frozen stop rule ended the trial; the other three planned calls were not attempted. There was no retry, repair, additional provider call, or question-bank write.

| Measure | Frozen denominator | Observed result |
|---|---:|---:|
| Calls | 4 | 1 attempted, 1 failed, 3 unattempted |
| Structurally valid calls | 4 | 0 |
| Learner admission decisions | 24 | 0 returned; 6 in failed batch, 18 unattempted |
| Task labels / answer choices | 24 each | 0 returned |
| Feedback labels | 120 | 0 returned |
| Difficulty values | 24 | 0 returned |
| Visible task/feedback reasons | 144 | 0 returned; 36 in failed batch, 108 unattempted |
| Selected original learner payloads | 12 sound expected | 0 selected; content-identity selection was not exercised |

The error contains no AWS error code, message, HTTP status or request ID. Usage is unavailable, **not zero**. No `raw` model JSON, native assessment, local assessment or reasoning block was received. Therefore there are no reasons or semantic decisions to audit, and neither semantic correctness nor a semantic defect can be inferred from the missing outputs. The read timeout alone does not establish the underlying provider or transport cause.

This was an **audit-only known-control test**. It sent the actual runtime `FULL_FEEDBACK_AUDIT_SYSTEM_PROMPT`, including its rubric, with `AuthoredFeedbackReviewContract(6)` / `experimental_authored_feedback_audit_v2_n6`. The 1,182-character shared schema had SHA-256 `a61fad5fd95ee8829c390e93f7aee534babae6a6ea1e66afb71ebdcbd90089d0`. Settings were Sonnet 4.6, adaptive thinking, high effort, 16,000 shared tokens, no temperature, connect 3 seconds, read 75 seconds, and SDK total maximum attempts 1. This trial invoked neither author nor solver nor the complete worker pipeline.

The first request contained the original familiar weighted-grade, paint and bus sound/defective controls in their original six-item order. All four planned inputs preserve their exact historical scope, stems, choice order, main feedback and four choice feedback strings. Explicit keys, difficulty, gold and earlier judgments are omitted from the model input. Authored feedback can still reveal the intended answer. All 24 original cases and their 12 accept/12 reject gold remain unchanged; the two nuanced field expectations remain diagnostic, untested annotations.

Frozen plan: `8c0eaaeec121b11ea9ba6aaf6bc8acbca1d47ac441d7d42845dc8e7b441b7b09`.
Frozen capture: `ea422ad2447e2fab468af1457a2c043dbb0df71350bdbc3d24e0e90363fe857b`.

`replay.py` blocks network connections, SDK creation and credential fetching. It checks the frozen plan and runtime/evidence/harness bindings, then uses one fake callback to reproduce the exact request, error envelope, hard stop and complete denominator accounting. Only the replay completion timestamp differs. `replay-summary.json` and `independent-output-audit.json` preserve the missing-output limitation explicitly.

`runtime-source.patch` and `runtime-reconstruction.json` preserve the 26 Python execution modules pinned by this trial. Reconstruction from base commit `bfaa34edb30070eecaa6e3d923f60e50b487224a` was independently checked in a new temporary directory: the zero-context patch applied cleanly with `git apply --unidiff-zero`, and all 26 resulting module hashes matched. The patch was generated with `git diff --binary --unified=0`, including new files, and must be applied with `git apply --unidiff-zero`. It covers nine changed/new Python modules; it does not claim to preserve every unpinned deployment, test or documentation change in the unfinished architecture proposal.

The 18 fake-client harness tests and Ruff checks pass. They verify source and input bindings, strict stops, native versus local failures, exact selection under handcrafted expected labels, safe errors, reason omission and deadline boundaries. These checks establish harness behavior, not model success. The frozen plan, source and capture were not edited during the replay or report.

The primary qualification remains failed: **0/4 structurally valid calls and 0/24 assessed admission decisions**. No worker, semantic, latency or release qualification follows. The capture is final and cannot be resumed. Any change in batch size, thinking, output budget, prompt or transport requires a separate prospectively reviewed plan; the current failure and every earlier trial retain their original results and criteria.
