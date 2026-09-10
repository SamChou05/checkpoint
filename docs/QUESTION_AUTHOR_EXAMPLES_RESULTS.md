# Example arm has more supported keys but the same complete-question count

The [prepared six-call comparison](QUESTION_AUTHOR_EXAMPLES_PROTOCOL.md) completed
on September 9, 2026 (Pacific time), after the saved preparation checkpoint.
The example arm had supported authored keys in 3/6 requested slots, versus 1/6
without examples in this selected run. Both arms still produced only one question
meeting all independent content criteria. Neither complete question fits all
current text limits. The intervention therefore does not qualify as a general
correctness fix or a production default.

The comparison held the actual balanced authored-solution prompt, Kimi K2.5,
disabled thinking, 6,000 output tokens, temperature 0.2 and paired source/goal
context fixed. Only the example suffix changed. There were three goals—Excel
references, map scale and food-web energy—with two requested questions per arm
per goal. No model review, runtime admission, repair, replacement, bank write or
deployment was part of these author-only calls.

## Results across all requested slots

“Both” means agreement between two fresh independent assistant assessors, not
human expert validation or measured learner difficulty. Two example-arm slots
failed the frozen strict response-format rule and were not assigned semantic
credit. They are format failures, not two independently established wrong keys.

| Observation | No examples | Three checked examples |
| --- | ---: | ---: |
| Requested slots | 6 | 6 |
| Raw items from strict whole-object responses | 6 | 4 |
| Slots lost to ambiguous duplicate fields | 0 | 2 |
| Unique authored key supported, both | 1/6 | 3/6 |
| Entire authored explanation supported, both | 1/6 | 2/6 |
| Complete content: key, premises, goal, difficulty, distractors and teaching, both | 1/6 | 1/6 |
| Complete content plus current stem320/choice140/main420 limits | 0/6 | 0/6 |
| Parsed main complies with author guidance of 320 characters | 0/6 | 0/6 |
| Parsed main fits runtime 420-character limit | 0/6 | 2/6 |

The complete-content items are q06, a baseline map-scale comparison, and q09,
an example-arm spreadsheet-reference question. q06 has a 325-character stem
and 464-character main; q09 has a 297-character stem and 434-character main.
The frozen backend admission limits exclude both. Their content remains useful evidence;
length rejection is not semantic error detection, and this experiment did not
shorten either item or test whether equivalent teaching could fit.

The transfer signal is uneven. Excel supported keys rose from 0/2 to 2/2 and
complete content from 0/2 to 1/2. Map supported keys remained 1/2 in each arm,
while complete content was 1/2 without examples and 0/2 with them. Neither arm
provided an eligible complete ecology question. The example ecology response
failed strict parsing; the baseline ecology questions have substantive defects.
The frozen fully favorable criterion of six complete example-arm items failed.
One batch per arm and goal cannot establish a causal improvement, general
accuracy, bank yield or learning gains.

## What still failed

| ID | Arm | Finding |
| --- | --- | --- |
| q01 | Baseline | Original 1:50,000 and 150% enlargement imply a 3 cm bar for 1 km, conflicting with the stated 4.5 cm. The 12 cm measurement also shifts from before to after copying. The main uses only the conflicting bar. |
| q02 | Baseline | Multiplies receiver diet shares into prey production as though they were prey allocations, deriving an unsupported minimum of 54. The sum's two contributions do not even preserve the stated 60:40 shares. |
| q03 | Examples | Original 1:10,000 and 80% resizing imply an 8 cm bar for 1 km, conflicting with the stated 2 cm. The main assumes the latter is valid without reconciling the premises. |
| q04 | Examples | Correctly derives `=SUM($B4:E4)`, then falsely describes the repeated cumulative sum as Q3 Jan–Apr sales. A sound key does not make the whole explanation sound. |
| q05 | Examples | Correct 2 km answer and teaching; routine demand and weak distractors. The answer can be obtained with one multiplication using the original map. |
| q06 | Baseline | Complete supported content under both assessments; exceeds stem and main limits. |
| q07 | Baseline | Asks for D5 although the described operations fill only columns B and C. The main invents an operation reaching D5. |
| q08 | Baseline | The stem places product names in column A. The key and main silently substitute prices there. |
| q09 | Examples | Complete supported mixed-reference question and teaching under both assessments; main exceeds 420 by 14 characters. |
| q10 | Baseline | Treats a possible producer-turnover explanation as established by biomass snapshots, and asserts an unsupported relationship between production and standing shellfish biomass. |

