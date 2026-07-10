# AI Backend Contract

Checkpoint can generate multiple-choice questions through a backend endpoint when higher-quality generation is explicitly needed beyond Apple Foundation Models and Local Templates. A first AWS Bedrock Lambda implementation lives in `backend/bedrock-question-service`.

The iOS app sends a `POST` request to the endpoint configured by the app or backend service layer. The normal user-facing Settings screen does not expose provider or endpoint selection. Internal endpoint configuration can come from `Checkpoint/Config/Secrets.xcconfig`, the `CheckpointAIBackendEndpoint` Info.plist key, or the `CHECKPOINT_AI_BACKEND_ENDPOINT` launch environment value. For an exposed Function URL, configure `CheckpointAIBackendToken` or `CHECKPOINT_AI_BACKEND_TOKEN` and set the same value as `CHECKPOINT_BACKEND_TOKEN` in Lambda; never place AWS credentials in the app.

For local/TestFlight builds, copy `Checkpoint/Config/Secrets.example.xcconfig` to `Checkpoint/Config/Secrets.xcconfig`. Use the escaped URL style shown in the example (`https:/$()/...`) so Xcode does not treat `//` as an xcconfig comment.

The app includes an anonymous `X-Checkpoint-Install-ID` header on backend calls. The Bedrock Lambda can use that header, plus source IP, for daily quota counters. The install ID is a random UUID generated on-device and is not a user account identifier.

The optional Pro server reserve adds an authenticated, durable contract under `/reserve/*`. It is disabled until the user explicitly opts in. The client creates a separate 256-bit `X-Checkpoint-Install-Secret`, saves it in Keychain before registration, and sends it only over HTTPS. The backend stores only its SHA-256 hash. This credential authorizes only the anonymous installation's bounded goal reserve; it is not an account, purchase credential, or cross-device identity.

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
  "coveragePlan": [
    {
      "topic": "arrays",
      "avenue": "Edge case or constraint"
    },
    {
      "topic": "recursion",
      "avenue": "Misconception diagnosis"
    },
    {
      "topic": "Big-O",
      "avenue": "Comparison or tradeoff"
    }
  ],
  "existingPrompts": [
    "Explain the tradeoff to watch for when solving an arrays problem."
  ],
  "existingQuestionCoverage": [
    {
      "topic": "arrays",
      "subtopic": "hash-map lookup tradeoffs",
      "avenue": "Application",
      "prompt": "A two-sum scan uses a hash map. Which resource tradeoff does this make?",
      "expectedAnswer": "It uses additional memory to reduce repeated searches.",
      "difficulty": 3
    }
  ],
  "reportedPrompts": [
    "What is an array?"
  ],
  "reportedQuestionFeedback": [
    {
      "prompt": "What is an array?",
      "reason": "Too Easy",
      "note": "This only tests a definition.",
      "expectedAnswer": "A contiguous collection accessed by index.",
      "choices": [
        "A contiguous collection accessed by index.",
        "A recursive function call.",
        "A database transaction.",
        "A network routing rule."
      ],
      "explanation": "The keyed response only checks a basic definition.",
      "topic": "arrays",
      "subtopic": "array representation",
      "avenue": "Foundational concept",
      "difficulty": 1
    }
  ],
  "targetCount": 20,
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
      "subtopic": "call-stack depth limits",
      "avenue": "Comparison or tradeoff",
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
- `prompt` must contain no more than 280 characters.
- `subtopic` should name the concrete knowledge component being tested, rather than repeat a broad goal title.
- `avenue` must be exactly one of: `Foundational concept`, `Application`, `Comparison or tradeoff`, `Misconception diagnosis`, `Edge case or constraint`, `Transfer to a new scenario`, or `Interpretation or inference`.
- `coveragePlan` is optional. When present, each `{topic, avenue}` entry is a required generation target. The provider should return one question per slot, copy its topic and avenue exactly, and choose a new concrete subtopic for it before producing unplanned questions. A plan topic equal to `Infer a concrete subject-matter skill` is a skill-map placeholder: replace it with a stable concrete skill inferred from the learning target. A partial HTTP success can still leave slots unfilled; the client should retain valid items and request the remaining deficit later.
- Older app requests may omit `coveragePlan`, and older provider responses may omit `subtopic` and `avenue`. Without a plan, the backend defaults `subtopic` to the returned topic and `avenue` to `Application`; with a plan, a metadata-free item can fill the next slot, while an explicitly mismatched topic is rejected rather than relabeled.
- The backend accepts up to the most recent 120 entries from each prompt-history, structured-coverage, and structured-feedback list. The iOS client sends the newest 16 existing-question records and 8 reports, then dynamically removes the oldest paired history until the encoded body is at most 240 KiB. History arrays are ordered oldest to newest; the newest entries belong at the end.
- Do not reuse a `topic + subtopic + avenue` combination already present in `existingQuestionCoverage` or already accepted in the current batch.
- All 4 choices must be meaningfully distinct in wording and substance. Do not include near-synonyms or paraphrases of the same answer, such as `maps virtual addresses to physical addresses` and `translates virtual addresses to physical addresses`.
- Distractors should test different misconceptions, not restate the same mechanism with synonyms.
- Avoid prompts listed in `existingPrompts` and `reportedPrompts`, plus prompts in `existingQuestionCoverage`. The backend also rejects conservative high-overlap token near-duplicates across historical coverage and the current batch.
- `reportedQuestionFeedback` is optional structured quality feedback. Supported reasons are `Too Easy`, `Too Hard`, `Confusing`, `Wrong Answer`, and `Irrelevant`. `prompt`, `reason`, and `note` are the legacy-compatible core. A client should also include the bounded `expectedAnswer`, four `choices`, `explanation`, `topic`, `subtopic`, `avenue`, and 1-through-5 `difficulty` fields when available so answer-validity reports are actionable. A structured feedback prompt is automatically part of the duplicate blocklist even if it is not repeated in `reportedPrompts`.
- Prefer objective questions for MVP.
- Every question should be answerable in 30 seconds to 3 minutes.
- Questions should target weak topics and stay near the user's estimated level.
- If `minimumDifficulty` is above 1, avoid remedial/basic questions unless the target topic cannot support harder prompts.
- If generated questions come back below `minimumDifficulty`, the backend and app should drop them instead of promoting their numeric difficulty.
- Use `learningTarget`, `contentTopics`, `questionDirective`, competency estimates, and `minimumDifficulty` together when writing the prompt and assigning difficulty.
- If `goal.needsSkillMap` is true, infer 4 to 6 subject-matter skills from the learning target and use those skill names as returned question topics. The app uses the first generated topics to seed the Skill Map before background bank refill.
- Treat verbs in the title such as `study`, `prepare`, `pass`, or `learn` as user intent, not as the tested subject. For example, `Study for the LSAT` should produce LSAT Logical Reasoning or Reading Comprehension questions, not questions about how to study.
- Do not ask about study plans, productivity, motivation, app blocking, or next steps unless the learning target is explicitly study skills.

