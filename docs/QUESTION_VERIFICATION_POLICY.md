# Verification policy freshness

`verificationVersion: 1` is the existing rendering and grading contract. It
preserves the reviewed stem, choices, answer, and feedback. It is not a freshness
indicator: older inventory already has this value.

The separate `verificationPolicyRevision: 1` records that the current independent
solver gate and final review ran successfully. Only the backend assigns it after
both stages pass. Author-provided metadata is discarded; review-only helpers and
local Foundation generation cannot mint this provenance. A missing revision is
legacy/unknown, represented as zero on the client, and is never backfilled.

This revision is **not a correctness certificate**. In particular, a solver can
still report `resolved` with empty limitations while describing an impossibility
only in its answer prose. An approving reviewer can accept that contradictory
record. Freshness closes reuse of older gates; it does not close this remaining
semantic gap or establish a production error rate.

## Admission and recovery

- Updated Pro clients require the current policy from their first question,
  including before any reviewed inventory or attempts exist.
- Claims send `minimumVerificationPolicyRevision`. The server strictly validates
  the integer, filters stale ready inventory, and rejects stale saved-claim
  responses on both normal and transaction-race replay paths.
- A policy change also changes the client's bank context, resetting obsolete
  bank and claim identifiers and blocked refill state.
- An explicit claim conflict rotates the saved claim identifier while retaining
  the bank. Transport failures retain the identifier for safe idempotent replay.
- Old questions and attempts remain in history with their original content,
  grading version, results, and revision. They cannot become fresh Pro practice
  merely by being loaded. This change does not reset past adaptive evidence.

## Rollout

Deploy the backend before releasing the updated client. A new Pro client pointed
at an old backend will reject unstamped questions and may remain without a ready
quiz. This is intentional rejection of unknown provenance, not successful
compatibility with the old backend. No deployment is part of this change.

Older clients omit the new claim minimum and retain legacy server behavior;
their installed local caches are also unchanged. This compatibility does not
mean they receive the new freshness guarantee. Starter behavior is unchanged.

Backend validation: 625 offline tests passed, with one existing opt-in test
skipped; these are protocol and regression checks, not 625 live model questions.
The explicit model-comparison source manifest includes the new policy module;
the other current experiment runners include it through their shared source
hashing. Existing frozen experiment snapshots and evidence remain unchanged.
