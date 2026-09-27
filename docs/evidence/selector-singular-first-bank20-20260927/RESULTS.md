# Singular-first selector: chronological 20/40/80 offline bank replay

Source is pinned to commit `1eff0a24c5177c0df7c57284dbc724385637214d` (backend tree `161904ea24be618fcfd3337288e9f433362e9241`). The [replay](replay.py) uses the same accepted deterministic v9 author-task capture, native adapter, code-owned selectors and compilers, recent-30 prompt history, durable full-bank variant-history projection, first-20 item shuffle, and per-item choice shuffle as the [balanced-selector replay](../selector-balanced-bank20-20260927/PREPARATION.md). Only the backend source pin changes. No provider, worker, bank, or deployment call was made.

| Frozen artifact | SHA-256 |
| --- | --- |
| [Replay script](replay.py) | `395fde4ec2bb69ce73cf5a239c8fc3d64b7fe0b23cf6b232080fe181604601c1` |
| [Structural summary](summary.json) | `ecc579d72c1f5c3bc54af27dc6592636a236937ec495c730e0362cef7a56a2d8` |
| [Keyless first-20 worksheet](worksheet.json) | `cde2879885d7c8404067052931be110deaca7e224671ad6a9234ccb9b5cf07d6` |
| Private answer map, outside Git at `/private/tmp/checkpoint-selector-singular-first-bank20-private-20260927/answer-map.json` | `80b45ed5cae182479f49982c8e433014e6f1821255805477e05dd79b4bf898cd` (mode 600) |

The accepted author capture is pinned at SHA-256 `17575d5a62b1fde235c3d43c7c9bc1d9e40385466e30b973fde1ca9cf1bbc9aa`; the source-task seed file at `97311ad795e7936ffd0c79b338762770a27336d86d3200c24afc21bb0bad05f5`. The [balanced wrapper](../selector-balanced-bank20-20260927/replay.py) is pinned at `80ce197f9979f937bbbdb99a30c88c0894b9148f91c8c44f5b5211a876b3ff69` and its [core replay](../combined-current-bank-replay-20260927/replay.py) at `e811d65677986e747433842ea5b191f5e32e493c870ec01545a735524b8bd5b9`. The script verifies unchanged backend source and author capture, refuses changed frozen output, and was rerun successfully against the frozen files.

## Structural result

| Chronological bank size | Unique exact stems | Code-owned unique keys / four literal-distinct choices | Same numeric solve-signature pairs across numeric slots | Same numeric solve-signature pairs by numeric slot | Same response-format pairs within slots, total |
| ---: | ---: | ---: | ---: | --- | ---: |
| 20 | 20 | 20 | 0 | 0 / 0 / 0 | 26 |
| 40 | 40 | 40 | 12 | 4 / 4 / 4 | 125 |
| 80 | 80 | 80 | 72 | 24 / 24 / 24 | 552 |

At 20 items, slots 0, 1, and 2 each have four numeric responses in their existing forms (exact rational expression for slot 0; bounded condition for slots 1 and 2). English slot 3 has four two-blank responses. English slot 4 has two two-blank and two full-sentence responses. At 40 items, the slot-4 split is five two-blank and three full-sentence; at 80, it is twelve and four. The corresponding same-format pair counts for slot 4 are 2, 13, and 72. The other four slots each contribute 6, 28, and 120 same-format pairs at 20, 40, and 80. Cross-family numeric signature pairs by numeric slot total 0, 2, and 8 respectively.

The first 20 full-sentence rows are **batch 1, slot 4: `select_archive/singular_first`** and **batch 4, slot 4: `select_lab/singular_first`**. The earlier balanced-source first-20 worksheet used the corresponding `plural_first` variants. Under the fixed worksheet shuffle, only Q07 and Q09 changed; the other 18 public prompt/choice objects are identical. All three 20/40/80 structural snapshot objects are otherwise exactly equal to the [preceding balanced summary](../selector-balanced-bank20-20260927/summary.json) (SHA-256 `0df67dd100a7a3aa8b8a5dbdb7d3f812af6eb99db7671e8767910964043454e8`). **No structural regression emerged** on the measured exact-stem, numeric-signature, or within-slot response-format metrics.

This is a constructor replay, not a full-worker acceptance. The separate answer-blind content review below measures the first-20 worksheet; it does not qualify future model output.

## Locked answer-blind first-20 review

[Reviewer A](review-a.json) and [reviewer B](review-b.json) each solved the same keyless worksheet before the private answer map was opened. Their locked review files have SHA-256 `41187c98989952d9462ef28ddf809d9ebf809cb07e7c5c32106b9f7ccb42bcf1` and `059db124b5d7b186c2f1c47521064aed0946f664084840c5cf86a1441060a55d`. Both selected the code-owned key on **20/20** items, found no second defensible key, rated every item difficulty 2–3, and judged **120/120** within-item choice pairs meaningfully different. This is agreement on exact answers and response distinctness, not proof that every distractor is equally plausible.

Both reviewed all **190** cross-item pairs and flagged the same four pairs as strongly repetitive: Q04/Q10, Q05/Q12, Q07/Q09, and Q08/Q17. Reviewer A required both the solving method and response format to be strongly alike, so rated **4/190** pairs strong and counted **29** pairs with a strongly shared response format. Reviewer B treated a repeated prompt/response skeleton as strong even when the method changed, so rated **31/190** strong; those 31 include A's four. B also called Q07/Q11 and Q09/Q11 strong for reusing agreement rules across formats, and identified three distinct but weakly plausible numeric distractors. The variation between four and 31 is a rubric difference, not a disagreement about the four common pairs.

Reviewer A did not see this worksheet's key map or source, but had seen a predecessor-bank summary naming those four strong pairs; its novelty ratings are therefore not wholly independent of that earlier context. Reviewer B stayed isolated from previous reviews and independently flagged all four. This review shows that changing the first full-sentence item to `singular_first` preserves one-key, distinct-choice, target-difficulty quality in this sample, but does **not** fix repeated formats and methods across the bank. At 40/80 items the structural repeat counts above remain warnings, not answer-blind content ratings.

Reproduce from the repository root with backend test dependencies installed:

```sh
CHECKPOINT_PRIVATE_MAP_DIR=/private/tmp/checkpoint-selector-singular-first-bank20-private-20260927 \
  /opt/homebrew/bin/python3.12 -B docs/evidence/selector-singular-first-bank20-20260927/replay.py
```
