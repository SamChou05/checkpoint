# Level-2 quarantine: chronological 20/40/80 offline bank replay

The [replay](replay.py) pins backend source `1e411c345a34d867bbee445953c1d0b29101e66e` and reuses the accepted v9 author-task capture, native adapter, actual code-owned selectors and compilers, recent-30 prompt window, durable full-bank variant history, and fixed item/choice shuffles from the [selector-balanced replay](../selector-balanced-bank20-20260927/replay.py). It runs 16 chronological five-item batches. No provider or worker call, bank write, or deployment occurred. This is constructor evidence, not a full-worker or content-review qualification.

The historical core replay requests a `sentence_selection` row for an auxiliary stratified worksheet after simulating 80 items. That format is now intentionally ineligible for mapped level-2 selection, so this wrapper substitutes the fourth eligible family, `number`, **only for that unused auxiliary sample**. The chronological 20-item worksheet still comes from the first four recorded batches. The wrapper restores the original sample configuration after the run and refuses source drift or changed frozen output on rerun.

| Frozen artifact | SHA-256 |
| --- | --- |
| [Replay script](replay.py) | `8f5ce142eba20c8490fdc25e593f02ed7a44aa4962bc6270595de677fafb8b39` |
| [Structural summary](summary.json) | `70aa96eeeffc2fc077d2b9e32071b4ac2d35e3c32168759eb2696bc07d1865aa` |
| [Keyless first-20 worksheet](worksheet.json) | `34e0dcf9e673f9791a32af437755d001f6a722fd5e3e7ec5e83e19ab442fbeb7` |
| Private answer map outside Git at `/private/tmp/checkpoint-level2-quarantine-bank20-private-20260927/answer-map.json` | `2246cb53d101a2b63fe748d1c91aac170af24ffcbf57255b47ee091e3d8eed3b` (mode 600) |

The accepted author capture is pinned at SHA-256 `17575d5a62b1fde235c3d43c7c9bc1d9e40385466e30b973fde1ca9cf1bbc9aa`; the source-task seed file at `97311ad795e7936ffd0c79b338762770a27336d86d3200c24afc21bb0bad05f5`. The [balanced wrapper](../selector-balanced-bank20-20260927/replay.py) is pinned at `80ce197f9979f937bbbdb99a30c88c0894b9148f91c8c44f5b5211a876b3ff69` and its [core replay](../combined-current-bank-replay-20260927/replay.py) at `e811d65677986e747433842ea5b191f5e32e493c870ec01545a735524b8bd5b9`.

| Chronological items | Unique exact stems | Code-owned one-key / four literal-distinct choices | Same numeric solve-signature pairs | Same response-format pairs within slots | Same family pairs within slots |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 20 | 20 | 20 | 0 | 30 | 0 |
| 40 | 40 | 40 | 12 | 140 | 18 |
| 80 | 80 | 80 | 72 | 600 | 112 |

The numeric signature counts are unchanged from the [singular-first selector replay](../selector-singular-first-bank20-20260927/RESULTS.md): 0/12/72 overall, or 0/4/24 in each numeric slot. Cross-family signature pairs are 0/2/8. The quarantine removes all full-sentence selections from the mapped level-2 slot: slot 4 now has 4/8/16 two-blank items at 20/40/80, rather than the previous two-blank/full-sentence splits of 2/2, 5/3, and 12/4. Its same-format pair count rises from 2/13/72 to 6/28/120. Across all five slots, this raises same-format pairs from 26/125/552 to **30/140/600**. Same-family pairs change from 1/18/106 to **0/18/112**. These are structural proxies for repetition, not answer-blind judgments of semantic similarity.

The first 20 contain one each of the slot-4 `gerund`, `compound`, `number`, and `correlative` families. Four public worksheet items (Q07, Q09, Q11, Q16) differ from the prior singular-first worksheet; the other 16 prompt/choice objects are identical under the fixed shuffle. The [worksheet](worksheet.json) omits the code-owned key.

## Locked answer-blind first-20 review

[Reviewer A](review-a.json) (SHA-256
`7d752b7f989484102b0853591062d61d24e302aefdd853806bd3ae403ef12c77`)
and [reviewer B](review-b.json) (SHA-256
`47a04135ba404a17c891bfddaafe108f5cccf0df77822e1533531826347e716b`)
independently solved the same keyless worksheet before the private answer
map was opened. Both selected the code-owned key on **20/20** items, found no
second defensible key, rated all 20 items difficulty 2–3, and judged **120/120**
within-item choice pairs meaningfully distinct. These findings support the
closed constructor's exact answers and option distinctness in this sample;
both reviewers also noted some weakly plausible numeric distractors.

Both reviewed **all 190** cross-item pairs and agreed that seven pairs strongly
repeat a solving method or response format: Q02/Q18, Q03/Q08, Q03/Q17,
Q06/Q13, Q06/Q20, Q08/Q17, and Q13/Q20. B used a narrower strong criterion
and flagged **7/190**; A also counted recurring two-blank agreement and answer
frames as strong, flagging **41/190**, including all seven from B. The counts
reflect different novelty rubrics, but both conclude the 20-item bank fails
their no-strong-repeat criterion. Removing the level-4-prone full-sentence
format preserves one-key and within-question distinctness while making bank
format repetition worse. This offline replay is not a live 20-item worker
trial and does not estimate future model yield.

Reproduce from the repository root with the backend test dependencies installed:

```sh
CHECKPOINT_PRIVATE_MAP_DIR=/private/tmp/checkpoint-level2-quarantine-bank20-private-20260927 \
  python -B docs/evidence/level2-quarantine-bank20-20260927/replay.py
```