The backend and iOS app also validate batches before storage. They drop blank questions, duplicate prompts, reported prompts, questions below the configured minimum difficulty, missing topics, missing answers or explanations, missing choices, duplicate or near-duplicate answer choices, off-target study-strategy prompts, and prompt text over 280 characters. If a provider returns an expected answer that is not in the choices, the sanitizer can repair the choices by adding the expected answer before storage.

## Request Bounds and Ordering

- The UTF-8 JSON body must be at most 256 KiB. Larger or malformed base64 bodies receive `400` before a model call.
- The backend normalizes and clips individual request fields: title 160 characters, category 64, focus areas 800, learning target 240, question directive 1,200, difficulty guidance 600, up to 24 content topics of 80 characters each, and up to 20 competency records.
- Prompt-history, report prompts, and learner report notes are clipped to 280 characters. Structured coverage uses topic 48, subtopic 64, prompt 280, and expected answer 280. Structured report context uses the same prompt/answer limits, explanation 420, and at most four choices of 140 characters each. The client also applies UTF-8 byte-aware clipping before encoding.
- `coveragePlan` is capped at `targetCount`; entries with a blank topic or unsupported avenue are ignored.
- The complete normalized history remains available to deterministic duplicate validation. Before a Bedrock call, model-visible request context is independently capped at 48,000 characters. If necessary, the backend removes oldest redundant history from model context first while preserving the newest coverage and feedback.

## HTTP Completion Semantics

- `200` means at least one usable question survived validation. The `questions` array may contain fewer than `targetCount` after duplicate rejection, quality filtering, or exhaustion of the bounded retry budget.
- Clients should accept and cache every returned usable question, recompute their bank deficit and missing coverage slots, and refill later rather than discarding a partial top-off.
- `400` means the request could not be decoded or normalized, `401` means authorization failed, `429` means the daily generation quota was reached, and `502` means no usable provider question was available.
- One request makes at most three Bedrock Converse calls total across initial generation, malformed-JSON repair, fallback-model use, and sanitized top-off passes. A later provider failure does not discard usable questions already accepted earlier in the same request.

## Optional Server Reserve API

The synchronous generation request above remains available at the Function URL root. Reserve routes use `POST`, the configured bearer token, `X-Checkpoint-Install-ID`, and (including registration) the client-generated `X-Checkpoint-Install-Secret`.

### Register

`POST /reserve/register` with an empty JSON object conditionally registers the hash of the client-generated secret. The same installation and secret are idempotent. An existing installation with a different secret returns `409`; registration never rotates or returns a plaintext secret.

### Sync

`POST /reserve/sync` uploads the bounded generation snapshot for one goal:

