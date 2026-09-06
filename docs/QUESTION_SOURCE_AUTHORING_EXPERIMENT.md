# Evidence before authorship: matched feasibility comparison

Status: completed on September 6, 2026; **the prospective success criteria were not met**. Giving the author inspected primary-source summaries produced mixed content results across two fresh goals and still allowed unsupported feedback and missing conditions. None of the twelve candidates combined complete supported reviewed content with independently assessed difficulty at least 3. These small samples do not establish a causal improvement or a production error rate. No production configuration was promoted or deployed.

The preceding [solver outcome gate](QUESTION_SOLVER_OUTCOME_GATE.md) closed an enforcement gap, but live controls still failed when the solver incorrectly declared `resolved`. This experiment changed evidence access before authorship. Its method and success criteria below were committed before execution in `6662f6b`; the bounded runner and tests were committed in `b6fdae1`.

## Results and independent assessment

Each cell below counts actual authored candidates, including those later excluded. Twelve candidates produced sixteen distinct exact displays because some choices were normalized or reordered; those additional displays are not new samples. Two assistant reviewers assessed the domain whose source packet the other reviewer had prepared. They froze literal answer, distractor and difficulty judgments before seeing arm labels, model keys, explanations, difficulty ratings or acceptance decisions. They then separately assessed authored explanations and all reviewer feedback. These are independent assistant assessments, not human educator review or calibrated measures of learning.

“Complete supported content” requires an unqualified supported question and key, the reviewer’s main explanation, and all four choice explanations without a material unresolved defect. It does not, by itself, certify challenging distractors. An unsupported claim is stronger than the inspected evidence establishes; that is not automatically proof that it is false.

| Goal and author arm | Authored | Returned | Complete supported content, all candidates | Independently rated ≥3 | Complete content and ≥3 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Plant propagation, goal-only | 3 | 3 | 0 | 2 | 0 |
| Plant propagation, source-first | 3 | 3 | 2 | 0 | 0 |
| Accessible forms, goal-only | 3 | 0 | 2 | 0 | 0 |
| Accessible forms, source-first | 3 | 2 | 1 | 0 | 0 |

Source-first had 3/6 complete supported candidates, compared with 2/6 for goal-only. The direction differed by goal: plant content improved descriptively, while forms content declined. Among returned items the counts were 3/5 and 0/3, respectively, but that comparison excludes two supported goal-only forms items rejected for difficulty. It must not be used alone to claim an improvement. Supported individual choice explanations were 20/24 versus 19/24. Plant best-listed-key agreement permits wording caveats; forms literal-warranted-key agreement does not. Those differently defined counts are preserved separately rather than combined as “correct answers.”

Concrete failures identify what the next intervention must preserve:

- **Evidence was extended into an unsupported mechanism.** A returned source-first plant question attributed injury to sunlight “amplified by the sealed cover”; its reviewer said the cover “intensifies light.” The extension sources support excessive heat/light injury and ventilation guidance, not this optical-amplification claim. The useful advice to avoid excessive exposure does not validate the added mechanism. Another choice explanation called rooting hormone “unrelated” to water absorption, overlooking its potential indirect effect through root growth.
- **A condition stated by the solver disappeared in acceptance.** A returned source-first forms item described an `aria-label`, a date-format placeholder and no nearby visible label. Its solver conditioned failure on there being no other adequate visible label or instruction, yet emitted `resolved` with empty required assumptions. The final review accepted the unconditional failure answer. The literal stem did not rule out adequate instructions elsewhere; the reference does not mandate an adjacent text label in every case.
- **Correctly rejecting one assertion did not establish the replacement explanation.** A goal-only speech-control item falsely claimed the accessible name `Email address` did not contain the visible text `Email`. The reviewer caught that substring error. Its alternative blamed an unassociated label for the speech-command failure without establishing the speech system’s matching or activation behavior. Runtime answer disagreement excluded the question, but this was not a validated repair of the causal question.
- **Difficulty remained overstated.** Every source-first item was independently rated level 2. Many distractors used obvious absolute claims or repeated the same weak misconception. The two goal-only items rated level 3 still had material content/feedback qualifications. A scenario or a model-assigned level 3 did not establish the requested cognitive work.

