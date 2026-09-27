# Compact mapped prose prompt v2: offline candidate

**Status: source and offline tests only. Do not activate or deploy yet.** The
bounded [compact typed-slot worker trial](../compact-typed-slots-qualification-20260926/RESULTS.md)
emitted all five slots, but returned only four questions. The excluded English
draft explained its answer as “In choice b” even though the sanitizer later
shuffled that answer to the first display position. It also claimed that other
possible antecedents had the same gender, which its displayed sentences did not
establish. The existing feedback guard correctly rejected the draft; a prompt
change cannot itself prove that future English questions are sound.

The opt-in `QUESTION_MAPPED_PROSE_PROMPT_REVISION=v2` adds one instruction span
to the compact mapped author's system prompt. It tells the author to explain
using literal answer content and stated facts, never choice labels or positions;
for pronoun-reference items it requires the displayed stem and candidate
sentences to establish relevant antecedent facts, including number or gender.
If the displayed facts do not determine exactly one answer, the author must
write a different complete item. The default `v1` prompt, user prompt,
accepted native schema, transport contract name, trusted assignment mapping,
compiler, sanitizer, solver, and reviewer are unchanged. Unknown mapped prompt
revisions fail closed before a provider request.

Using the exact assignments and prompt settings from the frozen prior plan, the
baseline system prompt is **10,606 bytes**, SHA-256
`d866eed0f1521ac92f6de1091d4371621c2f5b8b37c69138b1606c57d23f9f30`;
this matches that plan byte for byte. The v2 prompt is **11,284 bytes**, SHA-256
`c51391f986adb65700cd4dab578b3c86f57a617ef294fe24db35a41dc56f7c1e`.
Removing exactly the added v2 span from the latter reproduces the former. The
native JSON Schema remains **2,664 bytes**, SHA-256
`eee8c873b7892a8b96e510777fe9ffbbc8d10cf70846644ea0993946c9c2bb3c`.

The focused suite exercises the actual fake Converse dispatch, comparing the
wire system prompt and `outputConfig`, and verifies default, v2, invalid
revision, and unrelated author routing. All **7 focused** and **1,382 backend**
tests pass on Python 3.12 with pinned boto3/botocore 1.43.91. These tests prove
prompt selection and unchanged structure; they do not test model compliance or
answer quality. No AWS or Bedrock call was made for this candidate.

## Proposed one-shot author comparison

Freeze a separate, hash-pinned plan before any model call. Use the same exact
five-slot 3:2 request, Sonnet 4.6 profile, 2,664-byte schema, source revision,
user prompt, token settings, and original slot mapping for both arms. Change
only `QUESTION_MAPPED_PROSE_PROMPT_REVISION` from `v1` to `v2`; randomize arm
order before execution. Permit one author call per arm, no retry, repair,
fallback, top-up, or source edits, with a two-call ceiling and a fixed deadline.
Preserve raw request/response, usage, latency, prompt and schema hashes, and
unavailable slots even when a call fails. Stop at the deadline rather than
changing the prompts.

Commit and hash the captures, then give two independent reviewers answer-blind,
arm-blind worksheets with original slot identities hidden. Locally compile the
three quantitative tasks and apply the existing sanitizer and teaching guards
to each raw prose row. The reviewers judge whether each English stem has one
defensible answer, all six choice pairs differ in meaning, every required
antecedent fact is displayed, and the explanation supports that answer without
depending on order. Reveal keys and arms only after both reviews are locked.
The v2 candidate should yield all five usable rows, with both English rows
passing these checks and no regression in the quantitative rows, to warrant
broader qualification. One paired comparison cannot establish population
reliability or justify deployment by itself.
