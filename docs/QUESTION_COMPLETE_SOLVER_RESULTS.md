# Complete-question solver results: better coverage, persistent wrong answer

September 8, 2026 UTC. All sixteen calls in the [frozen first-solver comparison](QUESTION_COMPLETE_SOLVER_EXPERIMENT.md) completed. The complete-MCQ candidate correctly identified the unique key in all five valid controls and detected the grammar questions with zero and two supported answers. It nevertheless made the invalid all-pairs key eligible for review, with additional incorrect complexity reasoning. The current solver also gave an incorrect result and let that item reach review. The predeclared follow-up criteria were not met. No final-review follow-up, runtime integration, model promotion or deployment followed.

These are eight deliberately selected fixed questions with fresh solver responses. No author or final reviewer ran. The results describe eligibility to reach review, not final inventory acceptance, a production error rate, difficulty qualification or generalized learning quality.

| Fixed question | Current stem-only gate | Complete-MCQ gate |
| --- | --- | --- |
| Unique present-tense grammar answer | Blocks: sentences missing from input | Correct unique mapping |
| Unique future-directed non-past answer | Blocks: sentences missing from input | Correct unique mapping |
| Grammar with no non-past sentence | Blocks: sentences missing from input | Correct zero-answer veto |
| Grammar with two non-past sentences | Blocks: sentences missing from input | Correct multiple-answer veto |
| Ordinary no-real-solution answer | Blocks: canonical wording mismatch | Correct unique mapping |
| Boolean pair existence with expected hash-operation conditions | Eligible with supported result | Correct unique mapping; one rationale needs qualification |
| Historical all-pairs complexity claim | **Eligible with incorrect result** | **Eligible with incorrect key** |
| Ordinary cannot-determine answer | Blocks: canonical wording mismatch | Correct unique mapping |

The baseline had two eligible items: one valid control and the invalid all-pairs item. The candidate had six: all five valid controls and that same invalid item. Its four additional valid mappings comprise two choice-dependent grammar cases and two ordinary negative-answer wording cases. Those causes remain separate. Both the candidate's input and output contract changed, so this comparison does not isolate either change's causal effect.

## What improved

All four baseline grammar requests were byte-identical. Their responses correctly noticed that the candidate sentences were absent, but could not distinguish a valid question from either malformed choice set. Blocking the latter for missing input is not successful semantic defect detection. The candidate saw the exact choices and correctly distinguished all four cases, with supported present/past/non-past classifications.

The current solver also correctly proved that no real number squares to minus one and that an unspecified pumping rate does not determine a unique duration. The current gate excluded these valid MCQs because their negative choices differed from the application-owned canonical strings. The candidate's ordinary negative mappings preserved those meanings and refuted the three rivals as answers to the actual task. In the rate question, possible numerical durations were not mislabeled impossible.

The grammar responses use the conventional teaching label “future tense” for `will walk`; the decisive non-past classification is supported. No separate future inflection is asserted. For precise learner feedback, “future construction” avoids the distinction between future reference and inflectional tense discussed by [Cambridge's grammar reference](https://dictionary.cambridge.org/grammar/british-grammar/future) and its [grammar guide for teachers](https://www.cambridge.org/core/books/abs/grammar-for-english-language-teachers/future/42F99CBD7C7C9414B3FA20999CA01457). These solver reasons were not returned to learners.

## What still failed

Both fresh all-pairs solutions silently substituted the familiar one-pass pair-search task for the full question. Neither preserved the potentially quadratic matching-pair output. For an array of n zeroes with target zero, listing every distinct index pair requires n(n−1)/2 outputs. The unchanged stem does not authorize switching to Boolean existence or only distinct value pairs, or excluding output work. An unconditional linear total-time bound is therefore unsupported.

The candidate also stated that constant auxiliary space is incompatible with an O(n) space requirement. That is a definite mathematical error: O(1) space is also O(n) space for n at least one. The nested-loop option remains wrong on time grounds, but a correct rejection label does not make its entire explanation correct. Claims that all hashing operations are unconditionally constant amortized time also omit the required hash-behavior assumptions.

The valid pair-existence key was correctly selected under the expressly supplied expected constant-time hash-operation condition. However, its comparison-sort refutation asserts an O(n log n) upper bound for an unspecified comparison sort. Some comparison sorts can be quadratic; the warranted general reason is the comparison lower bound that prevents a universal expected-linear guarantee. This is a rationale qualification beside a correct key, not a new wrong-key case. Consequently, five correct valid mappings do not establish five complete, fully supported sets of reasons under the strict prospective criterion.

The [independent semantic assessment](evidence/complete-solver-semantic-assessment-20260908.json) records all eight baseline records, all thirty-two candidate judgments and reasons, and the prospective criteria. No case, answer or reason was repaired or replaced after dispatch. The all-pairs failure alone prevents the planned final-review follow-up; the rationale qualification is separately retained.

## Execution evidence and consequence

Source was `e0f8d86eda1e48a89333c6b8e61a5db4c2083a5b`, bound to canonical plan hash `50b9018d13841bad53ff7d337e47cc228db5aa97519467daf5c62fc7a71640a6`. All sixteen calls used the frozen Opus 4.6 adaptive/high settings and ended with `end_turn`. There were no retries, malformed outputs, failed or unattempted cases, or unknown input/output usage. No output-token cap was reached.

Known usage was 15,225 input tokens plus 6,183 output tokens, totaling 21,408. The sum of recorded call intervals was 101.673 seconds; it is not an independently measured whole-run wall time or a production latency benchmark. The immutable [capture](evidence/complete-solver-capture-20260908.json) has SHA-256 `f62718c7573728df00d9d5870df5cb332ef91b1b9cc88f65df3f109d26588a73`. The [operational audit](evidence/complete-solver-operational-audit-20260908.json) verifies exact request/source binding, isolation, budgets, usage and completion. Hidden reasoning and credentials are not retained.

This result preserves a demonstrated input/contract improvement while rejecting it as the correctness replacement tested here. The next useful change should address how a question's claims are grounded and constructed, rather than add another model-produced verdict to this chain. A subject artifact whose displayed content and answer are bound to an actual execution or observation is one candidate mechanism to test. Such a mechanism would need complete, useful questions and supported feedback; a successful tool call alone, a finite timing example, or a trivial formal puzzle would not establish the generalized learning objective.
