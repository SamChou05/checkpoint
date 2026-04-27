# AI Backend Contract

Checkpoint can generate multiple-choice questions through a backend endpoint when Apple Foundation Models is unavailable or when higher-quality generation is needed.

The iOS app sends a `POST` request to the endpoint configured in Settings.

## Request

```json
{
  "goal": {
    "title": "Pass a coding interview in 8 weeks",
    "deadline": "2026-06-27T00:00:00Z",
    "category": "Coding Interview",
    "currentLevel": "Basic Python. Shaky on recursion.",
    "focusAreas": "arrays, recursion, Big-O",
    "preferredQuestionStyle": "Multiple Choice"
  },
  "competencies": [
    {
      "topic": "arrays",
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
  "targetCount": 40
}
```

## Response

```json
{
  "questions": [
    {
      "prompt": "What is the time complexity of scanning an array once to find a maximum value?",
      "expectedAnswer": "O(n)",
      "choices": ["O(1)", "O(log n)", "O(n)", "O(n^2)"],
      "explanation": "You inspect each element once, so runtime grows linearly with input size.",
      "topic": "arrays",
      "difficulty": 1,
      "format": "Multiple Choice"
    }
  ]
}
```

## Response Rules

- Return only valid JSON.
- `difficulty` must be 1 through 5.
- `format` must be `Multiple Choice`.
- `choices` should include 4 options.
- `expectedAnswer` must exactly match one item in `choices`.
- Avoid prompts listed in `existingPrompts` and `reportedPrompts`.
- Prefer objective questions for MVP.
- Every question should be answerable in 30 seconds to 3 minutes.
- Questions should target weak topics and stay near the user's estimated level.

The iOS app also validates batches before storage. It drops blank questions, duplicate prompts, reported prompts, missing topics, missing answers or explanations, missing choices, answers that do not match a choice, and oversized prompt text.

## Cost Rules

- Generate in batches, not per blocked-app attempt.
- Cache generated questions in the app.
- Use backend generation only when:
  - the bank is low
  - the user refreshes
  - Apple Foundation Models is unavailable
  - the app needs better quality than templates
