# Preserve the whole solver and reviewer response

September 8, 2026. Semantic decision parsers now require the entire response to
be a JSON object, with optional surrounding whitespace or one sole JSON code
fence. They no longer salvage an object from surrounding prose. This is a
format/admission safeguard, not an independent correctness check.

## Problem and scope

The earlier assumptions-only gate has already been replaced: declared negative
outcomes, uncertainty, unresolved limitations, and exact alternative-key
disagreement have application-enforced vetoes in the historical stem-only path.
The current generation path uses complete-choice judgments, requiring exactly
one supported choice, three refuted choices, and exact author-key agreement.
Neither contract proves the model's judgments correct.

A separate data-loss path remained. The general author-response extractor could
discard text before and after a JSON object. Solver and reviewer parsers reused
that extractor, so an objection in surrounding prose could disappear from the
admission decision while an approving structured record survived.

In the unchanged [focused application capture](evidence/focused-application-capture-20260908.json),
two final-audit responses contain prose before the structured verdict. One
recognizes a contextual problem in the breakfast question before approving its
intended reading. The other reports a dough objection in its structured verdict
as well. The earlier report and capture remain historical evidence under their
original source version; this change does not rewrite their results.

A parser-only offline check of all eight saved semantic responses accepts the
four solvers and two exact-JSON audits unchanged, and rejects the two audits
with surrounding prose (zero-based capture call indexes 6 and 9). The source
capture retains SHA256
`b8375f724b5829145eec110c026d2cdc302005181abb9300341ced44aec003ae`.
These are two format rejections, not two newly established factual detections.

## Enforced behavior

The strict parser is used by the historical stem-only solver, complete-choice
solver, ordinary final reviewer, and opt-in authored-explanation auditor.

- A complete object or a sole fenced object remains accepted by the parser.
- Prefix/suffix prose, multiple objects, malformed fences, duplicate properties,
  and non-JSON numeric constants are rejected.
- Exact text inside JSON strings is preserved, including whitespace, Unicode,
  braces, and code-fence characters.
- Solver format failure prevents final review. Reviewer format failure prevents
  returning or stamping questions from that response. Existing diagnostic
  categories record these as format failures, not factual defect detections.

The authoring extractor retains its existing recovery behavior. Model settings,
prompts, call budgets, verification versions, and policy revisions are unchanged.
Historical evaluation source bindings are unchanged; source-bound captures must
still be interpreted with their recorded implementation.

## Limits and verification

Rejection applies to the whole response batch, including otherwise sound items.
Harmless introductory prose also fails. This conservative rule prevents ignored
response content; it does not determine whether that content is an objection.
A wrong label or contradiction entirely inside valid JSON can still pass the
existing declared-judgment checks. No live accuracy or yield improvement is
claimed, and stored questions are not retroactively revalidated.

Focused regression tests cover exact-content preservation and the runtime
no-review/no-stamp behavior across both solver contracts and both feedback
contracts. Validation passed the 895 existing backend tests and, in a separate
run after the new test file was added, all eight new regressions. Ruff, Python
compilation, the whitespace diff check, and independent review also passed.
No model call or deployment is part of this change.
