# Fuller explanations preserve one useful item without improving complete authorship

The [six-call explanation-capacity trial](QUESTION_MAIN_CAPACITY_PROTOCOL.md)
completed and produced all twelve requested questions. Each arm produced one
item meeting both independent assessors' complete-content requirements. Increasing
the author instruction from 320 to 900 characters did not increase that count.
It did reveal a narrow retention benefit: the expanded SQL item has a supported
529-character worked explanation and otherwise fits the current text limits.
It fits a virtual 900-character main allowance but fails the current 420 limit.

This is evidence that useful teaching can exceed the current main limit, not
that longer explanations make answers correct. The expanded arm also produced
wrong exposure answers and a false musical explanation. No runtime verifier,
production admission, client limit, default setting or deployment changed.

## Content and length results

Counts use all six requested raw slots per arm, with no missing, extra, repaired,
shortened or replacement items. “Both” means agreement between two independent
assistant assessors, not expert adjudication or learner calibration.

| Observation | Current instruction: 320 | Expanded instruction: 900 |
| --- | ---: | ---: |
| Uniquely supported authored key, both assessors | 5/6 | 2/6 |
| Entire main explanation supported, both | 3/6 | 2/6 |
| Complete content: key, premises, goal, depth, distractors and teaching, both | 1/6 | 1/6 |
| Complete content plus all text limits, with virtual main limit 420 | 0/6 | 0/6 |
| Complete content plus all text limits, with virtual main limit 900 | 0/6 | 1/6 |
| Main complies with its arm's author instruction | 0/6 | 6/6 |
| Raw main fits 420 characters | 1/6 | 0/6 |

The two complete-content items are q03 (current) and q04 (expanded), both SQL
ON-versus-WHERE comparisons. q03 has a 336-character stem and 502-character main;
q04 has a 294-character stem and 529-character main. q04's additional space
contains an accurate row-by-row explanation, rather than padding. Its retention
satisfies the protocol's narrow useful-capacity observation. However, the current
arm already generated similarly substantial teaching despite its smaller
instruction. Different sampled stems also affect admission. Neither result
establishes that this teaching could not be written within 420 characters, or
that a larger author instruction caused better reasoning.

The frozen fully favorable criterion—six complete expanded items—failed. The
supported-key counts are selected observations, not evidence of a general
accuracy decline caused by extra room. One batch per goal and arm is too small
for that inference. Field-size compliance is separate from the provider's output
token allowance; no call approached that allowance.

## Concrete remaining errors

| ID | Arm | Finding |
| --- | --- | --- |
| q01 | Expanded | Supported perfect-fourth explanation; direct application and weak distractors, below requested depth. |
| q02 | Current | Incorrectly asserts no solution for deeper depth of field at fixed shutter time. Increasing ISO from 200 to 400 compensates for f/8 to f/11. |
| q03 | Current | Complete supported SQL comparison; stem and main exceed current limits. |
| q04 | Expanded | Complete supported SQL comparison; only its main exceeds current limits. |
| q05 | Expanded | Slowing three stops calls for lower ISO at fixed aperture, but key/main increase ISO from 400 to 3200. None of the offered choices meets the task. |
| q06 | Expanded | Says no solution, ignores an allowed faster shutter, invents an ISO floor and miscalculates a two-stop change. |
| q07 | Current | Correct key and complete row trace, then falsely says the NULL-safe operator is decisive after acknowledging ordinary equality gives the same result. |
| q08 | Current | Supported exposure compensation; direct application and weak distractors. |
| q09 | Current | Correct error-identification key, but the main repeatedly calls F–B-flat a diminished fifth/tritone. It is a perfect fourth. |
| q10 | Expanded | Ambiguous inversion anchor and an unsupported answer; main calls E–B-flat a major sixth, although its written size is a fifth and pitch distance is six semitones. |
| q11 | Expanded | Intended NULL-match result depends on unstated comparison-compatible column types. Both assessors retain conditional support rather than certify the PostgreSQL query. |
| q12 | Current | Supported intervallic-inversion answer and main. Assessors disagree on difficulty, 2 versus 4; it does not meet their joint depth criterion. |

