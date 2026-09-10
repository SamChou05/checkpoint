# Cloud-agent implementation prompt: native structured outputs

Implement provider-native structured JSON output throughout Checkpoint's Bedrock
question pipeline, with explicit contracts from generation through validation to
the existing iOS UI. Deliver the implementation, meaningful tests, documentation,
and a reviewable PR. This is an implementation task, not another audit or a
prompt-only improvement.

## 1. Repository and starting point

Repository: https://github.com/SamChou05/checkpoint

Start from current `origin/main` in an isolated checkout and a `codex/` branch.
Ensure the branch includes audit commit
`3f695942672d9f7f65d1a830dfa891def88e29a1` or its changes; do not reset newer work.
Follow `AGENTS.md`: make cohesive verified commits, stage only your files, run
relevant checks and `git diff --check`, and push safely to the tracked branch.
Never force-push to resolve divergence. Other agents have unrelated learning-map
and author-experiment work; keep that out of this change.

Read first:

- `docs/QUESTION_OUTPUT_CONTRACT_AUDIT.md`
- `docs/AI_BACKEND_CONTRACT.md`
- `backend/bedrock-question-service/README.md`
- `docs/QUESTION_COMPLETE_CHOICE_RUNTIME_POLICY.md`
- `docs/QUESTION_AUTHORED_SOLUTION_CONTRACT.md`
- `docs/QUESTION_AUTHOR_SCHEMA_EXPERIMENT.md`
- `docs/QUESTION_TASK_OBSTRUCTION_SCHEMA_FIX.md`

The audit already fixed four issues: nonfinite/overflowing author numbers,
undeclared final-review fields, Swift rejecting numbered multiline stimulus,
and Python/Swift counting short Unicode stems differently. Preserve these fixes
and their regressions. Its recorded baseline was 992 backend tests and 102
targeted iOS tests passing; newer main may contain more tests.

## 2. Current behavior and intended outcome

Checkpoint turns a user's learning goal into a reviewed Skill Map, generates
questions for its skills/objectives, verifies them, caches them, and presents
multiple-choice checkpoints in SwiftUI.

Current production-path code asks the model to return JSON, then parses and
validates its text. It does not send native output constraints in the Bedrock
Converse request. Implement those constraints so schema correctness is enforced
by the provider as well as checked by the application.

The app sends structured goal, map, difficulty, history, allocation, and source
data. The actual cloud system/user prompts are built in `question_generation.py`.
Swift's `QuestionGenerationRequest.sourcePrompt` is diagnostic context and part
of the separate Apple-model path; it is not the cloud prompt sent to Bedrock.
Do not “fix” only that Swift string.

Keep the existing semantic process: author -> structural validation -> independent
complete-choice solver -> final reviewer -> accepted bank -> Swift decoding and
sanitization -> cached session -> UI/local grading. Native JSON correctness does
not establish factual accuracy, unique answers, appropriate difficulty, or sound
teaching. Keep those separate checks.

## 3. Implement explicit contracts for every stage

Introduce a small versioned runtime contract/schema layer. Pass an explicit
stage/contract identifier through `_generate_with_bedrock` and every relevant
caller, including retries, JSON repair, top-ups, fallback attempts, synchronous
requests, asynchronous workers, skill-map inference, and evolution. Never infer
the stage by matching prompt text or assume every call uses the author schema.

Provide separate native schemas and matching native prompt instructions for:

1. **Question author:** `questions` containing `prompt`, `choices`,
   `expectedAnswer`, `explanation`, `topic`, `difficulty`, `format`, and compatible
   skill/objective tags. Preserve behavior both with and without a supplied map.
2. **Skill-map inference:** `skills` containing `name` and `objectives` with
   `name`. The server assigns IDs. Code enforces 3–6 skills and 2–5 objectives.
3. **Skill-map evolution:** `changes` containing `action: "advance"`,
   `predecessorSkillID`, and `successor` with name/objectives. This is the model's
   shape; the server constructs the different app-facing map/replacements shape.
   Keep predecessor coverage, server-owned IDs, versioning, and stale-map checks.
4. **Complete-choice solver:** `solutions` containing question `index` and
   `choices` rows with exact `choice`, `judgment`, and `reason`. Judgments must
   support `supported`, `refuted`, and `uncertain`. The schema must permit zero
   or multiple supported answers; application code decides whether to accept.
