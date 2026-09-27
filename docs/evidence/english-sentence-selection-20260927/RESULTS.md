# English full-sentence selection prototype (2026-09-27)

Source commit: `27822513dcbb688881c4014bf7c14f9df8e31fd8` on isolated branch `codex/english-format-diversity`, based on `origin/main` at `ad5dd56`. No provider call, deployment, merge, or push was performed in this worktree.

The four-question [keyless worksheet](KEYLESS_SAMPLE.json) is frozen at SHA-256 `4b49ed977535b086ac1d7384ecc78a1683397c81bb8eedb482934b91771aea4c`. It contains prompts and choices only, with no answer key or teaching, for independent review of one-key correctness, level, and novelty.

The new slot-4 scene family asks learners to identify the only grammatical complete sentence among four alternatives. Each alternative tests a different nontrivial present-tense agreement relation: a joined subject followed by `each`, `each of` plus a plural noun, `neither...nor` with a plural nearer subject, or a singular -ing activity containing a plural noun. The compiler selects one grammatical form and deliberately makes the other three ungrammatical. It owns all choices, the exact key, main explanation, and per-choice feedback. Eight closed scene/order variants add eight distinct canonical stems, increasing the total English inventory from 64 to 72 and slot 4 from 32 to 40. The existing wire task kind remains `agreement_pair_v1` for compatibility; the closed `select_*` scene IDs identify the new format.

The combined native schema is 2,289 bytes, SHA-256 `bb7ac654a18fa34c5dedcaa25b76d3693b7a7d5ae9206a728ae2d895c10406fa`, transported as `question_author_constructed_mapped_families_v11_n5`. The agreement-only schema is 3,193 bytes, SHA-256 `fb2aec963d6283a524cdbe406138181b58290ec9f8956a7ae3a11e5d93228909`, transported as `question_author_constructed_mapped_agreement_v7_n5`. Schema validation and fake-provider transport/adapter/compile tests passed. Live Bedrock acceptance of these new schema bytes has **not** been tested.

The final source passed 1,464 backend unit tests, Ruff, and `git diff --check`. Tests use an independent expected-key table for all eight variants, check all four answer positions, exact one-key membership, four distinct full-sentence options, bounded explanations, and integration through the mapped slot compiler. The existing capacity harness now accounts for the additional finite variants. This does not establish that repeated use of the format is sufficiently diverse for a 20/40/80-item bank; independent blind content review is still required.

Two independent answer-blind reviews were then locked against the keyless
sample ([A](blind-review-a.json), [B](blind-review-b.json)). Both chose the
code-owned keys **A, B, C, D**, found no second viable answer, rated all four
at difficulty 2–3, and judged all 24 within-item choice pairs meaningfully
distinct. Each new question was rated low in similarity against the older
slot-3 inverted-subject/two-blank question from the live v10 worksheet. Both
reviewers rated all six new-to-new pairs strongly similar: the same four
agreement decisions and sentence-selection scaffold recur with new nouns.
This adds a genuinely different format for a paired English slot, but only
one use of this format is supported by the current blind novelty evidence.

After merging with the separately reviewed numeric-family expansion, the
combined schema is 2,357 bytes (SHA-256
`495db717d6b3fd6cc5272cdb289c7d77d9ca2e275b7c1d3f0cb856c1a18b6934`)
under transport version `v12`. The integrated backend passed **1,467 tests**,
Ruff, and `git diff --check`. Live acceptance of this merged schema remains
unverified; the route stays disabled in production.
