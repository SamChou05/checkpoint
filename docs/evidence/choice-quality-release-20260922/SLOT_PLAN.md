# Fixed-slot native solver qualification

The prior eight-call ordering comparison stopped after three calls when the
model produced seven pair rows, including a self-pair. That failed experiment
and the earlier four-call semantic failures remain unchanged. This new candidate
makes all four correctness judgments and all six unordered pair identities fixed
schema fields, removing model-generated pair counts and echoed choice text.

## Candidate contract and application behavior

`complete_choice_solver_v3` returns one indexed solution per input item:
`choices` contains exactly `a,b,c,d`, each with `reason,judgment`; `choicePairs`
contains exactly `ab,ac,ad,bc,bd,cd`, each with `reason,relation`. Closed required
objects enforce these identities. The native schema intentionally orders reasons
before final judgments and relations. Strict local parsing still checks every
index, field, enum and reason bound and rejects malformed batches.

The input maps exact offered strings into slots using a stable SHA256 ordering of
`[prompt, choice]` alone. Authored keys, feedback and original choice positions do
not participate. The existing production path rotated the sanitizer's choices;
it did not always present the key first. The new invariant is stronger: every
permutation and authored-key change gives identical slot input. Decoding uses
trusted input to restore exact choice text and invokes the existing complete-choice
and pair validators. It never accepts echoed or normalized text from the model.

This candidate combines fixed identifiers, key-independent ordering and reason
ordering. It is a structural/semantic qualification, not an isolated causal test
of reason ordering. It occupies the existing solver call with no new model stage.
Legacy/default APIs and output contracts are preserved.

## Prospective frozen trial

- Four candidate calls, one per original five-item batch: the same twenty
  independently reviewed gold cases, ten valid and ten defective. These are reused
  controls, not new unseen cases. No baseline call or author call is added.
- Gold and the original item text remain exact. Model requests omit keys/gold.
  Expected support and pair meanings map to slots only in local scoring.
- Use actual production `build_solver_prompt(..., audit_choice_pairs=True,
  choice_slots=True)`, native v3 schema/prompt, adapter, slot decoder and veto API.
  Run strict JSON and JSON Schema checks in addition to the native adapter.
- Sonnet 4.6, temperature 0.2, thinking disabled, 6,000 output tokens, 75-second
  read timeout, three-second connect timeout, one SDK attempt. No retries,
  repairs, replacements, label changes, or unplanned calls.
- Stop on first transport/abnormal-completion/JSON/schema/coverage/identity or
  reason-bound failure; keep unattempted calls in the four-call denominator.
  Continue after semantic errors to retain the full frozen semantic denominator.
- Qualification requires all four structurally valid completed calls, ten valid
  retained, ten defective excluded for the expected reason, all eighty choice
  judgments and 120 pair labels correct, no uncertainty, all eighty choice reasons
  before judgments and all 120 pair reasons before relations in actual output.
  Record token usage, latency, typed label/prose contradictions if present, and
  exact slot coverage separately. No broad accuracy or determinism claim follows.

`slot_experiment.py` defaults to offline construction and synthetic-gold round-trip
validation. Parent review of the frozen plan is required before `--run`. The
runtime/source hashes, reviewed packet, prior failures and exact requests are
bound before dispatch. No changes after model output begins.
