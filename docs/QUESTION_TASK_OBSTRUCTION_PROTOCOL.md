# Distinguish a broken task from an intentionally wrong answer

The [split sourced-review trial](QUESTION_SPLIT_EVIDENCE_RESULTS.md) exposed two
related failures: the solver accepted a premise after recognizing its problem,
and its generic issue list rejected valid questions for expected wrong options
or irrelevant qualifications. This candidate changes that decision contract.

Before judging the four exact choices, the solver must classify a task
obstruction as one of four states:

| State | Meaning and application gate |
| --- | --- |
| `none` | No shared task obstruction is established. The diagnostic choice ID must be null; the normal four-choice checks still apply. |
| `answered_by_choice` | An offered answer correctly diagnoses the false premise, inconsistency or information limit. Its ID must equal the sole supported choice. |
| `blocks_all_choices` | The problem prevents every offered answer from satisfying the task; always veto. |
| `uncertain` | The solver cannot establish the appropriate situation; always veto as uncertainty. |

False distractors are expected answer proposals, not facts asserted by the stem.
Explicit hypothetical rules remain valid givens for their own scenario. A
question asking which statement is false can have that false statement as its
correct answer. Missing information can warrant a substantive diagnostic answer;
the solver's lack of knowledge is different. A why-question's wording does not
prove the event or causal claim it presupposes.

The generic solver issue list is replaced by this scoped obstruction record.
The independent teaching audit retains its nonempty material-issue veto and
checks the unchanged main's actual claims, without silently substituting a more
defensible paraphrase. It receives no solver output or discovery hypothesis.
Server acceptance still requires exactly one supported choice, three refuted
rivals, exact authored-key agreement, supported teaching, no material teaching
issues and the diagnostic difficulty floor. No extra approval vote is added.

Internal reasons use the existing 24,000-character whole-response ceiling rather
than the prior 1,200-character per-reason limit. The model's output allowance stays
at 6,000 tokens. Learner-facing text limits are unchanged. This avoids losing a
complete diagnostic solely for its internal reason length; it does not establish
the reason's truth. Short evidence IDs retain the exact acquired-span mappings.

[FalseQA](https://aclanthology.org/2023.acl-long.309/) showed that false-premise
questions can elicit incorrect responses even when its tested models have the
needed knowledge, and studied training to improve rebuttal. A later
[presupposition-free claim-verification study](https://aclanthology.org/2025.starsem-1.20/)
found benefits from questioning unverified assumptions in its own evaluation.
These motivate testing explicit premise assessment; neither establishes that
this prompt, model or application will pass.

## Prospective qualification

Use the four unchanged source-bearing controls from the terminal v2 capture,
with the exact six acquired records and selected offsets, plus all six
[new diagnostic controls](QUESTION_PREMISE_CONTROLS.md). The new controls cover
probability, recipe scaling, Python assignment/copying, lunar phases and average
speed. Their independent assessment metadata, source URLs and answer keys are
excluded from provider inputs. Their source packets are explicitly empty;
assessor research and fixed native checks are not represented as model evidence.

There are ten cases, five valid complete items and five invalid authored items.
Both choices and teaching are checked for every case, even if the first would
veto admission. Freeze all 20 requests, model settings, source and fixture hashes
before dispatch. Use Sonnet 4.6, disabled thinking, 6,000 tokens, temperature 0.2,
static native schemas and the existing 300-second offline worker/read allowance.
Cap at 20 calls, zero fetches and 65,536 serialized input bytes per call. Reuse
durable progress, cleanup checks, no retries and exact no-client replay.

This is a new candidate qualification against frozen independent expectations;
no fresh baseline is dispatched. Comparisons with v3 are descriptive historical
comparisons, not a paired causal experiment. The candidate changes instructions,
the obstruction contract and internal reason bounds together.

Success requires all 40 exact choice judgments and all ten complete main
assessments to be independently supported, all five valid full items retained,
and all five invalid authored items rejected for their actual defects. In
particular, retain correct diagnostic answers rather than treating them as
nonresponsive; catch a false explanation even when its stored key is correct;
and do not veto a valid question merely because its alternatives are false.
Record malformed output, uncertainty, contradictory declarations, wrong factual
objections and justified rejections separately. An empty reference list is not
fabricated evidence, and a valid ID does not prove entailment.

These selected level-2 controls do not qualify fresh generation, advanced
difficulty, distractor discrimination, learner progress, bank availability or
production latency. Passing would justify broader fresh-content qualification.
Failing must preserve the actual result without repairing or relabeling the
captured questions. No production integration, model promotion or deployment is
part of this trial. Source-bearing plans and captures remain local; public
summaries must retain original hashes and clearly identify omitted raw content.

## Source validation before dispatch

The final complete backend suite passed: 972 tests, no skips, using Python 3.12.11.
Scoped Ruff, compilation and `git diff --check` passed. A no-client reconstruction
of the real ten-case plan validated all 20 native JSON schemas and Bedrock
request shapes. The requests total 227,482 serialized UTF-8 bytes, with a
27,376-byte maximum; the plan binds 39 source files and permits zero fetches.
These checks establish the experiment's mechanics, not the model's accuracy.
Independent review also found that Python equality equated an integer source
offset with a Boolean. The new adapter now compares canonical JSON bytes;
a regression reproduced that exact-record gap before the fix and passes after
it. This is record integrity, not a demonstrated model accuracy improvement.

September 9 compatibility correction: after the provider rejected the original
nullable enum representation, [the equivalent union form](QUESTION_TASK_OBSTRUCTION_SCHEMA_FIX.md)
passed 973 backend tests and the same local schema/request checks. The corrected
20 requests total 227,662 bytes, maximum 27,394. Questions, prompts and semantic
gates are unchanged. The corrected run requires a new committed-source plan and
capture; both earlier operational failures remain preserved.
