# Retrospective stage attribution

`trace.json` is a passive exact replay of the already committed
`../delivery-feedback-20260909/capture.json`. It binds historical source and SDK
versions and records the observer source hash separately. It is not a new model
run and does not apply current modified runtime code to old responses.

`stems-a.json` and `stems-b.json` contain 31 opaque raw occurrences each, shuffled
by ID, with keys, teaching, mode and downstream decisions withheld. The two
independent assistant assessors each assessed one packet. Their first passes are
in `assessment-a.json` and `assessment-b.json`; `freeze-a.json` and `freeze-b.json`
record exact hashes before author-key and stage joins. Each item has one assessor,
not two; no human expert adjudication is implied.

`private-mapping.json` preserves original operation/call/raw ordinals and raw
author content. All data is synthetic evaluation content. The name identifies
the file withheld during assessment; it contains no credentials or user secrets.

Run `python build-attribution.py` from this directory to rebuild `attribution.json`.
It verifies frozen hashes, exact author records and contexts, and joins by captured
occurrence identities. Aggregate cohort diagnostics remain separate from item
decisions. The script is specific to this complete historical capture and does
not infer missing observations for future captures.

`declared-reason-conflicts.json` preserves four manually reviewed contradictions
between labels and reasons. It is not a keyword-based semantic checker. The
reason-before-judgment hypothesis recorded there has not been tested.
`source-context-audit.json` records a separate current-normalizer truncation probe;
it does not attribute the historical selected-summary errors to that mechanism.

Read `../../QUESTION_STAGE_ATTRIBUTION_RESULTS.md` for findings, qualifications,
the earlier ecology-assessment disagreement and the next focused hypothesis.
