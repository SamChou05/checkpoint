# AI Backend Contract

Checkpoint generates multiple-choice questions only through AI providers. In production, `Automatic` routes directly to the configured cloud backend. It never substitutes canned or template questions. A first AWS Bedrock Lambda implementation lives in `backend/bedrock-question-service`.

Apple Foundation Models remains code-supported only as an explicit internal experiment. It is not selected by production `Automatic` and is not a production fallback or question source because availability, OS model version, and reasoning capability vary.

The iOS app sends a `POST` request to the configured API Gateway `/v1/questions` endpoint. The normal user-facing Settings screen does not expose provider or endpoint selection. Internal endpoint configuration can come from `Checkpoint/Config/Secrets.xcconfig`, the `CheckpointAIBackendEndpoint` Info.plist key, or the `CHECKPOINT_AI_BACKEND_ENDPOINT` launch environment value. For controlled development and TestFlight, configure a random bearer of at least 32 characters through `CheckpointAIBackendToken` or `CHECKPOINT_AI_BACKEND_TOKEN` and set the same value as `CHECKPOINT_BACKEND_TOKEN` in the backend stack; never place AWS credentials in the app. The embedded shared bearer and install UUID are not public-production identity: App Attest challenges/assertions, replay protection, server-held key state, and server-side StoreKit entitlement checks remain mandatory public-release gates.

For development and TestFlight builds, copy `Checkpoint/Config/Secrets.example.xcconfig` to `Checkpoint/Config/Secrets.xcconfig`. Use the escaped URL style shown in the example (`https:/$()/...`) so Xcode does not treat `//` as an xcconfig comment. CI can instead supply `CHECKPOINT_AI_BACKEND_ENDPOINT_OVERRIDE` and `CHECKPOINT_AI_BACKEND_TOKEN_OVERRIDE`.

Release builds fail at build time unless the resolved endpoint is HTTPS, the token contains at least 32 non-placeholder characters, and hosted HTTPS Privacy Policy and Support URLs are configured. CI must opt in explicitly when it uses reserved `.invalid` legal-link placeholders for a simulator-only compile check. This backend configuration is mandatory because the cloud backend is the canonical production question source.

The app includes an anonymous `X-Checkpoint-Install-ID` header on backend calls. The Bedrock Lambda can use that header, plus source IP, for daily quota counters. The install ID is a random UUID generated on-device and is not a user account identifier.

## Request

The minimum useful contract is the user's raw goal. `focusAreas` and `currentLevel` are optional. The backend derives content topics from focus areas when present and requests an AI-generated skill map when the goal remains broad. `learningTarget`, `contentTopics`, `questionDirective`, and `needsSkillMap` remain accepted as optional compatibility/enrichment fields, but correctness must not depend on a client recognizing the subject in advance.

```json
{
  "goal": {
    "title": "<raw user goal>",
    "deadline": "2026-06-27T00:00:00Z",
    "category": "Custom",
    "focusAreas": "<optional focus area one, optional focus area two>",
    "currentLevel": "<optional learner level>",
    "preferredQuestionStyle": "Multiple Choice"
  },
  "competencies": [],
  "existingPrompts": [],
  "existingQuestionCoverage": [],
  "reportedPrompts": [],
  "targetCount": 5,
  "minimumDifficulty": 3,
  "difficultyGuidance": "Medium application: apply concepts to a short scenario with qualifiers and plausible distractors."
}
```

## Response

```json
{
  "questions": [
    {
      "prompt": "<self-contained question grounded in the user's educational goal>",
      "expectedAnswer": "<complete text of the correct answer>",
      "choices": [
        "<complete text of the correct answer>",
        "<plausible misconception one>",
        "<plausible misconception two>",
        "<plausible misconception three>"
      ],
      "explanation": "<why the expected answer follows from the question and subject knowledge>",
      "topic": "<supplied or inferred competency>",
      "difficulty": 3,
      "format": "Multiple Choice"
    }
  ]
}
```

## Response Rules

