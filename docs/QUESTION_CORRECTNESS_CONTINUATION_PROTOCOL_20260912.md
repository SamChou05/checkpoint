# Corrected assumptions and next bounded comparisons

This continuation starts from `dda2691` on PR #9. Main remains `7d9cc6a`.
PR CI (backend, secret scan, iOS tests/Release/analysis) completed successfully.
The original checkout still has unrelated uncommitted work and is not edited.

## Correction to the previous interpretation

The source-visibility controls proved that removing source facts changes which
questions a model accepts. They did **not** establish that every question needing
those facts is defective. Uploaded study material can define private terminology,
a fictional language or a rule the learner is expected to recall. Checkpoint's
adaptive-learning contract explicitly supports private/unfamiliar/user-defined
subjects, and onboarding offers study materials for practice tied to that content.
A fact not displayed beside a question is not automatically an omitted scenario
premise. The author prompt's self-contained requirement also needs that distinction:
it should prohibit missing case data, not require stating the answer to a recall
question. Product preference has been requested; the controls will keep both
interpretations visible rather than assume the prior blanket removal is correct.

The earlier claim of four demonstrated false acceptances is therefore withdrawn
pending that distinction. Keep the original traces unchanged. Do not count
rejecting valid source-based recall as improved correctness. Stimulus deletion and
its positional-content controls are independent of this correction.

## Frozen scope and budget

At most **48 new provider calls** for this continuation; previous 102 calls remain
separate historical accounting. Stop an operation on transport failure. Do not
retry a timed-out request, deploy, or write learner inventory.

1. **Source-boundary control, at most 16 calls.** Four domains, four fixed items
   per domain. In each domain: two source-grounded recall/application items,
   one genuinely missing-case item, and one fully stated control. Compare the
   current displayed-only solver with an answer-blind source-supported solver.
   Exclude hidden goal/objective metadata in the candidate and prohibit borrowing
   another question's premises. Keep native transport and model fixed in both
   arms. Two existing verification stages, no regeneration.
2. **Teaching control, at most 8 calls.** Replay four actual final-review inputs
   containing previous false teaching: negative arithmetic, source-defined
   operators, SQL joins and solstice timing. Compare the current reviewer with
   direct rule/result contrasts that do not invent a learner's error or a
   counterfactual procedure. Hold input, model and native transport fixed. Read
   every main/choice explanation, not just the final key or an approval field.
3. **Fresh qualification, at most 24 calls.** Four new two-question requests across
   math, programming, language and facts, each run with the API Nova Lite author
   and worker Kimi author, with independently configurable native verification.
   Include sourced/source-free content and varied difficulty. One complete pass
   and at most three actual calls per job. No weaker parser or added retries.

Only retain source/prompt/default changes supported by matched results and fresh
checks. A native verifier contract must be configurable independently from the
author so that the API's Nova Lite author is not forced into an unsupported
native schema mode. Native output fixes envelopes, not semantic correctness.

Record exact sanitized calls and stage outputs, keys, ambiguity, main/choice
support, distractor quality, useful output, calls and latency. Label corrected
findings and uncertain interpretations explicitly. Preserve revisions for checks
actually performed and document backend-before-client release ordering if the
production policy changes again.

## Deployment correction

A fresh read-only configuration check found the deployed API's `SKILL_MAP_MODEL_ID`
is Kimi K2.5, although its question author is Nova Lite. The earlier deployment
snapshot omitted that field. The Nova map call remains a real local inference
with explicitly selected settings; it was not a test of the deployed skill-map
configuration. API/worker package hashes and modification timestamps are unchanged.
The [new configuration record](evidence/correctness-continuation-20260912/deployment-recheck.json)
includes the previously omitted field. Do not silently relabel the old trace.

## Goal-reference completion audit addendum

The 45-call milestone leaves an unverified loss in the proposed source-only
boundary: the request contract preserves literal subject material in goal and
skill descriptions, yet that material is discarded before solving. This repeats
the source-removal mistake for another supported input field. Use at most the
**three remaining calls**, keeping the existing total ceiling of 48, to compare
the same eight fixed questions under source-only and complete subject-reference
solving. Move the four existing reference texts verbatim into `goal.focusAreas`:
four valid learned-fact recalls and four missing-case questions. Two native solver
calls are matched; one candidate final-review call may follow. No new author
inference, retries, deployment or inventory writes. Preserve author blindness and
per-item case requirements. This is an evidence-driven boundary correction, not
an attempt to spend the unused budget or establish population error rates.
