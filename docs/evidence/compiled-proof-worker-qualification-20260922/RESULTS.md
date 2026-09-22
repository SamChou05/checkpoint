# Compiled-proof full-worker trial: failed

The frozen candidate returned **10/15 requested questions**, of which **8/15
planned questions passed both independent blind content reviews**. It fails the
original yield, compiled-item quotas and released-content requirements. All
12 provider calls completed with visible native output; there were no provider
failures, retries or replacement jobs. No setting or deployment was promoted.

| Fixed job | Returned / planned | Independently sound | Compiled returned | Calls | Runtime seconds |
| --- | --- | --- | --- | --- | --- |
| Quantitative | 2 / 5 | 2 | 2 | 5 | 166.077081 |
| Python | 5 / 5 | 5 | 0 | 3 | 68.278195 |
| Arithmetic / English | 3 / 5 | 1 | 1 | 4 | 137.222157 |
| Total | 10 / 15 | 8 | 3 | 12 | Three separate 240-second jobs |

All jobs stayed inside their original six-call and 240-second limits. The frozen
requirements were at least 14/15 returned, at least four per job, at least six
compiled overall including four quantitative and two mixed, and sound learner
content for every release. No criterion was changed after dispatch. Input usage
was 35,359 tokens and output usage 23,294; every call reported usage. Native
reasoning/signatures were omitted, and no conclusion is drawn from their content.

## What failed

The quantitative job produced 13 numerical drafts over three normal runtime
passes. Seven omitted the correct offered answer, three had malformed graphs,
and only three compiled. The seven missing-answer drafts comprised five exact
results and two explicit domain extrema. These are author errors, not JSON-shape
errors. The mixed job separately had three missing-answer specifications and one
malformed graph, with one compiled survivor. Across both jobs, 18 quantitative
rows produced four compiled candidates and 14 compilation rejections. Rejected
specifications were not repaired or silently treated as prose.

The final auditor rejected one of the three quantitative candidates for uncertain
teaching. Its condition was `7x + 20 - 55 >= x` over integers 5 through 12, asking
for the minimum. Independent exact evaluation establishes answer 6 and feasible
values 6 through 12. Its short explanation's witness and smaller-value claims are
true. The returned flags identify explanation uncertainty but provide no rationale;
we cannot infer why it objected. The two other quantitative candidates and the
mixed arithmetic item have exact keys and supported worked main and per-choice
teaching.

The two English items were released despite lacking an actual question or editing
instruction. Root and the independent reviewer locked their judgments before
opening keys, explanations or model judgments:

- The team/researchers sentence gives no target replacement or intended pronoun
  antecedent. `its findings` can refer to the team and `their findings` can refer
  to the researchers. The reviewer assumed the intended antecedent was the team.
- The neither-manager-nor-employees sentence gives no replacement instruction or
  requirement to preserve simple past. `were satisfied` is the expected answer
  **if** that missing task is added, while the offered plural `have been satisfied`
  and `are being satisfied` allow different grammatical tense/aspect readings.
  The solver invented a simple-past requirement and also falsely asserted that
  `are being satisfied` fails agreement with the plural nearer subject.

The final immutable auditor accepted both with no issue flags. This is an
observed shared interpretation error, despite existing instructions to avoid
missing premises. Four distinct strings, one model-selected key and agreeing
reviewers did not establish a complete question with one defensible answer.
Neither item is credited by inferring or adding the missing task afterward.

All five Python questions have correct keys and supported learner explanations
for their concrete expressions. Their 20 choice judgments and 30 pair judgments
also agree with independent solutions. Minor private wording qualifications are
recorded separately: a list-valued `or` result is not a universal rule excluding
Boolean results, and the number 3 does appear in an `if` condition although it is
not the resulting variable value. These are not false released Python teaching.

## Structure, provenance and display

The candidate used actual generation, sanitization, compiler provenance,
prose-only blind solving and final immutable audit. Compiled policy 8 and prose
policy 7 remain distinct. The original specifications reproduce all five fields
of the three returned compiled questions. The seven prose questions retain their
authored main explanations and empty per-choice feedback. Preservation is not a
semantic endorsement: it also preserved the two defective English tasks.

Root checked all ten exact stored keys across 24 choice permutations each (240
orders), with exactly one stored-key match in each. The eight unambiguous items
also match the independently solved answers in every order. This is an offline
binding check, not a new Swift simulator run, and cannot make an ambiguous key
correct. Separate structural review records exact source/request/native-response
and identity replay.

## Evidence and next change

- Frozen plan SHA-256: `703c0bb57e2c51b5226f537e592add1746c0462c259cd315b14ee341b0ae2ad4`.
- Capture SHA-256: `7d458b0f433018df5fa20c7d47c49f7c143c63f7201340a644df6ca31d37b0d3`.
- [Blind worksheet](blind-items.json), [root blind lock](root-blind-review.json),
  [independent blind lock](independent-blind-review.json) and
  [root content review](root-content-review.json) preserve item-level judgments.
- [Independent content review](independent-content-review.md),
  [structural replay](independent-structural-review.md) and
  [rejected-spec analysis](rejected-spec-analysis.md) preserve separate semantic,
  transport and authoring assessments.
- The capture's source is the unchanged `6959a26` checkout. Preparation wording
  in PLAN.md is historical; plan.json is the executed frozen contract. This result
  does not edit those artifacts or replace any earlier failed experiment.

A separate task-only numerical constructor addresses missing-answer drafts by
having code derive the correct result and three distinct wrong values before
compilation. It was not used in this trial and earns no retrospective yield
credit. Malformed graphs, insufficient distractor pools and unsuitable prose
remain separate failure modes. Its opt-in integration requires its own frozen
live qualification. The conditional deployment review is inactive because this
candidate failed its prerequisite.
