# Trial 03: author exhausted the output budget before verification

The independently reviewed [frozen plan](plan.json) was executed once with
the unchanged synthetic probability request and the opt-in 4+3 verifier source.
The exact plan SHA-256 was
`8c493d8e068ea153cf8a4225a7ed955df90d7c9cadd954e2b506b47dc941deff`.
The fresh [AWS precheck](launch-precheck.json) matched account `239342516379`;
the [immutable capture](capture.json) has SHA-256
`4a950b2cd3ec82fcb1d95f389bda3c14e7b098919bfae0d1d07d58dfe6267db8`.

The one native seven-row author Converse call was dispatched and returned
after **155.586 seconds** with `stopReason=max_tokens`. Bedrock reported
**3,368 input tokens and 16,000 output tokens**. The visible response ended
mid-JSON, so the strict author adapter raised `ProviderError` before
sanitization. The original job ended in **157.618 seconds** with **one**
durable Converse reservation/dispatch, **zero** solver calls, **zero**
reviewer calls, and **0/5** returned questions. No retry, fallback, top-up,
or second job ran for this trial ID. This is a failed trial, not a partial
success or a measurement of the new verifier transport.

The service config asks Claude Sonnet 4.6 for adaptive high effort and caps
thinking plus final output at 16,000 tokens. The capture establishes that
this particular response exhausted that shared output allowance; it does not
show how the hidden tokens were divided between reasoning and final JSON.
Trial 02 authored seven parseable rows with the same request and setting, so
the two one-shot outcomes also show this configuration is not reliably
bounded at seven rows. A separate, frozen author-only experiment can vary the
request guidance or thinking setting, but neither can relabel this outcome or
establish five-question worker reliability without a fresh full job.
