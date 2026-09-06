# Evidence before authorship: prospective comparison

Status: prepared experiment, no results yet. The previous goal turn was progress: it committed the solver outcome gate and completed a live run that showed both remaining defects originated in incorrect `resolved` conclusions. The [gate report](QUESTION_SOLVER_OUTCOME_GATE.md) preserves that result. This experiment changes evidence access before a question is written; it does not add another critic to the same bad items.

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

## Assessment declared before execution

Assess every raw candidate, not only retained inventory. Select all warranted answers to the literal displayed question, including the possibility of zero or several. Check whether facts or qualifications are missing, whether choices are distinct and plausible, and whether the question asks substantive subject knowledge. A question requiring an unpublished passage or merely asking which source said something does not establish the intended general learning experience. Unknown outside-source claims stay unverified until independently checked; absence from a packet is not proof of falsehood.

Estimate difficulty with the existing shared rubric before revealing the model's rating. A long scenario, obscure wording, or source quotation alone does not establish application-level reasoning. These assistant estimates are provisional judgments, not psychometric calibration or evidence of learner progress.

After freezing the answer/difficulty record, inspect authored keys and explanations, final reviewer keys, main explanations, and each choice explanation separately. Preserve exact erroneous or underqualified assertions, including errors on discarded questions. Count sound keys, unique-answer questions, reasonable distinct distractors, accurate complete feedback, and usable inventory at the requested challenge separately from formatting and provider failures. Do not credit a difficulty exclusion as detection of a factual defect.

A successful feasibility result requires source-first outputs with supported unique keys, defensible distractors, accurate teaching feedback, and the requested challenge across both goals. Descriptive comparison with the matched baseline informs the next intervention; one sample per goal/arm cannot establish a reliable causal effect or broad production accuracy. A clear factual or feedback failure stops promotion, not merely a single item's count. If source-first succeeds, automatic source acquisition and fresh-domain replication remain necessary. The old invalid controls remain unresolved unless separately demonstrated otherwise.

## Research informing this experiment

[Biancini et al.](https://arxiv.org/abs/2506.04851) studied MCQ generation with supplied knowledge and educator assessment. That motivates testing source access during authorship; its older models, selected material, and small educator study do not qualify Checkpoint. [Sauberli and Clematide](https://aclanthology.org/2024.readi-1.3/) separate answerability from guessability and report wrong labels, ambiguous choices, and insufficient evidence among generated-item problems. They also identify limits of model-only evaluation and the need to assess difficulty separately. These are reasons for the separate outcome measures above, not an automated correctness certificate.
