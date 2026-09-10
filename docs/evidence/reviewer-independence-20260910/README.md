# Reviewer independence evidence

This directory initially records prospective assessment before any calls under
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

Preparation tests exercise synthetic observer and policy responses only. Their
success is not evidence of live question correctness. A completed experiment
must add its exact plan, terminal capture, masked review assessment and results
before claiming any observed effect.
