# Selector-balanced chronological bank sample

The [replay](replay.py) pins backend source `01439703d647ab17246c4f9c821a4dd05b5b2a99` and reuses the accepted v9 author-task capture pinned by the [prior combined replay](../combined-current-bank-replay-20260927/RESULTS.md). It runs the actual native adapter, code-owned selectors and compilers, recent-30 prompt window, and durable full-bank variant-history projection offline for 16 five-item batches. No provider, worker, bank, or deployment call occurs. The source guard refuses changed backend code; frozen output files refuse byte changes on rerun.

The [keyless worksheet](worksheet.json) is the **first chronological 20 items**, shuffled with fixed seeds for item order and choice labels. It is distinct from the prior stratified 20-item worksheet. Its SHA-256 is `987217dc30c7694f3afb57c1c932a0595244002f281fa4ccb0437c04ff430587`. The code-owned answer map is outside Git at `/private/tmp/checkpoint-selector-balanced-bank20-private-20260927/answer-map.json` with file mode 600. Blind reviewers must read only this worksheet and lock their judgments before answer disclosure.

The [machine summary](summary.json) confirms 20/40/80 unique stems and code-owned one-key/four-literal-distinct-choice checks. Same numeric solve-signature pairs are **0/12/72**, compared with **1/14/78** on the preceding source. The first 20 have four two-blank slot-3 English questions and two two-blank plus two full-sentence slot-4 questions; the old selector produced four plus four two-blank questions. Same response-format pairs among all eight English items fall from 28 to 16. These are structural counts, not blind judgments of semantic novelty. The two full-sentence questions themselves may be strongly similar, as the earlier [format prototype](../english-sentence-selection-20260927/RESULTS.md) warned.

Reproduce from the repository root with backend test dependencies installed:

```sh
CHECKPOINT_PRIVATE_MAP_DIR=/private/tmp/checkpoint-selector-balanced-bank20-private-20260927 \
  PYTHONPATH=backend/bedrock-question-service:backend/bedrock-question-service/tests \
  python -B docs/evidence/selector-balanced-bank20-20260927/replay.py
```

This is an offline constructor sample. Independent answer-blind review and a full-worker qualification remain separate gates.
