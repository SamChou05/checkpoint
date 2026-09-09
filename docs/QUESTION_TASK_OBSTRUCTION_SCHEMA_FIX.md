# Preserve nullable answers in Bedrock's supported schema form

After AWS sign-in was renewed on September 9, the original frozen qualification
reached Bedrock but stopped on its first request with `ValidationException`.
A separately captured, single-request diagnostic repeated that exact request
and retained the service error: its schema checker rejected the string enum
values against the combined `["string", "null"]` type declaration.

The original schema passes a standard JSON Schema validator, and both null types
and primitive enums appear in the [Bedrock structured-output documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html).
That does not establish acceptance of every combination by the provider's schema
compiler. The [Claude structured-output documentation](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)
also describes union types and their limits. This failure concerns schema
compatibility; no model judged a question in either request.

Encode `choiceId` with `anyOf`: a string restricted to A–D, or a null value.
This preserves its set of valid JSON values. The application still permits a
non-null ID only for `answered_by_choice`, and requires that ID to identify the
sole supported answer. Explicit blocked/uncertain outcomes, key disagreement and
the independent teaching veto remain unchanged. Neither prompts nor questions
are revised by this compatibility correction.

The [derived failure evidence](evidence/task-obstruction-validation-failure-20260909.json)
records both attempts separately, with their original hashes. The qualification
capture has one worker launch, one provider dispatch, zero responses and zero
completed cases; worker cleanup is confirmed. Exact no-client replay reproduces
it. The additional diagnostic is one separate SDK attempt, also rejected before
a model response. There is no recorded token usage or correctness score.

The September 8 authentication failure and September 9 validation failure remain
unchanged local captures. A corrected qualification must freeze a new plan at
the corrected source commit and use a new exclusive output directory. Historical
plans must not be rewritten to make their invalid request appear successful.

Validation before the corrected run: all 973 backend tests passed without skips.
The added regression confirms old/new schemas accept exactly A–D and null among
the tested valid/invalid values. Scoped Ruff and diff checks passed. All 20
request shapes and native schemas validate locally; comparing the reconstructed
plans confirms unchanged questions, prompts, model settings and teaching schema,
with only the nullable choice-ID schema altered. Serialized requests now total
227,662 UTF-8 bytes, maximum 27,394. Native service acceptance and content accuracy
remain unproven until the corrected live run.

The [corrected run subsequently completed all 20 calls](QUESTION_TASK_OBSTRUCTION_RESULTS.md),
confirming native compatibility and both response contracts. Its full semantic
qualification failed; the schema fix is not itself a correctness improvement.
