# English v10 native author: one-call acceptance result

The [frozen plan](plan.json) used source commit `3456177` and the actual
production author wire for one synthetic five-slot 3:2 math/English request.
Its SHA-256 is `db6295d74338ddfe0219645fe0e41539c2c144cd1b254e6d681b27af36d0ace5`;
the harness SHA-256 is `056ab09a6163b8b063b125e1fb08a4408512cd2de4c9592f032a65644c41cbd3`.
The expanded native schema was 2,226 bytes (SHA-256
`3ac240ae33163d16481c18a9eb8d1032404e5f06bf30cdac4a96304ff637edda`).
Root and independent exact-hash review approved the bounded attempt in
[review-approval.json](review-approval.json). An earlier plan was rejected
because it did not check the exported credential expiration; it is retained as
[rejected-preflight-plan.json](rejected-preflight-plan.json). The corrected
harness required at least 150 seconds of session lifetime immediately before
the model call, from the same single exported credential snapshot.

The [sanitized capture](capture.json) (SHA-256
`712f7f4bd1581e87583fea2dbd11ae772e32f1faac1356eb9f2e45f616c0809e`)
records **one STS call and one Bedrock Converse call**, HTTP 200, `end_turn`,
19.652 seconds elapsed under the 120-second hard deadline, and 866 seconds of
credential lifetime at dispatch. The response satisfied the exact native JSON
Schema, production adapter, and closed compiler: **five of five** author
tasks compiled (three numeric, two English), with zero failures. An independent
read-only replay confirmed the pins, exact slot count, and compiler result.
The socket-free [probe tests](test_probe.py) cover the real wire builder,
adapter/compiler path, credential snapshot and expiration, and deadline guard.

For content review, the [keyless worksheet](worksheet.json) was frozen at
SHA-256 `86ab3293b3a212b3914a56fbd89c572c361f66ccddf741bebadf4a139a3d2488`
before answer disclosure. Two independent answer-blind reviews
([A](blind-review-a.json), [B](blind-review-b.json)) both selected the
[code-owned keys](post-lock-answer-map.json) **A, C, C, C, A**, found no second
viable key, and judged all 30 within-item choice pairs meaningfully distinct.
All five questions met the requested minimum difficulty 2 in both reviews.
Both reviewers rated Q02/Q03 strongly similar in bounded-condition format and
Q04/Q05 strongly similar in two-blank agreement format. Their detailed
judgments cover all ten cross-item pairs. A post-lock replay checked all five
main explanations and all 20 code-owned choice explanations; each was sound
and kept the answer unchanged. The answer positions in this one batch were
A, C, C, C, A, so this capture does not establish answer-position balance.

The live model selected the previously supported English scenes
`inversion_library` and `gerund_meals`; it did **not** select the new
`partitive_paint` or `compound_guides` scenes. The latter passed the fake
provider's exact-wire adapter/compiler test, but this run cannot establish
their live selection rate. This is a successful **author/schema acceptance**
trial, not a full-worker return or a repeated-bank diversity qualification.
No queue, bank, deployment, or release was changed.
