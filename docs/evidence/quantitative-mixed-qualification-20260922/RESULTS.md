# Mixed-route qualification: structure and provenance passed; overall trial failed

The actual generation runtime ran all three fixed jobs once, including its own
bounded top-ups. It made 13 provider calls and returned 12 of the 15 planned
questions. Every raw response ended normally and passed its exact JSON Schema.
No retries outside the runtime, fallback, repaired outputs or deployment occurred.

| Job | Returned / planned | Compiled returns | Calls | Seconds |
| --- | ---: | ---: | ---: | ---: |
| Quantitative | 4 / 5 | 4 | 4 | 85.414 |
| Python | 5 / 5 | 0 | 3 | 68.458 |
| Mixed arithmetic/English | 3 / 5 | 2 | 6 | 209.734 |

All jobs stayed within their 240-second and six-call limits. The primary
criterion failed: 12 is below 14 total, and the mixed job returned fewer than
four. The compiler thresholds were met: six total, four quantitative and two
mixed. One correctly assigned English prose item returned, though its content
still requires the same independent assessment as every other item.

The author produced four numerical specifications with no offered solution and
one with equivalent distractors. The compiler rejected all five. In the mixed
job the solver also vetoed an ambiguous pronoun question and marked another
candidate uncertain. These rejections preserved the release rules but reduced
yield; no rejected original was repaired or promoted.

[Offline provenance replay](provenance_review.py) reconstructs every returned
compiled specification from its original author row and source ordinal, then
recompiles it. All six returns preserve all five exact teaching fields. A separate
Fraction-based evaluator also confirms one offered answer and four distinct
numerical choices for each returned specification. All 13 raw response schemas
validate. [Machine-readable results](provenance-review.json) bind this replay to
the unchanged source files, frozen plan and capture.

The Python batch demonstrates why valid structure and a correct key do not
establish truthful feedback. Its first item's distractor explanation asserts
that Boolean operators return Boolean values and that None appears only when a
function has no explicit return. Python's and/or return an operand, and None is
also a built-in constant that can be written or returned explicitly. See the
[official Boolean operation rules](https://docs.python.org/3/library/stdtypes.html#boolean-operations-and-or-not)
and [None documentation](https://docs.python.org/3/library/constants.html#None).
The correct key for the specific question remains True. This is a new false
claim introduced by the final feedback writer after solving.

[Independent content adjudication](independent-review.md) checked all 12 main
explanations and 48 per-choice entries. All 12 keys were correct; 11 returned
items were sound and one contained the false Python feedback above. All met the
requested independent difficulty floor of 2. This cannot rescue the failed yield
criterion or the requirement that every returned item be sound. The trial does not qualify this complete configuration
for rollout. It does establish live use of the new mixed author grammar with
Kimi K2.5 and exact compiler provenance on six returned bounded tasks. It does
not establish arbitrary-topic accuracy or a population error rate.

Reported usage across all 13 calls: 43,239 input and 22,312 output tokens; every
call reported usage. Native reasoning content and signatures were omitted from
the capture. The prospective settings and original denominator remain unchanged.

- Frozen plan SHA-256: `969a26b22fc9d71b2e1f585e703231ba103218e867c24d75a41f0db2eae1f3ec`
- Capture SHA-256: `5a918fb1293e59488a6cbf912529f8268a270641704edb3e38b82ef63691ec73`
