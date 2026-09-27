# Selector-first v12 full-worker trial: failed 4/5

The one frozen live worker job returned **four of five original slots** and
failed its prespecified five-slot gate. It used three one-attempt Bedrock
Converse calls in **130.220 seconds**, within the six-call and 240-second
bounds. There was no retry, fallback, top-up, second job, bank or queue write,
or deployment. The previous v12 trial remains a separate failed 4/5 result.

All five native author tasks compiled and survived sanitization. The three
quantitative items passed their code-owned proof path. The answer-blind solver
supported one key and found six distinct choice pairs for each English item.
The final reviewer accepted original slots 0–3. For original slot 4 it selected
the code-owned answer, rated difficulty **3** (within the 2–3 target), and
reported no ambiguity, distractor, scope, or novelty issue. It returned
`valid:false`, `explanationSupport:"uncertain"`, and an explanation issue
flag. The worker recorded `review.uncertain_authored_explanation=1` and
withheld that slot. The capture does not include a reviewer rationale, so the
reason for uncertainty cannot be established from its verdict alone.

The selected full-sentence item was `select_archive/singular_first`, the
variant chosen by the new selector. Its main explanation correctly justified
the offered answer, “Maya and Theo each prepare lunch,” but asserted that all
other sentences were wrong without stating their three different corrections.
The final reviewer saw that main explanation and the choices, not the
rule-specific per-choice feedback. A missing worked rejection of the other
choices is a plausible cause of the uncertainty, not a proven causal account.
The final reviewer’s explanation veto remains in force.

After the capture was locked, two independent reviewers saw only the same
[keyless worksheet](blind-candidates/worksheet.json), SHA-256
`a7b4cba3b80a5bd2351640fbea8dccc08ee98c253035d36b212ec64a345cd97d`.
[Review A](blind-candidates/review-a.json) and
[review B](blind-candidates/review-b.json) independently selected the
code-owned key for **all five** sanitized candidates, found no alternative
viable key, judged **all 30 of 30** within-item choice pairs meaningfully
distinct, and rated all five difficulty 2–3. They both rated the withheld
full-sentence item 3. The reviewers disagreed about cross-question novelty:
A found no strong repeat among ten pairs; B called the two agreement items
strongly similar in solving method and the inequality-count/rational-equation
pair strongly similar in stem format. B also called two fraction choices weak
distractors because the result must lie between zero and one. These are
content-quality warnings, not additional live-worker returns. The private
answer map was opened only after both reviews were locked.

The immutable [capture](capture.json) SHA-256 is
`d23f4fb1ac51d672a9ab9b2e4d95ca26c184dab0a2fb9631a11c2287a6b9f62f`.
The one-shot [plan](plan.json) SHA-256 is
`3221e3a37c5ff0e0574dea067f917bf6332e56f6438b17407e93041808a35fd0`,
with source commit `1eff0a24c5177c0df7c57284dbc724385637214d`.
The [independent exact-hash review](independent-review.json) approved the
bounded launch; the fresh [credential precheck](launch-precheck.json) passed
with one STS request and zero provider calls before execution. The captured
worker status is `completed_pending_review` and `qualified:false`.

This remains one batch, not evidence of reliable 20-, 40-, or 80-item bank
yield. The [offline chronological replay](../selector-singular-first-bank20-20260927/RESULTS.md)
found no measured structural regression from the selector change; answer-blind
bank content review is separate.