The [scoped calculations](evidence/author-examples-20260909/native-checks.json)
confirm the conflicting scale-bar lengths, correct formula displacement and
resized distance. A permitted q04 dataset with January sales 1 and February–April
sales 0 yields E5 = 10 after the described cumulative fills; actual Jan–April
sales total 1. This refutes the teaching claim while preserving the correct
formula answer. These are specific arithmetic and coordinate checks, not a live
Excel execution or an arbitrary-subject verifier.

The final raw response is syntactically decodable JSON but repeats
`explanation` in its first question. An ordinary last-value-wins parser would
discard a conflicting explanation. The existing strict parser rejected the
whole response, preserving both requested slots as format failures.

Root inspected that [unchanged raw text](evidence/author-examples-20260909/malformed-job-5.txt)
only after the masked assessments were frozen. Its stem gives zooplankton
production 800 and producer production 10,000, but keys a claim that transfer
efficiency exceeds 10%. The first explanation correctly notices 8% and the
absence of any supported option, then proposes changing 800 to 1,200. The
repeated explanation calculates 12% from 1,200 while the actual stem still says
800. This is evidence of a stale question paired with rewritten evidence, in
addition to the duplicate-field defect. Neither explanation was selected or
repaired for assessment. The second question remains preserved without a
separate content verdict; strict response failure does not prove it false.

## Assessment and operational checks

Both assessors first saw shuffled IDs, unchanged stems and choices, raw goals
and source summaries. Neither saw the keys, authored mains, model difficulty,
arms, example set, length outcomes, root notes or the other assessment. Both
first passes were finalized and hashed before teaching disclosure. Both teaching
passes were finalized and hashed before keys and arms were disclosed. The main
naturally reveals an intended answer, so teaching-phase masking is partial.

They agree on supported choices, completeness, goal fit, distractor adequacy,
whole-main support and worked-solution completeness. They disagree about q04's
difficulty (3 versus 2) and q08's difficulty (2 versus 3); neither difference
changes the joint complete-content counts. Separate root notes preserve direct
inspection and counterexamples. Post-unmask inspection found no copied parcel,
email or experimental-design task in the outputs; this does not establish an
automatic plagiarism or similarity guarantee.

All six calls completed with `end_turn`, known usage and clean worker exit.
They used 16,825 input and 4,535 output tokens. Maximum per-call output was 1,272
of the 6,000-token allowance. SDK intervals total 51.088009 seconds; worker
intervals total 55.161426 seconds. These are recorded execution intervals, not
a production latency distribution. Neither truncation nor provider failure
explains the content defects.

Independent operational review verified all 35 source hashes against committed
source, dependencies, native request shapes, paired suffix differences and the
89,892 serialized input bytes. Exact replay passed with provider client creation
forbidden. The source milestone passed 984 backend tests with no skips; a focused
23-test verifier rerun also passed. No backend runtime source changed for this trial.

Source commit: `2d10ce9544b7b9b2a029b0f5ac4bb66e226a9640`.
Plan canonical SHA-256:
`1163b513776b9747f64facc008466e6aee72661521026984603a4d364c92b1dc`.
Original capture: 251,917 bytes, byte SHA-256
`9053f1e1dfe11b12a62aba1573293b932b2ed135a24b04877951b663c99e06f5`.
The [evidence directory](evidence/author-examples-20260909/README.md) preserves
all assessment inputs, ten exact parsed objects, the full duplicate-field
response, phase hashes, independent audits and derived counts. The full
source-bearing transport remains local; repository artifacts are not a
standalone provider replay archive.

## Implication for the next change

Checked examples remain a possible authoring aid, but this comparison found
equal complete-question counts. The failures occurred well below the output-token
ceiling. The defects concern whether the final question, all choices and all
teaching describe the same defensible task.

Do not propose explanation-first ordering or independent answer ownership as
untested fixes: the [release record](LEARNING_MAP_RELEASE.md) already documents
the former, and the [solution-construction trial](QUESTION_SOLUTION_CONSTRUCTION_RESULTS.md)
tested the latter with remaining failures. Likewise, the
[short-prompt comparison](QUESTION_PROMPT_EXPERIMENT.md) did not eliminate
knowledge or teaching mistakes. These records argue for reviewing the complete
set of prior interventions before another prompt-only trial. The broader
correctness and useful-learning goal remains open; no production qualification
or adaptive-learning outcome is established by this run.
