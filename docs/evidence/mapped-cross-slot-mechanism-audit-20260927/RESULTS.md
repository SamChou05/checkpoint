# Mapped bank cross-slot mechanism audit

At source `811ec0a` (after the slot-4 correlative expansion), the frozen
five-task seed produces 15/15, 40/40, and 80/80 unique exact stems with five
proved, four-choice rows per refill. The [offline audit](audit.py) replays the
current constructors and full-bank history through the existing
[capacity harness](../../../backend/bedrock-question-service/tests/mapped_bank_capacity_harness.py).
It makes no provider, worker, or bank call. Run it from the repository root:

```sh
PYTHONPATH=backend/bedrock-question-service:backend/bedrock-question-service/tests \
  python -B docs/evidence/mapped-cross-slot-mechanism-audit-20260927/audit.py
PYTHONPATH=backend/bedrock-question-service:backend/bedrock-question-service/tests \
  python -B docs/evidence/mapped-cross-slot-mechanism-audit-20260927/test_audit.py
```

| Bank items | Proximity × compound | Compound × compound | Quadratic max × linear max | Pattern total | Same slot/family pairs |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 15 | 1 | 0 | 1 | 2 | 0 |
| 40 | 9 | 3 | 6 | 18 | 35 |
| 80 | 36 | 15 | 25 | 76 | 175 |

The first three columns **count structural pairs matching patterns that both
independent reviewers called strong** in the earlier
[blind worksheet](../mapped-combined-bank-blind-20260927/RESULTS.md).
They are heuristics, not 2/18/76 newly blind-confirmed semantic duplicates.
The archived 15-item worksheet had four consensus strong pairs. Its source
preceded the correlative family; the current first-three-batch replay has two
pattern matches. A new answer-blind review must determine actual overlap in
the current and larger banks.

A selector alone cannot guarantee a strong-pair-free 80-item bank under the
current repertoire. Slot 2 has only two substantive decisions, minimum and
maximum, because both maximum expression families ask for the greatest
satisfying integer. By the pigeonhole principle, three slot-2 questions must
repeat one decision. Each English slot has eight exact stems in each of its
three families. At 80 total items each English slot must supply 16. Removing
proximity from slot 3 or compound from slot 4 leaves exactly 16 stems in that
slot. If even one spare stem is required to replace a rejected item, both
families must appear; their cross-slot pair is therefore unavoidable.

An experimental slot-2 selector balanced minimum and maximum before its
expression families. It changed the numeric cross-maximum counts at 15/40/80
from 1/6/25 to 0/4/16, while numeric same-decision pairs changed only from
1/13/60 to 1/12/56. In the first three batches it replaced the reviewed
maximum pair with two ratio-minimum tasks using the same expression and
threshold operation, differing only in constants. This is not a defensible
quality gain, so the selector was reverted and no production source changed.
The next useful intervention is additional reviewed, code-owned reasoning
mechanisms, followed by this audit and full-bank independent answer-blind
review. The opt-in route remains unqualified for release.
