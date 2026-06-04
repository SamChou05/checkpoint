# AI Backend Contract

Checkpoint can generate multiple-choice questions through a backend endpoint when higher-quality generation is explicitly needed beyond Apple Foundation Models and Local Templates. A first AWS Bedrock Lambda implementation lives in `backend/bedrock-question-service`.

The iOS app sends a `POST` request to the endpoint configured by the app or backend service layer. The normal user-facing Settings screen does not expose provider or endpoint selection. Internal endpoint configuration can come from `Checkpoint/Config/Secrets.xcconfig`, the `CheckpointAIBackendEndpoint` Info.plist key, or the `CHECKPOINT_AI_BACKEND_ENDPOINT` launch environment value. If an early testing endpoint uses a bearer token, configure `CheckpointAIBackendToken` or `CHECKPOINT_AI_BACKEND_TOKEN`; never place AWS credentials in the app.

For local/TestFlight builds, copy `Checkpoint/Config/Secrets.example.xcconfig` to `Checkpoint/Config/Secrets.xcconfig`. Use the escaped URL style shown in the example (`https:/$()/...`) so Xcode does not treat `//` as an xcconfig comment.

The app includes an anonymous `X-Checkpoint-Install-ID` header on backend calls. The Bedrock Lambda can use that header, plus source IP, for daily quota counters. The install ID is a random UUID generated on-device and is not a user account identifier.

## Request

```json
{
  "goal": {
    "title": "Pass a coding interview in 8 weeks",
    "deadline": "2026-06-27T00:00:00Z",
    "category": "Coding Interview",
    "focusAreas": "arrays, recursion, Big-O",
    "learningTarget": "coding interview in 8 weeks",
    "contentTopics": ["arrays", "recursion", "Big-O"],
    "questionDirective": "Generate concrete coding-interview knowledge checks about arrays, recursion, Big-O: data-structure choice, algorithm behavior, complexity, edge cases, or debugging.",
    "needsSkillMap": false,
    "preferredQuestionStyle": "Multiple Choice"
  },
  "competencies": [
    {
      "topic": "recursion",
      "estimatedLevel": 2.1,
      "masteryPercent": 50,
      "attempts": 4,
      "correct": 2,
      "partial": 0,
      "incorrect": 2
    }
  ],
  "existingPrompts": [
    "Explain the tradeoff to watch for when solving an arrays problem."
  ],
  "reportedPrompts": [
    "What is an array?"
  ],
  "targetCount": 40,
  "minimumDifficulty": 3,
  "difficultyGuidance": "Medium application: apply concepts to a short scenario with qualifiers and plausible distractors."
}
```

## Response

```json
{
  "questions": [
    {
      "prompt": "For an intermediate interview candidate, which tradeoff matters most when choosing between recursion and iteration for a tree traversal?",
      "expectedAnswer": "Recursion is concise, but iteration can avoid call-stack depth limits.",
      "choices": [
        "Recursion is concise, but iteration can avoid call-stack depth limits.",
        "Iteration always uses O(1) memory for every tree traversal.",
        "Recursion always changes the traversal from O(n) to O(log n).",
        "The choice only affects variable naming, not behavior."
      ],
      "explanation": "Both approaches can visit each node once, but stack depth and implementation clarity are the practical tradeoffs.",
      "topic": "recursion",
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
- All 4 choices must be meaningfully distinct in wording and substance. Do not include near-synonyms or paraphrases of the same answer, such as `maps virtual addresses to physical addresses` and `translates virtual addresses to physical addresses`.
- Distractors should test different misconceptions, not restate the same mechanism with synonyms.
- Avoid prompts listed in `existingPrompts` and `reportedPrompts`.
- Prefer objective questions for MVP.
- Every question should be answerable in 30 seconds to 3 minutes.
- Questions should target weak topics and stay near the user's estimated level.
- If `minimumDifficulty` is above 1, avoid remedial/basic questions unless the target topic cannot support harder prompts.
- If generated questions come back below `minimumDifficulty`, the backend and app should drop them instead of promoting their numeric difficulty.
- Use `learningTarget`, `contentTopics`, `questionDirective`, competency estimates, and `minimumDifficulty` together when writing the prompt and assigning difficulty.
- If `goal.needsSkillMap` is true, infer 4 to 6 subject-matter skills from the learning target and use those skill names as returned question topics. The app uses the first generated topics to seed the Skill Map before background bank refill.
- Treat verbs in the title such as `study`, `prepare`, `pass`, or `learn` as user intent, not as the tested subject. For example, `Study for the LSAT` should produce LSAT Logical Reasoning or Reading Comprehension questions, not questions about how to study.
- Do not ask about study plans, productivity, motivation, app blocking, or next steps unless the learning target is explicitly study skills.

The iOS app also validates batches before storage. It drops blank questions, duplicate prompts, reported prompts, questions below the configured minimum difficulty, missing topics, missing answers or explanations, missing choices, duplicate or near-duplicate answer choices, off-target study-strategy prompts, and oversized prompt text. If a provider returns an expected answer that is not in the choices, the sanitizer can repair the choices by adding the expected answer before storage.

## Cost Rules

- Generate in batches, not per blocked-app attempt.
- Cache generated questions in the app.
- On goal creation or goal changes, prepare a 5-question AI-first ready set, then asynchronously top off the remaining question bank.
- When the cached bank runs low, request more AI questions before the user runs out of usable checkpoints.
- If an AI backend is configured, the app should not silently substitute local template questions for short or failed AI batches.
- Keep cloud calls behind the backend service; the iOS app must never contain Bedrock, AWS, or other model-provider secrets.
- Cap batch size in the backend. The Bedrock Lambda defaults to 20 questions per call even if the app requests a larger bank.
- Rate-limit backend calls by anonymous app install ID and source IP before calling Bedrock.
- Retry malformed model output in the backend and use a configured fallback model before returning a generation error.
- Use backend generation only when:
  - the bank is low
  - the user refreshes
  - Automatic provider routing has an internally configured backend endpoint and no on-device Apple Foundation model is available
  - the app explicitly selects Backend generation internally
  - the app needs better quality than templates
