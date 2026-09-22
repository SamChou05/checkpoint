# Proposed final-content auditor comparison — not frozen or authorized

This experiment tests a read-only auditor after all learner prose has been written. It cannot repair a defect or emit replacement content. This proposal adds no production stage and authorizes no provider calls.

## Why it is a separate boundary

The current `reviewer_written` route checks the author's question with an independent solver, then the final reviewer writes the main explanation and all four choice explanations. The application checks their identity, lengths, types and display references; there is no subsequent semantic check of this newly generated learner prose (`question_verification.py`, lines 449–487).

The existing `authored_solution` route already audits an immutable authored main explanation and hides independent solver judgments from that audit. It returns the author's main explanation unchanged and an empty choice-feedback map (`question_verification.py`, lines 351–368 and 446–447; `question_teaching.py`). Contrary to an earlier working hypothesis, this route does not itself add new reviewer learner prose. Its narrower content contract cannot simply be relabeled as an audit of the five explanations produced by `reviewer_written`.

The proposed auditor receives the final prompt, four exact choices, displayed key, main explanation and four choice explanations together, plus task scope and supplied sources. It receives no solver/reviewer verdicts, rationales, case labels, provenance or gold. The displayed key is an untrusted claim to audit, not a request to choose or rewrite an answer. All accepted content is copied from the frozen input. Rejects and uncertainty cannot be rescued.

## Proposed transport and local contract

`FinalContentAuditContract(count)` accepts an actual integer from 1 through 40, excluding booleans. For count six, the root object contains only `audits`; that object requires exactly the six dense trusted string IDs `0` through `5`. Each required row contains exactly `reason` (string) followed by `verdict` (enum `accepted`, `rejected`, `uncertain`). Every object has `additionalProperties:false`. There are no arrays, model-authored indexes, answer fields, repairs or learner-content fields. The schema name is `final_content_audit_v1_n6`.

The native schema supplies the closed identity/field shape. Strict local validation additionally rejects duplicate JSON keys, trailing material, non-string or empty/whitespace-only reasons, reasons exceeding 600 codepoints, missing/unknown identities or fields, wrong types and unknown verdicts. It neither normalizes nor shortens text. The entire batch fails on a malformed response. The native output is required to finish with `end_turn`; truncation does not receive partial credit. Any future application filter can release only original accepted payloads, with exact canonical content hashes unchanged; no output field can replace content.

The proposed short system prompt is in `auditor-prompt.txt`. It audits supplied factual claims; it does not ask the model to write a worked solution or four feedback strings. Prompt/schema remain subject to parent review before freezing.

## Four-call comparison proposed by parent

The answer agent is preparing twelve full-response controls as six sound/defective pairs: three familiar diagnostic families (paint ratio, bus threshold, weighted grade) and three families never dispatched in the previous stopped trial (parallel timing, observational causality, signed-square). These are intentionally related diagnostic controls, not twelve independent unseen production samples. Historical defective strings remain exact where available; all repairs and evaluator-authored material have explicit hidden provenance. Gold is independently reviewed before freezing.

Each arm sees the same twelve payloads in two identical six-item batches. Proposed call order is batch 0 disabled, batch 0 adaptive, batch 1 adaptive, batch 1 disabled. The only configuration contrast is Sonnet 4.6 reasoning mode with its necessary compatible sampling/output budget: disabled uses temperature 0.2 and 6,000 maximum output tokens; adaptive uses high effort, no temperature and 16,000 shared output/reasoning tokens. This is a configuration comparison, not an isolated causal estimate of thinking alone. System text, serialized schema, content, ordering and gold remain identical across arms.

Both configurations use `us.anthropic.claude-sonnet-4-6`, Converse native `outputConfig.textFormat`, region us-east-1, read timeout 75 seconds, connect timeout 3 seconds and SDK total attempts 1. Maximum four dispatches; no retries, warm-ups, replacement calls or alternative arms. Stop the entire trial after the first provider failure, non-`end_turn` response or strict structural failure. Preserve failed and unattempted denominators. Semantic failure alone does not stop the planned comparison. Retain original response for validation, but omit provider reasoning text/signatures from saved evidence and record only their block count.

Qualification is prospective and separate per arm: both planned batches must be structurally valid within bounds; all six sound payloads must be accepted; all six defective payloads must be rejected; uncertainty counts as failure. All twelve reasons are independently checked for factual accuracy and correspondence to the exact payload. A correct verdict with a false reason fails full-content qualification. Every accepted payload must remain exactly unchanged. Report all twelve disposition results, sound retention, defective rejection, reason fidelity, timings, input/output tokens, timeout/truncation status and failures without relabeling after output.

## Integration and claim limits

Passing these controls would justify a separate fresh end-to-end qualification, not a universal correctness claim or deployment. A new final call would make the existing author → solver → feedback-writer route a four-stage pass. With the current six-call worker ceiling, two complete passes would no longer fit; a second pass must not start after the first four calls. The 240-second job deadline and 75-second per-call cap further constrain useful yield. These costs require explicit runtime budget logic and fresh worker measurements before any promotion. This proposal does not remove the solver, merge the writer with the auditor, increase the call budget, change defaults or bypass earlier rejections.
