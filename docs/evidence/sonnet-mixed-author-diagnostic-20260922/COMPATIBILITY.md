# Existing capability and prior evidence

Checked September 22, 2026. AWS's [Sonnet 4.6 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-sonnet-4-6.html)
lists Converse, structured outputs and the `us.anthropic.claude-sonnet-4-6` profile,
available from us-east-1. Its [adaptive-thinking documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-adaptive-thinking.html)
includes Sonnet 4.6 and the adaptive/effort controls; high is the default effort.
These are capability statements, not evidence this new mixed grammar has already
succeeded on Sonnet or that every account invocation will succeed.

The current frozen runtime already allowlists Sonnet 4.6 for native transport.
Its real request builder sends adaptive/high in `additionalModelRequestFields`,
sets 16,000 shared output tokens and removes sampling settings. The new offline
preflight captures and checks that exact request, using the already validated
nonrecursive mixed schema. No model allowlist or agreement change is needed.
The earlier [adaptive fixed-pair solver capture](../choice-quality-release-20260922/ADAPTIVE_RESULTS.md)
contains four completed native Sonnet adaptive/high requests from this account.
That proves observed access/configuration for those requests, not author quality
or this specific mixed-schema invocation. Credential/setup failures still stop.

The [September 8 author comparison](../../QUESTION_AUTHOR_MODEL_COMPARISON_RESULTS.md)
compared Kimi and Opus 4.6 with disabled thinking, rather than this Sonnet setting.
Opus produced five independently supported keys versus Kimi's two of six, but
more oversized explanations and only one item satisfying the combined key,
difficulty and distractor criterion before its length exclusion. Neither arm
qualified. Author model changes can affect quality without fixing all failures.

The [ordered native author comparison](../native-author-order-20260922/REPORT.md)
supports preserving stem-before-choice and explanation-before-key ordering; this
trial keeps the mixed route's already reviewed ordering unchanged. The independent
schema review verified all historical schemas stayed byte-identical and the mixed
wire schema expands to the same local validator.

The recent mixed-route Kimi trial is the motivation for diagnosis: deterministic
compilation rejected absent-answer/equivalent-choice drafts, and prose required
independent semantic rejection. Its full pipeline and top-ups are not a paired
baseline for three Sonnet author-only calls. Preserve its capture and audit without
relabeling failures; report later comparisons by initial authored batch separately.
