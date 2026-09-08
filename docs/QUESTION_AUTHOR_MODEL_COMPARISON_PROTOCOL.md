# Author-model comparison — September 8, 2026

## Question and isolated change

Can replacing Kimi K2.5 with Opus 4.6 improve complete, useful questions under the current authored-solution contract? The [previous fresh trial](QUESTION_AUTHORED_SOLUTION_FRESH_RESULTS.md) exposed wrong authored keys, long explanations and weak distractors. The [earlier reasoning comparison](QUESTION_REASONING_RECHECK.md) changed checking, not authorship. Previous Opus author trials used different contracts, thinking settings and deadlines; none establishes how this exact substitution behaves.

This prospective comparison changes **only the author model**. Each arm authors fresh questions. Neither receives prior candidates, known errors or the other arm's outputs. Sonnet 4.6 remains the complete-choice solver and immutable teaching auditor for both. No additional review stage, prompt rewrite, longer content allowance or deployment is introduced.

## Frozen inputs and execution

Reuse the exact three payloads from [the existing fixture](evidence/authored-solution-fresh-fixture-20260908.json), byte SHA256 `6fe797f70ab10c8d6418743c213337b406d15448f75ffb4bebe0abdb2fb2693d`: houseplant propagation, English articles and contour interpretation. Both arms request two questions per goal at minimum difficulty 3, for **12 candidate slots**. These goals have been examined before; the questions will be new, but the domains are not a new holdout.

The fixed author IDs are `moonshotai.kimi-k2.5` and `us.anthropic.claude-opus-4-6-v1`. All calls use disabled thinking, 6,000 output tokens and temperature 0.2. Retain the exact current author/solver/audit prompts, source text, 320-character stem/author-main instructions, 140-character choices and 420-character runtime main limit. Opus access was confirmed with a read-only AWS availability check; no agreement was accepted or account setting changed.

Interleave six operations: Kimi then Opus for plants, Opus then Kimi for English, and Kimi then Opus for contours. Each has one generation attempt, at most three calls and a separate 240-second window, with read75/connect3 and one SDK attempt. The whole run permits **18 calls maximum**, 32 KiB per serialized request and 576 KiB total. Existing author JSON repair consumes the same allowance and prevents an unrepaired success. There is no added repair capacity, fallback, retry, replacement or resume. A provider, lifecycle, binding or persistence failure stops all later operations; ordinary content rejection is recorded separately.

Reuse the current runtime evaluator and isolated observer. Freeze committed source/dependency hashes, fixture origin, normalized requests, operation settings and initial author requests before dispatch. Paired initial requests must be identical except for `modelId`. Persist every dynamic request and exact final output, usage/unknowns, stop reason, decision and cleanup observation. Replaying the terminal capture must require no provider call and reproduce the recorded behavior exactly.

## Assessment and decision

Assess all raw candidates, including rejected and malformed content. Use opaque candidate IDs and conceal author arm, key, explanation, model difficulty and pipeline verdict while independently solving stems and judging each choice. Freeze those judgments before assessing the exact authored main. Keep arm mappings separate until content judgments are saved. Record whether masking or a procedural disclosure could have influenced an assessment.

Score warranted unique keys, complete premises, three distinct plausible distractors, substantive goal fit, actual difficulty and complete supported teaching separately from structural compliance and runtime yield. Report exact length violations and preserve the distinction between the 320-character author instruction and 420-character admission limit. A correct key with a false explanation fails. A length rejection does not earn semantic-detection credit. Do not call an unsupported claim proved false merely because the supplied summary omits it.

A fully favorable challenger result requires all six requested Opus items to be returned in their first unrepaired passes, meet the displayed-content constraints and author instruction, have supported unique keys and complete teaching, and independently meet difficulty 3 with plausible distractors. Retain partial improvements and disagreements as observations, without weakening this criterion. The fresh Kimi arm provides a descriptive same-goal comparison; three goal pairs do not establish a statistically reliable general effect.

Even a favorable result would justify broader qualification, not automatic default promotion or deployment. Failure means this substitution did not meet this bounded criterion; no repeated sampling until it passes. Existing app behavior and bank provenance remain unchanged.

## Research informing the decision

[Anthropic's Sonnet 4.6 announcement](https://www.anthropic.com/news/claude-sonnet-4-6) identifies Opus 4.6 as its stronger option for demanding reasoning at that release. This is a reason to test an already available author, not evidence that it will produce correct MCQs here.

[Lee et al. (ACL 2025)](https://aclanthology.org/2025.acl-long.1154/) evaluate plausible distractors using student-choice prediction and a trained ranker/generator on computer-science subjects. Their results support evaluating what makes an incorrect option tempting, rather than counting distinct strings or trusting a difficulty label. This experiment does not reproduce their training or learner study, and their metrics do not qualify Checkpoint.
