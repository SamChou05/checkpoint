# Execution evidence is not yet an automatic correctness gate

The current generated-question contract does not provide enough reliable structure to use execution results as a general acceptance rule. A bounded inspection of 35 archived Python questions found only two that fit the smallest complete source-and-call pattern, both already valid. That pattern misses all five observed malformed-definition failures. Activating it would leave the demonstrated failure class unresolved.

The [coverage archive](evidence/execution-gate-coverage-20260906.json) preserves the historical questions, exact identities, provenance, classification rules and sample spans. It covers 20 schema-experiment questions, ten layout-experiment questions and five full-pipeline questions. Seven have a visibly separated multiline source prefix; five of those still need interpretation of trailing prose or a query operation. The two complete candidates have a source prefix followed by a blank line and `What does <literal call> return?`. Manual source spans are audit evidence, not a qualified automatic extractor. These are format-coverage findings, not a new accuracy benchmark.

Most choices look like Python literals, but that does not establish whether the question asks for stdout, a return value, a result's length, or a general behavior. None of these generated samples provides a correct explicit exception-answer control. The separate execution fixtures demonstrate compiler observations; they do not establish generated-MCQ extraction or option interpretation. A finite execution cannot establish a general complexity bound.

## Concrete adapter correction

The inspection also exposed a genuine eligibility defect. `print(ArithmeticError)` and `print(Ellipsis)` were eligible even though the child namespace omitted those ordinary builtins. Fixed local regression snippets reproduce the difference: ordinary Python prints the referenced objects, while the restricted namespace raises `NameError`. That would be misleading evidence if presented as the behavior of ordinary Python. Python documents both the [custom builtins behavior of execution](https://docs.python.org/3.12/library/functions.html#exec) and the [built-in exception classes](https://docs.python.org/3.12/library/exceptions.html#ArithmeticError).

The adapter now declines loaded builtin names that its namespace omits, before candidate execution. The remote parent recomputes the omitted-name set from its own Python builtins and repeats the check. Unknown non-builtin names remain observable, including genuine `NameError` examples, and intentionally invalid syntax can still produce compiler evidence. Locally shadowed omitted-builtin names are conservatively unsupported because this eligibility check does not prove their scope. Unsupported means the adapter has no applicable observation; it does not mean the question is wrong.

This correction does not certify equivalence to every Python runtime or deterministic output. Set display order and function representations can vary, and execution mode changes the meaning of an observation. A single observed value remains a record of that execution. The correction is tested locally with fixed benign inputs and generated-parent rechecks; it does not constitute a new managed-service experiment.

## Decision

Do not connect a canonical-format-only parser to question acceptance based on these samples. A future application-enforced gate needs exact bindings between the complete displayed question, source, inputs and mode; compatible runtime semantics; trusted typed option mappings; and correlated completed observations with cleanup confirmed. Any missing binding or inconclusive execution must remain a nonjudgment. Even a proved key contradiction can only reject the item: an output match cannot certify the explanation, all distractors, subject relevance or difficulty.

No runtime question-acceptance rule or deployed service changed in this milestone. The separate [paired model comparison](QUESTION_MODEL_COMPARISON_PLAN.md) remains frozen in its existing clean checkout at revision `1377b28`; its Opus 5 agreement approval is still pending.