5. **Default final reviewer:** preserve index, valid/invalid verdict, exact
   answer, independently assessed difficulty, main explanation, and per-choice
   feedback. Rejection must remain expressible without inventing an answer or
   learner feedback. Keep a supported union or explicitly documented negative
   representation and a strict adapter to the existing reviewer contract.
6. **Optional authored-solution reviewer:** its distinct fields are `index`,
   `valid`, `answer`, `difficulty`, `explanationSupport`, and `issues`.
   Support all existing negative/uncertain states. Preserve the author's immutable
   explanation; never substitute reviewer-written teaching or silently remove
   incoming choice feedback. Do not enable this unrelated opt-in mode by default.

Keep legacy stem-only solver/reviewer imports and frozen evaluation prompts
compatible. If they remain available, explicitly retain legacy transport or give
them separate contracts. Do not silently reinterpret historical evidence.

Use the current documented Converse interface:

```json
{
  "outputConfig": {
    "textFormat": {
      "type": "json_schema",
      "structure": {
        "jsonSchema": {
          "name": "checkpoint_stage_v1",
          "schema": "<serialized JSON Schema>"
        }
      }
    }
  }
}
```

Schemas should be static, closed, versioned, and reusable. Specify types,
required fields, enums, and `additionalProperties: false` where supported.
Do not put actual goals, choices, answers, UUIDs, or requested counts into schema
definitions; those belong in task data and application validation. Stable
serialization should permit grammar reuse and deterministic schema hashes.
Return fresh wrappers so mutating one request cannot alter another's schema.

Existing eval-only examples are in `evals/checkpoint_author_schema_eval.py` and
`evals/claim_evidence_schema.py`. Reuse their design lessons, not runtime imports
from `evals`. Keep schema declarations, stage prompts, adapters, and validators
aligned through focused contract tests.

## 4. Resolve feedback keys without changing the app contract

The default reviewer currently returns `choiceExplanations` as an object keyed
by arbitrary exact choice text. That conflicts with a static closed-object schema.

Prefer a provider-only array such as:

```json
{"choiceFeedback":[{"choice":"exact offered text","explanation":"..."}]}
```

Validate every row before converting it to the existing `choiceExplanations`
dictionary. Require exactly one row per offered choice for accepted items;
reject duplicate, missing, foreign, malformed, or unexpected rows/fields.
Never let dictionary construction silently overwrite duplicates. Preserve exact
choice bytes and feedback text. If choosing internal choice IDs instead, validate
their exact mapping and keep them out of visible answers and learner feedback.

Update the native reviewer prompt to describe the native shape. Preserve the
existing shape in explicitly selected legacy mode. Validate native output before
adapting it so unknown or contradictory fields cannot disappear during conversion.

The external app response must remain compatible: textual `prompt`, four textual
`choices`, textual `expectedAnswer`, `explanation`, `choiceExplanations`, topic,
skill/objective metadata, difficulty, stable question ID, and service-owned
verification metadata. No frontend redesign or data migration should be needed.

Keep wire verification version 1, current complete-choice policy revision 2,
and optional authored-solution revision 3 unless a separate semantic-policy
change actually warrants a revision. Native schema enforcement alone does not.

## 5. Preserve validation, provider behavior, and compatibility

Retain strict JSON duplicate-key and finite-number checks, unknown-field
rejection, exact question-index/choice coverage, exact answer agreement, literal
content preservation, Unicode ambiguity checks, and correct feedback binding.
Keep count, length, scope, skill/objective, duplicate-history, and difficulty
checks in application code when the provider schema cannot express them.
Preserve code indentation/newlines and the shared multilingual regressions.

Do not constrain the model to approve an item: allow false, uncertain,
unsupported, empty-answer, and issue-bearing results where the stage supports
them. Never expose the author's key to an answer-blind stage through a schema,
prompt, adapter, or telemetry. Keep the authored-solution review's existing
visibility rules distinct from the default review.

Preserve reasoning/sampling settings, guardrails, IAM scope, quotas, durable
provider-call accounting, deadlines, retry ceilings, and accepted partial work.
Reject truncated/refused/failed outputs before admission even if their text parses.
Schema errors must not create uncounted calls or automatic unconstrained retries.

