# Full-path correctness audit protocol

Baseline: current main `7d9cc6a`; isolated branch `codex/question-correctness-audit-20260912`.
Preserve prior literal-content, exact-choice, complete-solver, response-contract,
shared-answer-vocabulary and explanation-heuristic fixes. The previous four-item
grammar smoke is evidence for its particular false-rejection repair only.

## Broad pass before choosing an intervention

1. Inspect request construction, source extraction/selection, author prompts,
   raw drafts, normalization, solver/reviewer correlation, teaching replacement,
   filters/retries, bank serialization, Swift decoding, display and grading.
2. Snapshot actual TestFlight application hashes and safe model settings. The
   September 12 read-only snapshot matches all 23 main application modules in
   API, worker and outbox. The API author is Nova Lite; worker author is Kimi
   K2.5. Both use Sonnet 4.6 for verification, disabled thinking and legacy JSON.
3. Run the frozen twelve-request matrix: three requests each for math,
   programming, language and factual knowledge; two questions per request;
   difficulty floors 1, 3, and 4/5; six sourced and six source-free requests.
   Source notes are synthetic summaries, not acquired authoritative documents.
   This starts at normalized explicit-topic requests, without inferred maps.
4. Read every actual prompt and response, including failed drafts and retries.
   Assess stems/choices independently before comparing keys and teaching where
   practical. Use Python/SQLite/calculations and primary references for checks.
   Review all rejected raw candidates as well as final output.
5. Add controlled boundary probes for source omissions, hidden prerequisites,
   equivalent choices, incorrect author keys, answer ordering, partial rejection,
   retries and transport. Distinguish synthetic verdict enforcement from live
   model competence. Rank hypotheses only after the broad pass.

The evaluator captures original and normalized requests, exact provider prompts
and final response text, parsing and sanitizer outputs, solver input/parsed
decisions, verification outputs, quality counters, retry requests, bank preparation
and JSON roundtrips. It never records reasoning blocks, credentials, headers or
raw error messages. All content is synthetic. No learner bank is modified.

The fresh broad pass has a hard ceiling of 72 provider calls (six per request,
at most two complete three-call passes), one job per request, and no fallback
model. A transport failure stops that case. Independent cases can continue.
An additional controlled diagnosis is capped at 16 calls; reserve at most 36
calls for matched intervention tests and fresh validation. Do not silently
expand these budgets. Report actual calls, failures and latency, not just limits.

## Competing explanations

- Author introduces wrong facts, keys, missing conditions or weak distractors.
- Necessary source/task information disappears before authoring or display.
- Normalization changes a literal, conflates choices, or miscorrelates keys.
- Verification supplies missing premises, accepts flawed reasoning, or rejects
  valid controls; shared model agreement is insufficient evidence.
- The final reviewer introduces unsupported teaching when replacing the draft.
- Length, scope, difficulty or other filters discard sound useful questions.
- Retrying, storing, transporting or shuffling changes a formerly sound item.
- Deployment differs from the audited implementation or model configuration.

For each observed defect record the earliest failing stage, exact input/output,
later amplification/miss/repair and corroboration in other cases. Count wrong or
ambiguous answers, unsupported teaching, distractor quality, target difficulty,
useful yield per requested slot and per provider call, latency and tokens.
Do not equate more rejection or higher model agreement with improvement.

## Intervention qualification

Choose simple general changes only after evidence ranks the hypotheses. Use
unchanged failing inputs plus valid controls to isolate the proposed mechanism,
then fresh cases across the matrix. Keep changes that improve useful output
without hiding correctness defects. Otherwise preserve the evidence and report
the unsuccessful intervention. Unit tests qualify implementation behavior, not
the models' semantic reliability. No deployment or model promotion is implied.
