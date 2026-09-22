# Independent structural review

**Structural replay passes; the full trial fails its frozen yield requirements.** All 12 recorded requests, reservations, per-pass records and exact runtime returns reproduce offline through the unchanged worker source. No provider calls were made. All 34 source/artifact pins match; the dedicated source remains clean at `6959a265a222e6e1c9234f139a667f55c2dda4de`.

| Job | Requested / returned | Calls | Worker seconds | Compiled returned / prose returned |
|---|---:|---:|---:|---:|
| Quantitative | 5 / 2 | 5 | 166.077081 | 2 / 0 |
| Python | 5 / 5 | 3 | 68.278195 | 0 / 5 |
| Mixed | 5 / 3 | 4 | 137.222157 | 1 / 2 |

The original denominator is **15**, with 10 returned against the required 14, and only 3 compiled against the required 6. Quantitative and mixed each miss the four-per-job floor. Twenty-five raw author rows across six bounded author attempts are diagnostics, not a replacement denominator. All jobs finish within 240 seconds. There is no provider, native-format or local-stage-format failure; the recorded stop reasons are 12/12 `end_turn`. The remaining call slots do not authorize a new pass: the quantitative job exhausted three author attempts, and the mixed job has only two reservations left when a new mixed pass conservatively requires three.

All 12 responses validate against their actual serialized native schema and native adapter. The two prose solver calls cover 7 exact identities, 28 choice judgments and 42 unordered pair judgments. The four immutable audits cover 11 identities and 66 typed issue flags, with 10 positive and one negative disposition. Actual strict local validators accept all stage envelopes. These counts establish format and correlation, not the factual correctness of their declarations. Only the native cardinalities actually observed are covered.

Four compiler candidates reproduce all five learner fields from their original closed specifications; three survive the final audit. Every returned compiled question retains those exact five fields and policy 8. All seven returned prose questions retain their exact authored main, empty choice-feedback map and policy 7. The live observer's retained verifier-object identities and current-pass source records are independently recreated during replay; the report does not infer memory identity from serialized text alone. Compiled items skip only the prose solver; all 11 survivors still receive the immutable final audit.

The actual Kimi disabled author requests use 6,000 tokens and temperature 0.2; Sonnet adaptive/high solver/auditor requests use 16,000 tokens without sampling fields. Every request equals the reconstructed frozen runtime request. Captured transport is one SDK attempt, three-second connection timeout and read ceiling 100 seconds. Call 4 records a reduced 98.191-second read timeout. The unchanged client formula implies 104,192ms remaining when configuring that timeout, versus 104,174ms recorded before Converse; the 18ms interval is inferred because no separate factory timestamp was captured. All actual elapsed calls are below their recorded read limits. Offline replay verifies the same content/control flow, not a fresh latency measurement.

Reported usage totals **35,359 input tokens and 23,294 output tokens**, with no missing usage. Provider-call time sums to 370.870272 seconds across independent jobs; total worker time is 371.577433 seconds. Seven native reasoning blocks were omitted. No reasoning text or signature was reviewed, and no private reasoning is inferred from the returned flags.

Compiler failures are visible: 18 numerical drafts yield four compilable candidates, with ten `no_answer` and four `invalid_spec` failures. The separately preserved [rejected-spec analysis](rejected-spec-analysis.md) covers the quantitative job's earlier immutable snapshot only: seven missing-answer and three unreachable-node failures. It does not relabel the later mixed-job failures or accepted content. Learner-content and private-reason semantics belong to the separate content review.

Replay used Python 3.12.11 from `/tmp/checkpoint-reliability-20260921-venv/bin/python`, imported the pinned `mixed_probe.py`, called `check_plan`, and invoked its actual `run_jobs` with only the SDK factory replaced by exact recorded responses. Socket connections were explicitly blocked. It asserted all 12 dynamically reconstructed requests equal their recorded counterparts, exact reservations, and equality of every job's `passes`, `returned`, `returned_sources`, `returned_provenance` and `provider_calls`. Native wire schemas were also checked with `Draft202012Validator`, then the actual native adapter, complete-choice parser and authored-review parser. Final source/plan/capture hashes remained unchanged.

Bindings:

- Plan: `703c0bb57e2c51b5226f537e592add1746c0462c259cd315b14ee341b0ae2ad4`.
- Capture: `7d458b0f433018df5fa20c7d47c49f7c143c63f7201340a644df6ca31d37b0d3`.
- Detailed derived checks: [independent-structural-review.json](independent-structural-review.json).

This is a failed candidate trial on repeated scopes. Structural success does not establish broad semantic accuracy, causal improvement, deployment readiness or permission to alter its frozen criteria. No historical source, plan, capture or gold was modified.
