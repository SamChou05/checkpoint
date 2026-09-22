# Adaptive-thinking candidate qualification

The disabled-thinking endpoint trial retained all ten valid questions and rejected
all ten defective questions, but failed full-label qualification at 116/120 pair
labels. Reasons still sometimes addressed another pair's options. This experiment
tests whether the current endpoint/slot candidate with adaptive thinking meets the
same frozen twenty-case criteria. It does not change the production default.

## Exact request construction and bounds

Use the actual production `_generate_with_bedrock` path with Sonnet 4.6,
`BEDROCK_CLAUDE_THINKING=adaptive`, effort `high`, and
`BEDROCK_THINKING_MAX_TOKENS=16000`. The runtime removes temperature and sends
`inferenceConfig.maxTokens=16000`; this is a shared reasoning-plus-final-output
cap, not an additional 16,000 tokens on top of a 6,000-token final response.
Preserve the exact current endpoint slot prompt, trusted item text/choice/pair
mapping, native v3 schema and independent gold. The only provider-request changes
from the disabled endpoint trial are adaptive/high fields, removed temperature,
and the output cap required by the existing runtime.

Default preparation captures real runtime request construction using an offline
client; no model calls occur. It asserts exact prompt/input/schema identity with
the disabled endpoint plan and compares every changed request field. Offline
checks also exercise the shared four-call `ProviderCallBudget`: a fifth attempt
must be blocked before the fake client. A mocked production `_bedrock_client`
confirms exactly one SDK attempt, three-second connect and 75-second read timeout.
Live dispatch uses those same production runtime and client helpers. Adaptive
thinking changes inference inside a call; it adds no provider stage or retry.

Four candidate calls maximum, one per unchanged five-item batch. These are the
same twenty reviewed reused controls, not a fresh held-out suite. No baseline,
author, repair, replacement or follow-up judging calls. No after-output gold or
criterion changes. Stop on transport failure, abnormal completion/truncation,
strict JSON/schema, exact identity/coverage or reason-bound failure; preserve all
unattempted cases in the planned denominator. Continue planned batches after
semantic errors.

Qualification remains four valid completed calls, ten valid retained, ten
incorrect/duplicated items rejected for the expected reason, eighty correct choice
labels, 120 correct pair labels, no uncertainty, eighty choice reasons before
judgments and 120 pair reasons before relations. No relaxation for an item whose
final eligibility happens to be right despite a wrong pair label.

## Cost and interpretation

Report every call's output/input tokens, elapsed seconds, completion status and
returned reasoning-block count. Do not store reasoning text or signatures. Usage
may combine reasoning and final output tokens; do not invent a breakdown if the
provider does not supply one. Compare descriptively to the existing disabled
endpoint capture (16,841 input / 7,219 output tokens; 72.782 summed seconds), while
keeping both denominators intact. This is not a concurrent paired experiment and
cannot attribute a difference solely to adaptive thinking: sampling and output
budget also change as required by the runtime.

The worker allows 240 seconds for the full author/solver/reviewer sequence and up
to six provider calls. The 75-second individual read bound stays fixed here.
Measure solver latency and maximum observed call duration explicitly; four isolated
solver calls do not prove a full worker run fits its deadline. No result changes
production defaults or establishes universal accuracy or deterministic semantics.

Parent review of frozen `adaptive-plan.json` is required before `--run`.
