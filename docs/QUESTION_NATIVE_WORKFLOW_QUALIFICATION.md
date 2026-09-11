# Fresh native workflow qualification

This prospective evaluation checks the combined context, source-guidance and
output-order corrections from candidate `2aa085a`. It extends the existing runtime
qualification runner. No model result has informed these fresh inputs. The
preparation and scripted checks are not evidence of question correctness.

## Question and scope

Can the combined candidate turn ordinary learning goals into useful, correct
multiple-choice practice through the actual native author, sanitizer, solver,
reviewer, bank delivery and client feedback paths? Assess questions, every choice,
the key and all learner-facing teaching separately. Model agreement and JSON
validity cannot answer that question by themselves.

The fixed [fixture](../backend/bedrock-question-service/evals/fixtures/question_native_workflow.json)
contains three fresh goals, requesting five items each at difficulty three:

| Goal | Coverage |
| --- | --- |
| Sound intensity and decibels | Quantities, units, logarithmic comparisons, and independently calculable answers |
| English conditions and scope | Case text, qualifications, negation, competing interpretations; no supplied source |
| Plant water transport | Learned mechanisms, visible case facts, environmental qualifications, and causal explanations |

Physics and biology receive short, assistant-written selective study notes
checked against [OpenStax Physics](https://openstax.org/books/physics/pages/14-2-sound-intensity-and-sound-level)
and [OpenStax Biology 2e](https://openstax.org/books/biology-2e/pages/30-5-transport-of-water-and-solutes-in-plants).
They are paraphrases, not acquired full pages or quotations, and their selective
coverage is explicit in the model input. The fixture is study material, not
product prompt changes or answer-specific instructions. English relies on
established language knowledge and the case material the author displays.

This is an initial-practice check with empty history and no supplied skill map,
adaptive plan or explicit client-derived target override. The existing Swift
delivery helper reconstructs precisely the raw fields used here. This evaluation
does not qualify adaptive selection, skill-map generation, unseen source text,
all domains, other models, long-term learning gains or deployed queue/refill
behavior. The prior unsupported-third-operand failure remains unresolved evidence;
it is not rerun merely to obtain a better outcome.

## Fixed execution contract

One native workflow arm uses Kimi K2.5 authoring and Sonnet 4.6 checking, disabled
thinking, temperature 0.2, and 6,000 output tokens. Use reviewer-written feedback,
three ordinary generation attempts and six provider calls per goal: at most
18 calls across 15 requested slots. Runtime content replacement and repair follow
the current code within that allowance. A response rejected for format or
insufficient content remains a content/availability observation; it is not a
successful factual catch. Provider, capture, correlation, cleanup or persistence
failure stops later dispatch. Do not resume, replace or top off the trial outside
the frozen runtime allowance after an operational failure.

Each goal has a 240-second operation clock. Each serialized request has a
32 KiB ceiling. The existing isolated caller keeps one SDK attempt, read timeout
75 seconds and connection timeout three seconds. Its fixed read window makes
late admission conservative relative to the deployed client factory. Local
timeout does not establish remote cancellation or zero usage.

Freeze the exact source revision and source/dependency hashes, raw fixture,
normalized requests, settings, operation order, native prompt text, complete
serialized schema bytes and hashes, and first requests. Persist every subsequent
dynamic request before dispatch. The new mode requires an exclusive claim beside
the frozen plan so changing the output directory cannot repeat an executed plan.
Old modes keep their historical legacy transport. Replay reconstructs all native
adaptation, replacement, admission and accounting without SDK or socket access.

## Assessment before release decisions

1. Preserve every parseable raw author occurrence with its call/index identity.
   Independently assess the literal stem and all four choices before revealing
   its key, author explanation, solver verdicts, reviewer output or survival.
   Retain ambiguity and missing-premise judgments explicitly. Then assess the
   authored key and main explanation against that prior assessment.
2. Inspect every actual returned item and all final teaching, even when the key
   is correct. Track relationships through sanitization, choice shuffling,
   filtering, replacement and reviewer writing. A wrong draft replaced by a sound
   item differs from a wrong draft admitted, a valid draft wrongly vetoed, or an
   error newly introduced in final feedback.
3. Run returned batches through the existing offline prepare/claim helper and
   the real Swift decoder, whole-batch sanitizer, persistence round trip and
   feedback composer. Retain all losses and all four composed feedback displays
   for every client-retained item. Independently assess those exact displays,
   including contradictions between a choice explanation and the main solution.

For every stage, record unique supported answer, key agreement, distinct and
plausible distractors, factual explanation support, ambiguity, goal relevance and
actual cognitive difficulty as separate judgments. A simple recall question with
a difficulty-three label does not establish useful level-three practice.
Calculate exact numeric cases independently; use authoritative subject sources
to resolve relevant factual claims. Language judgments must preserve defensible
readings instead of automatically treating the authored interpretation as unique.
Record unresolved assessor disagreements rather than silently selecting a key.

Two independent assessors evaluate each raw occurrence and each final teaching
packet. Both save stem/choice judgments before receiving authored keys or
teaching. They then save teaching judgments without seeing runtime verdicts.
For aggregate counts, an item is useful only when it has one warranted keyed
answer, complete required premises, goal relevance, distinct plausible
distractors, supported complete composed teaching and assessed difficulty at
least three. Both assessors must support those conditions, or a recorded
adjudication must resolve their disagreement with an explicit derivation or
authoritative evidence. Unresolved items remain visible and do not enter the
confirmed-useful numerator. Report agreed defects and disagreements separately;
do not turn conservative exclusion into a claim that an item is definitely wrong.

Report raw-author occurrences, runtime returns, bank-claimable items,
client-retained items and correct/useful client-retained items separately. Keep
all 15 requested slots in coverage denominators; an empty return has zero
coverage and undefined precision. Report malformed, timed-out and unattempted
output separately from content correctness. Three selected goals cannot estimate
a production error rate or prove generalized reliability. A passing local check
does not authorize deployment.

## Preparation verification

All 1,069 backend tests pass, including the 32 unchanged historical runner tests,
12 new native-workflow tests and 12 offline delivery tests. The new checks cover
actual scripted native generation, ordinary replacements, malformed output from
each stage, unknown usage, failed replacements with partial returns, exact replay,
frozen prompt/schema/source drift and duplicate execution prevention. The delivery
tests preserve completed, content-failed and empty operations through real
prepare/claim code. Whole-service Ruff, compileall and diff checks pass.

The restored optional Swift helper compiles in a temporary copy of the existing
project. Its synthetic feedback control passes on the dedicated iPhone 17 Pro
simulator, with one test and no skips. This is preparation evidence only; actual
generated content must still run through its capture test and exported attachment.
The ordinary Xcode project and runtime modules are unchanged by this evaluation.
Independent review found no blocking issue in the native request/replay guards,
delivery-source binding, fixture or assessment protocol.

The first serialized author requests use 13,652, 12,449 and 13,961 UTF-8 bytes
in fixture order. Later solver/reviewer request sizes depend on generated content
and remain subject to the 32,768-byte limit. The plan binds 35 runtime files and
93 delivery files before inference. No provider call has been made for this
fixture at the preparation milestone.

From the backend service directory, prepare a plan using
`python evals/checkpoint_runtime_qualification.py --fixture evals/fixtures/question_native_workflow.json --output PLAN_DIRECTORY`.
Execution uses the resulting plan file, its exact canonical SHA-256, the
`--execute` flag and a new output directory. The output directory must not be
changed to repeat an already executed plan. After a terminal capture, run
`evals/checkpoint_native_delivery.py` with `--capture` and a new `--output` file;
that wrapper requires an exact network-free replay before bank delivery.
Supply the resulting report to `QuestionDeliveryCaptureTests` in the temporary
scheme's explicit TestAction environment, require the capture test to run without
a skip, and export its JSON attachment. The attachment's fixture hash must match
the exact report bytes before assessment.

Record the frozen plan hash and any terminal live capture separately before
interpreting factual quality or drawing release conclusions.
