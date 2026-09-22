# Native reviewer follow-up: shape improved, semantic fix not established

The separate native-output experiment produced **three schema-valid JSON
responses**, but only two passed the production adapter. Both usable responses
still approved semantically duplicate wrong choices. The previously promising
wording change should not be promoted on this evidence.

This follows the four-call legacy [experiment](README.md), whose four strict
format failures remain unchanged. It uses the same eight fixed cases, same
reviewer core, same contextual pairwise-diversity suffix, and planned ABBA order.
The [new frozen plan](native-reviewer-plan.json) was saved at revision `e759e25`
before dispatch. Exact requests were built through the real
`_generate_with_bedrock(contract="default_reviewer_v1")`, including native schema
and transport instructions. During each live call the recorder checked exact
request equality, then passed the actual response through the production native
adapter and `verify_questions(preserve_reviewed_text=True)`.

The [raw capture](native-reviewer-capture.json) and
[summary](native-reviewer-summary.json) preserve all denominators:

| Outcome | Count |
| --- | ---: |
| Planned calls | 4 |
| Attempted calls | 3 |
| Valid JSON conforming to the sent JSON Schema | 3/3 |
| Responses passing the production native adapter | 2/3 |
| Responses violating a cross-field application invariant | 1/3 |
| Unattempted calls after the required stop | 1 |

The first baseline and first treatment each admitted four of eight fixed cases:
the three valid controls plus the bad verbal-distractor case. Both reject the
numeric-duplicate, multiple-answer, and no-answer controls. In the admitted bad
case, the stem explicitly asks for the number two and the choices are `Two`,
`Three`, `The number three`, and `Four`. Feedback explicitly recognizes that the
two wrong verbal choices both mean three. Thus identifying the equivalence in
prose still did not force the overall verdict to reject the item.

The second treatment finally declares that verbal-distractor case `valid:false`,
but simultaneously retains `answer:"Two"`, a nonempty main explanation, and
four feedback rows. The native schema permits those field types together; the
production adapter forbids learner feedback or a selected answer on a rejection.
It correctly rejects the entire response. The run stopped immediately as planned;
the fourth call was not attempted and no retries were made.

That third response illustrates a second layer of structured-output reliability:
valid JSON and correct field types do not establish valid relationships between
fields. The semantic prompt cannot make a permissive JSON schema enforce those
relationships. This is distinct from the original four responses' surrounding
prose and malformed draft JSON.

These were isolated reviewer calls, with no invented solver records, authored
keys, author calls, question-bank writes, or additional model stages. There was
one completed baseline and one completed treatment, not a complete replicated
comparison. No population error rate, broad distractor improvement, or end-to-end
production readiness follows from eight selected simple controls.

The result supports keeping three separate checks: transport shape, cross-field
application consistency, and semantic quality. It does **not** support deploying
the tested pairwise wording as a demonstrated semantic fix. A future experiment
could make pairwise judgments explicit in the existing reviewer representation,
but those judgments would still be fallible and would need their own held-out
assessment. No such change is included here.

Usage for this separate follow-up was 5,326 input and 2,118 output tokens. The
three calls took 7.864, 8.075, and 9.102 seconds. The runner passes Ruff
`--isolated` and Python compilation. The completed first milestone's 42 targeted
tests still pass; no production file changed during this follow-up.
