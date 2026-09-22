# General counterexample prompt: 22/24, not qualified

The frozen four-call candidate failed the unchanged qualification criterion. All twenty-four rows passed native and local structure checks, all twelve sound learner payloads were accepted, and ten of twelve defective payloads were rejected. The model falsely accepted equivalent wrong distractors written as `2` and `two`, and again accepted the ambiguous semicolon question with its false punctuation explanation. All six independently designed new controls received the expected dispositions. These partial successes do not qualify the candidate for production.

Plan SHA: `7c9fcc97e4259758c85a2b36f0d0d508e71d97040daa41dabb0b10918f0ce315`. Capture SHA: `36705b403a4f28ff0fa1435d1af2fa45b742e24c9fed6a6766ab65674fb0f74f`. The first three requests preserve the exact eighteen previous Sonnet adaptive-only payloads, gold and ordering; only the system prompt changes. The fourth adds six independently designed full learner responses, approved before dispatch. The new packet SHA is `5ba726f57b54ab43493c4bde6bd18a9d29200defaa57bb03b86599cefcfd1dd4`. All prior trials, failures, inputs and prompts remain unchanged.

## Semantic failures

The duplicate-answer item asks for the result of 2+2. Its choices include the correct 4 and the two wrong forms `2` and `two`. The model calls the forms meaningfully different because one is a numeral and the other a word. The stem tests a numerical result, so both propose the same wrong value. True feedback and a unique key do not make those distractors distinct. In the fresh editor-action item, the model correctly detected a different pair of equivalent wrong paraphrases. The contrasting outcomes demonstrate inconsistent contextual equivalence judgments within this trial.

The semicolon rejection was missed again. The model says the key is the only standard construction and calls the alternative with comma-however-semicolon misplaced. The unchanged stem does not require however to begin the second independent clause. Bruce Aune's rule R2 explicitly permits the adverb to attach to the first clause, set off by a comma, before the semicolon joining the two clauses. At least two offered constructions are defensible, and the feedback's mandatory-placement rule is false. The qualified counterpart, which explicitly requests however at the beginning of the second clause, was correctly accepted. [Primary grammar source, printed page5](https://cse.buffalo.edu/~rapaport/Papers/Papers.by.Others/aune01-punctuation.pdf).

The generic instruction to seek counterexamples and test every non-key alternative did not reliably overcome these errors. This trial does not establish that the prompt caused the additional numeric-duplicate miss: the earlier comparison was not concurrent or randomized. It establishes that this exact frozen candidate did not satisfy its prospective criterion.

The six new controls distinguish necessary from sufficient conditions, complete from missing geometric information, and task-relevant exact text from equivalent action meanings. Their dispositions all matched independent gold: the ticket inference, rectangle perimeter and exact-text identifier were retained; the invalid converse, undetermined triangle side and duplicate discard actions were rejected. These are six new situations, not repaired versions of the previous failures.

Independent review of every returned reason confirms twenty-one of twenty-four reasons fully grounded. In addition to the two material false rationales, the rectangle acceptance fails exact-item grounding: it calls all four choices distractors and lists half-perimeter and two-side sum as separate errors even though both describe 13 cm. This additional reason error leaves its correct acceptance disposition unchanged but independently fails the all-reasons requirement. The repaired semicolon reason's placement shorthand is sound only relative to that stem's explicit restriction, not as a universal rule. The independent audit verifies system-only request deltas for the original eighteen, hidden gold for the new six, strict native/local checks and all fourteen exact selected-original hashes. Its SHA is `46bbe264cb303b31762b33c37c210596fa8b6adb7e8ae23eedcb14dc6baba72b`. No numerical disposition score substitutes for reason fidelity.

## Operational result

| Batch | Time | Input tokens | Output tokens | Correct dispositions |
|---|---:|---:|---:|---:|
| Familiar numerical and threshold pairs | 26.541s | 3,102 | 2,631 | 6/6 |
| Timing, causal evidence and square pairs | 35.444s | 2,828 | 2,864 | 6/6 |
| Grammar, duplicate and representation pairs | 38.613s | 2,746 | 3,200 | 4/6 |
| Six independent new situations | 62.153s | 2,804 | 5,375 | 6/6 |

Total time was 162.751s, with 11,480 input and 14,070 output tokens (25,550 total). All usage was known. All twenty-four reasons preceded their verdicts and stayed within the 600-codepoint local bound; the maximum was 534. Four provider reasoning blocks were omitted from evidence; their text and signatures were never saved. There were no retries, warmups, replacement calls, timeouts, truncations, failed envelopes or unattempted cases. The exact four-call maximum was exhausted once.

All fourteen selected original payloads retained their exact content hashes, including the two defective false acceptances. The selector did not repair or rewrite them. The closed identity contract and immutable admission work structurally while leaving semantic errors observable.

No-network replay verifies the frozen sources and dependencies, exact request hashes, native/local response validation and unchanged selected originals. Twenty-six combined offline test groups cover the original contract, previous bounded wrappers and this four-call extension. A single run over eighteen repeated diagnostics and six new situations supplies neither a broad accuracy estimate nor full-worker yield evidence. The slowest final-auditor call alone used 62.153s, so a fourth production stage still requires an independently measured end-to-end deadline and call budget. No production prompt, model setting, routing or deployment was changed by this trial. Do not promote this failed candidate.
