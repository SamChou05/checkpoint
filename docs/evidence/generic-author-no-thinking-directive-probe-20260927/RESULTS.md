# Disabled-thinking author-only probability directive trial

The [frozen plan](plan.json) SHA-256 is
`4904119d0e962b5fce8af6ba9645c1c320315eb533d9992e4e48f0560ddda73f`.
It changed only the request's 681-character probability question directive
relative to the prior disabled-thinking author-only probe. The one-shot
[capture](capture.json) SHA-256 is
`47b2bbfbd9a73ba20a4b80564573607e7ea899edf106a0f83f97838481f1a524`.
Fresh AWS identity matched the planned account. The native author call
completed in **19.641 seconds** and the bounded run in **20.916 seconds**;
Bedrock reported `end_turn`, 3,538 input tokens, and 1,390 output tokens.

The native contract held all seven rows. Offline replay of the existing
sanitizer accepted **six of seven** and rejected one for `duplicate_choices`.
The six surviving candidates are in a source-order-blind [worksheet](worksheet.json)
at SHA-256
`6fbabc26cfed021228a9e6ec888a3d7144961a6742e918645f42b3ac240ea773`.
The [worksheet builder](make_sanitized_worksheet.py) pins the capture and
sanitizer hashes, replays acceptance, and stores its answer map outside Git.
Two independently locked keyless reviews ([A](review-a.json),
[B](review-b.json)) agreed that only **five of six** sanitized items have a
supported offered key. Public P02 asks for expected net gain from one $150
prize, two $25 prizes, 200 tickets, and a $2 ticket cost. The correct value
is `($150 + 2×$25)/200 − $2 = −$1.00`, absent from all four choices. After
the reviews were committed, the private map showed that P02 is author source
ordinal 6, with asserted key `−$0.50`. Its authored explanation itself ends
with `−$1.00`, so the explicit key, choices, and teaching disagree. The
sanitizer checks literal choice uniqueness and format, not arbitrary-topic
mathematical truth; the mandatory answer-blind solver was **not run** in this
author-only probe.

Both reviews rated P03 below the requested level 2 and flagged P02–P06 as a
strong repetition of expected net monetary gain with dollar-only responses.
They differed on whether P01 is below level 2 and whether P03 literally
matches the directive's direct-complement exclusion. Their choice-pair
assessments also used different thresholds for a *meaningful* distractor, so
we do not treat numeric distinctness alone as quality. The clearer directive
therefore did not yield a sound, varied author batch in this sample. It is
not a validated prompt improvement or a five-question worker qualification.
