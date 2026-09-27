# Slot-4 -ing activity subject: offline capacity result

The mapped English slot at global ordinal `4` now has a fourth code-owned
agreement decision. A clause beginning with an -ing activity takes a singular
verb even when that activity contains a plural object; a paired ordinary
plural subject takes a plural verb. For example, “Proofreading the reports
requires patience, while the editors check every heading.” The code derives
the four ordered choices, the sole key, and feedback for each choice. Its
other order variant uses different activity, subject, and verbs, so it is
not a clause-order mirror. [Cambridge's gerund entry](https://dictionary.cambridge.org/us/dictionary/english/gerund)
illustrates an -ing activity as the subject of a singular verb.

The four fixed scene records provide eight exact stems. Each compiled
question has two blanks, four distinct ordered choices, exactly one listed
key, complete choice feedback, and text within constructor limits. The final
code uses “and” between these gerund and plural clauses and distributes the
eight correct-answer positions evenly across A–D. The phone also shuffles
choices on display; the backend order no longer leaks a B/C pattern.

From the repository root, replay the current constructors and full-bank
history without provider or bank access:

```sh
PYTHONPATH=backend/bedrock-question-service:backend/bedrock-question-service/tests \
  python -B backend/bedrock-question-service/tests/mapped_bank_capacity_harness.py \
  --items 15 40 80 85 --max-family-uses 20 --reserve-exact-stems 0
```

| Bank items | Previous same-slot/family pairs | Gerund-only prototype | Integrated with numeric two-root family | Previous flagged structural patterns | Integrated patterns |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 15 | 0 | 0 | 0 | 2 | 2 |
| 40 | 35 | 32 | 29 | 18 | 13 |
| 80 | 175 | 164 | 153 | 76 | 55 |
| 85 | 200 | 188 | 176 | — | — |

The pattern count uses the earlier [audit's](../mapped-cross-slot-mechanism-audit-20260927/RESULTS.md)
three pair formulas: slot-3 proximity × slot-4 compound, pairs within slot-4
compound, and slot-2 quadratic maximum × linear maximum. These are structural
warnings, not newly confirmed semantic duplicates. The source still selects
some compound tasks; an 80-item bank could instead use the 24 noncompound
slot-4 exact stems and retain eight spare stems. That removes the earlier
capacity argument that compound and proximity must overlap, but does not
prove that a selector using those stems would produce a good bank.

The isolated gerund schema was 2,074 bytes. After integration with the
independent numeric two-root change, the mapped family schema is 2,101 bytes
(SHA-256 `ed2e1fbd2dff973a8a15c94d15a54dc8952f5c25a865a13c411e3a31e6c00cb0`)
and its transport name is `question_author_constructed_mapped_families_v7_n5`.
The mapped-agreement schema is 3,060 bytes. No live Bedrock call or full-worker
qualification was performed on these changed schemas. The opt-in route remains
disabled.

The first answer-blind review found eight correct keys and distinct choices,
but flagged repeated templates and two awkward phrasings. The phrasings and
connector were revised. A fresh answer-blind review of the final
[keyless worksheet](blind/worksheet.json) independently selected all eight
code-owned keys and judged all 48 within-item choice pairs distinct. It found
all eight natural, self-contained, and individually near level 2, while
flagging strong near-duplicates G1/G5, G2/G6, G4/G8, and G3/G7
([locked review](blind/review.json)). The balanced backend answer positions
are A–D twice each. Repeating this family across a bank can make it easier
than each item alone. The strict one-use-per-family 80-item capacity gate
still fails because all slots require repeated mechanisms.

Integrated verification: 1,452 backend unit tests, Ruff on changed Python,
and `git diff --check` passed. This is an incremental repertoire improvement,
not qualification of an 80-item bank.
