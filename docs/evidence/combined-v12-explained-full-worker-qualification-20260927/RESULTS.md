# Explained v12 full-worker trial: failed 4/5

The single frozen live worker job returned **four of five original slots** and
failed its prespecified five-slot gate. It used three one-attempt Bedrock
Converse calls in **89.112607 seconds**, within the six-call and 240-second
bounds. There was no retry, fallback, top-up, second job, real bank or queue
write, or deployment. The two earlier v12 full-worker trials remain separate
4/5 failures.

All five native author tasks compiled and survived sanitization. The three
quantitative items passed their code-owned proof route. The answer-blind
English solver supported both agreement candidates. The final reviewer
accepted original slots 0–3. For original slot 4, it selected the code-owned
answer, marked the revised main explanation **supported**, reported no issue
flag and `valid:true`, but rated the question difficulty **4**. The existing
level-2 agreement policy admits only difficulty 2–3, so it withheld the slot
and recorded `agreement_difficulty_disagreement=1` and `difficulty_target=1`.
The candidate was `select_archive/singular_first`, whose correct sentence is
“Maya and Theo each prepare lunch.” Its main explanation explicitly accounts
for all four sentence choices. The prior trial's uncertainty about the shorter
explanation did not recur; this trial does not prove that the revision caused
the changed reviewer declaration. The difficulty rating is another fallible
model judgment and remains a genuine gate failure, not a fifth returned item.

The immutable [capture](capture.json) SHA-256 is
`8337af2d8d23ede59ec0f487ab8095de2515719a4702ab29eabd49bffcaed696`.
The frozen [plan](plan.json) SHA-256 is
`7e8c98159f28e0dfd8269fee708731377f1d4cf7b76898340fefa04ecc8d106d`,
source commit `67fee6e0bcbccc5e0e051bb857f672b965072f7d`, with the unchanged
accepted v12 author wire and schema. The [independent exact-hash
review](independent-review.json) approved the one-shot preparation, and the
fresh [credential precheck](launch-precheck.json) passed before execution.
The captured worker status is `completed_pending_review` and `qualified:false`.

After the capture was locked, two independent reviewers saw only the same
[keyless worksheet](blind-candidates/worksheet.json), SHA-256
`de706786fdad59260b636ea2ab36260a44a8bdaf2034f4786a27855c303b0d34`.
[Review A](blind-candidates/review-a.json) (SHA-256
`3d9cdf7fa0ac608b1eb60b4172829341107969235cbf6ca798059f987d720a79`)
and [review B](blind-candidates/review-b.json) (SHA-256
`cd99f7f51a1459950a35c08a3fc983bdad2a4de146bd300f6d906f7bc32f4a11`)
independently selected the code-owned key for **all five** sanitized
candidates, found no alternative viable key, rated each difficulty 2–3, and
judged **all 30 of 30** within-item choice pairs meaningfully distinct. Both
rated the withheld full-sentence item **3**, in disagreement with the live
reviewer's 4. Both called the English Q01/Q04 pair a strong repetition of
subject–verb agreement; A also called the two integer-response Q02/Q05 items
strongly similar in format while B rated that pair moderate. Both noted some
weak numeric distractors even though the responses are distinct. The private
answer map was opened only after both reviews were locked; it matched every
selected key. These blind assessments do not retroactively change the failed
worker return or resolve the subjective difficulty disagreement.

This one batch cannot establish reliable 20-, 40-, or 80-item yield, and the
current mapped route remains opt-in.