- Return only valid JSON.
- `difficulty` must be 1 through 5.
- `difficulty` should be greater than or equal to `minimumDifficulty` from the request.
- Use `difficultyGuidance` to make the question substance match the configured level; do not relabel an easy question as hard.
- `format` must be `Multiple Choice`.
- `choices` should include 4 options.
- `expectedAnswer` must exactly match one item in `choices`.
- All 4 choices must be meaningfully distinct in wording and substance. Do not include near-synonyms or paraphrases of the same answer.
- Distractors should test different misconceptions, not restate the same mechanism with synonyms.
- Avoid prompts listed in `existingPrompts` and `reportedPrompts`.
- Prefer objective questions for MVP.
- Every question should be answerable in 30 seconds to 3 minutes.
- Questions should target weak topics and stay near the user's estimated level.
- If `minimumDifficulty` is above 1, avoid remedial/basic questions unless the target topic cannot support harder prompts.
- If generated questions come back below `minimumDifficulty`, the backend and app should drop them instead of promoting their numeric difficulty.
- Treat the raw goal and focus areas as canonical. Use optional derived fields and competency estimates only when they remain aligned with that user input.
- If focus areas are present and derived topics are absent, split the focus areas into the initial topic map. If the goal remains broad, infer 4 to 6 subject-matter skills and use those skill names as returned question topics.
- Treat verbs in the title such as `study`, `prepare`, `pass`, or `learn` as intent, not as the tested subject. Test the knowledge or skill named by the goal itself.
- Use one domain-general assessment prompt and structural validator path. Production code must not branch on named exams, languages, technical fields, or other subjects; named examples belong in eval fixtures.
- Do not ask about study plans, productivity, motivation, app blocking, or next steps unless the learning target is explicitly study skills.

The iOS app also validates batches before storage. It drops blank questions, duplicate prompts, repeated answer-choice sets, reported prompts, questions below the configured minimum difficulty, missing topics, missing answers or explanations, missing choices, duplicate or near-duplicate answer choices, generic meta-assessment filler, off-target study-strategy prompts, and oversized prompt text. If a provider returns an expected answer that is not in the choices, the sanitizer can repair the choices by adding the expected answer before storage.

Checkpoint does not mark the first practice set ready unless at least five questions survive validation. A short or rejected response remains unready; no canned questions are inserted to reach the minimum.

## Client Readiness And Recovery

- While generation and validation are running, the app shows that questions are being prepared and lets the user leave the screen.
- Missing or unusable provider configuration surfaces a visible service-unavailable state.
- Network, timeout, rate-limit, or provider failures surface a retryable connection/service state.
- Responses rejected by the app's quality checks surface a quality state with `Try again` and `Edit topics` actions.
- If an already-ready bank cannot be topped off, existing accepted questions remain usable while the refresh failure is handled separately.

## Cost Rules

- Generate in batches, not per blocked-app attempt.
- Cache generated questions in the app.
- On goal creation or goal changes, prepare a validated 5-question ready set, then asynchronously top off the remaining question bank.
- When the cached bank runs low, request more AI questions before the user runs out of usable checkpoints.
- Do not substitute canned or template questions for short, failed, or rejected AI batches.
- Keep cloud calls behind the backend service; the iOS app must never contain Bedrock, AWS, or other model-provider secrets.
- Exposed backend URLs should fail closed without `CHECKPOINT_BACKEND_TOKEN`; only set `ALLOW_UNAUTHENTICATED_BACKEND=true` for controlled local/private testing.
- Cap batch size in the backend. The Bedrock Lambda defaults to 20 questions per call even if the app requests a larger bank.
- Rate-limit backend calls by anonymous app install ID and source IP before calling Bedrock.
- Retry malformed model output against the pinned production model before returning a generation error. Alternate models remain disabled unless they pass the same eval suite and quality thresholds.
- Use backend generation when:
  - production `Automatic` prepares a question batch
  - the bank is low
  - the user refreshes
  - the app explicitly selects Backend generation internally
