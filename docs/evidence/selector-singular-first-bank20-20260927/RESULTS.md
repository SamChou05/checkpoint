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

This is a constructor replay, not a full-worker acceptance or blind content-quality result. The two full-sentence questions still share a response scaffold; unchanged structural counts cannot establish that they are semantically novel or that independent reviewers will rate their difficulty as intended. The answer-free worksheet is ready for a separate blind review before key disclosure.

Reproduce from the repository root with backend test dependencies installed:

```sh
CHECKPOINT_PRIVATE_MAP_DIR=/private/tmp/checkpoint-selector-singular-first-bank20-private-20260927 \
  /opt/homebrew/bin/python3.12 -B docs/evidence/selector-singular-first-bank20-20260927/replay.py
```
