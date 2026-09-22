# Independent blinded task review

Blinded worksheet SHA256: `981f55d0247f93060e76264e2a7a1c7d32e30b39d0769a31b2a569621379d66a`.
Review JSON SHA256: `9bb34e03e8deac38eaac330a33036b771e3d7d091f995bfbf8a7a8be87bc9e31`.

All fifteen tasks were solved before opening the capture, author keys, explanations, compiler decisions or other reviews. The eight formal numerical tasks were independently checked with exact rational arithmetic; the five short Python examples were evaluated as inspected local literals, without evaluating provider-written code or importing the project compiler. This records task/choice judgments only; all teaching remains unreviewed.

Fourteen items have a unique supported answer. One pronoun item remains uncertain and therefore fails this stage: the crew/repairs alternative has a defensible clear reference under standard American singular collective-noun agreement. Some distractors are weak, as recorded below, but they remain contextually distinct.

| Source | Independent answer | Task/choice result |
|---|---|---|
| quantitative:0 | 19/12 | pass |
| quantitative:1 | 3 | pass |
| quantitative:2 | 5/6 | pass |
| quantitative:3 | 4/9 | pass |
| quantitative:4 | 7 | pass |
| python:0 | True | pass |
| python:1 | 40 | pass |
| python:2 | "small" | pass |
| python:3 | "hello" | pass |
| python:4 | [15, 20] | pass |
| mixed:0 | 3 | pass |
| mixed:1 | 12 | pass |
| mixed:2 | 14 | pass |
| mixed:3 | are | pass |
| mixed:4 | David handed the package to Kevin, who signed for it immediately. | uncertain_fail |

For `mixed:4`, the David/Kevin sentence has a clear relative-clause reading. The alternative “The crew finished the repairs, and they looked excellent afterward” can also be read with “they” referring to “repairs”: the singular collective “crew” is excluded under a conventional American number-agreement analysis. Notional reference to crew members makes another reading possible, but the task supplies no convention requiring that analysis. This interpretation dependence prevents reliable single-answer scoring. [Purdue agreement guidance](https://owl.purdue.edu/owl/general_writing/grammar/subject_verb_agreement.html) and [pronoun clarity guidance](https://owl.purdue.edu/owl/general_writing/grammar/pronouns/index.html).

For `python:3`, `False` and `0` compare equal numerically, but they are different exact Python results/types in an expression-evaluation task. They are not merged into duplicate answers merely because both are falsey. [Python expression semantics](https://docs.python.org/3/reference/expressions.html) and [built-in types](https://docs.python.org/3/library/stdtypes.html).

The quantitative minimum questions explicitly request a minimum. Larger satisfying offered values therefore remain wrong and distinct. No unstated minimum was added during solving. All items fit their requested topic and involve direct application at difficulty2; ambiguity prevents credit for the final English item. Actual assignment tags, author keys, main explanations and compiler feedback remain withheld and must be audited separately.
