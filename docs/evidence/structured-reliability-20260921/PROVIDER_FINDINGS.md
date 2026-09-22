# Provider transport investigation — September 21, 2026

The deployed question worker has native JSON-schema support in its package, but
its configuration still selects **`legacy`**, which sends ordinary text prompts
without `outputConfig`. Native structured output is therefore not constraining
the deployed model's response. This is directly established by the parent's
[fresh deployed package/configuration snapshot](../question-reliability-20260921/deployed-snapshot.json),
not inferred from old documentation. The worker uses Kimi K2.5 for authoring and
Sonnet 4.6 for solving/review, with thinking disabled. Seven relevant deployed
module hashes match upstream revision `7d9cc6ad93128893fb52f1a0183fea620b3b00ac`.

## Fresh live result

Native output **worked for the actual worker model pair** in two bounded local
passes through production authoring, sanitization, independent complete-choice
solving, and final review. Six calls completed normally, all three schemas were
accepted twice, and two generated arithmetic questions passed admission. There
were no SDK retries, fallbacks, top-ups, deployment changes, or bank writes.

| Stage | Model | First schema use | Repeated schema use |
| --- | --- | ---: | ---: |
| Author | Kimi K2.5 | 1.677 s | 1.313 s |
| Independent solver | Sonnet 4.6 | 3.320 s | 1.899 s |
| Final reviewer | Sonnet 4.6 | 6.355 s | 4.845 s |

Both passes used the same initial synthetic request at difficulty 1. The first
question was `What is 7 + 5?` with choices `12, 10, 11, 13`; the second was
`What is 9 + 5?` with choices `14, 12, 13, 15`. Each has exactly one correct
offered value, and each returned `expectedAnswer` equals that value. Every
choice received a keyed explanation. Native transport does not make repeated
requests return identical questions; these requests were intentionally sampled
at the deployed default temperature of 0.2.

The [immutable plan](live-native-plan.json), [runner](live_native_probe.py), and
[raw synthetic capture](live-native-capture.json) preserve source/schema hashes,
requests, ordinary responses, stop reasons, timings, token usage and admission
metrics. Reasoning blocks and credentials are excluded. Total usage was 9,688
input tokens and 842 output tokens. The captured plan's SHA256 is
`8ec972e0f1ff290d2151bdd92d4a6717aebe982487c436620581317c8aacbf2a`.

This establishes compatibility of three schemas on these two models for a
small synthetic full-pipeline smoke. It does not estimate a general correctness
rate or question-diversity rate, qualify skill-map schemas/optional authored
review, or exercise the deployed queue. First/repeated is not confirmed
cold/warm: provider grammar cache state is unavailable. The configured
75-second read timeout was preserved. Each pass was bounded to one generation
attempt and three calls; these experiment limits prevented additional retries.

## Shape is different from correctness

The [offline probe](provider_contract_probe.py) exercised 13 schema cases, five
alternative-shape cases and five request configurations, with results saved in
[provider-contract-probe.json](provider-contract-probe.json). Current native
author schemas reject missing fields, unknown fields, wrong JSON types and
wrong enums. They nevertheless accept all of these at the **transport** layer:

- An empty question batch or empty stem.
- Three choices, five choices, or duplicate choice strings.
- An `expectedAnswer` absent from the choices.
- An out-of-range integer difficulty.

These are not evidence that such questions enter the bank. The downstream
sanitizer and solver/reviewer gates separately enforce counts, bounds,
correlation and agreement. Existing complete-choice tests explicitly establish
that model-declared judgments can still be confidently wrong; schema enforcement
cannot prove that a natural-language option is true or that two differently
worded options mean the same thing.

An offline alternative uses four required object fields `A`–`D` and an answer
enum selecting one of those fields. With only object/string/enum primitives,
it rejects a missing fourth choice, a fifth choice and a nonexistent answer
slot. Application code could materialize the existing public array/string key
from that representation, avoiding repeated copying of the full answer text.
It still permits identical text in two fields, which remains an application
validation responsibility. This alternative was not sent to Bedrock and is not
a production implementation change.

## Current rollout constraint and recommendations

The same SAM parameter controls both API and worker output mode. The freshly
inspected API still uses Nova Lite for legacy synchronous authoring, while its
skill-map role uses Kimi. Runtime native support explicitly permits Kimi K2.5
and Sonnet 4.6, and rejects Nova Lite before invoking the provider. Flipping the
existing global flag would therefore break that synchronous author route.

The practical next step is independent worker/API rollout control, so the
qualified worker stages can use native output while the compatibility API keeps
its current model behavior. Keep application invariants and semantic validation;
do not reinterpret native formatting success as proof of correct distractors.
Consider stable choice IDs/fixed slots as a separately tested schema revision
if copying/count failures are materially present in production telemetry.

AWS documents Converse `outputConfig.textFormat` for constrained JSON and a
limited JSON Schema subset: `minItems` is limited to 0 or 1; numerical and
string-length bounds are unsupported. New grammar compilation may take minutes,
with a 24-hour cache, so first/repeated observations must remain separate.
These are documented possibilities, not delays observed in this smoke.
[AWS structured outputs](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)

Both model cards list structured-output capability:
[Kimi K2.5](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-moonshot-ai-kimi-k2-5.html)
and [Sonnet 4.6](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-sonnet-4-6.html).
The fresh smoke supplies runtime evidence beyond those capability claims.

## Source provenance and verification

The initial user checkout was 28 commits behind upstream, at `aa2db49c`, and
contained pre-existing uncommitted native-output work. Its old HEAD had no
native transport, while the dirty files introduced it but defaulted to legacy.
The initial characterization is preserved separately as
[provider-contract-probe-stale-checkout.json](provider-contract-probe-stale-checkout.json).
It must not be described as current deployed code.

Current upstream already includes pinned boto3/botocore packaging, CI dependency
installation, packaged SDK checks, explicit native service-error classification,
and improved rejected-review prompt instructions. Apparent defects in those
areas from the stale checkout were withdrawn after inspecting upstream. No
pre-existing files were edited. All new evidence resides in the isolated current
upstream worktree.

Verification on current upstream: all 15 native-output unit tests passed; all
23 offline characterization cases passed; Ruff and `git diff --check` passed
for these new probe files. The parent's complete backend suite independently
passed 1,050 tests before integration changes.
