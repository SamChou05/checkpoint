# Unfrozen Opus 4.7 final-audit diagnostic

This is a separate draft; it does not alter the frozen Opus 5 plan or any trial.
No inference or account changes have occurred. Root must review the complete
requests and digest before freezing or executing. The harness has no activation
API and stores no credentials, offer tokens, temporary legal URLs, or provider
reasoning/signatures.

This diagnostic uses ordinary Bedrock Converse JSON prompting. The exact scoped
audit v3 system prompt and difficulty rubric are followed by its unchanged exact
count-bound output schema in a text delimiter. No `outputConfig`, tool schema,
or native constrained-generation guarantee is requested. The response must pass
the existing strict local decoder and audit validation without JSON repair.
AWS's [Opus 4.7 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-4-7.html)
lists Converse and adaptive reasoning support, and lists structured outputs as
unsupported. The candidate is `us.anthropic.claude-opus-4-7` through the us-east-1
Bedrock Runtime endpoint. The US profile can route to us-east-1, us-east-2 or
us-west-2. Sampling parameters are unsupported and omitted. AWS's
[adaptive-thinking guide](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-adaptive-thinking.html)
places `thinking.type=adaptive` and the separate `output_config.effort=high`
inside Converse `additionalModelRequestFields`.

Fresh read-only checks at 2026-09-22T10:50:38.943305+00:00 reported agreement
AVAILABLE, authorization AUTHORIZED, entitlement AVAILABLE, region AVAILABLE,
and an ACTIVE SYSTEM_DEFINED US profile. `access-evidence.json` pins only these
sanitized statuses, profile identity and routing regions. The two control-plane
reads made no inference calls or account changes. Availability is a point-in-time
observation and does not prove a future Converse invocation will succeed.

The 24 complete original learner controls and gold are unchanged. Their original
order is grouped 5+5+5+5+4. As in the composed trial, only the common empty skillMap
representation changes from `[]` to `null`; all scope prose is identical. The
actual audit builder supplies empty assignment objects and empty history. Explicit
keys, gold and prior judgments are hidden; the unchanged teaching can reveal keys.

There are at most five provider calls, one per fixed independent batch. Settings
are adaptive/high reasoning, 16,000 shared tokens, no sampling controls, read 100
seconds, connect 3 seconds and exactly one SDK attempt. There are no retries,
fallbacks, rescues, author calls or solver calls. Ordinary provider, timeout,
non-end-turn and malformed-output failures fail that batch and continue the next
fixed batch. Credential/setup, source/request/configuration drift and budget or
content-integrity failures stop globally. All 24 items remain in the denominator.

The prospective criterion requires all five calls to complete normally within
100 seconds, strict local validity, all 24 admission decisions correct, all 12
sound controls retained and all 12 defective controls excluded. Selected teaching
must exactly equal the original five learner fields. Difficulty is reported with
a permissive gate. Task/answer/feedback labels and all 144 task/feedback reasons
are separate diagnostics, with independent reason adjudication required.

Full exact requests, schema text, original controls/gold, scope normalization,
runtime modules, requirements/verifier, helper/harness files, dependencies and
budgets are pinned. Pins are checked before and after every dispatch and at
completion. Exclusive plan/capture creation prevents accidental overwrite or
resume. The bounded 15-second/32-KiB credential-export helper is reused; credentials
stay in memory. Provider responses retain visible text and whitelisted bounded
numeric metadata only; headers and unrecognized metadata are dropped. Error
fields redact exact credentials, URLs and offer-token assignments before saving.

Offline: `python -B opus47_probe.py --preflight`. `--draft` prints the reviewable
plan and its canonical digest without saving or freezing. `--freeze DIGEST`
creates `plan.json` after fake preflight. `--execute PLAN_SHA256` requires the
exact reviewed frozen plan, source pins and an absent capture file. Neither
operation accepts an agreement or activates an account. This preparation leaves
`plan.json` and `capture.json` absent.

Five requests capped at 16,000 shared output tokens allow at most 80,000 output
tokens. Input and output usage are reported separately. Missing timeout usage is
not zero; no unverified model price or hard dollar cap is claimed.

This is a candidate model/configuration diagnostic on repeated known controls.
Regrouping and JSON-prompted transport prevent a causal model comparison. Even a
perfect result cannot qualify production, fresh author generation, worker yield,
or deterministic semantic correctness. No deployed data or runtime is changed.
