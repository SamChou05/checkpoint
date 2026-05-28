# AI Backend Contract

Checkpoint can generate multiple-choice questions through a backend endpoint when higher-quality generation is explicitly needed beyond Apple Foundation Models and Local Templates.

The iOS app sends a `POST` request to the endpoint configured by the app or backend service layer. The normal user-facing Settings screen does not expose provider or endpoint selection.

## Request

```json
{
  "goal": {
    "title": "Pass a coding interview in 8 weeks",
    "deadline": "2026-06-27T00:00:00Z",
    "category": "Coding Interview",
    "currentLevel": "Basic Python. Shaky on recursion.",
    "focusAreas": "arrays, recursion, Big-O",
    "learningTarget": "coding interview in 8 weeks",
    "contentTopics": ["arrays", "recursion", "Big-O"],
    "questionDirective": "Generate concrete coding-interview knowledge checks about arrays, recursion, Big-O: data-structure choice, algorithm behavior, complexity, edge cases, or debugging.",
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
  "minimumDifficulty": 3
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
- `format` must be `Multiple Choice`.
- `choices` should include 4 options.
- `expectedAnswer` must exactly match one item in `choices`.
- Avoid prompts listed in `existingPrompts` and `reportedPrompts`.
- Prefer objective questions for MVP.
- Every question should be answerable in 30 seconds to 3 minutes.
- Questions should target weak topics and stay near the user's estimated level.
- If `minimumDifficulty` is above 1, avoid remedial/basic questions unless the target topic cannot support harder prompts.
- Use `learningTarget`, `contentTopics`, `questionDirective`, current-level text, competency estimates, and `minimumDifficulty` together when writing the prompt and assigning difficulty.
- Treat verbs in the title such as `study`, `prepare`, `pass`, or `learn` as user intent, not as the tested subject. For example, `Study for the LSAT` should produce LSAT Logical Reasoning or Reading Comprehension questions, not questions about how to study.
- Do not ask about study plans, productivity, motivation, app blocking, or next steps unless the learning target is explicitly study skills.

The iOS app also validates batches before storage. It drops blank questions, duplicate prompts, reported prompts, questions below the configured minimum difficulty, missing topics, missing answers or explanations, missing choices, off-target study-strategy prompts, and oversized prompt text. If a provider returns an expected answer that is not in the choices, the sanitizer can repair the choices by adding the expected answer before storage.

## Cost Rules

- Generate in batches, not per blocked-app attempt.
- Cache generated questions in the app.
- Use backend generation only when:
  - the bank is low
  - the user refreshes
  - the user explicitly selects Backend generation
  - the app needs better quality than templates
