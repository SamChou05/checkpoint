# Closed numeric solve-mechanism expansion

The mapped numeric bank previously had only three distinct compiled solve
mechanisms in each of slots 1 and 2. A strict one-use-per-mechanism rule would
therefore stop after three complete five-question batches, or 15 items
([diagnostic](../solve-signature-gate-20260927/RESULTS.md)). This change adds
an expanded quadratic **nonroot count** in slot 1 and a centered-square
**strict-inequality count** in slot 2. Their compiled relations/degrees are
different from the existing mechanisms and from each other. The closed
inventory now has four distinct graph-derived mechanisms in each numeric
slot, 12 distinct numeric mechanisms globally, and 976 executable numeric
variants. Theoretical one-use capacity rises from 15 to **20 complete items**.
This is an inventory bound, not an enabled selector or observed worker yield.

The source first tried an expanded three-root cubic for slot 2. In the frozen
[eight-item keyless sample](cubic-keyless.json), two independent answer-blind
reviews ([A](cubic-blind-review-a.json), [B](cubic-blind-review-b.json)) agreed
on all eight [code-owned keys](cubic-post-lock.json), with one key per item,
but both rated Q06–Q08 at difficulty 4, above the target 2–3. The cubic was
replaced before integration.

The first centered-square [eight-item sample](centered-square-keyless-v1.json)
also had eight unique keys and distinct choices in both blind reviews
([A](centered-square-blind-review-a.json),
[B](centered-square-blind-review-b.json)); both rated its smallest-radius Q05
at difficulty 1. The constructor now uses `radius = a + 1`, so its smallest
allowed radius is three. A subsequent [four-item keyless check](radius3-keyless.json)
was solved by an independent [blind reviewer](radius3-blind-review.json): all
four matched code-owned keys, all 24 within-item choice pairs were distinct,
and all four were rated difficulty 2 in isolation. The reviewer also noted
that seeing repeated versions together makes later items easier. The final
radius adjustment has one blind content review; it is not a statistical
reliability estimate.

The two eight-item reviews found strong within-family repetition, as expected
when four variants of one solve mechanism are shown together. In the
centered-square sample, the reviewers also found that all eight questions
share the generic domain/condition/count presentation, even when the solving
steps differ. A solve-signature gate would address method repeats, but not
that format repetition. Strict cross-bank selection and broader formats remain
separate work; a 20/40/80-item bank is not qualified by these samples.

The two new families have code-owned answers, four distinct choices, a
checked domain-wide proof, and feedback for every offered choice. Exhaustive
tests cover all 72 admitted parameter pairs per new family; the integrated
backend passed **1,467 tests**, Ruff, and `git diff --check`. The merged
numeric/English native schema is 2,357 bytes and awaits a bounded live
Bedrock acceptance check. The mapped route remains opt-in and disabled in
production.