```json
{
  "goalID": "4D8A4A43-0914-4EC6-B245-8FD695792F77",
  "goalRevision": "sha256-of-question-shaping-context",
  "desiredReserveCount": 20,
  "syncSequence": 12,
  "generationRequest": {
    "goal": {},
    "competencies": [],
    "existingPrompts": [],
    "existingQuestionCoverage": [],
    "coveragePlan": [],
    "reportedPrompts": [],
    "reportedQuestionFeedback": [],
    "targetCount": 20,
    "minimumDifficulty": 3,
    "difficultyGuidance": "..."
  }
}
```

`syncSequence` increases monotonically for one installation. A lower sequence returns `409`; the same sequence and request digest are an idempotent retry; the same sequence with different content returns `409`. `desiredReserveCount` is clamped to 0 through 20. Zero invalidates outstanding work and removes retained request/question content for that goal.

### Pull

`POST /reserve/pull` sends `goalID` and `goalRevision`. It returns no delivery when the reserve is still preparing, or one stable held delivery:

```json
{
  "state": "held",
  "preparedCount": 0,
  "delivery": {
    "deliveryID": "9bf37ad4-48f5-457a-b76d-a52bcb265f56",
    "goalRevision": "sha256-of-question-shaping-context",
    "questions": [
      {
        "reserveQuestionID": "3792788d-c8aa-43fd-8cca-76ce1b80197b",
        "prompt": "...",
        "expectedAnswer": "...",
        "choices": ["...", "...", "...", "..."],
        "explanation": "...",
        "topic": "...",
        "subtopic": "...",
        "avenue": "Application",
        "difficulty": 3,
        "format": "Multiple Choice"
      }
    ]
  }
}
```

Repeated pulls return the same delivery until acknowledgement. Held questions count toward the desired reserve, preventing an extra batch from being generated while delivery is outstanding.

### Acknowledge And Delete

`POST /reserve/ack` sends `goalID`, `goalRevision`, and `deliveryID`. Only that exact held delivery is cleared. A repeated successful acknowledgement is idempotent, while a stale acknowledgement cannot clear a newer delivery. Delivered prompt/coverage fingerprints remain in a bounded duplicate-avoidance history.

`POST /reserve/delete` accepts up to five `goalIDs` and idempotently removes those goal reserve records. Disabling the feature, deleting a profile, or resetting the app uses this route; backend TTL remains the fallback when the device is offline.

## Cost Rules

- Generate in batches, not per blocked-app attempt.
- Cache generated questions in the app.
- On goal creation or goal changes, prepare a 5-question AI-first ready set, then asynchronously top off the remaining question bank.
- When the cached bank runs low, request more AI questions before the user runs out of usable checkpoints.
- If an AI backend is configured, the app should not silently substitute local template questions for short or failed AI batches.
- Keep cloud calls behind the backend service; the iOS app must never contain Bedrock, AWS, or other model-provider secrets.
- Exposed backend URLs should fail closed without `CHECKPOINT_BACKEND_TOKEN`; only set `ALLOW_UNAUTHENTICATED_BACKEND=true` for controlled local/private testing.
- Cap batch size in the backend. The Bedrock Lambda defaults to 20 questions per call even if the app requests a larger bank.
- Rate-limit backend calls by anonymous app install ID and source IP before calling Bedrock.
- Retry malformed model output in the backend and use a configured fallback model within the shared three-call provider budget before returning a generation error.
- Use backend generation only when:
  - the bank is low
  - the user refreshes
  - Automatic provider routing has an internally configured backend endpoint and no on-device Apple Foundation model is available
  - the app explicitly selects Backend generation internally
  - the app needs better quality than templates

## Background Delivery Model

- The iOS client keeps the local bank as the latency boundary: a blocked-app attempt reads a complete cached set and never waits for live generation.
- The client submits `BGAppRefreshTask` and `BGProcessingTask` maintenance requests and fills the bank in backend-sized chunks. iOS chooses whether and when those tasks run, and normal background relaunch is unavailable after a force-quit.
- The optional server reserve persists one authorized, revisioned generation snapshot and at most one 20-question prepared-or-held batch per opted-in Pro goal.
- A global EventBridge recovery schedule and SQS worker continue bounded generation while the app process is absent. Revision-bound leases, refill epochs, daily worker quotas, failure backoff, and a DLQ make at-least-once queue delivery safe and cost-bounded.
- The app fetches only when the local usable or fresh reserve is low, saves stable question IDs locally, then acknowledges. The local bank remains the immediate-availability mechanism.
- The install ID alone remains anonymous rate-limit context and is never accepted as reserve authorization. Durable state additionally requires the locally generated installation secret and explicit user consent.
- See `docs/SERVER_QUESTION_RESERVE.md` for lifecycle, retention, recovery, and release-gate details.
