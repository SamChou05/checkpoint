# General question-generation context and output corrections

This change fixes four concrete input/output problems in the generalized quiz
pipeline. It preserves the same learning goals, adaptive difficulty rules,
generation/solver/reviewer stages and acceptance gates. It does not introduce
exam-specific rules or certify model-generated answers as facts.

## Runtime behavior

1. **Preserve subject meaning before generation.** Goal title, focus, current
   level, learning target, question directive and explicit topic examples retain
   meaningful whitespace, notation and Unicode. For example, quoted `"a  b"`
   and `"a b"` stay distinct, indented code keeps its layout, and `Learn A minor`
   retains `A minor`. The app no longer strips signs or decimal points from the
   subject. Existing size/type limits and transport/control cleanup still apply.
   Optional skill-name suggestions are omitted when distinct subject examples
   collide under the skill-name identity rules; the complete goal remains
   available for inference.
2. **Give checking stages the intended objective.** An optional candidate
   objective label now survives into solver/reviewer context. This matters when
   a derived objective ID has no matching definition in the supplied skill map.
   Private author keys and other excluded metadata remain hidden as before.
3. **Use consistent study-source instructions.** The author and current checking
   stages share `question_source_guidance.py`. Relevant substantive study facts,
   fictional rules and established subject knowledge may support a question.
   A title or unfetched URL cannot supply unseen evidence. A particular passage,
   table, code sample or other case stimulus needed for the task must be visible
   in the question or choices. Learned knowledge need not be restated in a way
   that gives away the answer. Qualifications and truncation remain explicit;
   untrusted source commands cannot change model instructions.
4. **Preserve intentional explanation order.** Solver examples and native choice
   properties now use `choice, reason, judgment`. Native author properties
   preserve the existing prompt's `prompt, explanation, expectedAnswer, choices`
   sequence instead of alphabetically writing choices before the task. Only
   those two schema property paths change order. All fields, types, required
   arrays, other contract bytes and admission rules remain the same. Metadata
   hashes the actual transmitted schema string.

The author schema emits required fields before optional skill/objective
metadata. Its important required-field order matches the existing author
prompt. Legacy author instructions already used that order; legacy solver
requests now receive the reason-first example without a native schema.

## Implementation lineage and evidence

Runtime code and directly relevant regressions are preserved byte-for-byte from
the tested candidate `7e5a857`, applied to current `main` at `a4e3bf1`. Existing
model-comparison provenance adds the new shared source module to its explicit
dependency list. The preparation runners, frozen historical fixtures and large
experiment archives remain in their original committed branches; this branch
does not weaken their source guards or reinterpret their outputs.

The underlying fixes are `ec17ecb` (subject context), `cf29ad9` (objective
context), `8d35e4c` (shared source instructions) and `7e5a857` (output order).
The candidate passed all 1,138 backend tests before this integration.

The [paired solver-order results](https://github.com/SamChou05/checkpoint/blob/b87086f3ddd827d900c574d9109bb87740b20194/docs/QUESTION_SOLVER_ORDER_RESULTS.md)
provide the narrow behavioral evidence for reason-first. Among 30 available
scored subject/repeat pairs, six improved only with reason-first, 22 were correct
in both and two failed in both. The six improvements span four distinct
subjects. Ten planned pairs were incomplete after a format rejection, a timeout
and unattempted requests. Independent assessment found seven verdict/reason
contradictions among 36 available scored judgment-first responses and none among
30 reason-first responses. These selected repeated subjects are not a production
accuracy estimate.

The native author correction restores the existing prompt order documented in
[the release history](LEARNING_MAP_RELEASE.md); it is not a claim that a new
authoring experiment succeeded. The shared source-instruction correction was
not included in the ordering trial. Correctness of the combined candidate still
requires fresh full-workflow evaluation.

## Verification and release boundary

Regression tests inspect actual normalization, encoded app payloads and provider
request construction, including source/objective context and native schema
order. Scripted replies exercise routing and unchanged gates; they are not
evidence that a model follows every instruction or gives correct answers.

The integrated branch passes all **1,045 backend tests** and **142 affected iOS
simulator tests**, with no failures or skips. The iOS run covers question
validation, goal creation, backend engine contracts and skill maps on the
dedicated iPhone 17 Pro QA simulator. The 138 focused backend tests, whole-service
Ruff, compileall and diff checks also pass.

SAM build succeeds. Each of the three function artifacts contains all 24 runtime
Python modules byte-for-byte as tested, including the new shared source-guidance
module. Isolated packaged-SDK validation uses boto3/botocore 1.43.91 from each
artifact and accepts all six native request contracts without provider calls.
These checks establish package inclusion and SDK shape support, not cloud model
obedience or deployed behavior.

The known unsupported-third-operand question still passed both arms of the
isolated ordering trial. A consistent explanation can still be false, and a
reviewer can still generate faulty teaching after a correct key. Full-workflow
qualification must assess fresh stems, every choice, keyed answers and every
final learner-facing explanation together, while keeping unavailable or malformed
results separate from factual catches. Source text previously discarded by
truncation is not recovered by these changes.

Model settings, output-token allowances, source limits, verification policy
revisions, native/legacy deployment defaults and infrastructure are unchanged.
This is a review candidate. No deployment or production release qualification
has occurred.
