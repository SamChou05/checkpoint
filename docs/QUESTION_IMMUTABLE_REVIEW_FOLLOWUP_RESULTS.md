# Immutable teaching audit: follow-up results

September 8, 2026 UTC. The [separate five-case trial](QUESTION_IMMUTABLE_REVIEW_FOLLOWUP.md)
completed all five calls. Application decisions matched all five predeclared
expectations: three sound controls were retained and two defective items were
rejected. The all-pairs rejection came from the application's **nonempty-issue
veto**, even though the model marked the item valid and all its explanations
supported. This is evidence for enforcing reported objections in code, not for
treating the model's overall approval as a correctness certificate.

The original six-case trial remains a separate operational failure after one
call. Its first case was neither retried nor imported into this result. These
are selected fixed items, including supplied corrected explanations; this is
not a fresh-generation accuracy estimate or a full author/solver/reviewer test.

## Per-case findings

| Fixed item | Model's overall judgment | Application decision | Assessment |
| --- | --- | --- | --- |
| Controlled photography with sound feedback | Valid; all five feedback fields supported | Retained, difficulty 2 | Correct aperture key; exact qualified feedback preserved |
| Historical music with bad distractor feedback | Invalid; three wrong-choice fields unsupported | Rejected: unsupported feedback | All three predeclared explanation defects identified |
| Same music task with sound feedback | Valid; all five feedback fields supported | Retained, difficulty 3 | Correct B-flat major key and feedback preserved |
| Historical all-pairs question with wrong key | **Valid; all five feedback fields supported; one decisive issue** | **Rejected: reported issue** | Correct output-size objection, followed by an unjustified waiver |
| Explicit all-index-pairs negative control | Valid; all five feedback fields supported | Retained, difficulty 3 | Correct quadratic-output conclusion and feedback preserved |

The music rejection correctly distinguishes three errors. Ignoring transposition
would retain the written G major triad, not produce C major. Correctly transposing
the root G for alto sax gives B-flat, not E-flat. A consistent whole-tone downward
transposition does produce F major, although that is the wrong transposition for
alto sax. The auditor's additional upward minor-sixth example for E-flat major
is consistent at the pitch-class/triad level. The unchanged main explanation
and correct-choice feedback were properly retained as supported within the
rejected item; those judgments did not override the bad distractor explanations.

The all-pairs response recognizes that explicitly enumerating matching index
pairs can require quadratic output. For example, an array of n zeroes with target
zero contains n(n-1)/2 matching pairs. It then appeals to interview convention
and the hash map being the best available option to waive the obstruction. That
does not establish the unchanged question's unconditional linear-time guarantee.
Calling every explanation supported is also inconsistent with its own objection
to the central bound. A correct observed rejection therefore coexists with
incorrect model validity and feedback judgments.

No automatic retrieval, external calculation, generated-code execution or native
verification occurred. The counterexample above is an independently inspected
mathematical argument. Proposed feedback reveals the intended answer, so this
is not an answer-blind review. The auditor assigned different difficulty levels
to the two otherwise identical music tasks; one call per variant cannot establish
why. Difficulty calibration and advanced adaptive progression were not tested.
The separate assistant assessment rates both music tasks at level 2; changing
feedback alone is not demonstrated to increase the question's cognitive demand.
That assessment had access to the expectations and its author prepared the
fixture. It is a disclosed content inspection, not a blind expert replication.

## What this changes

The diagnostic parser fix allowed internal objections to be recorded without
altering learner text bounds. The code prevented an overall approval from
overriding the all-pairs objection. All three retained items preserve every
frozen content field; only the independently assigned difficulty may change.

The decision-level target was met. A stronger claim that every model judgment
and supporting reason was sound was not met. The model still demonstrated the
same tendency to reinterpret a broken guarantee as an intended interview task.
It may also omit an objection entirely on another call. Five selected decisions
do not establish dependable correctness across arbitrary learning goals.

No production integration, runtime model promotion or deployment follows from
this trial. Before considering integration, the complete-content authoring step
must produce admissible, useful items, the exact content audited must survive
storage and client display, and a fresh full-pipeline evaluation must preserve
sound controls while blocking defective keys and feedback. Another paraphrase
of the same generic judge is not established as a remedy by these results.

## The current solver contradiction is still open

A separate [current-source mocked reproduction](evidence/answer-only-gap-20260908.json)
confirms that a solver can label its result `resolved`, say that no real number
satisfies x squared equals -1 only in its answer, and leave limitations and
assumptions empty. A deliberately approving reviewer then accepts the offered
key `0` and the current verifier stamps it with verification version 1 and policy
revision 1. Declaring `no_solution`, supplying a limitation, or naming an exact
rival choice blocks review in the corresponding controls.
The root independently reproduced all four archived observations against the
recorded source hashes, without provider calls.

That is a reachable local control-flow defect, not a measured live-model failure
rate or a claim about the deployed service. The immutable audit above does not
consume that solver report and does not close this answer-only semantic gap.
The existing [limitations gate documentation](QUESTION_SOLVER_LIMITATIONS_GATE.md)
already distinguishes these cases. A reviewer must not be able to waive a
reported obstacle merely because its final answer agrees with the author.

## Operational evidence

The run used clean source `0529a717e6e7274f837c51a4672ba526747b3804`, Opus 4.6
adaptive thinking at high effort, and a 16,000-output-token allowance. All five
calls ended normally with `end_turn`, with no retries, replacements, malformed
reviews, skipped cases or output-token exhaustion. Recorded usage totals
6,399 input and 9,381 output tokens: 15,780 tokens. Recorded call intervals sum
to 158.005 seconds; this is not a production latency benchmark.
The four reported diagnostics were 226, 332, 337 and 442 characters. Three would
have exceeded the original 280-character diagnostic bound; all fit the corrected
2,400-character limit. The longest raw review was 1,125 characters, below the
24,000-character envelope limit. Learner text was neither expanded nor clipped.

- [Frozen plan](evidence/immutable-review-followup-plan-20260908.json)
- [Exact terminal capture](evidence/immutable-review-followup-capture-20260908.json)
- [Bound replay](evidence/immutable-review-followup-replay-20260908.json)
- [Independent operational audit](evidence/immutable-review-followup-operational-audit-20260908.json)
- [Per-case semantic assessment](evidence/immutable-review-followup-semantic-assessment-20260908.json)

The capture byte SHA-256 is
`b0fb8330ddbbe08c0bd46ccdd49e7162d30f90b68b9acb1253a7bf694aa02feb`;
the replay byte SHA-256 is
`763386d99cb2097d3276829e89cf3c16a14717e5b2d34a71719ca2feb8bd2f9f`.
Reconstruction uses the original clean source and Python 3.12.11 with
boto3/botocore 1.43.89. Private reasoning and credentials are absent. Replay
verifies captured bindings and code decisions, not model factual accuracy.
