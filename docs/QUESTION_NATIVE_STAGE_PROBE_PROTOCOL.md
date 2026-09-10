# Native formatting regression protocol

Prepared September 9, 2026, after the completed delivery comparison. This is a
bounded diagnostic of the exact downstream inputs that previously produced
unparseable responses. It is not a fresh question-generation comparison or a
production rollout qualification.

## Question and fixed comparison

Can the production native response contracts make all seven observed malformed
checker inputs parseable while preserving their subject data, independent
visibility, and ability to report rejection or uncertainty?

The historical control is the immutable capture in
`docs/evidence/delivery-feedback-20260909/capture.json`, with byte SHA-256
`b2b4d385fcde8143d8d43ea34cb17d6e4963fb816793cb5feed9a776c02b3049`.
All seven selected calls completed normally but failed their strict JSON front
end because explanatory prose preceded fenced JSON. The new requests preserve
each original user payload and system instructions, adding only the committed
native transport instructions and its corresponding `outputConfig` schema.
These are fresh stochastic responses to historical inputs; their outcomes are
not a randomized estimate of the native mode's general effect.

Dispatch order, using zero-based original capture call indexes:

| Stage | Original calls, in order | Attempts |
| --- | --- | ---: |
| Independent complete-choice solver | 7, 14, 16, 18, 20, 7 | 6 |
| Default reviewer | 5, 5 | 2 |
| Authored-explanation auditor | 28, 28 | 2 |

This covers every observed formatting failure plus one exact repeated request
per downstream schema. First/repeated measurements do not establish cold/warm
grammar-cache state. The optional authored-explanation contract is tested because
it produced one of the recorded failures; the diagnostic does not enable that
feedback mode for users.

## Bounds and preservation

- Ten provider attempts total, serial, with one SDK attempt each. No model
  fallback, repair, replacement case, automatic restart, or resumed directory.
- Exact model/profile `us.anthropic.claude-sonnet-4-6`, `us-east-1`, thinking
  disabled, 6,000 output tokens, temperature 0.2. These match the historical
  checker requests. No guardrail setting changes within the comparison.
- Read timeout 75 seconds, connect timeout 3 seconds, and at most 240 seconds
  per isolated observation including worker setup. Preserve the existing local
  cleanup checks. Disk persistence is not a hard real-time bound. Missing
  responses leave remote completion and usage unknown.
- At most 32 KiB of serialized UTF-8 request data per attempt and 320 KiB total.
  This is not a billing or token cap. Output capture retains the existing
  bounded worker transport limit.
- Freeze the exact requests, schemas, settings, source bytes and committed
  revision, dependencies, and original capture before live execution. Use the
  pinned boto3/botocore 1.43.91 runtime in the isolated checkout.
- Persist the planned attempt and admission before permitting dispatch.
  Provider, unfinished-response, cleanup, worker/request-binding correlation,
  or persistence failure stops later requests. Preserve completed text even if
  its native schema or application content is invalid, including completed
  stage index/choice correlation rejection; that content failure consumes its
  planned slot and cannot trigger repair or replacement.

AWS documents that new schemas may require several minutes to compile. A timeout
under the existing limits is a relevant result; do not increase limits simply
to obtain a pass. Cache state is unobservable in this diagnostic.
[AWS structured outputs](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)

## Assessment and decision

Report all ten planned slots, including any not dispatched after a failure.
Separate actual dispatch count, provider completion, known token usage, elapsed
time, cleanup, raw native JSON/schema validity, adapted response validity, and
exact stage input/output correlation. Preserve the raw final model response
before the default reviewer's provider-only feedback array is adapted to the
public feedback dictionary.

Use the actual solver and authored-review validators for their exact input
items. Record declared supported/refuted/uncertain judgments and reviewer
verdicts separately from formatting outcomes. The default reviewer has no
standalone full policy validator: any partial shape/correlation check must be
identified as such and must not be reported as runtime acceptance. Full
production review, key agreement, teaching, difficulty, and fresh inventory
yield remain separate checks. No question becomes learner inventory here.

Inspect the complete returned records for contradictions, changed choice text,
lost qualifications, and negative outcomes that were forced into approval.
Formatting success alone does not establish correct answers, useful distractors,
teaching accuracy, or difficulty. The existing semantic gates remain unchanged.

Before any live request, a fresh independent assessor evaluated the 19 distinct
subjects and all 76 exact choices using only stems, choices, goal, and supplied
sources. The first pass was frozen at `2026-09-10T05:23:41.922568+00:00`, with
assessment byte SHA-256
`38f73d44bac4b01187b8009dc859ffa534c2461a19d94eb68db85cb2acc0b869`.
The assessor saw no authored keys, explanations, solver/reviewer outputs, model
identities, or other assessments. Preserve disagreements between this fallible
assessment and the new records for explicit analysis; a model-assessor agreement
is not expert calibration or factual proof. Archive the packet, mapping and
freeze metadata with the results. This supplemental review cannot turn the
selected regression set into a general accuracy sample.

Read-only preflight resolves the diagnostic profile in the current account;
public evidence includes model IDs and destination regions without account IDs,
credentials, or provider exception text. Error classes alone cannot establish a
specific AWS service error code. Synthetic content is retained in local evidence;
operational summaries contain bounded metadata rather than learner data.

If the stage diagnostic completes, the next experiment measures fresh returned
question quality and coverage through the actual generation/verification path.
The author and both skill-map schemas, other models, production IAM, API/worker
deployment, and global native-mode enablement are outside this diagnostic's
qualification scope. In particular the documented synchronous Nova Lite role
remains incompatible with the current native capability allowlist. Keep
production settings unchanged until the wider qualification is complete.
