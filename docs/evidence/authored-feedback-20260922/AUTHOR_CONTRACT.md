# Inactive author and immutable learner-payload prototype

This is a proposal and offline implementation, not a frozen trial or production route. No provider was called. Historical schemas, prompts, captures and policy revisions remain unchanged. The companion reviewer prototype is owned separately.

The author supplies the full question, exact four choices, exact key, main explanation and all four choice explanations before independent solving and final review. A later reviewer must be able to accept or reject the frozen content without writing replacement learner text. This addresses the unchecked final writer while retaining a possible three-call author → solver → immutable reviewer pass. It does not establish that authored content or an accepted model verdict is true.

## Native shape and deliberate text order

`author_schema(count)`, `output_config(count)` and `metadata(count)` require a trusted integer count from 1 through 40; booleans and all other types are invalid. The native `questions` object contains exactly the required keys `"0"` through `str(count - 1)`. There are no model-authored indexes, question arrays, optional output identities or response fields that can mint verification. Each schema is named `experimental_authored_feedback_author_v1_nN`.

Each closed question row has the following property order:

1. `prompt`
2. `choices`, a closed object with string slots `a`, `b`, `c`, `d`
3. `explanation`, the main learner explanation
4. `choiceFeedback`, a closed object with one string explanation at each of the same four slots
5. `correctChoice`, one of the four slot names
6. `topic`, `difficulty`, `format`, and optional `skillID`, `objectiveID`, `objective`

The serialized schema preserves that order rather than alphabetically placing the key ahead of the question. This ordering is an implementation choice for the proposed contract, not evidence that the new shape has been provider-qualified. A future writer prompt must request all five complete explanations and remove the existing main-only instruction that forbids choice feedback; this pure module supplies no writer prompt or inference configuration.

Native shape enforces exact item identities, exact feedback/choice slots, types and the key-slot enum. Strict local checks add length bounds, exact duplicate-choice rejection, complete feedback association, UTF-8 validity, and difficulty range. No schema length keyword is relied upon. All objects reject extra properties. Metadata fields remain data, are preserved exactly when present, and receive no defaults; later scope/allocation validation remains necessary.

## Adaptation and frozen content

`adapt_author_response(raw, expected_count=N)` accepts strict JSON text only. Duplicate JSON keys, nonfinite numbers, fences, trailing material, missing/extra identities, malformed sibling rows and embedded indexes reject the entire response. It restores the ordinary question list in trusted numeric-ID order, regardless of JSON object ordering.

The adapter reads choices in trusted `a`–`d` slot order. It checks all four exact choice strings for duplicates **before** constructing a feedback dictionary, so distinct feedback in two duplicate-text slots cannot overwrite one another. It then resolves `correctChoice` to the exact corresponding choice text and maps each feedback slot to that same exact choice. It never decides correctness from explanation prose.

`freeze_learner_payload(payload)` accepts exactly these five fields:

```text
prompt: string
choices: four exact strings
expectedAnswer: one exact offered string
explanation: string
choiceExplanations: exactly one string for every exact offered choice
```

The prompt must contain 12–320 characters, each choice 1–140, the main explanation 12–420, and each choice explanation 12–280. Minimum lengths inspect nonblank content using `strip()`; maximum lengths count the original string. Every returned string retains its original whitespace, line endings, Unicode codepoints and UTF-8 bytes. Text is never trimmed, clipped, case folded, Unicode normalized or repaired. Unpaired Unicode surrogates are rejected because they cannot form valid UTF-8. Rejected input is not partly emitted.

The frozen payload is an independent deep copy, not a new immutable Python type. `learner_content_digest(payload)` validates the complete learner fields and hashes canonical JSON containing those exact strings and choice order. A later caller must retain the frozen copy privately and compare its digest before release. No validator or digest assigns verification, semantic approval, or a policy stamp.

## Integration obligations and limits

The new mode still needs complete key-blind solving, key-independent slot ordering, all six semantic pair judgments, exact key agreement, full-feedback immutable review and difficulty admission. The solver must not see the author key or any of the five explanations. The immutable reviewer must not receive solver verdicts/reasons as evidence. Its view of the authored teaching can itself disclose the intended answer even if the explicit key is hidden.

The caller owns normalized-choice eligibility, shuffle-safe prose checks, goal/source scope, allocation, historical coverage, deadline/quota accounting and versioned provenance. Normalization cannot silently rename a choice and leave its feedback bound to an older string; this prototype preserves both exactly. The current main-only `authored_solution` flag and revision 3 must not silently acquire a different contract. Existing revision 4 specifically identifies pair solving followed by reviewer-written teaching and also cannot be relabeled as this new mode.

Exact duplicates are structural errors. Different strings such as `2` and `two`, or composed and decomposed Unicode, deliberately remain separate input strings here. Whether they express equivalent proposed answers depends on the task and belongs to later admission. A regression intentionally passes a structurally valid but factually wrong key, duplicate meanings and shuffled-position prose, showing that this module is not a semantic gate.

Producing all feedback earlier moves token and latency work into the author; it does not prove the three-call pipeline will meet the worker deadline or preserve useful yield. Closed count-specific schemas may also have different provider preparation behavior. Fresh full-pipeline measurements are required before routing changes. Prior failed trials and their frozen reason-fidelity criteria remain unchanged; a future production quality assessment should distinguish incorrect learner content from a private review reason's incidental wording when the item and decision are independently sound.

## Offline verification

Twenty focused tests pass using the existing reliability virtual environment. They cover all 40 supported counts and malformed identity sets; all 24 question-map orders; all 24 choice-slot orders with four keys (96 combinations); every exact duplicate pair; exact choice/feedback binding; text boundaries; Unicode and CRLF preservation; no replacement/policy fields; strict JSON/types; complete-batch failure; deep-copy isolation; hash sensitivity; and the explicit absence of semantic approval. Exported schemas also pass `jsonschema` checks in tests. The module itself uses only the Python standard library.

Ruff passes for the two owned Python files. These tests exercise deterministic application behavior only. No live author output, throughput qualification, deployment, bank write or new correctness claim results from this prototype.
