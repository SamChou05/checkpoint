# Mapped refill reviewer timeout audit

The [frozen refill capture](evidence/mapped-refill-qualification-20260927/capture.json)
records one successful author call, one successful answer-blind solver call, and
a `ReadTimeoutError` on the final reviewer call. Its 70-second botocore read
timeout and single SDK attempt were explicit in the frozen plan. The worker
returned no verified questions. The reviewer produced no captured response or
usage, so neither its eventual remote completion nor a necessary timeout can
be inferred. The frozen harness also lost its final status and per-call timing
on this failure; its separate operational-failure record reconciles the result.

The earlier successful five-question batch used the same reviewer schema and
model family. Its reviewer returned in 44.394 seconds, with 3,864 output tokens.
The refill reviewer user payload was 7,131 characters, versus 5,071 in that
first batch, because it included the five prior questions as novelty context.
The refill author and solver responses reported 7,457 input and 2,947 output
tokens together, but the capture lacks their wall times. The reviewer could
have exceeded 70 seconds because of longer reasoning, provider latency, or
additional history; the available evidence cannot distinguish these causes.
The production worker's default read timeout is 75 seconds under a shared
240-second Lambda deadline. Increasing that default on this single failure
would be an unqualified behavior change, not a demonstrated fix.

The runtime already records the native stage and elapsed time in request
metrics when Converse fails. This audit adds only the bounded role, outcome,
and elapsed time to the worker's emitted metrics. It does not log question
text, prompts, model output, provider errors, or account identifiers. A
simulated reviewer timeout verifies the exported diagnostic.

For a fresh bounded diagnostic, freeze a **new** plan and use the exact archived
reviewer wire as one isolated Converse call. Use the same model, schema,
adaptive-effort setting, and one SDK attempt, with a 130-second read timeout
and a 150-second total deadline. Record dispatch/end wall time, stop reason,
usage if returned, and a privacy-redacted response hash. Do not treat a
successful standalone reviewer as a successful full-worker refill. A response
after 70 seconds would directly support a higher worker ceiling; a response
before 70 seconds would show latency variance; another timeout would leave the
underlying provider latency unresolved. Separately, a **new** full-worker
qualification must assess cross-bank near-duplicates, which already failed
candidate-only blind review in this frozen refill.
