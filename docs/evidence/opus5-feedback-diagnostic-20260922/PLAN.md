# Unfrozen Opus 5 final-audit diagnostic

No provider calls or agreement/account activation are authorized by this draft.
Root must review its complete requests and digest before freezing, and obtain
separate approval for any commercial agreement before confirming account access.
The harness has no account-activation API and never stores an offer token,
presigned legal URL, credential, or provider reasoning/signature.

This diagnostic uses ordinary Bedrock Converse JSON prompting. The exact scoped
audit v3 system prompt and difficulty rubric are followed by its unchanged exact
count-bound output schema in a text delimiter. No `outputConfig`, tool schema,
or native constrained-generation guarantee is requested. The response must pass
the existing strict local decoder and audit validation without JSON repair.
AWS's [Opus 5 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-5.html)
lists Converse and adaptive reasoning support, and lists structured outputs as
unsupported. The candidate is `us.anthropic.claude-opus-5` in us-east-1.

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

Offline: `python -B opus5_probe.py --preflight`. `--draft` prints the reviewable
plan and its canonical digest without saving or freezing. `--freeze DIGEST`
creates `plan.json` after fake preflight. `--execute PLAN_SHA256` additionally
requires `--agreement-confirmed`, which confirms separately authorized access;
it neither accepts an agreement nor activates the account.

Root's read-only offer check identified offer `offer-f3u6lgbrem3zs`, standard
rates of $5.50 per million input tokens and $27.50 per million response tokens,
and a no-refunds policy. Five calls capped at 16,000 shared output tokens imply
at most $2.20 in output charges. Input charges are additional; unavailable timeout
usage must not be treated as zero. This is not a hard total dollar cap. The public
[third-party model terms](https://aws.amazon.com/legal/bedrock/third-party-models/)
are the review link; only the checked PDF size/hash and sanitized offer metadata
are pinned, without a downloaded agreement or temporary legal URL.

This is a candidate model/configuration diagnostic on repeated known controls.
Regrouping and JSON-prompted transport prevent a causal model comparison. Even a
perfect result cannot qualify production, fresh author generation, worker yield,
or deterministic semantic correctness. No deployed data or runtime is changed.
