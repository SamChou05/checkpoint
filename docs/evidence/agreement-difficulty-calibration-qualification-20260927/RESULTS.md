# Agreement difficulty calibration: one-shot qualification result

**Official outcome: FAIL the prespecified content gate.** The worker returned
all **5/5 original slots** in one bounded job, with unique correct keys and
distinct answer choices. After the capture was committed, two independent
answer-blind reviewers both judged original slot 4 to be **difficulty 1**.
The frozen request requires at least level 2, and the protocol prespecified
level-2 content review for every returned slot. Thus the level-2 blind
consensus is **4/5**, even though the mechanical return count is **5/5**.
No route activation or deployment follows from this trial.

The source under test is main commit
`22aec98b5ba7685a30218441029d0f7299776a35`. The [frozen plan](plan.json)
SHA-256 is `d7f257343300ac5765d3389104260ac62c2f42f8349c4201af751f230d753dd6`;
the [harness](full_worker_probe.py) SHA-256 is
`7d9fb0c787297c51ef4bb37de6cd85ca02e885d70993cc5ee4f5ea70edcde9ed`.
The [capture](capture.json) SHA-256 is
`f8a912da0c29df783303d9afca5f0af0b559408f80ff6b37eae7755a285ff145`.
The exact prior normalized five-slot request SHA-256 remained
`212cea7d53ddefe17fbe8f2459705b46b871793e62e0e58b56cc11e3626e63ae`,
and Bedrock accepted the unchanged 2,701-byte native author schema SHA-256
`2e2508e3c7944a0b51246e6fa5febcdd57b84c0003ae81315f36c1107cdbbb6c`.
The old full-worker trial remained **3/5 FAIL**; its three retained responses
were replayed offline through this verifier for regression diagnosis only.
That replay made zero fresh AWS calls and did not count toward this result.

The reviewed launch made one read-only STS precheck and one execute-time STS
identity check. The single original job made three Converse calls: author,
answer-blind solver and teaching reviewer. It finished in **92.08736 seconds**
from the execute/capture start, including credential export and execute STS,
under the 240-second ceiling. Reported usage was 10,662 input and 9,866 output
tokens. There was no retry, fallback, repair, top-up or resumed call. All five
slots passed the local sanitizer and final worker verifier. The model teaching
reviewer recorded difficulty disagreement for both agreement slots, and the
narrow policy admitted its level-3 estimates while releasing code-owned
level-2 agreement metadata.

The [official keyless worksheet](official-worksheet.json) SHA-256 is
`e0896bdcf33c763fa9f27b4f0bee79aa364d8a51d91cc9464ae6f86114e62721`.
It showed five readable questions, randomized display choices and IDs, and
no keys, source slots, model ratings or teaching. Both independently locked
reviews were verified before opening the [private map](blind-private-returned_output.json):
[review A](blind-review-a.json) SHA-256
`2424af66093316eecd26ceaf17fdc76f56e90956a3785adb6b494b815ac9b86a`
and [review B](blind-review-b.json) SHA-256
`1350cf9288cc5f603ae474fbb834c8221cd5b771513c4295c34fcb7c0a0cdf16`.
Both selected all five explicit code-owned keys, found all six choice pairs
meaningfully distinct in every item (**30/30 pairs each**), and found all
five stems self-contained. Their displayed answers were A, A, A, D, D;
those labels were random worksheet positions, not learner-output labels.

| Original slot | Task and code-owned key | Model reviewer level | Released level | Blind A/B level | Level-2 gate |
| --- | --- | ---: | ---: | ---: | --- |
| 0 | Exact fraction expression, `38/3` | 3 | 3 | 2 / 2 | Pass |
| 1 | Exact fraction expression, `25/12` | 3 | 3 | 2 / 2 | Pass |
| 2 | Bounded integer inequality, `7` | 2 | 2 | 2 / 2 | Pass |
| 3 | Agreement with intervening `near` phrases, `sort; organizes` | 3 | 2 | 2 / 2 | Pass |
| 4 | Compound subject and `every guest`, `prepare; receives` | 3 | 2 | **1 / 1** | **Fail** |

The [post-lock audit](post-lock-audit.json) recomputed all **25 learner fields**
(stem, choice list, key, main explanation and per-choice feedback for each
of five items) from the captured three quantitative specifications and two
enumerated agreement tasks. Every field matched the released row and retained
provenance exactly. Independent fraction arithmetic and inequality checks
also reproduced the three numeric keys. Each source assignment matches the
frozen objective: the first three items evaluate exact rational expressions
or a bounded condition, and the last two apply subject–verb agreement. The
blind reviewers could not assess *target* objective fit because their worksheet
intentionally hid the assigned objectives; that alignment was checked only
after review lock.

I inspected every released main explanation and all 20 per-choice feedback
entries after unblinding. The numeric calculations and inequality checks are
correct. The agreement teaching identifies the actual head subjects, explains
why nearby nouns do not control agreement, and treats `every guest` as
singular. Every wrong pair receives accurate feedback for each blank. Explanations are keyed
to literal choices and contain no display-position references, so display
shuffling does not change the teaching. The two fraction items' distractor
feedback is accurate but generic: it mostly states the computed exact value
rather than explaining the specific misconception behind each distractor.

Within-batch novelty remains limited. Slots 0 and 1 use nearly identical
unitless-`q` exact-fraction stem templates with different operations and
numbers; both blind reviewers marked that pair low novelty. Slots 3 and 4
share the same two-blank/four-ordered-pair format, although they test different
agreement constructions. The inequality item adds a distinct task form.
These repetitions do not create duplicate *choices* within any question, but
they matter for a broader bank-quality assessment.

This fresh result shows that the closed route can produce a structurally
complete five-question response with correct code-owned keys and usable
teaching in one sample. It also exposes unreliable difficulty calibration:
the model rated slot 4 at 3, the constructor released it at 2, and both blind
reviewers rated it at 1. The disagreement is material because the requested
minimum was 2. The one-batch result does not establish deterministic yield or
population reliability, and the opt-in agreement route remains unqualified.