Both plant batches returned all three candidates. The source-first forms batch returned two and excluded one for difficulty. The goal-only forms batch excluded one for answer disagreement and two for difficulty. A difficulty exclusion is not credited as detection of a factual defect.

## Execution and archived evidence

The single execution used a clean worktree at `b6fdae1` and the frozen plan SHA256 `eacd50347f10905cf62c1ac4a0e37d28dc695d52c83d20089f8e76c1b60bcd27`. All twelve provider calls completed normally with `end_turn`, known usage, no retries and no replacement cases. Total usage was 26,451 input and 28,666 output tokens; the largest output used 5,255 of the 16,000-token allowance. Output truncation did not explain these failures. All responses contained a reasoning block; its private text was not retained.

The four jobs took 145.302, 81.465, 104.404 and 124.046 seconds, respectively, summing to 455.217 seconds. One author call took 84.204 seconds, exceeding the deployed worker’s 75-second read setting while fitting the experiment’s 100-second limit. This is not a production latency qualification. Input text totaled 116,750 UTF-8 bytes; this is not a token or dollar measurement.

- [Exact live capture](evidence/source-authoring-feasibility-20260906.json), SHA256 `cb3b3442eb6159e55c703edd14e0dcdb61b50835f83fd7e1f2e96a5da5de8a91`, preserves the plan, source/prompt hashes, actual requests and final responses, all candidates, feedback, usage and exclusions.
- [Independent adjudication archive](evidence/source-authoring-adjudication-20260906.json), SHA256 `8c7646b57400ada8244090da607f7bf18bbaf31390de61aa72ce1e6b5b343d5b`, preserves all eight original input/review documents verbatim with hashes and explicit joins to the twelve captured candidates. Blind input coverage, frozen review IDs, raw/display question content, solver/reviewer records and returned status were checked against the capture. The live capture’s historical `feedback_assessment: unassessed` state is intentionally unchanged; the separate archive records the later assessment.

The runner milestone passed 462 backend tests with one skip, Ruff and `git diff --check`; the evidence milestone adds integrity checks without changing runtime behavior. Source summaries were manually selected and inspected before authorship. This run did not implement automatic retrieval, validate arbitrary goal coverage, resolve the old invalid controls, recheck existing inventory, or measure adaptive learning outcomes.

The result supports retaining evidence fidelity, necessary conditions and teaching-feedback correctness as separate requirements. Adding a source packet alone is insufficient. A next construction or verification mechanism must demonstrate those properties on fresh items as well as the unresolved controls; another matching model verdict or a higher returned count does not supply that evidence.

## Question and matched conditions

Does giving the author relevant primary-source material improve the questions it chooses to write, compared with supplying that material only to the checker? Prior [evidence-assisted review](QUESTION_EVIDENCE_EXPERIMENT.md) and [isolated candidate review](QUESTION_ISOLATED_CANDIDATE_EXPERIMENT.md) did not test that intervention. Neither stronger reasoning nor an explicit outcome field has qualified the current solver on the known defective controls.

Two new ordinary learning goals cover indoor plant propagation by stem cuttings and accessible web forms. University extension publications and W3C guidance provide short, independently inspected summaries. These were selected and paraphrased by the assistant before any generated item was seen. They test evidence use; they do not establish automated retrieval, coverage of arbitrary goals, or the accuracy of unchecked summaries.

Each goal has two arms:

- `goal_only`: the author receives the goal and focus areas with no source documents.
- `source_first`: the author receives the identical request plus the reference packet.

