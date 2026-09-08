# Fixed-solver answer compatibility diagnostic

Status: prospective, September 8, 2026 UTC. No calls have been dispatched for this experiment. This is an isolated evaluation; it does not change production verification or qualify the question generator.

The exact [dispatch plan](evidence/solution-compatibility-plan-20260908.json) is frozen at source commit `04e9304`, with canonical SHA-256 `ad43b24c7e22039e9a870946d23539dbb329c03ea8966a34547c0c4bd7fc5e67`. It contains sixteen requests totaling 67,914 UTF-8 input text bytes; the largest is 5,819 bytes. Execution uses the dedicated detached worktree at that commit and the recorded Python 3.12.11, boto3 1.43.89, and botocore 1.43.89 environment. Later report commits do not change that source snapshot.

## Question and intervention

The current verifier enforces declared solver outcomes and nonempty limitations, but a report labeled `resolved` can bury a decisive objection in its answer text. The final reviewer already receives that text and instructions to preserve it. Earlier [claim audits](QUESTION_CHOICE_AUDIT_EXPERIMENT.md) and [isolated-choice audits](QUESTION_ISOLATED_CANDIDATE_EXPERIMENT.md) also produced incorrect semantic judgments, so another elaborate checklist is not sufficient evidence of improvement.

This diagnostic holds each question and solver record fixed. One call uses the current final-review role. A separate call checks only whether the full solver conclusion supports the unchanged choices as answers to the unchanged task. It must preserve conditions and negation and recognize conflicts between the declared status and the written result. It does not write teaching feedback, assign difficulty, or establish the solver's underlying factual correctness.

Both calls receive the same question, rotated choices, goal, skill context, and solver record. Neither receives the authored key, author explanation, expected judgments, native observations, or the other call's output. The current verifier constructs the user payload, which is identical for both roles; only their system instructions differ. The order of the two calls alternates by case. There is no author call, fresh solver call, repair, retry, replacement, or top-up.

## Controls and denominators

The [fixture](../backend/bedrock-question-service/evals/fixtures/question_solution_compatibility.json) contains eight selected controls. All pass the current structural and pre-review solver gates and fit the existing 320-character stem and 140-character choice limits. Minimum difficulty is 1 to keep difficulty filtering separate from the compatibility question; these are not calibrated learning or distractor-quality benchmarks.

| Control | Independent assessment before dispatch |
| --- | --- |
| Impossible real-number result only in a `resolved` answer | The authored positive key is unsupported; the record contradicts its declared resolution. |
| Journey time with an unstated speed condition | The solver's conditional result cannot establish the unconditional authored key. |
| Python filter returning an empty list | A valid count of zero remains an ordinary resolved answer. |
| Canonical no-solution choice | A proved negative answer remains eligible. |
| Grammar question asking for the non-past sentence | Negation in the task or answer is not itself an impossibility finding. |
| Journey time with speed explicitly supplied | A justified condition must be preserved without causing rejection. |
| Historical all-pairs caveat relocated into the answer | The solver's complete qualifications do not establish the unconditional linear-time key. |
| Internally coherent but factually wrong HTML solver | Agreement with its claimed `true` is compatibility, not correctness; the actual property is `false`. |

Seven records are synthetic. The eighth is an explicitly synthetic field relocation of a historical real response: its exact answer and exact limitations are joined with one newline into `answer`, `limitations` becomes empty, and `outcome` is set to `resolved`. The original question and source record are retained in external provenance. This is not a newly observed response under the current solver prompt.

The HTML reference and a [native browser observation](evidence/solution-compatibility-html-native-20260908.json) are held outside both provider inputs. They establish the independent factual assessment without instructing the mapper to repeat that answer. The four valid controls and four incorrect authored keys are reported separately. All eight controls and all sixteen planned calls remain in the denominator, including unattempted or failed calls.

## Decisions and scoring

The mapper must return a coherent, inconsistent, or uncertain record assessment and exactly one row for each unchanged choice. Choice relations are `entailed`, `contradicted`, or `not_established` **as answers to this task**, not isolated sentence truth. For example, identifying a false statement is a legitimate task. Conflicting solver statements do not authorize arbitrary conclusions.

Code derives two distinct observations:

- Selected-answer compatibility: a coherent record has exactly one entailed choice and it matches the authored key.
- Strict mapper eligibility: selected-answer compatibility also has all three other choices contradicted as answers. For a coherent record, an unresolved rival prevents this eligibility and is recorded as abstention, not successful defect detection. An inconsistent-record finding takes precedence over unresolved choice rows; its reason is independently assessed as a record conflict.

The proposed combined disposition is the unchanged baseline verifier's acceptance AND strict mapper eligibility. The mapper cannot rescue a question that the baseline rejects. This paired diagnostic estimates the consequence of adding this particular veto to each observed baseline response. It does not compare the extra call against spending the same additional budget on another ordinary reviewer, and it does not claim statistical independence between calls to the same model.

Before considering a fresh-solver follow-up, the three targeted incompatible records must be blocked for supported semantic reasons, all four valid controls must retain the correct mapping, and at least one observed baseline false acceptance must gain a supported veto. Malformed output, provider failure, uncertainty, or an unrelated difficulty rejection earns no defect-detection credit. Reasons and scope matter, not just label agreement. Per-choice labels after an inconsistent-record finding are not exact-match scored as though the inconsistent record were a valid proof.

The HTML boundary is assessed separately: mapping the solver's wrong conclusion is never a factual success. If the mapper instead uses independent subject knowledge to reject it, report that reasoning separately from record compatibility. This set lacks a valid canonical cannot-determine control and a task whose essential data is supplied only in the options; those require follow-up coverage. No result from eight selected records establishes arbitrary-subject correctness, question-bank yield, useful challenge, learning gains, or accurate teaching feedback. Meeting the narrow criteria would justify another bounded integration test, not deployment.

## Execution contract

The dry-by-default runner freezes the exact sixteen request bodies, prompts, fixture, current source hashes and revision, dependencies, model settings, and limits. Execution requires the frozen canonical plan hash and an exact current rebuild. It runs from the matching isolated source snapshot and writes a new capture directory; it cannot overwrite or silently resume a prior attempt.

Use the already available `us.anthropic.claude-opus-4-6-v1`, adaptive thinking with high effort, and a maximum of 16,000 output tokens per call. Limits are sixteen calls total, two per case, one SDK attempt, a 3-second connect timeout and 100-second read timeout, 32,000 UTF-8 text bytes per call and 512,000 total. Text-byte and output-token ceilings are not a dollar-cost cap. Dispatch intent and exact requests are saved before each call. Preserve received final text, usage, stop reason, elapsed time, and reasoning-block presence; do not retain hidden reasoning text.

An operational or required-format failure stops the run without retries or replacement cases. Unknown usage after a timeout remains unknown. The 100-second local timeout does not establish readiness for the production worker's shorter per-call timeout or total deadline. A fourth production call would also require changes to the current three-call admission estimate and shared call budget; none are made here.

## Research informing the hypothesis

[Using contradictions improves question answering systems](https://aclanthology.org/2023.acl-short.72/) tested contradiction and entailment signals with calibrated QA models and found small improvements in some settings. It motivates measuring contradiction separately; it does not validate this prompt, model, or generated-question pipeline. [On Reference (In-)Determinacy in Natural Language Inference](https://aclanthology.org/2025.findings-naacl.450/) shows that context mismatches can cause false entailment and contradiction judgments. Accordingly, this diagnostic preserves the complete task and qualifiers, allows uncertainty, and checks the model's reasons independently. These are design hypotheses informed by research, not guarantees supplied by the papers.
