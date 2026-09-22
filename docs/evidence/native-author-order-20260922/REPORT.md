# Author schema property order: controlled comparison

Four authorized Kimi K2.5 calls compared the existing alphabetically sorted fixed-slot author schema with a schema that orders question fields as `prompt`, `choices`, `explanation`, `correctChoice`, then metadata. Each arm generated five arithmetic/logic items and five Python items. The [plan](plan.json) fixed the same prompts, model, temperature, token/time limits, field types, required-field arrays, enum and schema name. Only the serialized question-property order changed. Arithmetic ran sorted then ordered; Python ran ordered then sorted. No production serializer changed during the experiment.

The [capture](capture.json) retains every exact dispatched request, raw response, adapter result and sanitizer result. Both arms completed normally with valid native JSON, five items per call, four distinct visible choices per item and mapped answer keys. All 20 items met the existing display bounds and passed the existing sanitizer without choice/key text changes. Provider output followed the schema property order: the sorted arm placed the key and explanation before the stem; all ten ordered items placed stem and explanation before the key.

| Measure | Sorted | Ordered |
| --- | --- | --- |
| Calls / generated items | 2 / 10 | 2 / 10 |
| Strict schema, count and display-bound passes | 10/10 | 10/10 |
| Keys supported without the recipe ambiguity below | 7/10 | 9/10 |
| Definite incorrect keys | 3 | 0 |
| Ambiguous proportional-recipe assumption | 0 | 1 |
| Input / output tokens | 3,968 / 1,658 | 3,968 / 1,374 |
| Total provider-call wall time | 29.737 s | 27.472 s |

Two agents independently reviewed every unchanged question, with direct arithmetic/Python calculations. The [per-item adjudication](manual-review.json) records each finding. Sorted arithmetic item 4 keys 15 even though the intended calculation yields 9 and 9 is absent. Sorted Python item 1 keys 2 for a loop that counts to 3; item 2 keys 6 for an expression evaluating to 8. In two of these failures the explanation itself contradicts the selected key. Sorted Python item 3 has the correct key 14 but adds an incorrect parenthesized counterfactual: `(4 + 2) * 3 + 4` is 22, not 18.

The ordered arm's keys agree with the calculations under the usual proportional-recipe reading, but it is **not ten unambiguous semantic passes**. Arithmetic item 3 requires scalable portions and fractional eggs to reach 15 servings; these assumptions are not explicit, while complete six-serving batches would permit only 12. Its Boolean-expression item has a correct key and short-circuit conclusion but abbreviates the right-hand grouping imprecisely. These limitations remain in the evidence.

The experiment supports schema field order as a concrete contributor to the observed author inconsistency: content can be generated in a more useful dependency order without changing the semantic schema or prompts. It does not prove deterministic correctness, quantify a general error rate, or qualify final learner feedback. The sample contains only two paired prompts, temperature is 0.2, generated questions differ across arms, and grammar-cache state is unobservable. The earlier sorted-author probe's bounds failures remain separate evidence; this comparison's sorted arm met all bounds. Independent solving and final review remain necessary.

Plan SHA256: `05dc4287280e553d2eb284edd68fe93c4805eedba6f42ddfebb156207410b829`. Exactly four calls were made, with one SDK attempt each and no retries, fallback, repair, provider judge, question-bank write or deployment.