Both arms' solver and reviewer receive the **same full reference packet**, with the same normalized goal and constraints. That holds checker evidence access fixed and isolates author access to the packet. The goal-only arm is therefore an evidence-assisted baseline, not a claim to reproduce deployed defaults. Arms run in alternating order by goal, with fresh calls and no cross-arm context or earlier inventory.

Each arm requests three questions at minimum difficulty 3. The current author, solver, and reviewer prompts and application sanitization/acceptance rules are unchanged. The experiment makes one author call and, for surviving candidates, one solver call and one reviewer call. There are no repairs, retries, top-ups, skill inference, or learner simulation. All raw author candidates and all returned reviewer feedback are retained, including questions later excluded for difficulty or formatting.

## Limits and evidence capture

The existing Opus 4.6 US profile uses adaptive thinking, high effort, and 16,000 output tokens per call. The run permits at most twelve calls total and three per arm, with one SDK attempt, a three-second connection timeout, and a 100-second read timeout. Each request is limited to 32,000 UTF-8 input-text bytes and the run to 384,000. Byte limits are not represented as token limits or a guaranteed dollar cap. No new model agreement, resources, account permissions, deployed settings, or production records are changed.

The executable plan binds the fixtures, normalized author and checker requests, prompts, ordered jobs, settings, and source hashes. Execution requires the exact prepared plan hash and a fresh capture. Actual requests are persisted before dispatch. Only final response text, stop reason, elapsed time, reported token usage, and reasoning-block presence are captured; private reasoning is excluded. The entire run stops on provider failure, nonterminal output, or malformed model output. A partial run remains partial. No unused allowance is transferred to replacement cases or reruns.

The source-selection provenance and prospective teaching checklist remain assessment metadata; they never enter provider requests. Blinded exports contain exact stems, ordered choices, goal, and the common reference packet. Content identities bind those values so arm labels, keys, explanations, difficulty labels, and runtime decisions can be joined only after the independent record is frozen.

## Assessment declared before execution (preserved)

Assess every raw candidate, not only retained inventory. Select all warranted answers to the literal displayed question, including the possibility of zero or several. Check whether facts or qualifications are missing, whether choices are distinct and plausible, and whether the question asks substantive subject knowledge. A question requiring an unpublished passage or merely asking which source said something does not establish the intended general learning experience. Unknown outside-source claims stay unverified until independently checked; absence from a packet is not proof of falsehood.

Estimate difficulty with the existing shared rubric before revealing the model's rating. A long scenario, obscure wording, or source quotation alone does not establish application-level reasoning. These assistant estimates are provisional judgments, not psychometric calibration or evidence of learner progress.

After freezing the answer/difficulty record, inspect authored keys and explanations, final reviewer keys, main explanations, and each choice explanation separately. Preserve exact erroneous or underqualified assertions, including errors on discarded questions. Count sound keys, unique-answer questions, reasonable distinct distractors, accurate complete feedback, and usable inventory at the requested challenge separately from formatting and provider failures. Do not credit a difficulty exclusion as detection of a factual defect.

A successful feasibility result requires source-first outputs with supported unique keys, defensible distractors, accurate teaching feedback, and the requested challenge across both goals. Descriptive comparison with the matched baseline informs the next intervention; one sample per goal/arm cannot establish a reliable causal effect or broad production accuracy. A clear factual or feedback failure stops promotion, not merely a single item's count. If source-first succeeds, automatic source acquisition and fresh-domain replication remain necessary. The old invalid controls remain unresolved unless separately demonstrated otherwise.

## Research informing this experiment

[Biancini et al.](https://arxiv.org/abs/2506.04851) studied MCQ generation with supplied knowledge and educator assessment. That motivates testing source access during authorship; its older models, selected material, and small educator study do not qualify Checkpoint. [Sauberli and Clematide](https://aclanthology.org/2024.readi-1.3/) separate answerability from guessability and report wrong labels, ambiguous choices, and insufficient evidence among generated-item problems. They also identify limits of model-only evaluation and the need to assess difficulty separately. These are reasons for the separate outcome measures above, not an automated correctness certificate.
