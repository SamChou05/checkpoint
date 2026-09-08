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

## Recorded results

The frozen comparison completed four calls at source
`518df3e174654935e3b463f5962e752277da1bce`. All returned `end_turn` with confirmed
local cleanup. There were no retries, repairs, replacement operations or unknown
usage. Both solvers declared the same five supported keys and fifteen refuted
alternatives. Reasoning did not improve their declared admission decisions.

| Observation | Disabled | Adaptive/high |
| --- | --- | --- |
| Calls completed | 2 | 2 |
| Runtime items returned | 0 | 5 |
| Input / output tokens | 4,506 / 2,385 | 4,447 / 8,150 |
| Sum of observed call process intervals | 34.0 seconds | 91.9 seconds |
| Reviewer output tokens | 1,081 | 5,843 of 6,000 |
| Structural result | Entire review rejected for malformed JSON | Five policy-2 items returned |

The disabled review used a comma instead of a colon after the `About 50%` feedback
key, at zero-based character 1,387. This was ordinary invalid JSON, not truncation,
a duplicate-key rejection, or a factual rejection. No malformed content was
repaired or admitted. Four other item objects can be decoded in isolation for
diagnostics, but that is not a supported runtime acceptance route. The raw
unaccepted text repeats the incorrect claim that a 50% posterior requires about
50% prevalence. The unchanged numbers instead require 1% prevalence.

The adaptive reviewer completed close to its token cap; it did not exhaust it.
That is evidence about this batch's fit, not assurance that 6,000 suffices for more
demanding batches. Process intervals above sum individual local calls; they are
neither production latency estimates nor the exact whole-run wall clock. Total
usage was 19,488 tokens: 8,953 input and 10,535 output.

### Content assessment

Two assessors examined separate item groups with treatment labels and model
difficulty hidden. They knew earlier findings, so this was treatment masking,
not new answer-key blindness. They froze exact-field assessments before seeing
the treatment mapping. All 25 absent disabled teaching fields remain unobserved;
none receives correctness credit. All 25 adaptive fields were assessed.

| Adaptive item | Independent result |
| --- | --- |
| Hospitals | Conventional key and teaching require the unstated common sampling model. Feedback again claims that no additional information is needed. Level 2. |
| Rare-disease test | Correct approximately-9% key and main calculation. The old 50%-prevalence mistake disappears. Calling 1% near the prior remains misleading when the actual prior is 0.1%; it is not an explicit false equality. Level 3. |
| Ice cream and drowning | Main and every choice explanation promote a possible confound to an established explanation, including unsupported claims that it fully explains the pattern. Level 2. |
| Marbles | Correct approximately-18% key and materially sound five-field teaching under ordinary independent uniform sampling. Level 3. The selected-answer feedback shows the derivation omitted from the shorter main. |
| Customer survey | Main mislabels 80% satisfaction as a response rate; actual response rate is 20%. Four of five teaching fields contain false or unsupported statements, including established upward bias and an unqualified margin-of-error claim. Level 2. |

The model again rated the questions `[3,4,3,4,3]`; the independent ratings remain
`[2,3,2,3,2]`. Only marbles satisfies the predeclared complete-teaching criterion at
the requested challenge. This is not a one-in-five production accuracy estimate.
The favorable follow-up criterion failed: Bayes and marbles did not both receive
ten sound teaching fields, and new material errors appeared.

Independent survey counterexamples make the inference failure concrete. The
1,600 satisfied respondents are compatible with population satisfaction of 16%,
80% or 96%, depending on the 8,000 nonrespondents. The counts establish neither
the existence nor direction of bias. All three populations preserve the exact
displayed counts. [Native calculations](evidence/reasoning-recheck-native-checks-20260908.json).

Some returned mathematical text also contains literal Unicode escape sequences,
such as `\u00d7`, inside already decoded explanation strings. This is a separate
display-quality observation, not evidence that the underlying calculation is
wrong. The captured content remains unchanged.

## Decision and next mechanism

Do not promote adaptive thinking on this evidence. It produced parseable output
and avoided one previous false claim, at greater observed token use and latency,
but did not establish accurate complete teaching. Neither a formatting failure
nor a supported label establishes semantic correctness.

The next content experiment should give the final reviewer an already completed
worked explanation to assess, and preserve that exact explanation on acceptance.
The current final stage writes new teaching after the independent solution, so
its newly introduced claims are not subsequently assessed as an immutable object.
This is an enforceable construction gap even though an immutable model audit can
still make mistakes, as the [earlier CSS trial](QUESTION_FRESH_AUTHOR_IMMUTABLE_RESULTS.md)
demonstrated.

A high-level UI check also found that four choice explanations are not required
for teaching or grading. `Question.feedbackExplanation(for:)` uses the selected
choice's explanation when present and otherwise returns the main explanation;
saved history preserves that displayed text. Existing validation tests explicitly
support zero, one or four feedback entries. The four-entry requirement comes from
the backend reviewer contract. A prospective complete worked explanation with
optional, justified choice feedback therefore fits the current product. It must
still evaluate all four choices, retain plausible distractors, and teach the
decisive reasoning. Removing feedback after observing its errors would not count
as an experimental success, and accurate main explanations must be qualified on
fresh, diverse goals. The current survey and causal main explanations also fail;
simply removing their choice feedback would not fix them.

Provider-enforced structured output is a separate candidate for preventing the
observed JSON syntax failure. AWS exposes schema-constrained output through
Converse; this constrains format, not the truth of claims. Compatibility, exact
schema constraints and runtime behavior need qualification before integration.
[AWS structured outputs](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html).

## Evidence and validation

- [Exact capture](evidence/reasoning-recheck-capture-20260908.json), file SHA-256
  `604a8ec64ac3fa0e3c12643f2878f3639cf378810238783d8cd400074e091214`.
- Plan SHA-256 `addd6a7b7bb3b8372dd11cd9da32c9d22f2f96f8938c9b4aa9f723627814e34b`.
- [Independent operational, parse and solver audit](evidence/reasoning-recheck-operational-audit-20260908.json)
  rebuilt the exact plan and replayed the full report with clients and observer
  creation prohibited. Replay establishes internal consistency, not truth.
- [Masked assessment A](evidence/reasoning-recheck-assessment-a-20260908.json),
  [masked assessment B](evidence/reasoning-recheck-assessment-b-20260908.json),
  [treatment mapping](evidence/reasoning-recheck-treatment-mapping-20260908.json)
  and exact input packets are archived together.
- [Summary and evidence hashes](evidence/reasoning-recheck-summary-20260908.json).

Seven new focused tests pass; the full repeat run passed all 864 backend tests.
The initial full run hit an unchanged orphan-cleanup assertion. Three bounded
local diagnostic repetitions confirmed cleanup, with no surviving marker, and
the full repeat run passed. The original cause remains unproven; no timeout or
assertion was weakened. Its [diagnostic record](evidence/reasoning-recheck-cleanup-diagnostic-20260908.json)
is preserved separately from the successful model run.

No production model setting, prompt or deployment changed.
