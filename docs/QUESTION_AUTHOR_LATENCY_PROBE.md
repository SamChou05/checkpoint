# Observe author completion with a longer offline window

Prospective diagnostic, September 8, 2026 UTC. The
[first complete-authoring trial](QUESTION_COMPLETE_AUTHORING_RESULTS.md)
returned no content before its first call reached a 100-second read timeout.
The failed request's token usage, remote completion and content quality remain
unknown. That original trial is terminal and is not resumed by this diagnostic.

## One changed transport setting

Keep the exact author requests from the frozen four-goal plan, the same Opus 4.6
US inference profile, high effort, adaptive thinking, 16,000 output-token cap and
nonstreaming Converse operation. Extend only the offline SDK read window to
300 seconds. A parent process also imposes a 300-second worker deadline, including
worker bootstrap and client creation. The deadline is an additional resource
boundary, not a promise that the provider stops inference when the client exits.
Connection timeout remains three seconds and the SDK makes one attempt.

The two preselected author-only cases are the original CSS request (case 0) and
the unsourced English conditions/scope goal (case 2). The CSS request is explicitly
a repeated request in a separate diagnostic, not an independent new accuracy
sample or a recovered response from the failed call. The English request was
unattempted in the original run. No solver, auditor, repair, replacement content,
retry, production write or deployment is included. At most two workers may run,
serially. A failure stops admission of the next worker.
An observed response that fails the author content contract is still retained;
a normally completed first call permits the preselected second observation.

The parent freezes the exact requests, original plan/capture hashes, current
probe source and dependency hashes before execution. It alone writes the durable
capture. Workers report a dispatch boundary and bounded sanitized final response;
private reasoning and credentials are not transmitted into the artifact.
The parent distinguishes launch intent, observed dispatch and unknown dispatch
when termination makes the boundary ambiguous. It records final text, available
usage, stop reason and elapsed time, or an explicit failure. A killed or timed-out
request has unknown usage unless usage was actually observed. Workers are reaped;
the output directory cannot be overwritten or resumed.

## Why isolate this variable

AWS documents a much longer model inference window for Claude 4 than the SDK's
default read timeout. That explains why the transport window can censor a
response; it does not promise low latency or recommend waiting minutes in the
app. [AWS Claude message parameters](https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-anthropic-claude-messages.html)

Anthropic recommends adjusting effort when exploring latency. Effort changes
model behavior and requires a quality comparison. Shrinking the output ceiling
instead can truncate thinking or final JSON because they share the allowance.
Neither change is justified as a correctness fix by a response that was never
observed. This first diagnostic therefore preserves both settings.
[Thinking controls](https://platform.claude.com/docs/en/build-with-claude/thinking),
[effort controls](https://platform.claude.com/docs/en/build-with-claude/effort)

Streaming could separately expose time to first event, first answer text and
final completion, but an early event would not itself be a usable quiz question.
It also changes the transport and requires handling terminal errors and usage
metadata. It is outside this diagnostic.
[ConverseStream contract](https://docs.aws.amazon.com/bedrock/latest/APIReference/API_runtime_ConverseStream.html)

## Interpret the observations narrowly

Record worker lifetime and the SDK call interval separately, including whether
completion takes at most 100 seconds, longer than 100 seconds, or remains
unavailable. A later completion exceeds the original observation interval; it
does not prove that the old socket read timeout would reject this new call,
because elapsed call time and read inactivity are different measurements. A
response within 100 seconds likewise leaves the original timeout unexplained.
Neither result reconstructs the original request's server-side outcome.

If a complete MCQ is returned, preserve it unchanged and independently assess
the key, choice distinctness/plausibility, every explanation, field bounds and
actual difficulty. It has not passed the intended solver/auditor sequence and
cannot be counted as verified inventory. Missing or malformed outputs remain
visible; no narrower question is substituted to turn the run into a success.

Keep the production timeout and worker budget unchanged. A longer observation
window does not accelerate generation or qualify deployment. After this bounded
diagnostic, use the actual content and timing to choose whether a same-model
effort comparison or pipeline scheduling change is justified.

## Local verification before dispatch

Thirteen focused tests pass in both the standard Python environment and the
live dependency environment. The full backend suite passes 729 tests with one
existing optional-runtime skip. Tests cover exact frozen input isolation,
unknown usage, persistence before worker admission, partial response frames,
deadline cleanup of an inert descendant after its parent exits, and preserving
an observed response when later cleanup fails. Independent review found no
remaining blocker. Ruff and whitespace checks pass. No provider call has been
made at this protocol stage.
