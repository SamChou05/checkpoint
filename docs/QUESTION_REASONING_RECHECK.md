# Reasoning comparison on unchanged runtime questions

September 8, 2026. Prospective protocol, before any calls in this comparison.

The [completed worker-setting qualification](QUESTION_RUNTIME_QUALIFICATION.md)
found a correct answer accompanied by false mathematical feedback and several
unsupported explanations. None of its calls exhausted the output allowance. This
comparison tests whether enabling reasoning changes those outcomes without also
raising that allowance or rewriting the questions and prompts.

## Frozen comparison

Reconstruct the five fresh author candidates from the exact archived raw response
using the current runtime parser and sanitizer, with the original normalized
request. Run the production complete-choice solver and final reviewer twice:

| Arm, in execution order | Model | Thinking | Output allowance | Sampling |
| --- | --- | --- | --- | --- |
| Disabled | Sonnet 4.6 | Explicitly disabled | 6,000 | Temperature 0.2 |
| Adaptive | Sonnet 4.6 | Adaptive, high effort | 6,000 total | No sampling overrides |

The source capture file SHA-256 is
`6b4e90c111164618d042fe7b920d15bf0bd878dbd4b1a397b8de694c95bb3c5d`.
Freeze current runtime and evaluator hashes, dependency versions, normalized
request, exact candidates, and each arm's first solver request before execution.
The runtime source must match the original capture. The new evaluator has its
own provenance; it must not silently claim to be the historical evaluator.

The two solver requests have the same subject content and instructions. Review
requests are constructed normally from each solver's actual results and survivors;
their content can differ. This compares two complete checking paths, not the
isolated effect of reasoning in the final reviewer.

AWS documents that the cap includes thinking and final text, and thinking requires
removing customized sampling. The existing provider helper already implements
this request shape. Both ordinary and thinking token settings are explicitly
6,000 here. [AWS adaptive thinking](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-adaptive-thinking.html),
[AWS compatibility](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-extended-thinking.html).

Each arm permits at most two calls and 240 seconds, with the existing isolated
observer, read timeout 75 seconds, connection timeout 3 seconds and one SDK attempt.
The total is at most four calls and 128 KiB of serialized input, at most 32 KiB per
call. No author, repair, top-off, fallback, retry or replacement arm is allowed.
An operational failure stops the comparison; it is not a content rejection.
Record exact requests and final responses, usage, completion reason, reasoning
block counts, latency, and confirmed cleanup. Local completion is not a remote
cancellation guarantee. No learner inventory or deployed configuration is changed.

## Independent assessment, declared before outputs

Use all five starting items, including rejected items, when describing outcomes.
Score the key, premises, distractors, main explanation, each of four choice
explanations and actual challenge separately. An omitted or rejected teaching
field is unobserved, not a correct explanation. Preserve exact returned wording
and its item/choice association. Do not grade model declarations as truth.

The existing blinded assessments and arithmetic establish these comparison
anchors; their content is never added to model prompts:

| Original raw item | Prospective assessment anchor |
| --- | --- |
| 0: Hospitals | Small hospital follows under a common independent approximately-half sampling model; missing-model ambiguity must be disclosed. Intended work is level 2. |
| 1: Rare-disease test | Posterior is 11/122, about 9.016%. A 50% posterior needs 1% prevalence for the stated sensitivity and specificity. Main and all distractor feedback must be accurate. Level 3. |
| 2: Ice cream and drowning | Confounding is a possible explanation; association alone does not establish a likely actual cause or prove no causal effect. Familiar rule application is level 2. |
| 3: Marbles | Conditional probability is 3/17, about 17.647%, under ordinary independent uniform draws with replacement. Check every calculation and feedback claim. Level 3. |
| 4: Customer survey | Potential selective response affects generalization; low response does not establish response motives or upward bias. The respondent statistic can still be correct. Level 2. |

Use distinct findings for definite falsehood, unsupported strengthening,
assumption-sensitive wording, and plausible but weak distractors. An independent
difficulty judgment is not calibrated psychometrics. Bayes and marbles are the two
previously supported items at the requested level; rejecting everything does not
demonstrate a useful improvement. Examine new claims as well as the known errors.

For a favorable follow-up decision, adaptive must preserve both Bayes and marbles
with sound keys and all ten teaching fields, introduce no new material error, and
show a concrete improvement over the fresh disabled arm. If both arms avoid the
historical mistake, that demonstrates rerun variation rather than an improvement
attributable to reasoning. Rejection for difficulty is distinct from detection of
an incorrect explanation.

The selected questions and one batch per arm cannot estimate production accuracy,
prove a causal effect despite sampling/order variation, or qualify arbitrary
subjects. Assessors know earlier findings; this is not a newly blinded experiment.
Improved checking cannot repair defective frozen questions. A useful result would
justify a subsequent fresh, diverse-goal trial, not automatic promotion. A failure
would redirect work to generation and independently supported teaching content,
not another prompt tweak against these five examples.
