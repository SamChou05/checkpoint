# Expanded mapped numeric repertoire: offline result

The code-owned mapped 3:2 route now has three solve structures per numeric
slot. Slot 0 adds the reciprocal of a sum of fractions; slot 1 adds a unique
rational equation; slot 2 adds a distributed linear budget maximum. The
provider still supplies only a family name and two bounded integers. The
server constructs all learner text, four choices, their explanations, the
answer key, and an independently rechecked proof.

The mapped-family author contract is version 3 on the Bedrock transport and
version 5 in internal diagnostics. Its name is stable across request metadata;
the changed family enum receives a new name and schema hash, leaving the
previous agreement-only contract untouched.

Every one of the 624 allowed numeric task variants compiled. All 624 rendered
stems were distinct; each task had four distinct answer choices and exactly
one matching key. The mapped native schema remains a small three-field slot
shape: 1,888 UTF-8 bytes, SHA-256
`6f2adb240e75098162ed4002346a50b31d4ce118d6f4a9aa6e62065b63c8b59d`.

The [replay check](check.py) uses the existing frozen
[simulation's](../mapped-bank-diversity-simulation-20260927/run.py) seed,
adapter, proof, full-bank history, and recent-30 window without calling a
model or bank. It does not alter that earlier frozen evidence.

| Bank size | Unique exact stems | Numeric same-slot/family pairs, before → after | All five slots, before → after |
| ---: | ---: | ---: | ---: |
| 40 items | 40 | 36 → 21 | 60 → 45 |
| 80 items | 80 | 168 → 105 | 280 → 217 |

These are structural family-pair counts, **not blind judgments of semantic
near-duplicates**. The English slots retain two structures each and both
inventories exhaust immediately after 80 items. The new families do not by
themselves qualify live worker yield, difficulty, or whole-bank content
diversity. A model-originated pass and independent answer-blind review remain
necessary before enabling this route in TestFlight.

From the repository root, with backend test dependencies available:

```sh
python -B docs/evidence/mapped-numeric-repertoire-20260927/check.py
```
