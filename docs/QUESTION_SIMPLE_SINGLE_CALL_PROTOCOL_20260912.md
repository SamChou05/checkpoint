# One-call, direct-prompt trial

Requested simplification: one model call creates each two-question batch, using a
short direct prompt. The candidate provides a question, four choices, exact key,
and one worked explanation. It has no solver, rewriting reviewer, repair or
replacement call. It is an evaluation prototype, never marked policy-8 verified.
No deployment, bank writes or client changes are part of this trial.

The earlier September 6 short-author-prompt trial was faster but did not improve
quality. This experiment tests a simpler complete path with the current Nova and
Kimi authors and preserved reference facts. It does not claim that prompt length
alone is the independent variable.

Freeze **12 calls maximum**, two requested questions per call:

- Eight calls repeat the exact four final-audit requests with both author models.
  Historical baseline: 22 calls, 16 drafts/slots, five correct-key returns, three
  with supported full feedback. Compare key/main-explanation quality on both arms;
  the candidate omits per-choice teaching and must not win by quietly dropping
  those fields from an otherwise identical quality score. Compare raw author
  quality separately from full-pipeline returns. This uses saved baseline calls,
  not a randomized concurrent A/B or a causal model-ranking experiment.
- Four calls use new requests: price changes, Python dictionaries, English modal
  deductions, and a fictional reserve handbook. Kimi is selected now for these
  fresh requests because it is the worker author, independent of trial results.

Keep model, thinking, output allowance and temperature unchanged. Legacy transport
supports both authors. One actual call per job, including failures; no retries.
Keep original case facts, difficulty guidance and mapped IDs. Current deterministic
admission is measured separately from semantic content and gives no verification
stamp. Assess exact raw outputs even when they fail admission. Independently check
keys, missing premises, competing choices, main teaching, difficulty and distractor
quality; use arithmetic, literal code execution and supplied facts where possible.
Report prompt size, provider tokens, call counts, latency and all requested slots.
A small successful trial may justify further implementation; it does not authorize
silently bypassing production's verification-policy contract.
