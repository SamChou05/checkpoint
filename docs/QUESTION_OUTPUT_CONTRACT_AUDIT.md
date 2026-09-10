# Question output contract audit

Date: September 9, 2026.

Scope: the checked-in question author, solver, reviewer, HTTP/bank response,
Swift decoding, sanitization, grading, and question view. This is a code and
automated-test audit, not a live-model quality evaluation or a deployed-service
certification.

## Assessment

The pipeline uses structured JSON content with application-enforced validation.
It does not yet use provider-native schema-constrained generation. The main
question fields have a consistent mapping through the backend and into SwiftUI.
Four reproduced edge cases required fixes: nonfinite author numbers, unknown
final-review fields, multiline numbered question text, and Unicode length counting.

## Which instructions reach the model

`BackendQuestionRequest` encodes goal context, the skill map, allocations,
difficulty, history, and source text as data. It does not send the Swift
`QuestionGenerationRequest.sourcePrompt` string to Bedrock. That string is kept
as local diagnostic context and is also used by the separate Apple model path.
Its wording is not a verbatim record of the cloud request.

The cloud author receives `_system_prompt()` and `_user_prompt()` from
`question_generation.py`. The system prompt specifies the output object, field
names, four textual choices, exact answer membership, plain-text content, and
length guidance. The user prompt supplies the normalized task JSON and requested
count, scope, and difficulty. Both tell the model to return a JSON object. The
solver and reviewer each receive their own output contracts; the author schema
is not mistakenly reused for those calls.

## Field and stage agreement

| Content | Author and backend | App and UI |
| --- | --- | --- |
| Question | `prompt` string, self-contained, plain text; author is asked for at most 320 characters, backend accepts 12–360 Unicode code points | Stored as `CheckpointQuestion.prompt`; shown with `Text(question.prompt)`; minimum length uses the same code-point count |
| Choices | Exactly four distinct strings, at most 140 characters each | Validated, shuffled without rewriting reviewed text, rendered as four buttons |
| Answer key | `expectedAnswer` must match one choice; complete-choice solver and final reviewer must agree | Stored as text and graded locally using exact choice identity, independent of display order |
| Main feedback | Author drafts it; default final reviewer supplies the accepted explanation, at most 420 characters | Shown after answer checking; reviewed text is preserved |
| Choice feedback | Default reviewer supplies one explanation for each exact choice, at most 280 characters; optional authored-solution mode supplies none | Exact choice text selects the feedback; missing feedback falls back to the main explanation |
| Scope | Canonical `topic`, `skillID`, `objectiveID`, and objective name are assigned/validated against the supplied map | Associated with the goal, used for selection/progress; topic appears in a badge |
| Difficulty | Author labels it; final reviewer independently supplies an integer 1–5 meeting the requested floor/target | Stored, used for selection and adaptation |
| Verification | Service assigns provenance after review | Current policy required for member fresh practice; historical grading keeps its separate wire version |

The generated output does not define screen layout or executable UI. Code,
equations, passages, and other stimulus material must fit inside the plain-text
question/choice fields. There is no separate rich stimulus field in this wire
contract.

## Checks already present

- The provider adapter rejects token-truncated output and guardrail intervention
  before trying to parse content; reasoning blocks are not treated as answer text.
- The author parser rejects duplicate JSON keys. Markdown wrapping or a top-level
  question array can be recovered, but recovered questions still undergo the
  same validation and answer checks.
- The complete-choice solver requires the exact response shape and item indexes,
  one row per offered choice, one supported answer, three refuted alternatives,
  no uncertain choice, and agreement with the author's key.
- The final reviewer checks answer agreement, independently assessed difficulty,
  full choice-feedback coverage, and feedback bounds before assigning verification
  metadata. It rejects answer-letter references that would break after shuffling.
- Swift rejects incorrectly typed decoded fields. Missing legacy fields have
  compatibility defaults, but empty required content and invalid answer membership
  are rejected by sanitization before storage.
- Reviewed content and UTF-8 choice identity are preserved through decoding,
  sanitization, feedback selection, and grading. Unicode-equivalent choices that
  the UI cannot distinguish are rejected.
