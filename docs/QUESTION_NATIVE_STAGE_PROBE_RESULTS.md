# Native formatting passes; premise substitution remains a correctness defect

September 9, 2026 (Pacific time). The ten-call
[historical-input diagnostic](QUESTION_NATIVE_STAGE_PROBE_PROTOCOL.md) completed.
Every response passed native JSON/schema validation and adaptation, and every
response passed its stated stage check. All seven previously malformed inputs
were covered, with one exact repeat per downstream schema. This establishes a
formatting improvement on the selected regression inputs, not general question
correctness or sufficient fresh inventory.

The recovered responses expose substantive problems that invalid formatting
had previously withheld: a solver reconciles conflicting map facts incorrectly,
another imports a condition from an answer choice, and the default reviewer
approves an extra spreadsheet operand that the task never specified. These are
content failures inside valid JSON. Do not enable the global native flag on the
strength of this formatting result.

## Operational result

| Observation | Result |
| --- | --- |
| Planned / dispatched / normally completed | 10 / 10 / 10 |
| Native schema / adaptation checks passed | 10 / 10 |
| Stage checks passed | 10; default review checks cover indexes/choices only |
| Previously malformed distinct inputs covered | 7 / 7 |
| Distinct question subjects / reviewed occurrences | 19 / 27, including repeats |
| Known input / output tokens | 23,161 / 8,134 |
| Largest output / allowance | 1,544 / 6,000 tokens |
| Total serialized request bytes | 90,201 |
| Provider failures, unfinished responses, unattempted slots | 0 / 0 / 0 |

All worker processes and groups finished cleanly; none required termination.
SDK intervals sum to 119.089157 seconds and worker intervals to 125.161007
seconds. Individual SDK intervals range from 1.835298 to 20.926300 seconds.
These are recorded local intervals, not production latency percentiles.
No output ceiling was reached. First/repeated observations do not establish
grammar cache state.

All calls used the original Sonnet 4.6 US inference profile with disabled
thinking, temperature 0.2, 6,000 output tokens, read75/connect3 and one SDK
attempt. Native instructions and the native schema were the only provider
request changes. Kimi authoring and skill-map generation were not exercised.
The run used committed source `751bdaa` and boto3/botocore 1.43.91.

## Content findings

The independent assessor's first pass covers all 19 subjects and 76 exact
choices. It was frozen before live calls and without seeing keys, authored
teaching, model outputs, or other assessments. Its records remain unchanged;
the observations below distinguish its judgments from root's checks.

- **Conflicting map facts (`item-11`).** The stem gives a road as 3 km, a map
  ratio of 1:50,000, and a printed road length of 5 cm. The last two imply
  2.5 km, not 3 km. Reducing the stated ratio to 80% gives 1:62,500; using
  the stated road distance and measured length instead gives 1:75,000. The
  solver notices the 2.5 km calculation but calls the conflicting label
  consistent and supports 1:62,500. This is an unsupported reconciliation of
  the original facts. Only solver eligibility was tested for this subject;
  no fresh final reviewer was called on it.
- **Condition supplied by a choice (`item-12`).** The stem gives a 0–1 km scale
  bar but never its physical length. After 125% enlargement, a 9 cm route
  represents `9 / (1.25 × original_bar_cm)` km. The model selects the choice
  that assumes an original 2 cm bar, yielding 3.6 km, and uses that unstated
  length to refute other answers. The conditional arithmetic is correct;
  the stem does not establish that condition or ask which hypothetical
  scenario would produce it. The existing solver instructions explicitly
  prohibit using a choice's assumption to repair the shared question.
