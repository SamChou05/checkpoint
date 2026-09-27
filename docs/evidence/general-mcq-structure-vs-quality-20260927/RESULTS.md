# Two-call structure versus question-quality comparison

The frozen comparison asked Opus 4.6 for five level-3 multiple-choice questions
about a short synthetic Python source file. The same author request was sent
once with native structured output and once without it. This was a bounded
author-only diagnostic, not a full bank-worker or deployment qualification.

| Arm | Bedrock stop | Input / output tokens | Runtime | Format | Sanitizer yield | CPython key check |
| --- | --- | ---: | ---: | --- | ---: | ---: |
| Native schema | `end_turn` | 2,604 / 7,875 | 123.414 s | bare JSON | 5/5 | 5/5 |
| Ordinary output | `end_turn` | 2,150 / 10,008 | 135.374 s | sole JSON fence accepted by the runtime | 5/5 | 5/5 |

Both responses parsed, matched the author schema after parsing, and presented
four distinct listed choices with exactly one CPython-supported key per item.
The two calls used `us.anthropic.claude-opus-4-6-v1`, adaptive/high reasoning,
16,000 maximum output tokens, a 300-second client read timeout, and no hidden
SDK retries. The request objects were equal except for `outputConfig`; there
were exactly two provider dispatches. Reported usage totaled 4,754 input and
17,883 output tokens.

An independent reviewer read only [blinded.json](blinded.json) and locked
[item-level judgments](blind_review_numeric_bank_novelty.json) before opening
the keys or captures. They selected the model's key on all 10 items and rated
every stem self-contained and uniquely solvable, but rated five questions
level 1 and five level 2; none met the requested level 3. They flagged four
near-duplicate pairs: Q001/Q010, Q002/Q004, Q005/Q010, and Q007/Q008. Six
items exercised the same replace/skip/strip pipeline and four exercised
literal-space splitting. The post-key [nonblind assessment](assessment.json)
was less severe, rating seven items level 2 and three level 3. The locked
blind review is the stronger difficulty observation; difficulty remains a
human judgment, not a mathematical oracle.

This supports the user's intuition that a modern model can make a small,
correct, structurally valid quiz on a concrete topic. It also isolates a
different failure: format and key agreement did not enforce requested
difficulty or bank variety. It does not estimate population success, compare
models, prove schema superiority, or qualify the full author-solver-reviewer
worker. The ordinary arm's sole JSON fence was tolerated by the then-current
runtime parser; the sample says nothing about responses wrapped in
contradictory prose.

The [frozen plan](plan.json) records the exact request, schema, model settings,
and two-call ceiling. [capture.json](capture.json), [call01.json](call01.json),
and [call02.json](call02.json) retain responses and reported usage;
[answer_key.json](answer_key.json) maps the blind items back to their keys.
The [oracle](oracle.json) executed the exact source under CPython 3.12 and
checked the literal stem operations against all offered choices. Source
revision was `4c03889a802403cea6c9d4e485c8ccc384c33555`. Plan SHA-256:
`744fc6af51e5f2bd0684c2b5c0ebbf423992c6c63fc5e9c72d6efa599e94c848`;
capture SHA-256:
`25e0317f564f78505d009feb16780b3f9438537bc6e903054338a82d6257bdbf`.
