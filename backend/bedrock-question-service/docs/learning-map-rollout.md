# Configurable learning map contract and rollout

The native map editor adds learner-authored scope and practice preferences. Deploy the HTTP service and question-bank worker code together before distributing an iOS build that exposes the editor. The learning-map feature itself adds no DynamoDB schema, resource, or data migration: new fields are optional on the wire and old queued requests retain their previous field defaults. The configured TestFlight service also lacks earlier reviewed-question work, so its full release delta is larger; see the live audit below.

## Fields and limits

| Field | Accepted values/default | Effect |
| --- | --- | --- |
| `skillMap.skills[].detail` | Optional string, at most 500 characters; empty by default | Defines the substantive scope of that skill in generation and successor planning. |
| `skillMap.skills[].objectives[].detail` | Optional string, at most 500 characters; empty by default | Defines the substantive scope of that focus point. |
| `skillMap.skills[].isPaused` | Boolean; `false` by default | Excludes the skill from generation, answer acceptance, bank inventory targets, and evolution eligibility. |
| `skillMap.skills[].practiceEmphasis` | `balanced`, `focus`, or `maintain`; `balanced` by default | The app combines emphasis with learning evidence in `desiredSkillAllocation`. Server preference weights are a fallback only when that allocation is absent; they are never applied twice. |
| `skillMap.skills[].challenge` | `adaptive`, `foundations`, or `stretch`; `adaptive` by default | Foundations targets the goal's difficulty floor. Stretch targets one level above the app's adaptive target, capped at 5. Server validation enforces at least floor + 1 for stretch without adding another increment to client-computed targets. |
| `skillMap.growthMode` | `automatic`, `reviewSuggestions`, or `manual`; existing automatic behavior when omitted | The app controls when a proposal is accepted. The server rejects evolution for manual maps and preserves the selected mode in its response. |

Descriptions preserve meaningful subject spacing and line breaks. They travel as JSON data, with explicit provider instructions treating them as untrusted descriptions rather than commands. Existing source-document grounding rules still apply. Description edits do not claim mastery or assign evidence.

The planned map and evolution map retain 3–6 skills; the editor keeps 1–5 focus points per skill and at least one skill unpaused. Question-generation requests accept 1–6 skills, including a single unpaused branch. This 1–6 generation contract predates this feature (`request_contract.py` at commit `e0f8d86`); it is separate from the 3–6 evolution/inference gates.

## Identity and compatibility

Generation payloads exclude paused skills in the app as well as on the server. Evolution payloads preserve the entire current map, including paused positions. Neither filtering path changes goal ID, skill/objective IDs, map version, or the caller's opaque context revision. The established FNV map fingerprint remains based on skill/objective IDs and names. App-side version and generation-context fencing account for configuration edits.

Unchanged evolution positions preserve their exact descriptions and preferences. A successor inherits practice emphasis and challenge; its description starts empty because its new capability differs from the predecessor. The old skill and its description remain in the app's archived history.

Old clients omit the new fields and continue to use their previous defaults. The configured TestFlight service understands `desiredSkillAllocation` and accepts a one-skill generation map, so client-computed emphasis and client-filtered pause behavior are compatible with that endpoint. A read-only source audit on September 7, 2026 found that this endpoint does **not** understand `adaptiveSkillPlans`, descriptions, or reviewed-question inventory. Its deployed `request_contract.py` matches repository commit `4a6257f` from September 3. It therefore does not honor edited descriptions or per-skill challenge targets. Do not release the editor against that service revision.

Descriptions are intentionally not copied into `goal.questionDirective`: that legacy field has a 1,000-character limit, while a complete edited map can contain 18,000 description characters. Combining descriptions there would lose scope, objective attribution, or precision. They also cannot be passed as source documents, which would incorrectly treat learner preferences as factual evidence.

## Inventory and release order

When `requiresFullObjectiveCoverage` is true, whole-bank targets first reserve one slot for every focus point on every positive-weight skill. Remaining slots follow practice weights. The same targets drive request validation, chunk generation, and refill. A total too small to cover the requested objectives is rejected; the server never expands a finite inventory entitlement. Legacy requests without this flag retain their existing one-slot-per-skill baseline.