The [native checks](evidence/main-capacity-20260909/native-checks.json) independently
compute conventional exposure compensation and written/pitch interval distances.
For q06, f/1.4, 1/1000 s and ISO 100 is consistent with all stated constraints.
Opening and slowing one stop each would instead require ISO 25 from ISO 100,
not the main's ISO 50. These calculations test literal supplied quantities;
they are not a general automated prose verifier.

A manually constructed, in-memory SQLite execution confirms q03's portable
join/filter result. It is explicitly not a PostgreSQL execution. PostgreSQL's
[type-resolution rules](https://www.postgresql.org/docs/18/typeconv-oper.html)
and [comparison semantics](https://www.postgresql.org/docs/18/functions-comparison.html)
support retaining q11's type caveat: comparison legality cannot be inferred
merely from an intended NULL match. No local PostgreSQL runtime was available.
The root also recorded q12's potentially confusing anchor wording; both masked
assessors accepted its ordinary intervallic-inversion reading. That caveat remains
visible rather than silently replacing their frozen judgments.

## Assessment and operational evidence

Two fresh assistant assessors received shuffled opaque IDs, exact stems/choices,
raw goals and the same supplied source summaries. Neither saw keys, mains,
model difficulty, arms or length outcomes in the first phase. Both first passes
were saved and hashed before either received unchanged mains. Both teaching
passes were saved before unmasking. Main wording reveals the intended answer
and length may suggest its arm; masking is therefore partial. The assessments
agree on supported keys and whole-main support. They disagree on distractor
adequacy at q07/q09 and on q12's difficulty; all disagreements are retained.

The [evidence directory](evidence/main-capacity-20260909/README.md) contains exact
raw question objects, masked packets, all four assessments, phase hashes,
independent operational checks and the derived summary. Original source-bearing
provider requests/responses remain in the local terminal capture; repository
question objects and hashes do not constitute a standalone transport replay.

All six provider responses ended normally, with known usage and confirmed worker
cleanup. They consumed 14,898 input and 4,307 output tokens. Per-call output was
637–794 tokens against 6,000 allowed. SDK intervals total 54.855511 seconds;
worker intervals total 58.923574 seconds. These are recorded execution intervals,
not a production latency distribution or independent end-to-end timing.

Source commit: `f55e5018a5a71db72c8864d9a79a44bd8ae41877`.
Plan canonical SHA-256:
`1932764c04d2846079f72019c1639221c4d62e0bf1acedfefc4dc9c605d83608`.
Original capture: 230,337 bytes, byte SHA-256
`744ee9eea9ce8604c1a927fdd9b3cd39d4a8f41cb7215ef70bcd8ee66637258d`.
Independent exact replay succeeded with provider client factories and socket
connections forbidden. All 34 source hashes matched the committed source; all
six frozen request bindings, native input shapes and assembly joins passed.
The source milestone passed 980 backend tests without skips.

## Next intervention

Retain the narrow capacity finding, but do not use a larger limit as a correctness
fix. The recurring errors concern construction of a valid task, use of supplied
rules, meaningful alternatives and complete teaching. Prior source/model/review
experiments do not justify adding another approval vote as the next remedy.

A distinct next test is to give the author a small set of independently checked,
complete examples that demonstrate those requirements, then measure transfer to
separate goals. Existing prompts supply rules and schemas but no such examples.
The hypothesis is improved construction, not guaranteed truth or memorization
of the twelve failures above. Example selection and model/settings should be
fixed prospectively, with fresh goals and the same independent content checks.

There is relevant but limited research support: Bitew and colleagues found that
retrieved question-bank demonstrations improved distractor generation relative
to zero-shot and static-example prompting in their setting. Their task supplied
existing questions and keys and evaluated ten proposed distractors; it does not
establish complete-question correctness or transfer to Checkpoint's current
models. [Predictive-prompting study](https://arxiv.org/html/2307.16338v1)
Feng and colleagues separately found that mathematical validity did not reliably
translate into distractors representing real learner misconceptions. That is a
reason to retain independent distractor assessment and eventually learner data.
[Math distractor study](https://aclanthology.org/2024.findings-naacl.193/)

The broader correctness and adaptive-learning objective remains incomplete.
