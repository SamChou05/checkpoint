# Closed negative reviewer states — September 21, 2026

The proposed v2 schema prevented the captured negative-state format failure, but
**failed useful-answer qualification** in its bounded live smoke. Both calls
returned valid JSON conforming to v2 and passed the actual production adapter.
Both also rejected all eight controls, including all three valid questions.
No items were admitted. This is not a successful mixed-response quality result
and does not justify enabling this contract in deployment.

The original v1 failure is preserved in
[native-reviewer-capture.json](../choice-reliability-20260921/native-reviewer-capture.json),
call 3, item 2. The reviewer correctly noticed two equivalent wrong distractors
and declared `valid:false`, while retaining an answer and learner feedback.
That row satisfies v1's declared JSON schema; it fails the separate adapter rule
requiring empty answer/feedback on a rejection. A defective item can have a
known correct answer, so this need not be a contradictory semantic judgment.
It is a mismatch between the schema's representable states and the application's
negative-response contract.

V2 uses a closed `anyOf` at each review item: accepted records retain the existing
feedback fields and require `valid:true`; rejected records contain only `index`
and `valid:false`. Both branches forbid additional properties. The rejected
branch cannot represent the offending v1 state. Local tests preserve v1's exact
schema hash and behavior, reject the original captured row under v2, and admit
well-formed mixed positive/negative fixtures without surfacing rejected feedback.
Boolean/integer confusion, unknown fields, duplicate JSON keys, duplicate feedback
rows and invalid index coverage remain rejected. Transport schema version 2 is
separate from the unchanged public verification policy revision.

The [new frozen plan](reviewer-v2-plan.json) and [runner](reviewer_v2_probe.py)
used the same eight controls and semantic prompts as the failed explicit-diversity
arm, with the new v2 native transport instruction/schema and actual production
provider adapter. The semantic diversity prompt is experimental; this schema
change does not promote it into the production reviewer. Two identical requests
were dispatched to Sonnet 4.6 with thinking disabled, temperature 0.2, 6,000 output
tokens, 75-second reads and no SDK retries. No author/solver invocation, deployment
or bank write occurred. Original plans and captures were not rewritten.

| Observation | First request | Repeated request |
| --- | ---: | ---: |
| Completion | `end_turn` | `end_turn` |
| Elapsed | 5.330 s | 1.763 s |
| Schema and adapter valid | Yes | Yes |
| Minimal rejected records | 8 / 8 | 8 / 8 |
| Valid controls falsely rejected | 3 / 3 | 3 / 3 |
| Invalid controls rejected | 5 / 5 | 5 / 5 |
| Admitted questions | 0 | 0 |

The [capture](reviewer-v2-capture.json) retains provider text, adapted text,
per-control verdicts, admission metrics and usage: 3,886 input tokens and 160
output tokens total. The plan SHA256 is
`0ebe2da31efbec1689763ab53b2926f4ec007abb57218251e55bb8161e3a626a`.

The provider accepted the exact union schema in these calls. The live responses
exercise only its negative branch; accepted-branch and mixed-batch behavior is
established by local controlled tests, not by these live observations. The
experiment does not establish whether all-negative output comes from branch
selection, the asymmetric response shapes, or prompt interaction. No rationale
was returned by the minimal rejection branch, so a causal explanation would be
speculation. The two-call ceiling is exhausted; no further trials were made.

Formatting can be made stricter without improving useful output. Preserve these
two results separately: the known illegal negative representation is excluded,
while this candidate's live false rejection behavior prevents qualification.

The final change therefore **retains v1 production routing** for both native
and legacy calls. V2 is available only to explicit experimental stage calls;
it is not the default selected by enabling native mode. Tests enforce that
selection boundary and unchanged v1 schema hash. The frozen plan's source hashes
describe the temporary candidate tested before the unsuccessful qualification;
the final routing was restored afterward. No old plan or capture was rewritten
to make the failed experiment appear successful.
