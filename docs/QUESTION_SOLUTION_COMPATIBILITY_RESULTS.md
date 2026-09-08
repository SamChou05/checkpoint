# Solution compatibility results: no added protection

September 8, 2026 UTC. The [frozen sixteen-call comparison](QUESTION_SOLUTION_COMPATIBILITY_EXPERIMENT.md) completed, but the additional mapper did not improve acceptance decisions. The current reviewer and the combined reviewer-plus-mapper retained the same four valid controls and the same defective all-pairs item. The mapper is not being integrated into production on this evidence.

These are eight selected fixed solver records, not fresh generated questions, a production error-rate estimate, or a measure of learning quality. Four authored keys are correct and four are incorrect under the independently recorded assessments. The historical all-pairs record is an explicitly synthetic relocation of preserved real response text, not a newly observed solver response under the current prompt.

| Fixed control | Current verifier | Strict mapper | Combined disposition |
| --- | --- | --- | --- |
| Impossibility only in the answer | Blocks | Blocks: no choice entailed | Blocks |
| Missing speed condition | Blocks: different reviewed key | Blocks: inconsistent record | Blocks |
| Valid count of zero | Retains correct key | Permits | Retains correct key |
| Valid canonical no-solution answer | Retains correct key | Permits | Retains correct key |
| Valid negated grammar task | Retains correct key | Permits | Retains correct key |
| Valid supplied speed condition | Retains correct key | Permits | Retains correct key |
| Relocated all-pairs caveat | **Retains incorrect key** | **Permits incorrect mapping** | **Retains incorrect key** |
| Coherent but wrong HTML solver | Blocks: different reviewed key | Permits agreement with wrong solver | Blocks |

The weaker selected-answer policy and strict policy produced identical dispositions in this run. No additional baseline acceptance was vetoed. The only `not_established` rows belong to the already inconsistent missing-speed record; the record conflict takes precedence over per-choice abstention. There were no uncertain-record or coherent-unresolved-rival abstentions.

## What the reasons establish

The mapper correctly preserved the zero, negative-answer, grammar-negation, and supported-condition controls. It also detected the missing-speed conflict: a conditional one-hour answer cannot support a resolved, assumption-free answer to the unchanged stem. The current reviewer independently selected the correct cannot-determine choice, so the existing answer-agreement check already blocked the authored one-hour key.

For the impossible real-number equation, the mapper incorrectly classified the record as `coherent`, explaining that proving nonexistence counted as resolving the question. This conflicts with the frozen contract's explicit distinction between `resolved` and `no_solution`; it is a contract-classification error, not an error in the nonnegative-square proof. Its four choice refutations were nevertheless correct, so its derived gate blocked the item. The current reviewer already rejected it because no offered choice was correct.

The all-pairs failure is more consequential. Both calls acknowledged or had access to the solver's output-size and expected-hashing qualifications, then accepted the hash-map option without carrying those qualifications into the requested bound. The mapper called the record coherent and treated a description of the method as sufficient support. The reviewer returned an explanation asserting linear overall time while omitting the potentially quadratic output. The returned main and hash-choice explanations therefore retain the original defect. Other sorting-cost statements also require assumptions about the sorting model and are not a remedy for the output-size problem.

The HTML boundary worked as a distinction between agreement and truth: the mapper explicitly recognized that the solver's claim was wrong under the HTML standard but still mapped the stated conclusion to `true`. The current reviewer selected the factually correct `false`, causing answer disagreement and preventing return of the authored key. Compatibility with a solver is not an independent factual check.

The [independent semantic assessment](evidence/solution-compatibility-semantic-assessment-20260908.json) records the per-case reasons and feedback review. All four retained valid controls have supported returned main and choice feedback in their question context. Rejected-item reviewer feedback remains separate from content returned to learners. The predeclared follow-up criteria were not met: the historical incompatibility still passed and there was no incremental supported veto. No prompt was retuned or failed case replaced within this run.

## Operational evidence

Execution used source `04e93046b6985399fff9a13184b32e899bfa8343`, canonical plan hash `ad43b24c7e22039e9a870946d23539dbb329c03ea8966a34547c0c4bd7fc5e67`, and the frozen Opus 4.6 adaptive/high settings. All sixteen calls completed with `end_turn`, two per case, with no retry, malformed output, failed case, or unattempted case. Both roles received the same exact user text, and neither received the authored key or external assessment fields.

All reported input/output usage is known: 15,378 input tokens and 11,310 output tokens, totaling 26,688. The sum of recorded call intervals is 198.898 seconds; this is not an independently measured whole-run wall time or a production latency benchmark. No response hit its output-token cap.

The immutable [capture](evidence/solution-compatibility-capture-20260908.json) has SHA-256 `29b58ead8f4583f5eee89ec874c4c3a5a309f49aa2c46bd97b63efbf24912106`. The [operational audit](evidence/solution-compatibility-operational-audit-20260908.json) independently verifies exact request bindings, order, budgets, usage and completion. Hidden reasoning text is not retained. No deployment, model promotion, or runtime verification change followed.

## Consequence for the next change

This result argues against adding this particular fourth call. It supplies another direct example of a model treating a decisive limitation as a harmless qualification, despite a narrower task and explicit instructions.

A distinct information issue remains worth testing: the current first solver is given the stem without choices, although some valid MCQs put essential data in those choices. Changing only the options can change a question's unique answer while leaving the solver's input identical. A fresh comparison should give the independent solver the complete MCQ while continuing to hide the authored key and feedback, and include valid, zero-answer, and multiple-answer versions of the same stem. That would test restoration of necessary input; it is not yet an implemented fix or evidence that the shared all-pairs error is solved.