- Generation and replacement attempts have bounded provider-call budgets. Empty
  or rejected output does not become canned practice content.

## Reproduced defects and fixes

1. **Nonfinite author numbers could escape parsing and crash integer coercion.**
   Python's default JSON decoder accepts `Infinity` and turns the valid JSON
   number `1e309` into infinity. A `difficulty` with either value could raise
   `OverflowError` instead of following the controlled invalid-output path.
   The author parser now rejects nonfinite constants and overflowing float
   literals using the existing strict numeric parsing helpers.
2. **Unknown reviewer fields could hide a conflicting verdict.** A response with
   a supported `valid: true` field could also contain an extra `issues`,
   `validity`, or `repairedPrompt` field describing a defect, and the old parser
   ignored it. The reviewer envelope and item field names now have an explicit
   allowed shape; unknown fields reject the response instead of being discarded.
   The reviewer prompt explicitly states the allowed fields and the minimal
   negative-review form.
3. **Numbered multiline stimulus could pass the backend and be rejected by iOS.**
   Swift's embedded-answer-options detector allowed a wildcard to cross line
   breaks, unlike the Python detector. A valid question containing numbered
   pseudocode (`1) if x < 0:` followed by an indented assignment, then
   `2) print(x)`) was mistaken for answer options. Both detectors now use the
   same line-boundary behavior, covered by a shared fixture.
4. **Some short non-Latin questions passed Python and failed Swift.** Python
   counts Unicode code points, while Swift's default `String.count` counts
   grapheme clusters. The Hindi stem `कौन सा सम है?` has 13 code points but
   10 grapheme clusters, so the phone rejected it against a 12-character minimum.
   The app now uses Unicode scalar counts for that minimum, with a shared
   question fixture and a regression assertion.

## Remaining improvement: native constrained output

The current Bedrock request has no `outputConfig.textFormat` JSON Schema and no
strict tool definition. Saying “return only JSON” in a prompt does not constrain
the provider's decoder. Schema mistakes can still cost a rejection or another
model call even when the app ultimately receives valid data.

AWS documents a native JSON Schema mechanism for Converse through
`outputConfig.textFormat`; its model cards list support for
[Kimi K2.5](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-moonshot-ai-kimi-k2-5.html)
and [Claude Sonnet 4.6](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-sonnet-4-6.html).
The [supported schema subset](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)
does not enforce every application requirement, including string-length and
numeric-bound constraints. Native schema generation would therefore complement
the current validators and semantic checks, not establish factual correctness.

A follow-up implementation should define separate author, skill-map, solver,
and reviewer schemas, check the selected model/SDK capability, and qualify
end-to-end behavior and cold-schema latency before rollout. The default reviewer
uses arbitrary choice text as object keys; a portable closed schema may need
stable choice identifiers or feedback rows, with explicit conversion back to
the existing app contract. This audit does not enable a new generation mode or
change the deployed model.

## Verification

- **992 backend tests passed**, with no skips, using an isolated Python 3.12
  environment with `boto3` and `jsonschema` installed:

  ```sh
  cd backend/bedrock-question-service
  python -m unittest discover -s tests
  ruff check ./*.py tests evals
  python -m compileall -q ./*.py tests evals
  ```

- **102 iOS simulator tests passed**, with no skips, on Xcode 26.4.1 / iOS 26.4.1.
  The selected suites were `BackendQuestionEngineContractTests`,
  `QuestionValidationTests`, `QuestionContentPreservationTests`,
  `ReviewedStemPreservationTests`, `ReviewedFeedbackPreservationTests`,
  `VerificationPolicyFreshnessTests`, and `EmbeddedOptionsContractTests`.
- New backend regressions demonstrated failures before the fixes and success
  after them. A Swift source harness improved from six failures to zero across
  20 text-admission, persistence, and grading cases.
- Ruff, Python compilation, and `git diff --check` passed.

The model responses in these tests are controlled fixtures. These results verify
contract handling and preservation; they do not measure live model compliance,
answer accuracy, model latency, or the currently deployed app/service version.
No live inference, model change, native-schema rollout, or deployment was made.
