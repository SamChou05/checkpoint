# Can checked examples improve complete question authorship?

The [explanation-capacity trial](QUESTION_MAIN_CAPACITY_RESULTS.md) retained one
useful long explanation under a virtual limit, but did not improve complete-content
counts. Earlier model and review experiments also left faulty keys, explanations
and weak distractors. This experiment changes the author's examples while keeping
its model, rules, goal context and output requirements fixed.

The intervention is a small set of original, independently checked complete
MCQs. They demonstrate interpreting a compact representation, respecting the
limits of evidence, and preserving meaning while evaluating alternatives. The
examples are construction demonstrations, not evidence for new subjects. They
are not chosen from the twelve recent failures or from the new transfer outputs.

## Prospective design

Three fresh goal/source packets cover spreadsheet reference copying, map scale,
and food-web energy flow. These tasks differ from the examples' parcel
routing, experimental design and English reference editing. Exact packets are
fresh; no claim is made that the broader subject areas have never appeared in
prior work. Only payload goals and labeled source summaries enter both arms.
Assessor notes and source-provenance metadata stay outside provider requests.

There are six author-only calls, requesting two questions each at minimum
difficulty 3. The baseline is the actual balanced author prompt under the
`authored_solution` contract. The intervention appends one fixed explanatory
paragraph and the same three subject-context/question examples to that system
prompt. It changes no original instruction or paired user input. Example IDs,
independent review notes and source provenance are excluded from the suffix.

Both arms use Kimi K2.5 with disabled thinking, 6,000 output tokens, temperature
0.2, stem guidance 320, choice guidance 140 and main guidance 320. No larger main
allowance carries over from the previous experiment. The order is baseline/examples
for the first goal, examples/baseline for the second, baseline/examples for the
third. No earlier generated item feeds a later call. Added example context is
part of the intervention; this is not an equal-input-token comparison or a test
of dynamically retrieved demonstrations.

Before dispatch, commit and freeze the fixture, all six exact requests, source
and dependency hashes, example text and settings. Reuse the existing disposable
worker and raw capture: one SDK attempt, read75/connect3, worker90, 32 KiB maximum
serialized request and 192 KiB aggregate. Preserve empty/whitespace response text
and known usage as unusable output. Operational or unfinished/unusable responses
stop remaining calls. Completed nonempty malformed JSON remains captured and
later jobs continue. No repair, retries, replacements, top-ups, model review,
production admission, bank writes or resumed captures.

## Assessment and decision

Retain every raw occurrence, including incorrect, oversized, malformed, missing
and extra items. Missing requested slots fail; extras cannot selectively replace
failures. Parse only whole JSON objects or sole fenced objects using the existing
strict parser, with format failures reported separately from content judgments.

Two independent assistant assessors receive opaque shuffled IDs, exact
stems/choices, raw goals and source summaries. They do not receive the author
key, main, model difficulty, arm, example set or length outcomes. Save both
first passes before showing unchanged mains. Save both teaching passes before
unmasking arms and keys. This is partial masking: a main reveals intended
answers and style can suggest the intervention. Assessments are not human
expert or learner calibration.

Assess the exact task, complete premises, exactly one warranted key, all choices,
three plausible distinct distractors, goal fit, actual cognitive demand and a
wholly supported worked explanation. Do not rescue a missing or wrong answer
by assuming the author meant a nearby problem. Legitimate diagnostic or negative
answers remain eligible. Preserve uncertainty and disagreement.

Report complete-content counts per six requested slots in each arm, then the
counts also fitting the existing stem320/choice140/main420 runtime lengths.
Separately report compliance with main320 author guidance, each semantic
component, and copying or intrusion of example subject matter. Greater brevity
or instruction compliance alone is not a correctness improvement. Difficulty
labels and several written steps do not themselves establish cognitive depth.

More complete supported items in the example arm would be an exploratory
transfer signal; show its distribution across all three goals rather than
hiding a failed domain. Six of six meeting every content and current-length
requirement would be fully favorable for this selected run. Partial benefits
remain observations without redefining that result or the broader user goal.
No small selected run establishes general accuracy, bank yield, learner gains
or reliable adaptive progression. Production integration requires a separate
end-to-end check of the author, verifier and displayed questions; no default
promotion or deployment is part of this experiment.

## Research rationale and limits

Bitew and colleagues reported gains from relevant question-bank examples when
generating distractors, including teacher assessments. Their setting supplied
existing questions and keys; retrieved examples outperformed static ones in the
reported language-learning comparison. That motivates testing examples, but does
not establish that three static cross-subject demonstrations improve complete
MCQ generation in Checkpoint. This experiment is our transfer hypothesis, not a
replication of their retrieval method. [Primary study](https://arxiv.org/html/2307.16338v1)

## Prepared checkpoint and continuation

At the user's pause checkpoint on 2026-09-09, the runner, final three examples
and three transfer source packets are prepared. **No live calls for this
experiment have started.** The [demonstration review](QUESTION_AUTHOR_EXAMPLES_DEMONSTRATIONS.md)
records exact content, identities and limitations; the
[source notes](QUESTION_AUTHOR_EXAMPLES_SOURCES.md) record checked primary pages
and unchanged transfer payload identities.

The full service suite passed 984 tests with no skips. Scoped Ruff and Python
compilation checks passed. Separate harness review found no concrete defect;
the four new tests and seven existing capacity tests passed. These checks
establish runner behavior, not question correctness.

Independent dry validation of the completed fixture passed all six native
Converse request shapes. Serialized request sizes, in planned order, are
12,503; 16,103; 17,082; 13,482; 13,561; and 17,161 bytes (89,892 total).
The plan contains 35 source hashes. Each pair differs only by the example
suffix, and all three transfer payload hashes match the source notes.
This validation created no provider client and made no live call.

To continue, first confirm the saved branch and clean source state. Compile a
new frozen plan with `evals/checkpoint_author_examples_trial.py`, using the
committed fixture and a new plan path. Check source hashes against that commit
and validate all six exact requests before dispatch. Execute the bounded plan
once using renewed AWS access and a fresh capture directory. Then follow the
two-phase masked assessment above; preserve both first passes before revealing
teaching and both teaching passes before revealing keys and arms. Do not reuse
the example-preparation reviewer as an output assessor.

Current repository generation uses the complete-choice solver contract and
blocks explicit uncertainty, zero or multiple supported choices, and unique-key
disagreement before final review. The older assumptions-only diagnosis is no
longer an accurate description of that path. A confidently incorrect support
label, including one contradicted by its own prose, can still pass these
structural gates and a fallible final reviewer. A focused rerun of 23 verifier
tests passed at this checkpoint; one intentionally documents that semantic
limitation. This experiment investigates author quality rather than claiming
that additional examples eliminate it. Deployed-version status was not checked.
