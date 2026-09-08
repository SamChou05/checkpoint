# Fresh premise and non-defect controls

[The fixture](../backend/bedrock-question-service/evals/fixtures/question_premise_controls.json)
contains six newly constructed questions, independent of the forthcoming candidate
prompts. They cover probability/proportions, Python, astronomy and motion. Three
complete authored items are supported; three have an incorrect key or main.
These are level-2 diagnostic controls, not model-generated samples, advanced
learning qualification or an estimate of production error rates.

| Case | Independently warranted answer | Whole authored item |
| --- | --- | --- |
| Spinner probability | The premise is wrong: the probability is 3/8. | Reject: the stored key/main confuse probability with favorable-to-unfavorable odds. |
| Recipe scaling | 300 mL; apply the common factor 1.5. | Retain; the wrong alternatives are ordinary distractors. |
| Python assignment | It prints 3 because both names refer to the same list. | Reject: the stored key/main claim assignment makes a copy. |
| Python copy | It prints `[4, 5]`; the outer list was copied. | Retain; `append` returning `None` does not mean `print(a)` prints `None`. |
| First-quarter Moon | The observer sees about half of the sunlit hemisphere. | Reject the main's Earth-shadow mechanism while retaining the correct key. |
| Cyclist's speed | Elapsed time is unknown; no unique speed follows. | Retain; two permitted arrival times establish the information limit. |

The two false “why” presuppositions do not make the offered error diagnoses
nonresponsive. The assessor must identify those exact warranted choices, rather
than defend the assertion or call every choice unsupported. A correct key does
not rescue the lunar explanation. Conversely, a false alternative, harmless
context, or intentionally absent measurement addressed by the answer does not
invalidate an otherwise sound question. Possible numerical speeds are refuted
as warranted answers, not declared physically impossible.

Each case stores exact per-choice reasons, main assessment, material defects,
non-defects, an assessor-only correction, and canonical question/context hashes.
The future runner must whitelist inputs: the choice stage receives goal, exact
stem/options and any separately frozen evidence; the teaching stage additionally
receives the exact main. Neither receives assessment, case IDs, provenance,
author key/difficulty, source-check summaries or previous verdicts. No candidate
prompt was inspected to construct these controls.

Full diagnostic success requires correct reasoning for all 24 choices, the
specific defects in all three rejected items, and retention of all three valid
items with supported complete mains. Record format/reference failures,
uncertainty and unsupported objections separately; none earns factual-catch
credit. Difficulty and distractor plausibility are independent assistant
judgments, not calibrated learner measures. This fixture authorizes no calls or
runtime changes and specifies no subject-specific acceptance rules.

The arithmetic and information-limit cases follow directly from their stated
facts. Python semantics were checked against the [Python 3.12 list tutorial](https://docs.python.org/3.12/tutorial/introduction.html#lists)
and [list-method documentation](https://docs.python.org/3.12/tutorial/datastructures.html#more-on-lists).
The astronomy basis is [NASA's phase explanation](https://science.nasa.gov/moon/moon-phases/)
and [eclipse explanation](https://science.nasa.gov/moon/eclipses/). References were
reviewed on 2026-09-08. The fixture contains short assessor paraphrases, no copied
passages, and empty provider `sourceDocuments`; any evidence acquisition must be
separately specified. No source page bodies were downloaded.

Offline validation passed the existing authored-question admission contract for
all six exact objects, their content hashes, phase input isolation, the 3/3
eligibility split and the 320/140/320 stem/choice/main bounds. The two exact,
inspected finite Python programs independently ran under Python 3.12.11: assignment
printed `3\n`, and copying printed `[4, 5]\n`; both exited successfully with no
stderr. Their UTF-8 source hashes are respectively
`1c4ab7cb559c969d8457c2a8f362a06eef6aa81b6cddf87444a98153986943d0`
and `76b228eac1fbcd000cfd82ff987b5048374f9bd7feed80e8dd6b9854a04a6f90`.
Exact arithmetic independently confirmed 3/8 differs from 3/5, the water scales
to 300 mL, and durations of 1, 2 and 0.5 hours give 18, 9 and 36 km/h. These are
ground-truth checks of the displayed controls, not model experiment results or
new provider evidence. Root independently reviewed the six judgments and cited
primary pages. No provider calls, source-page downloads or commits were made.