1. Run backend unit tests, Ruff, and the existing deployment-script tests. Run the native contract/model tests against the intended app revision.
2. Deploy the reviewed service package to the intended environment, preserving all existing provider, quota, credentials, and entitlement parameters. Update both HTTP and worker functions from the same revision. `scripts/deploy-sam.sh` is the repository's deployment entry point when its environment is configured. The learning-map feature introduces no parameters, but the full release from the configured September 3 service requires reviewer parameters and related infrastructure changes described below.
3. Verify deployed normalization of descriptions and a one-skill generation payload, full-map evolution fencing, and a skewed six-skill/five-focus-point inventory request. A real generation smoke should inspect that questions use the edited scope and supplied challenge plan; local contract tests alone cannot prove a deployed model followed the description.
4. Distribute the iOS build only after those checks pass. If rolling back the service, also withhold or roll back the editor build: pause and skill-weight compatibility do not establish challenge, description, verification, or full-coverage support.

## Configured TestFlight audit and proposed full release

Read-only AWS inspection identifies the app's configured endpoint as stack `checkpoint-question-service-testflight` in `us-east-1`. The stack and all three functions were last updated on September 3, 2026. Its synchronous author is Nova Lite, asynchronous author is Kimi K2.5, worker timeout is 120 seconds, and queue visibility is 720 seconds. The live functions have no reviewer setting. The current client requests verified inventory for eligible learning flows, so a map-only patch to this older service would not establish the requested end state.

The repository's manual deployment workflow exists, but the GitHub repository had no environments, Actions secrets, or Actions variables configured at audit time. Local AWS CLI login credentials could make read-only calls successfully. A nonexecuted CloudFormation change set can be prepared locally without copying existing secret values: use `UsePreviousValue: true` for all 37 live stack parameters, including the bearer, quota hash, current author models, generation limits, and receive-count limit of 5.

The current template adds two required reviewer parameters. The proposed candidate uses the repository's existing default, `us.anthropic.claude-sonnet-4-6`, whose active inference profile and three US destination model ARNs were verified through Bedrock metadata. Its allowlist must contain the account's profile ARN and the foundation-model ARNs for `us-east-1`, `us-east-2`, and `us-west-2`. This reviewer is an added role in the pipeline; the existing Nova and Kimi authors are preserved. Four new reasoning parameters use their existing repository defaults: thinking disabled for Kimi and Claude, a 16,000-token thinking ceiling, and Claude effort high. Disabled thinking keeps that ceiling and effort inactive.

The full template also raises worker timeout to 240 seconds and queue visibility to 1440 seconds, adds reviewer invoke permissions to the HTTP and worker roles, and introduces earlier question verification, independent solving, and evidence checks alongside this map feature. These are material earlier undeployed changes, not changes caused by the map alone. A release package should contain only tracked runtime modules, excluding experiments, evaluation captures, tests, and local configuration. Preserve the deployed outbox package when it does not need a code change.

The candidate must remain unexecuted until its expanded change set has been reviewed for exact resource changes, preserved parameters, and replacement/deletion behavior. A successful package build or change-set creation is not a deployment and does not prove the deployed endpoint honors the new contract.

The prepared candidate is `learning-map-d6b6e39-review2-20260908`, created for the TestFlight stack on September 8 UTC (September 7 Pacific). It is available for review and has not been executed. The 92,650-byte runtime package contains 17 tracked Python modules from `d6b6e39`, with SHA-256 `72ff03514a4254ab55933acba32b347ba733c4d3ce7dea7bd16c5926c6ae6658`. SAM validation/build and a package import check passed.

Comparing the expanded candidate and deployed templates finds exactly five resource definitions with property changes: HTTP function code/environment, HTTP role reviewer permissions, worker code/environment/timeout, worker role reviewer permissions, and queue visibility. There are no added or removed resources, and the outbox code and resource definitions stay unchanged. CloudFormation's change-set view also lists dependent updates and labels the worker's SQS event-source mapping as a conditional replacement through the queue ARN dependency; the mapping definition is byte-equivalent as parsed JSON, and the queue itself is an in-place visibility update. Review that distinction before execution rather than interpreting the conditional label as a proven replacement or a guaranteed no-op.

## Local evidence

`tests/test_learning_map_configuration.py` covers backwards-compatible defaults, invalid settings, prompt boundaries, description preservation, pause exclusion, concrete challenge targets, preference weighting, and evolution preservation. `tests/test_question_bank_allocation.py` covers a 30-focus-point map under 99:1 emphasis across multiple chunks and an exact maintenance-focus refill. Native `BackendQuestionEngineContractTests` covers field round-trip, active-only generation, full-map evolution identity, description bounds, and provider context.