Add explicit documented configuration for native and legacy modes. In native
mode, every applicable call and retry must send the right schema. Unsupported
models/SDKs or service schema errors must produce a clear bounded failure;
do not silently remove constraints or switch models. Preserve the current mode
as an explicit rollback option. Wire configuration through SAM/deployment
settings and tests, with rollout disabled until qualification is complete.

Check actual configured author, worker, skill-map, reviewer, and any fallback
model IDs/profile ARNs independently. Do not assume one capability from another.
Confirm botocore understands the request in the **built Lambda artifact**.
The service uses SAM/Python 3.12; updating `evals/requirements.txt` does not upgrade
the deployed SDK. Add a reproducible runtime dependency/package strategy if needed.

## 6. Use existing evidence and qualify the provider boundary

Re-check current primary documentation:

- https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html
- https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-moonshot-ai-kimi-k2-5.html
- https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-sonnet-4-6.html

Use Bedrock's supported subset, not merely general JSON Schema validity. The repo
records a real provider rejection of an enum combined with `type:["string","null"]`;
an `anyOf` string-enum/null representation fixed it. Preserve rejection semantics
when expressing nullable or alternative shapes.

The earlier Opus 4.6 author-only experiment had native calls around 146 and 139
seconds, beyond the runtime's 100-second read-timeout maximum. It did not prove
production-ready latency or better correctness. Those results are limited to
that experiment, not measurements of every model. Do not silently raise timeouts,
budgets, or worker concurrency to make a smoke test pass.

Provide a dry-run qualification plan. If an already authorized test environment
is available, use synthetic goals and a fixed small live-call budget, at most
12 provider attempts including retries, to exercise selected native contracts
and first/repeated requests. Otherwise finish the implementation and offline
tests and state exactly which external qualification remains unavailable.
Do not describe first/repeated calls as confirmed cold/warm unless cache state
is observable. Record normal completion, service compatibility, schema results,
semantic rejections, latency, tokens, and call accounting separately.

Keep metrics bounded and free of learner text, answer keys, credentials, and
reasoning content: stage, selected mode, schema name/version/hash, provider
outcome, elapsed time, token/call counts, and classified validation failures.

## 7. Tests, completion criteria, and handoff

Add meaningful tests for:

- Every stage's positive and negative schema shapes, types, enums, missing/extra
  fields, stable serialization, and independence from per-question data.
- Correct schema and matching prompt on initial/repair/top-up/fallback requests,
  including worker and skill-map paths; explicit enabled/disabled/unsupported modes.
- Exact SDK request validation using the packaged botocore service model.
- Malformed, duplicate-key, nonfinite, truncated, and rejected responses;
  missing/duplicate/foreign indexes and choices; unknown verdict fields.
- Strict feedback-array conversion, byte preservation, shuffling, local grading,
  and display-feedback compatibility with the current Swift wire contract.
- Zero/multiple supported choices, uncertainty, answer disagreement, rejected
  reviews, and immutable authored explanations remaining unaccepted as appropriate.
- Retry/deadline/quota accounting and preservation of already accepted work.

Run the full backend suite, Ruff, compileall, and relevant SAM validation/build
checks. Run the existing iOS contract/preservation suites if macOS/Xcode is
available; otherwise report that limitation and include shared fixtures and CI
instructions. Never claim unrun checks passed. Keep historical captures unchanged.

Useful backend files under `backend/bedrock-question-service` include
`question_generation.py`, `question_quality.py`,
`question_verification.py`, `complete_question_solution.py`, `question_teaching.py`,
`skill_maps.py`, `request_contract.py`, `question_bank_worker.py`, and `template.yaml`.
App counterparts include `Checkpoint/Services/BackendPayloads.swift`,
`Checkpoint/Services/BackendQuestionBankClient.swift`,
`Checkpoint/Services/QuestionBatchSanitizer.swift`,
`Checkpoint/Models/QuestionModels.swift`, `Checkpoint/Models/AnswerGrader.swift`,
and `Checkpoint/Views/CheckpointAttemptView.swift`.

Finish with a reviewable PR covering the implemented native mode, unchanged
public contract, runtime dependency strategy, tests, rollout/rollback settings,
and measured versus unmeasured qualification. Success means the real runtime
paths use their native schema when enabled and still enforce all existing
acceptance checks—not just that a schema file or isolated demo exists.

Prepare the change for deployment review. Do not deploy, enable it in production,
change the selected model, or claim improved factual accuracy as part of this task.
