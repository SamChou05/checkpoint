# Seven-candidate generic reserve: first bounded trial

**Failed before Bedrock dispatch; no model-quality inference.** The frozen
plan SHA-256 was
`771538ec09d7e88d0e555020c20806d4b0a9bab40dfe58aea31631ee9ddae12d`.
The reviewed AWS precheck verified account `239342516379` and fresh
credentials. The one-shot execute then verified the same account and reserved
its first Converse slot, but a local provenance guard stopped the job before
the SDK call. The immutable capture SHA-256 is
`607cd5037da7e892c9a70f65fe29ae3342d2eb795e7c90917d8060569efc3a94`:
one provider reservation, **zero saved or dispatched Bedrock calls**, zero
authored candidates, zero returned questions, 1.328 seconds total.

Two independent socket-free reproductions identified the exact harness bug.
During `run_job`, the per-dispatch `pin_check` called `check_plan`, which
rebuilt the plan by making a fake author request. That re-entered the patched
production `_generate_with_bedrock` while the original author stage was
active, so the stage-order guard rejected a second author call. The runtime
wrapped that integrity failure as `ProviderError`; the capture's
`request_or_provenance_integrity` stop and reserved-but-unattempted slot match
the reproduction. The initial review's 15 fake tests did not exercise the
real per-dispatch `pin_check` callback, so they missed this reentrancy.

This trial ID is terminal: its plan, precheck, and capture remain unchanged.
A successor requires a new trial ID, a static non-reentrant per-dispatch
source/plan check, a socket-free regression using that exact callback, and
fresh independent hash review before any AWS call. The opt-in reserve remains
unqualified and disabled by default.
