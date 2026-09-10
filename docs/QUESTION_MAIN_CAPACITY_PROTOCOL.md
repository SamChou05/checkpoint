# Does explanation capacity improve complete fresh questions?

Completed September 9: [results and retained evidence](QUESTION_MAIN_CAPACITY_RESULTS.md).
The pre-dispatch design below is preserved.

The [author-model comparison](QUESTION_AUTHOR_MODEL_COMPARISON_RESULTS.md) lost
six of twelve candidates to oversized mains, including some supported but basic
teaching. The [fresh authored-solution run](QUESTION_AUTHORED_SOLUTION_FRESH_RESULTS.md)
also lost four of six candidates to length checks. These exclusions are not
semantic detection: several excluded items had incorrect or underqualified
content. A [larger-stem comparison](QUESTION_STEM_LENGTH_RESULTS.md) did not
establish a clear benefit. Do not repeat that intervention or treat a larger
model output-token allowance as a remedy for learner-text limits.

This is a six-call author-only experiment. It asks whether changing the main
explanation instruction produces more complete, useful fresh items, separately
from the deterministic effect of a larger admission limit. It does not run or
widen the production verification pipeline, client limits or bank admission.
Both arms receive the same independent assessment procedure after capture.

## Frozen intervention

Use the three [goal/source packets](QUESTION_MAIN_CAPACITY_SOURCES.md): SQL joins
and NULL, musical intervals/transposition/inversions, and photographic exposure
tradeoffs. Each requests two MCQs at minimum difficulty 3. These exact packets
and questions are fresh; the broad domains have appeared in prior evaluations.
Source material consists of explicitly labeled, bounded paraphrases of primary
references, not acquired full-page evidence or ready-made questions and answers.
Only each case's payload enters the normalized author context; assessor notes,
provenance metadata and arm labels remain outside model inputs.

Capture the actual current author request under the balanced prompt and
`authored_solution` feedback contract. The current arm retains the exact main
instruction of at most 320 characters. In the expanded arm replace only that
number with 900, asserting one exact replacement and otherwise identical paired
requests. Stems remain limited to 320 characters and choices to 140. Preserve
the instruction that premises belong in the question rather than only in feedback.

Both arms use Kimi K2.5, disabled thinking, 6,000 output tokens and temperature
0.2. Interleave current/expanded for SQL, expanded/current for music, and
current/expanded for photography. There are six requests and twelve requested
candidate slots. No previous generated content or judgment enters a later call.
Freeze committed source/dependency hashes, the fixture, normalized inputs and
all provider requests before dispatch. Use one SDK attempt per request, read75 /
connect3 and the existing 90-second disposable-worker allowance. Cap serialized
input at 32 KiB per request and 192 KiB overall. No repairs, retries, top-ups,
replacement questions, source fetches during the trial, or resumed captures.

Persist every request before dispatch, exact final responses and progress,
stop reasons, usage/unknowns and cleanup observations. Operational, unfinished or
unusable provider responses stop remaining calls. Empty or whitespace-only final
text is retained with its usage but marked invalid by a trial-local response
projector; the shared supervisor remains unchanged. Nonempty completed text is
retained even when its question JSON is malformed, and does not trigger a repair
or replacement. Reuse the existing worker supervisor and exact
no-client terminal replay. This experiment adds no model review votes.

## Independent assessment and denominators

Keep every raw response and every unambiguous question occurrence, including
oversized items, unexpected counts and contract failures. Do not sanitize,
truncate, shorten, or repair content before assessment. Report strict JSON
envelope validity separately; the current strict parser accepts a whole JSON
object or a sole JSON-fenced object, but not surrounding prose, duplicate keys
or bare arrays. Ambiguous or missing content is not a success.

Give two independent assistant assessors opaque shuffled question IDs, raw goals,
source summaries, and exact stems/choices, withholding arm, author key, main,
model difficulty and length outcomes. Save both first passes before revealing
the unchanged mains. Save teaching assessments before unmasking the arms. Main
length may suggest the arm, so this is partial masking rather than a guarantee
against inference. These assessments are not human expert or learner calibration.

For each item assess the uniquely warranted answer, complete premises, three
distinct plausible distractors, goal fit, actual cognitive demand and a fully
supported worked explanation. Preserve uncertainty and disagreements. Correct
keys with false teaching, missing qualifications, weak alternatives or work below
difficulty 3 do not meet the complete-content endpoint. Longer wording and more
steps stated in prose do not themselves establish greater cognitive demand.

After content assessments, report every raw item against both virtual main
admission limits, 420 and 900, and separately against its arm's author instruction,
320 or 900. Keep all other current content limits visible. These are hypothetical
length observations, not claims that an item would pass production verification.
Missing requested slots remain failures; extra items are retained but cannot
substitute selectively for defective requested slots.

The primary observation is complete-content item counts per six requested slots
in each arm, followed by counts within each virtual limit. A useful capacity
signal requires more fully qualifying items under the expanded policy, with
at least one longer main supplying useful worked reasoning or qualifications
rather than padding. This would not prove that the same teaching could never
be expressed within 420 characters. Report whether extra room also introduces
unsupported claims or merely reduces format exclusions. All six expanded items
meeting every requirement would be a fully favorable selected run; partial
improvements remain observations without redefining that full result.

One unrepaired batch per goal and arm cannot establish a reliable general effect,
production bank yield or learning outcomes. Even a favorable result requires
broader qualification and coordinated client/runtime changes before use. Keep
the existing unresolved semantic-verification failures in scope; longer teaching
cannot be presumed to repair them. No deployment or default promotion follows.

## Pre-dispatch validation

The prepared source passed all 980 backend tests without skips, scoped Ruff,
compilation and whitespace checks. The seven new capture tests cover the exact
paired request change, source/context isolation, durable raw output, malformed
completed content, unusable empty output with retained usage, fail-stop behavior,
tamper rejection and no-client replay. These checks establish experiment
mechanics, not question correctness. The fixture's source facts and scope were
independently checked before any author response existed.

Independent dry review also validated all six actual requests against the local
Botocore Converse input shape, with client and socket creation forbidden. Paired
requests differ only in the 320-to-900 instruction; model, reasoning, token and
temperature settings remain fixed. All supplied sources and normalized goals
remain unchanged, and assessment metadata is excluded. Serialized requests total
80,448 bytes, with a largest request of 13,503 bytes. No provider call was made
for these checks.
