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
Two independent keyless content reviews are pending. This is an author-only
diagnostic and cannot qualify the five-question worker.
