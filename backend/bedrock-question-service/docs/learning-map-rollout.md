# Configurable learning map contract and rollout

The native map editor adds learner-authored scope and practice preferences. Deploy the HTTP service and question-bank worker code together before distributing an iOS build that exposes the editor. No DynamoDB schema, resource, or data migration is required: new fields are optional on the wire and old queued requests retain their previous defaults.

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

Old clients omit the new fields and continue to use their previous defaults. Existing deployed services already understand `desiredSkillAllocation` and `adaptiveSkillPlans`, so client-computed emphasis/challenge and client-filtered pause behavior remain compatible. However, an older service discards `detail` during normalization, so it **does not honor edited descriptions**. Do not release the editor against that older service.

Descriptions are intentionally not copied into `goal.questionDirective`: that legacy field has a 1,000-character limit, while a complete edited map can contain 18,000 description characters. Combining descriptions there would lose scope, objective attribution, or precision. They also cannot be passed as source documents, which would incorrectly treat learner preferences as factual evidence.

## Inventory and release order

When `requiresFullObjectiveCoverage` is true, whole-bank targets first reserve one slot for every focus point on every positive-weight skill. Remaining slots follow practice weights. The same targets drive request validation, chunk generation, and refill. A total too small to cover the requested objectives is rejected; the server never expands a finite inventory entitlement. Legacy requests without this flag retain their existing one-slot-per-skill baseline.

1. Run backend unit tests, Ruff, and the existing deployment-script tests. Run the native contract/model tests against the intended app revision.
2. Deploy the reviewed service package through the existing deployment workflow to the intended environment, preserving its current provider, quota, credentials, and entitlement configuration. Update both HTTP and worker functions from the same revision. `scripts/deploy-sam.sh` is the existing deployment entry point; this feature introduces no new parameters.
3. Verify deployed normalization of descriptions and a one-skill generation payload, full-map evolution fencing, and a skewed six-skill/five-focus-point inventory request. A real generation smoke should inspect that questions use the edited scope and supplied challenge plan; local contract tests alone cannot prove a deployed model followed the description.
4. Distribute the iOS build only after those checks pass. If rolling back the service, also withhold or roll back the editor build: pause and adaptive allocation compatibility do not establish description support or the new full-coverage allocation behavior.

## Local evidence

`tests/test_learning_map_configuration.py` covers backwards-compatible defaults, invalid settings, prompt boundaries, description preservation, pause exclusion, concrete challenge targets, preference weighting, and evolution preservation. `tests/test_question_bank_allocation.py` covers a 30-focus-point map under 99:1 emphasis across multiple chunks and an exact maintenance-focus refill. Native `BackendQuestionEngineContractTests` covers field round-trip, active-only generation, full-map evolution identity, description bounds, and provider context.
