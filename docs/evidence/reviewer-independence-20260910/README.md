# Reviewer independence evidence

This directory records the completed comparison and its prospective assessment under
`paired-reviewer-solver-context-v1`. The protocol is
[QUESTION_REVIEWER_INDEPENDENCE_PROTOCOL.md](../../QUESTION_REVIEWER_INDEPENDENCE_PROTOCOL.md).

`subjects.json` contains twelve unchanged reviewer subjects without authored
keys, prior solver judgments, teaching or arm labels. `mapping.json` joins them
to the two already-committed historical captures. `independent-subjects.json`
contains the independent first assessment; the assessor may retain earlier task
context and is not described as fully blinded. `root-pre-response-notes.json`
preserves a distinct interpretation assessment, identifying the one unequivocal
spreadsheet defect, seven uncontested valid controls and four convention/scope
concerns. All twelve remain in the comparison.

`first-pass-freeze.json` binds those four files before fresh responses. Its own
hash is enforced by the runner. `access-preflight.json` is a sanitized read-only
availability check for the existing Sonnet profile; it contains no account
credentials and represents no inference or agreement change.

`plan.json` binds the exact ten jobs and 67 committed runtime sources.
`capture.json` is the terminal ten-call record. `plan-audit.json` explicitly
records that the independent audit completed after launch; root's exact source
checks preceded launch. `operational-audit.json` independently verifies all
calls, usage, cleanup, content observations, nine local policy replays and the
masked feedback export. `dispatch-record.json` names the one capture location.

`reviews.json` contains all 24 masked planned occurrences, including five null
records for the final malformed batch. `independent-feedback.json` and
`root-feedback-notes.json` preserve both assessments. `second-pass-freeze.json`
binds them before the final paired semantic summary. The original export's
`private-mapping.json` is archived as `feedback-mapping.json`, and its
`binding.json` is archived as `feedback-binding.json`; these are byte-identical
copies with descriptive names. Their original basenames remain in the freeze.
Mapping is public here only after assessment, to permit reproduction.

Run `python3 summarize.py` in this directory to reproduce `summary.json` using
only saved evidence. This helper does not invoke a provider or storage API.
To revalidate source-bound runtime policy, check out preparation commit
`040d0e5`, use Python 3.12 with boto3/botocore 1.43.91, and invoke the probe's
offline `content_observation`/`export_assessment` functions with these records.
Do not execute or restart the live plan. Original `/tmp` paths are provenance,
not required destinations for a local evidence copy.

Preparation tests use synthetic responses; they are not live correctness cases.
Read [the results](../../QUESTION_REVIEWER_INDEPENDENCE_RESULTS.md) for the
negative finding, scope and preserved interpretation differences. The manifest
binds every other file in this directory.
