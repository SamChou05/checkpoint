# Closed English bank: stronger variety within the same 20-item replay

This isolated candidate expands slot 3 with a closed mass/count partitive
family and changes slot 4's compound family to contrast two roles of `each`.
For example, `Each of the clerks ___` takes a singular verb, while `Ava and
Ben each ___` keeps a plural verb. [GrammarBook's subject–verb agreement Rule
6](https://www.grammarbook.com/grammar/pronoun.asp) explicitly distinguishes
`each of` from `each` following a plural subject. The model supplies only a
scene ID and clause order; the server constructs the prompt, four choices,
key, explanation, and feedback for each choice.

The [keyless worksheet](worksheet.json) SHA-256 is
`636811004c5b9d3e99a275a432222f2af51fcd6748a453805b27088264146b18`.
It replays one captured native author task object across four offline
five-question refills. The [preparer](prepare.py) and [summary](summary.json)
lock source hashes and output bytes. No new model, full worker, queue, or
durable-bank call occurred. The [answer map](post-lock-answer-map.json) stayed
sealed until review A locked; review B was separately scoped to the keyless
worksheet and locked before answer-map comparison.

Both reviewers read only the worksheet. [Review A](blind-review-a.json)
SHA-256 `46ed9c44a4c988dda8ee81ebae42e569fece7c3fdfbca02eb507fe7fc3fe2b01`
and [review B](blind-review-b.json) SHA-256
`1c1a72cc93ccf1cf9f18da23866e19c6b9666fde2cbaf018c03f06f61bccf4cc`
each selected all **20/20** compiler keys, found all **120 within-item
choice pairs** distinct, and rated all questions within the target
difficulty 2–3. Both selected `D` for the new `each` item Q08 and rated it
difficulty **3**. They marked the English Q01/Q04 relation moderate and did
not flag a strong English near-duplicate.

Both reviewers assessed all **190 cross-item pairs** and independently
identified the same two highest-overlap numeric pairs:

| Pair | Solve-level overlap | Family labels |
| --- | --- | --- |
| Q05/Q06 | Solve a bounded integer quadratic, then select a valid root | `bounded_two_root_minimum` / `bounded_quadratic_equation` |
| Q11/Q16 | Reduce a linear inequality to an integer upper bound | `bounded_linear_budget_maximum` / `bounded_solution_count` |

Review A called these two pairs **strong** and recorded 19 moderate pairs.
Review B called them **high** and recorded 21 moderate and 39 low pairs;
their scales differ, so only the same top-pair finding is consensus. This
demonstrates that one-use-per-family selection can still repeat a learner's
solve process across different family names. Review B also noted one weak
arithmetic distractor at Q02 and artificial wording at Q17. The
[post-lock audit](audit.py) verifies all item/map joins, both reviewers'
keys and choice-pair judgments, all 190 pair IDs per reviewer, and the shared
top pairs; its [output](post-lock-audit.json) is reproducible.

**The English-specific change is supported; the 20-item bank is not yet
qualified for rollout.** The numeric solve-level repeats remain, and the
new provider schema has not been accepted by Bedrock in a live call. The
mapped-family native transport changes from
`question_author_constructed_mapped_families_v9_n5` to
`question_author_constructed_mapped_families_v10_n5`; its canonical schema
changes from 2,156 to **2,226 bytes**, SHA-256
`3ac240ae33163d16481c18a9eb8d1032404e5f06bf30cdac4a96304ff637edda`.
The agreement-only transport advances from `_v5_n5` to `_v6_n5`. The legacy
scene ID `compound_every` stays valid on the wire; the provider prompt now
calls its rendered task a compound-subject/each-of contrast.

The backend suite passed **1,462 tests**. Ruff, `git diff --check`, exact
worksheet replay, and the post-lock audit passed. These checks establish
offline constructor behavior and blind answer quality for one frozen sample;
they do not establish live worker yield or 80-item bank capacity.
