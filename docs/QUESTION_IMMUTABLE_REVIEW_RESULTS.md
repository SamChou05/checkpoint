# Immutable teaching audit: first live result

September 8, 2026 UTC. The [six-case frozen trial](QUESTION_IMMUTABLE_REVIEW_EXPERIMENT.md)
stopped after its first call. The model identified the three targeted photography
feedback defects, but one internal diagnostic issue was 283 characters, exceeding
the contract's 280-character limit. The primary result is therefore a malformed
review and operational failure, **not a completed six-case correctness pass**.
The other five cases were not dispatched. No question was accepted or returned.

The response finished normally in 40.399 seconds with 1,300 input and 2,632 output
tokens, one reasoning-content block and `end_turn`. It did not reach the 16,000
output-token allowance. The three issue lengths were 234, 283 and 190 characters.
Outer Markdown fences were accepted by the existing JSON parser; they did not
cause this failure. Raw text was not shortened, repaired or resubmitted.

## What the raw response establishes

The auditor selected the warranted aperture answer, rated the controlled question
at difficulty 2, marked the main and shutter explanations unsupported, and set
overall validity false. It specifically identified:

1. The main explanation says no other listed change affects depth of field,
   although the 85 mm lens changes it and its own explanation acknowledges that.
2. The claimed sharpness coverage of both row distances is not established by
   the task or the supplied qualitative reference summary.
3. The shutter explanation says it only changes exposure, although shutter
   duration also affects motion rendering.

These match the predeclared defects. The second issue additionally invokes
unspecified standard depth-of-field calculations and calls coverage borderline
and format-dependent. No calculation was executed or captured in this trial;
that extra assertion is not external evidence. The missing coverage guarantee
can be identified directly from the stated information without that assertion.
These are offline assistant assessments of the raw response, not a rerun or
retroactive acceptance of its malformed contract.

## Concrete change indicated

The 280-character limit was incorrectly shared in spirit with learner-facing
feedback even though `issues` is internal diagnostic text. Its overrun prevented
recording an otherwise explicit rejection and stopped unrelated cases. Separate
the diagnostic contract from display bounds: ask for concise issues while allowing
a bounded longer note. Keep all learner-facing limits and immutable-content
requirements unchanged, retain strict types and issue count, and bound the whole
review response before parsing. An approving overall verdict must still be unable
to override any issue or unsupported field.

The original trial remains failed. Any follow-up needs a new frozen plan and
output directory. The five unattempted controls still need actual observations,
especially whether sound counterparts are retained and the internally consistent
wrong all-pairs answer is rejected. One correctly criticized bad-feedback item
does not establish that complete-item authoring works, prove correct feedback on
new questions, or qualify production integration. No deployment or model
promotion occurred.

## Evidence

- [Original frozen plan](evidence/immutable-review-plan-20260908.json)
- [Exact terminal capture](evidence/immutable-review-capture-20260908.json)
- [Exact replay of the failed prefix](evidence/immutable-review-replay-20260908.json)

The capture's byte SHA-256 is
`6c2d67c0c85a61956cf51d81018869ddfd291242614be1c2a8e8dd5a6e14ce1b`.
Replay and full plan reconstruction succeed from the original isolated source
`976060f3068084deb87c24f3f545697ed142a3b7` using Python 3.12.11 and
boto3/botocore 1.43.89. They show one dispatch and no completed review observation.
Private reasoning and credentials are absent. Replay verifies consistency, not
the factual truth of a model's judgments or provider authenticity.
