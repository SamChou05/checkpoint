# Prospective paired model comparison

Checkpoint's current checker retained a Spanish question built on a false grammar rule and produced contradictory photography feedback. The next experiment asks whether changing the checking model improves these observed failures without rejecting valid questions. It does not test question authorship, adaptive learning, or qualify a model for production.

This plan is prospective. **No Opus 5 agreement has been accepted and this comparison has not run.** Activation is a separate AWS account action that accepts commercial model terms. The user must authorize that action before execution.

## Matched conditions

Use the same four frozen questions in two fresh arms: `us.anthropic.claude-opus-4-6-v1` and `us.anthropic.claude-opus-5`. Each arm runs the existing option-blind solver, then the existing reviewer when the solver allows it. Both use adaptive thinking, high effort, and a 16,000-output-token limit. Prompts, question text, option order, source context, and runtime acceptance rules are identical between arms. No new reference material, search, execution tool, native output schema, author call, or repair call is added.

The fixture preserves each original question and normalized request. Runtime verification determines what context reaches each stage: the solver sees the stem and relevant goal/source context; the reviewer also sees rotated choices, existing coverage, and that arm's fresh solution. Neither receives the current item's stored answer or old explanation, independent adjudication, expected outcome, or feedback checklist. The two arms do not see each other's responses.

The pronoun control came from a second generation attempt. Its original reviewer context contains three earlier accepted-question coverage records, including the erroneous negated-doubt key. That historical context remains identical in both arms; the solver excludes it under the existing runtime policy. This tests the actual context behavior and does not claim that every historical answer is hidden from the reviewer.

Use a fixed interleaved order, reversing which model goes first on alternate cases. There are four case pairs, with at most two calls per model per case: **16 calls total**. A semantic rejection may use fewer calls. One SDK attempt per call; stop the entire run on provider failure, nonterminal output, or malformed response. Do not retry or transfer unused calls to more questions. Record requests before dispatch and preserve partial results and unknown usage on timeout.

The earlier four-domain run is the source of cases, not the paired baseline. It reviewed batches and used generated context that cannot be treated as equivalent to a new single-item run. A fresh Opus 4.6 arm prevents that batching difference from being mistaken for an improvement due to the model.

## Frozen cases and success criteria

| Case | Expected decision | Required assessment |
| --- | --- | --- |
| Spanish negated doubt, `9e2995f0…` | Reject | Recognize that *No dudo que Juan sepa…* is not inherently a mood error and none of the complete listed answers supplies a sound rule. An output-format failure or difficulty rejection does not count as catching this defect. |
| Group photo depth of field, `591ba431…` | Validate the aperture answer; apply the difficulty floor separately | Produce sound main and four-choice feedback. Do not claim that no other listed option affects depth of field, that shutter speed only affects exposure, or that the given aperture guarantees exact sharpness at both distances regardless of focus/format. |
| Spanish pronouns, `4f5c7000…` | Validate | Preserve Ana as the indirect-object recipient and the gift as the direct object, with accurate feedback for the other choices. |
| Three-stop exposure change, `003fd2a0…` | Validate ISO 1600 | Preserve the aperture and shutter constraints and the eightfold ISO calculation. Explain brightness compensation without asserting that ISO restores captured photons or that every walking subject necessarily blurs at one speed. |

The exact objects, full content hashes, provenance and assessment checklists are in [the fixture](../backend/bedrock-question-service/evals/fixtures/question_model_comparison.json). The prior source evidence is in [the four-domain report](QUESTION_FOUR_DOMAIN_EXPERIMENT.md).

Record model validity, inventory acceptance, rejection reason, unchanged-key agreement, main-explanation accuracy and every choice explanation separately. The group-photo question was independently rated difficulty 2 while its original request requires at least 3. A sound `valid:true` review followed by difficulty-floor removal is a factual-check success and a legitimate inventory exclusion. Preserve that floor and audit its generated feedback even when it is not returned; do not inflate difficulty to make an acceptance metric look better.

A retained key alone is not a pass. A blanket factual rejection strategy is not a pass. Independently review final text against the frozen criteria; runtime decision matching remains an observation until that audit is complete. Export anonymized arm labels for that assessment where feasible.

One pass on four deliberately selected cases is a diagnostic result, not a generalized accuracy estimate. Even a clean result requires a broader held-out generation evaluation before any model promotion. A failure means this substitution did not solve the selected problems; it does not justify repeated runs until a favorable response appears.

## Access, cost and execution readiness

AWS read-only availability checks found Opus 5 authorization, entitlement and regional availability present, but its model agreement unavailable. A self-service agreement offer exists. The offer points to the [Anthropic commercial terms on AWS](https://aws.amazon.com/legal/bedrock/third-party-models/) (August 18, 2025 version). This is a commercial account agreement, not merely a code setting. The offer shows usage charges and no refunds; no fixed upfront charge was shown. Agreement acceptance is still pending.

Read-only AWS agreement-offer rate cards show the same US geographic standard rates for both models: $5.50 per million input tokens and $27.50 per million output tokens. Sixteen calls at the full output limit would cost $7.04 for output. Allowing 256,000 input tokens adds $1.408, giving an illustrative **$8.448 before tax for both arms**; use $10 as a planning allowance. This is not a guaranteed dollar cap: exact input usage is returned after calls, and a timed-out call may have unknown usage. Record each arm's actual reported usage and any unknown usage separately.

Every request is limited to 16,000 UTF-8 input-text bytes and 256,000 bytes across the complete paired run. This keeps prompts small but is not represented as a provider-certified token bound. Maximum calls and maximum output tokens are enforced independently. No production settings, account quotas, IAM permissions, infrastructure or deployed model selection are changed by the evaluation.

Before execution, commit the verified fixture, runner and compatibility change, then freeze a canonical plan that binds exact prompts, settings, cases, ordered jobs and source hashes. The dry run must use no credentials or provider calls. Execution must name that exact plan hash and a fresh output location. Accept the Opus 5 model agreement only after explicit user authorization, then run this frozen comparison once.

Provider compatibility references: [Opus 5 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-5.html), [adaptive thinking](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-adaptive-thinking.html), and [sampling changes from Opus 4.7](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-4-7.html). The compatibility change must explicitly request the chosen reasoning mode and omit unsupported sampling fields; it does not select a new production default.
