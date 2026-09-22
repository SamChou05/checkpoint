# Opus4.6 final auditor: 17/18, not qualified

The modelId-only final-auditor qualification failed the unchanged semantic requirement. All three native requests completed within bounds, all eighteen reasons respected the 600-character limit, and every response had valid closed identities. Opus4.6 accepted all nine sound payloads and rejected eight of nine defective payloads. It falsely accepted the same ambiguous semicolon question that defeated Sonnet and endorsed the faulty punctuation feedback.

Plan SHA: `f6b10c447e3f67cee9c3d2786ab5f1bdeecdaa22d1ac03ee7a3a70c218ae9d5b`. Capture SHA: `750a7e8a890d98fd82f8d20bfad4e136a33fb2bcd0bf547953ca728eba87d8bc`. Every request is identical to its preceding Sonnet adaptive-only counterpart except modelId, now `us.anthropic.claude-opus-4-6-v1`. Adaptive high, no temperature, 16000 shared tokens, native count-six schema, prompt, controls, gold, ordering and all thresholds are unchanged. All cases are reused diagnostics. Earlier failed trials remain failed.

## Persistent semantic error

The failed reason calls the alternative with comma-however-semicolon a “misplaced semicolon” and says each choice explanation accurately identifies its error. But the unqualified stem does not specify that however must begin the second clause. Bruce Aune's R2 explicitly permits a conjunctive adverb to attach to the first clause, set off by a comma, with the semicolon separating the two independent clauses. Thus at least two offered constructions are defensible, and the feedback's mandatory-placement rule is false. The sound paired stem explicitly requests the second-clause placement and was correctly accepted. [Primary grammar source, printed page5](https://cse.buffalo.edu/~rapaport/Papers/Papers.by.Others/aune01-punctuation.pdf).

The incorrect acceptance preserves the original bad payload exactly. This is a factual judging failure, distinct from the earlier response-shape failures. Native schema and trusted identity mapping prevent missing/duplicate rows and content substitution; they cannot turn a common learned heuristic into a universally true rule.

The other seventeen dispositions matched gold, including duplicate wrong answers versus distinct wrong answers, and a required written representation versus an unrestricted equal-value question. Independent audit of all eighteen reasons confirmed the false semicolon rationale and a separate unsupported provenance claim: the defective decimal explanations were described as “evidently copied” from the sound counterpart, although identical text does not establish copying direction. Fifteen reasons had no recorded accuracy or grounding issue; one more had only the minor terminology error of calling all four choice explanations distractor explanations. The remaining two had the material punctuation error and unsupported provenance claim. All ten selected payloads, including the bad semicolon question, retained exact original hashes. The audit verified modelId-only request isolation and all native/local checks. Its SHA is `92bf5623fca065871f58d4d447721895728883adf5af32aaadae926ca29ceb97`. Several reasons refer to paired counterparts, limiting inference beyond the diagnostic setup.

## Operational result and limits

| Batch | Time | Input tokens | Output tokens |
|---|---:|---:|---:|
| Familiar numerical/threshold pairs | 50.624s | 2,957 | 3,281 |
| Parallel/causal/square pairs | 25.175s | 2,683 | 1,710 |
| Grammar/duplicate/representation pairs | 33.715s | 2,601 | 1,901 |

Total time was 109.514s, with 8,241 input and 6,892 output tokens (15,133 total). All usage was known. All eighteen rows returned reason before verdict; the maximum reason length was 498 characters. There were no retries, timeouts, truncations, failed envelopes or unattempted calls. Three provider reasoning blocks were stripped from evidence; their text/signatures were never saved. No warmup, replacement or extra inference call was made.

Read-only preflight confirmed the Opus4.6 profile active and agreement/authorization/entitlement/region available; no activation or subscription was performed. Opus5 was not dispatched: official documentation listed native structured outputs unsupported and account preflight reported its agreement unavailable. Production native admission still allows Kimi/Sonnet only; no model allowlist or production default was changed by this trial.

Twenty combined offline test groups covered the original contract and bounded harness plus both wrappers. Exact no-network replay verifies the pinned sources, earlier captures, unchanged requests, strict response validation and original-payload admission. A single repeated diagnostic run supplies neither a broad accuracy rate nor a contemporaneous randomized model-effect estimate. This failed final-stage qualification does not justify global adaptive thinking or a fourth production call. Preserve the evidence and do not promote the candidate from partial success.
