# TestFlight deployment refresh — September 26, 2026

Read-only AWS checks at approximately 20:24 UTC used the current login in account `239342516379`, region `us-east-1`. No function was invoked, package downloaded, configuration changed, or deployment attempted.

| Observed identity | Selected result |
| --- | --- |
| CloudFormation stack | `checkpoint-question-service-testflight`, `UPDATE_COMPLETE`; last updated `2026-09-11T15:35:21.693000+00:00` |
| API Lambda | `checkpoint-question-servi-CheckpointQuestionFuncti-GwrpPtUv4A7u`; Python 3.12, 30-second timeout, last modified September 11; package SHA-256 (base64) `YaJGqVgADEWGbtv6j1b96SYBmt8pAkcWaiYzgngMW/Y=` |
| Worker Lambda | `checkpoint-question-servi-QuestionBankWorkerFuncti-EIEsbeyLC1WU`; Python 3.12, 240-second timeout, last modified September 11; package SHA-256 (base64) `Hh0yKkR0RJy9t5K78eZTk6e05diWNWPV86fJSve7Hyo=` |
| Selected runtime modes | Both functions report `BEDROCK_STRUCTURED_OUTPUT_MODE=legacy`. Author mode, cardinality and feedback overrides are absent from the selected environment values. The worker read-timeout value is `75` seconds. |

These selected values and package hashes match the [September 22 read-only review](../compiled-proof-rollout-review-20260922/ROLLOUT_REVIEW.md). The verified source improvements on main are therefore not installed in this TestFlight stack. This refresh did not download the packages or compare every deployed module; it establishes the selected configuration and unchanged package identities only. The native, count-bound and immutable-main worker routes remain unqualified for deployment.
