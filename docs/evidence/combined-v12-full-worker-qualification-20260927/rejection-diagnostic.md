# Frozen v12 full-worker slot-4 rejection diagnostic

## Scope and disposition

This is a read-only diagnostic of the one-job frozen capture at source commit `01439703d647ab17246c4f9c821a4dd05b5b2a99`. The capture SHA-256 is `fe66f66fe9bc1b8eefa62c167447e73a62d41cf362850a3db8cbc912298af31d`. It returned original slots 0–3 and omitted original slot 4: four of five planned questions, with three provider calls and no job error or deadline breach. Its recorded state is `completed_pending_review`, `qualified=false`. The omitted item should remain a rejection in this frozen trial. This note does not adjudicate any forthcoming blind-candidates worksheet.

## What slot 4 contained

The author supplied `agreement_pair_v1` with `scene=gerund_meals` and `order=singular_first` for original slot 4. The closed agreement selector intentionally chose a novel `select_archive` full-sentence scene with `plural_first` for that slot (see `agreement_task_constructor.py`, `_select_novel_task`, especially the `sentence_due` preference). The selected item asked which whole sentence has correct present-tense agreement. Its four choices were:

1. “Each of the guests receive a plate.”
2. “Neither the curator nor the assistants sort the records.”
3. “Verifying the totals demand careful work.”
4. “Maya and Theo each prepares lunch.”

The code-owned answer is the second sentence. The other sentences respectively need *receives*, *demands*, and *prepare*. `_compile_sentence_selection_question` in `agreement_task_constructor.py` constructs these four different subject–verb relations, proves one correct answer by construction, and supplies explanations. `CompiledAgreementCandidate.content` revalidates the task and hard-codes `difficulty: 2` for this scene as it does for every closed agreement scene. The item survived sanitization; the job records `sanitize.accepted=5`.

## Exact rejection path

The answer-blind complete-choice solver reviewed the two English survivors. For slot 4, its dense index 1, it marked the code-owned answer `supported`, the other three `refuted`, and all six choice pairs `distinct`. The final authored-solution reviewer then received the prompt, choices, and immutable main explanation, but not the expected answer or code-owned difficulty. Its slot-4 response was:

```json
{"valid":true,"answer":"Neither the curator nor the assistants sort the records.","difficulty":4,"explanationSupport":"supported","issueFlags":{"answer_or_ambiguity":false,"explanation":false,"distractors":false,"scope_assignment":false,"novelty":false,"other":false}}
```

In `question_verification.py`, the reviewer loop at lines 480–536 takes this path:

1. `authored_review_rejection_reason` in `question_teaching.py` returns no rejection: support is declared, no issues are flagged, validity is true, and the answer equals the code-owned key.
2. The general validity and exact-answer checks pass. Reviewer difficulty 4 is a well-formed integer in the allowed 1–5 range.
3. `trusted_agreement[index].content(question)` succeeds and supplies code-owned difficulty 2. The request's `minimumDifficulty` is 2, and `adaptiveSkillPlans` is empty, so neither the floor nor adaptive target rejects it.
4. The closed-agreement veto at `question_verification.py:532–537` rejects because reviewer difficulty 4 is outside `(2, 3)`. It records `review.difficulty_target` and continues before appending the item.

The job's quality counts are `review.accepted=4`, `review.agreement_difficulty_disagreement=1`, and `review.difficulty_target=1`. The disagreement count belongs to the accepted original slot 3, whose reviewer rating was 3; it is not a second slot-4 error. Slot 4 was rejected **only** by the conservative difficulty veto. The reviewer did independently report difficulty 4 despite affirming the key and explanation. The `difficulty_target` metric name does not mean an adaptive target was set here.

## Does independent evidence justify code-owned level 2?

No for this particular full-sentence item. The locked 20-item worksheet at `../combined-current-bank-replay-20260927/worksheet.json` (SHA-256 `265579e1a486435975e723e23b5364e4d72d9883ebd2ae3c87cb0f31bc4a48ed`) contains the *identical prompt and four choice texts* as Q15, in a different order. Its two independent answer-blind reviews, `blind-review-a.json` and `blind-review-b.json`, both selected the same unique answer, found no other viable key, rated difficulty **3**, and marked it within the target 2–3 range. Thus the direct prior blind evidence supports correctness and target-range fit, but specifically does **not** support the current code-owned level 2. It also conflicts with the one captured reviewer rating of 4; the current evidence does not establish 4 as the correct learner-facing level.

The shared rubric in `question_difficulty.py` calls level 2 direct application of one familiar rule, level 3 interpretation of evidence to distinguish plausible conclusions, and level 4 connection of multiple steps or interacting constraints. This item asks the learner to compare four complete sentences, each testing a different agreement construction. Level 3 is defensible under that rubric and matches both prior blind ratings. `verification_policy.py` describes revision 10's level-2 authority and 3-as-advisory rule for a bounded agreement subset, but that policy statement alone is not independent calibration of this newer full-sentence format. The current implementation applies level 2 to all agreement scenes without distinguishing this format.

## Safe follow-up choices

1. **Preserve the frozen result and independently adjudicate the new trial.** Count slot 4 as rejected, with no retry, top-up, or post hoc override. This keeps the trial's original acceptance criterion intact and allows independent reviewers to assess whether the returned four questions meet the qualification target. It does not improve yield.
2. **Calibrate the sentence-selection family separately in a future source revision.** Set code-owned difficulty 3 only for the full-sentence scenes if broader scene-level blind evidence confirms the two prior Q15 ratings. Add tests for each sentence-selection scene, provenance revalidation, and reviewer ratings 2/3/4. This fixes learner metadata and the mismatch with existing Q15 evidence. **It would not admit this captured reviewer-4 item** while the current `(2, 3)` veto remains.
3. **Keep the rating-4 veto while revising or constraining full-sentence items.** Simplifying the range of rules per question, or temporarily selecting other English forms, could reduce difficulty disagreement, but changes diversity and requires fresh blind content review and another full-worker trial.
4. **Relax the veto only with new independent evidence of reviewer overrating.** A narrowly scoped sentence-selection exception for rating 4 might improve yield, but it weakens the second model's independent difficulty veto precisely where it disagreed most. A global threshold change, or retroactive admission of this slot, would be poorly supported by the current evidence. Any exception should be predefined, tested, and evaluated in a new frozen trial.

No backend, AWS, bank, or capture state was changed for this diagnostic.
