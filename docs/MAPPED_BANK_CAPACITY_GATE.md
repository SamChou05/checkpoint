# Offline mapped-bank capacity gate

The opt-in, fixed 3:2 route can produce 80 different exact stems from a frozen
five-task author response, but a stem is not a reasoning mechanism. Run the
reusable gate from the repository root with the backend test dependencies:

```sh
python -B backend/bedrock-question-service/tests/mapped_bank_capacity_harness.py \
  --items 40 80 --max-family-uses 1 --reserve-exact-stems 1
```

It emits JSON and exits nonzero when a target bank cannot be completed, a slot
lacks enough families, actually uses a family more than the allowed number of
times, or does not retain the requested number of unused stem variants. The defaults
are intentionally strict: at most one use of each substantive family per
slot and one spare exact stem per slot for replacement or a failed item.
Change the limits explicitly when evaluating a different product standard;
do not silently count operand or scene changes as new reasoning families.

The harness runs the current native adapter and constructors with the
[frozen source-task seed](evidence/mapped-bank-diversity-simulation-20260927/seed.json).
Each batch receives the last 30 prompts and the worker's **full-bank**
numeric and English variant projections. It verifies each code-owned proof,
four distinct choices, a single listed key, and complete choice feedback,
then stores the compiled rows in an in-memory DynamoDB-shaped history. It
makes no provider or bank call. Its family catalog is built from the current
numeric inventory and explicit English scene-to-mechanism groups; an
unclassified new scene fails the harness until its mechanism is reviewed.
This keeps the [frozen 40/80 evidence](evidence/mapped-bank-diversity-simulation-20260927/RESULTS.md)
immutable while allowing the current constructors to be evaluated again.

At the current source, the gate reports 40/40, 80/80, and 85/85 unique exact
stems. Slots 0, 2, and 3 have three substantive families each; slots 1 and 4
have four. The 40-, 80-, and 85-item banks have 29, 153, and 176
same-slot/family pairs, respectively, down from 35, 175, and 200 before the
two-root numeric and -ing-activity English additions. Slot 4 now has 32 exact stems, with 16 unused
at 80 items and 15 at 85. The default gate still fails because every slot
reuses its families many times. Its messages identify insufficient family
capacity and actual overuse.

This is a structural capacity gate, not an automatic judgment of semantic
novelty. Two distinct families can still ask nearly the same question, and
multiple examples of one family need not be equally redundant. A future
constructor expansion should reduce these structural counts, then pass a
repeated-bank, answer-blind content review for one correct answer, plausible
and distinct choices, requested difficulty, and semantic overlap. The gate
does not qualify model/provider reliability or a production rollout.
