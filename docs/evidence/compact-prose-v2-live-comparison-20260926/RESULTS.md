# Compact mapped prose prompt v2: one-shot paired author result

**Result: v2 scored one more usable item in this paired sample, but still failed
the five-of-five content gate. Do not activate or deploy it on this evidence.**
The v2 arm had four of five items with one answer supported by both blind
reviewers; v1 had three of five. Both arms produced five native-schema-valid
author slots, and all ten passed local compilation/sanitization. Those structural
passes did not establish semantic correctness of the English items.

The frozen [plan](plan.json) SHA-256 is
`20b369b9719c1cad29642dfe66e3c94b89f6632931dafe79654b3ff5402d3bdb`.
The one-shot [capture](capture.json) SHA-256 is
`1638dbed88def242362a4b215e652ca41ffc688cb473b3124b7e189308e5093b`.
The randomized order was **v2, then v1**. Both requests used the same exact
five-slot 3 arithmetic : 2 English normalized request, Sonnet 4.6 profile,
2,664-byte native schema (`eee8c873...`), user prompt, adaptive high effort,
16,000-token cap, and trusted slot assignments. Only `system[0].text` differed.
There were exactly two Bedrock Converse author calls, one per arm, with one SDK
attempt each; no solver, reviewer, repair, fallback, or top-up call. Both
responses ended normally and adapted under the native schema. Total elapsed
time was 141.136 seconds. V2 used 5,144 input and 7,876 output tokens in 79.7
seconds; v1 used 4,995 input and 5,932 output tokens in 60.241 seconds.

The [keyless worksheet](worksheet.json) was generated in a separate reviewer
directory with shuffled item order and choice order, random IDs, and no arm,
key, explanation, or original slot. Its SHA-256 is
`f8f4d74b160df0bcef77cbd8a143dbc0d6e95dccd8433f92f375212e6bbef4d7`.
Independent [review A](review_a.json) and [review B](review_b.json) were locked
before the [private map](blind-private-map.json) was opened; their hashes are
`4db38bf9fec83046817059b52c05a38e9656216014670073b790eb19bece68f9`
and `98640af22f2744a523cc19af874e29f9a9268b949778afb6a5edf8f8deaed1af`.
The private map hash is
`10d40d10e174a5e3925318ae3743feae480d6ac0e5b9af81208c4ea45cfc3b1c`.
Both reviewers judged every one of the six choice pairs distinct in every
readable item. They selected the explicit key for all six compiled arithmetic
items and the v2 agreement item. Deterministic recompilation of all six
arithmetic tasks reproduced the same specifications and learner fields; none
failed compilation. The actual sanitizer accepted all five slots in each arm.

| Arm | Original slots 0–2 | English slot 3 | English slot 4 | Both reviewers support one key |
| --- | --- | --- | --- | --- |
| v1 | Three compiled arithmetic items; both reviewers agree with each key | Collective-noun completion: both reviewers found the unstated variety/tense context capable of making another form defensible | Asks for an unambiguous *pronoun reference*, but intended keyed sentence removes the pronoun; both reviewers withheld a unique answer | **3/5** |
| v2 | Three compiled arithmetic items; both reviewers agree with each key | Singular `box` agreement with an intervening plural phrase: both reviewers selected the explicit key | Names the actor after stating that the actor was nervous: reviewer A selected the explicit key, while B found the stated revision criterion could also admit naming the director unless preservation of the actor referent is made explicit | **4/5** |

The v2 English explanations have no display-position references. Its agreement
explanation supports the selected literal answer. The v2 pronoun explanation
has a separate factual teaching error: it says naming the director as nervous
"contradicts" the stated fact that the actor was nervous. Both people can be
nervous; that fact alone does not exclude the director answer. An independent
post-lock teaching audit identified this unsupported exclusion. The split blind
judgment already made the question unresolved under the all-reviewers gate;
the false exclusion is an additional reason not to credit its teaching.

The v1 pronoun explanation refers to answer letters `(a)` through `(d)` after
the answer choices can be shuffled; the existing
`contains_answer_label_references` guard flags it. It also says `they` must be
plural, overlooking singular `they`, so its teaching is unsound even apart
from the missing-pronoun key. The v1 collective-noun explanation invokes
American English even though the learner stem does not state that convention.
Numeric compiler teaching is exact and shuffle-safe, though exact-value
wrong-choice feedback remains generic.

This is an author-only paired sample. It shows that the accepted native schema
can enforce five typed slots and that the v2 instruction avoided the prior
position-label failure in this draw. It does not measure a population failure
rate, prove v2 always writes unambiguous English, or establish the number a
full worker with independent solver and teaching reviewer would return. The
next candidate needs a local deterministic English constructor or a stronger
semantic admission rule, followed by fresh full-worker qualification before
any rollout.
