# Preserve the intended author and solver output order

The solver now asks for each concise reason before its supported/refuted/uncertain
verdict. Native output serialization preserves that order. The native author
contract also preserves the existing prompt's explanation-before-key-and-choices
sequence instead of alphabetizing those fields.

## Why these changes are connected

The [September 10 paired diagnostic](https://github.com/SamChou05/checkpoint/blob/b87086f3ddd827d900c574d9109bb87740b20194/docs/QUESTION_SOLVER_ORDER_RESULTS.md)
tested the same Sonnet 4.6 complete-choice solver with only its prompt example
and equivalent schema property order changed. Among 30 available scored
subject/repeat pairs, six had correct verdicts only with reason-first, 22 were
correct in both, and two in neither. Those six improvements span four subjects.
Independent assessment found seven verdict/reason contradictions among 36
available scored judgment-first responses and none among 30 reason-first
responses. Ten of 40 planned pairs were incomplete. This supports the specific
ordering adjustment, not a general correctness guarantee.

The author had a separate compatibility defect. Its existing prompt uses
`prompt, explanation, expectedAnswer, choices, ...`, an intentional correction
recorded in [the release history](LEARNING_MAP_RELEASE.md). The native schema
declared the older choices-before-explanation layout, and recursive key sorting
then transmitted the required fields as
`choices, difficulty, expectedAnswer, explanation, format, prompt, topic`.
Consequently, native mode reversed the established explanation-before-answer
sequence even though the prompt text was unchanged. Merely removing sorting
would preserve the older, still conflicting schema declaration.

## Contract behavior

| Stage | Native output property order |
| --- | --- |
| Author, required fields | `prompt, explanation, expectedAnswer, choices, topic, difficulty, format` |
| Author, optional metadata | `skillID, objectiveID, objective` |
| Each solver choice | `choice, reason, judgment` |

Required properties may be emitted before optional properties, as described in
[Anthropic's structured-output documentation](https://platform.claude.com/docs/en/build-with-claude/structured-outputs#property-ordering).
The author's required-field sequence matches the corresponding projection of
the existing prompt. Optional metadata remains optional.

The schemas' fields, types, required arrays and acceptance semantics stay the
same. A small serialization step restores intentional order only at the author
item and solver choice paths after canonical serialization. Other contracts
retain their existing bytes. Contract metadata hashes the actual schema string
sent to the provider, so the two changed transport identities are visible.

Legacy solver requests receive the revised prompt example without a native
schema. Native solver requests receive both. Legacy author instructions already
had the intended sequence and are unchanged. No model, thinking setting, token
allowance, character limit, solver veto, answer-key ownership, reviewer decision
rule, persistence behavior or deployment default changes.

This branch includes the separate [source-instruction correction](QUESTION_SOURCE_EVIDENCE_CONTRACT.md).
The ordering experiment did not include that correction. The combined candidate
therefore still needs full-workflow qualification; its behavior cannot be
claimed from the isolated ordering trial.

## Verification and remaining work

Provider-boundary regressions inspect the actual built system prompts and
serialized schemas, including required/optional projection and metadata hashes.
Schema-equivalence and gate tests preserve admission behavior. Historical
diagnostics load explicit archived contracts only inside tests; their production
source and prompt guards continue to refuse changed-source execution.

Validation passed with Python 3.12.11 and boto3/botocore 1.43.91: all 1,138
backend tests, the 85 focused contract/pipeline/historical-probe tests, Ruff and
diff checks. Tests inspect actual request construction using scripted responses;
they do not establish provider obedience or question accuracy. The transmitted
author schema SHA-256 is
`76fcf193d302609a08a116d9a168e0b8dfc9ea662a44fb5287cf7ca46b9294f5`;
the solver schema SHA-256 is
`12ad4fefd897015baa60b400ae9b6f3006aeeda34b57de1dabfb344f5e6c5e61`.

The original trial still falsely admitted the same unsupported-third-operand
question in both arms and both repetitions. Output consistency does not prove
factual support. A full-workflow qualification must inspect fresh stems, all
choices, keys and every final teaching field, with format losses kept separate
from factual catches. Native author model obedience, complete question quality
and production delivery are not established by the local regressions.

No deployment has occurred for this candidate. The original experiment and its
execution claim remain untouched; do not restart it to fill missing responses.