- **Extra spreadsheet operand (`item-17`).** The stem specifies multiplying
  the quarter factor in A1 by the regional target in B1. It separately places
  quarter labels Q1–Q4 in A3:A6. All offered formulas add a third factor from
  A3, and both native reviewer responses approve `=$A$1*B$1*$A3`, explaining
  those labels as numeric quarter factors. This silently changes the stated
  calculation. Literal nonnumeric labels also cannot serve as numbers in
  ordinary arithmetic formulas; Microsoft's guidance identifies text in
  referenced cells as a cause of value errors.
  [Microsoft Excel guidance](https://support.microsoft.com/en-us/excel/how-to-correct-a-value-error)
  No actual Excel process was executed for this analysis.
- **Ambiguous food-web interpretation (`item-18`).** Both authored-teaching
  audits approve 160 kJ/m²/year without issues, while the independent
  assessment finds the shrimp feeding/energy description ambiguous. Retain
  this as a premise-interpretation concern, separately from the concrete
  spreadsheet and map contradictions.
- **Variable teaching rejection (`item-19`).** Both audits select 625 correctly
  under the stated per-transfer interpretation. The first reports a concern
  about an explanation's hypothetical inverted-pyramid remark; the repeat
  reports no issue. Their cognitive rating is 3, while the independent
  assessment rates the two direct percentage applications at 2. This repeat
  does not establish stable teaching or difficulty assessment.

There are eight solver choice-label disagreements against the independent
first pass across 84 choice judgments, including repeats. That is not an error
rate. Three disagreements belong to the valid cannot-determine question
(`item-14`): the independent assessor marks possible numeric values uncertain,
while the model refutes them *as uniquely warranted answers* and supports the
information-limit answer. Root finds that distinction consistent with the
actual solver contract. Do not count those three as demonstrated model errors
or silently rewrite the frozen assessment. The remaining disagreements concern
the conflicting and underdetermined map subjects above.

Some correctly classified solver choices also have flawed reasons. For example,
one map record describes 1:40,000 as both incorrect and the correct enlarged
scale, and another uses the wrong direction for a reduction's ratio. These
records are solver evidence, not approved learner feedback. A correct label
does not establish that its complete explanation is sound.

## Actual application-policy replay

A separate offline check recovered the exact authored candidates and current
request state by replaying the original operations up to their final reviewer
calls. All 11 requests through the two target reviewer calls matched the
original capture, and regenerated solver and reviewer prompt text matched the
archived bytes. The real
`verify_questions` function then consumed the original solver responses and
the fresh native reviewer records, with native feedback preservation enabled.

| Native slot | Review input | Actual local policy outcome |
| --- | --- | --- |
| 6 | Spreadsheet `item-17` | Returns the defective item with policy revision 2. |
| 7 | Exact repeated spreadsheet input | Returns the same defective item with policy revision 2. |
| 8 | Ecology `item-18`, `item-19` | Returns `item-18`; rejects `item-19` for reported issues. |
| 9 | Exact repeated ecology input | Returns both items with policy revision 3. |

Thus the spreadsheet defect is an application-acceptance problem, not merely
an intermediate review declaration. The authored path correctly enforces an
issue veto even when the model says `valid:true`, but that only helps when the
model actually reports the issue. Existing solver vetoes for a multiple-answer
gradebook question and a zero-supported-answer wetland question also remain
intact during the replay.

These are local policy outputs using historical preceding model evidence plus
fresh native reviews. They do not establish fresh end-to-end native generation,
deployed behavior, or inventory delivery. No provider or production storage
call occurred in the replay. The exact
[policy report and helper](evidence/native-stage-20260909/README.md) are preserved.

## Consequence and next work

Native formatting directly addresses the observed malformed-response problem.
It cannot enforce factual agreement between a statement and a model's reason.
The [earlier task-obstruction experiment](QUESTION_TASK_OBSTRUCTION_RESULTS.md)
already demonstrated that explicit extra verdict fields do not reliably catch
silent premise substitution. The
[complete-choice comparison](QUESTION_COMPLETE_SOLVER_RESULTS.md) also showed
why removing all choices would exclude legitimate choice-dependent questions.
Do not repeat either approach unchanged or add another prohibition that the
current prompt already states.

The next correctness work must test whether verification preserves the original
facts and requested operation, with evidence or execution that can contradict
the proposed solution. It must retain valid controls, including substantive
negative answers and questions whose subject is carried in the choices. Fresh
generation and its runtime admission, useful difficulty, bank fill, and every
production role still require qualification. The overall correctness goal
remains unresolved.

The [evidence directory](evidence/native-stage-20260909/README.md) preserves the
frozen plan, original final responses, independent assessment, derived counts,
preflight checks and audits. No learner inventory, deployment, production
default, model selection, or output budget was changed by this diagnostic.
