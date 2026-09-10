# Checked author demonstrations

Prepared on 2026-09-09 for the [prospective transfer experiment](QUESTION_AUTHOR_EXAMPLES_PROTOCOL.md).
The exact three original examples are in
[`question_author_examples.json`](../backend/bedrock-question-service/evals/fixtures/question_author_examples.json).
They were written and revised manually before any transfer outputs existed.
They are demonstrations of construction standards, not retrieved evidence for
the transfer subjects or a validated question bank.

## Review of the final examples

The root assistant and a separate assistant reviewed the keys, all choices and
complete explanations. The separate reviewer saw the proposed keys and teaching;
this preparation review was not blind or performed by human subject experts.
Initial parcel and English drafts were too simple to demonstrate the requested
difficulty, so they were revised before the final assessment below.

| Example | Final content check | Distractor errors |
| --- | --- | --- |
| Parcel assignment | Exhaustive enumeration of the nine possible van assignments leaves only A in Q and B in L. A requires padding and capacity at least 6 kg; B requires capacity at least 7 kg; vans cannot be reused. The main preserves all three constraints. | Insufficient capacity, missing padding, reusing a van. |
| Bundled treatments | Fertilizer-only, light-only and an interaction requiring both can all produce greater growth in the group receiving both changes. Random assignment does not separate these bundled effects. The stated comparison cannot identify which treatment change caused the difference. The main does not claim a significance result or that randomization eliminates every prior difference. | Attributing the effect to fertilizer alone, light alone, or asserting both were necessary. |
| Reporting an email | Maya sends thanks to Lena for lending notes. The keyed report preserves those roles and the stated action. Lending does not establish ownership. The final ownership distractor explicitly says Lena owns the notes; it does not rely on the ambiguous possessive phrase “Lena's notes.” | Unsupported ownership, reversed participants, substituting returning for lending. |

Root independently checked the final revisions. A local enumeration confirmed
the parcel result. Three simple countermodels, with growth increment respectively
`F`, `L` and `F*L` for binary treatment indicators, agree on both observed bundles
while attributing the change differently. These demonstrate non-identifiability;
they are not empirical plant-growth models. English review checked ordinary
reported meaning and each added claim directly.

All three keys and mains are supported under their stated scope. Each example
has four distinct choices and three identifiable mistakes. Difficulty 3 is a
qualitative assessment near its lower boundary, especially for experimental
design and English. Experienced learners may answer them readily. There are no
learner measurements establishing difficulty or distractor attractiveness.
The experiment must therefore test transfer rather than assume these examples
are sufficient instruction for advanced authorship.

| Example | Stem characters | Choice characters | Main characters |
| --- | ---: | --- | ---: |
| Parcel assignment | 259 | 14 / 14 / 14 / 14 | 222 |
| Bundled treatments | 253 | 17 / 22 / 28 / 48 | 302 |
| Reporting an email | 166 | 40 / 51 / 40 / 42 | 258 |

The negative answer uses the canonical cannot-determine wording required by the
unchanged author prompt. Each example uses the exact author field names and
`Multiple Choice` format. Only its subject context and question enter provider
input; its ID, preparation review and transfer assessment notes do not.

## Identity and limitations

The completed fixture is 13,903 UTF-8 bytes, with byte SHA-256
`82fb6ca25666ab4d00c0780cae9f1d41e0ff9fecd33555e99b0d50e57f393bc8`
and canonical SHA-256
`9362c40b5c7557e7924293faae75ed5418a6805a5a4e49c6a45df4f1f1921cb0`.
The canonical hash of `demonstrations` alone is
`a121937d77ab0f99240867eafbeb5bc5b94a6ac245d90a6dd616965159a94937`.
Canonical serialization is defined in the [source packet notes](QUESTION_AUTHOR_EXAMPLES_SOURCES.md).

The examples differ from the transfer tasks, but experimental design and ecology
share a broad science setting. Static demonstrations add tokens and can prime
style or content; this small comparison cannot isolate those influences. No
provider calls have yet tested these demonstrations, and no production prompt
has been changed.
