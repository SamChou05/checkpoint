# Agreement difficulty calibration: next one-shot qualification

This is a **new, unlaunched protocol** for the narrow agreement difficulty
calibration change. The previous agreement full-worker capture is a **3/5
original-slot failure**. Its two blind diagnostic reviews support testing a
bounded calibration change, but neither those pre-review candidates nor this
offline plan convert that failed run into a pass.

`request.json` is the exact prior normalized five-slot request (SHA-256
`212cea7d53ddefe17fbe8f2459705b46b871793e62e0e58b56cc11e3626e63ae`).
It asks for three exact-arithmetic and two standard-written-English questions,
at target level 2. `qualification-spec.json` pins the request, the opt-in
`QUESTION_MAPPED_AGREEMENT_TASKS=enabled` route, Sonnet 4.6 in `us-east-1`,
native output, adaptive/high effort, authored-solution feedback, no fallback,
and the prior accepted 2,701-byte native author schema. The candidate may
change only the narrow post-review difficulty admission policy; the author
prompt, author wire request, native schema and other settings must retain
their pinned hashes. If any of these change, this comparison is invalid and
requires a new reviewed protocol before a provider call.

## Source and launch gate

The source under test was deliberately unset in the initial draft. Candidate
source commit `22aec98b5ba7685a30218441029d0f7299776a35` has since landed on
main. The draft specification retains empty source fields as a record of the
unlaunched proposal; the new harness inserts the full commit, source-worktree
path, and SHA-256 of every relevant runtime/source/test/protocol file into a
fresh frozen plan. The source commit must be reviewed as the narrow policy
change, include focused tests for reviewer levels 1–5 and malformed responses,
and stay fixed throughout the run. Recompute the exact normalized request, goal, initial author prompt,
native schema/config, and initial author wire from that source. Validate the
schema with JSON Schema Draft 2020-12 and the outgoing Converse wire with the
local botocore service model. Source/prompt/schema/wire mismatch aborts before
AWS. Do not use the old source revision or old capture as the candidate.

Adapt the archived durable full-worker harness into this **new evidence
directory**, then freeze a new immutable `plan.json` only after the candidate
source commit and all runtime hashes are inserted. The harness itself is
hash-pinned. Root and an independent reviewer must inspect the source,
protocol, harness and exact frozen plan SHA-256 and explicitly approve the
same hashes in a launch lock. After those reviews, allow exactly **one**
read-only STS identity request in the launch precheck. At execution, reserve
exactly **one more** read-only STS identity request from the exported
credential snapshot before the first Converse dispatch: two STS identity
requests total, one SDK attempt each, both pinned to the reviewed STS
endpoint. These are separate from the six-call Converse inference ceiling.
A failed or stale precheck ends the trial; never refresh the plan around a
failure or retry a provider call.

The frozen execution reserves **one original five-slot job** and six possible
provider-call slots durably before dispatch. Start the **240-second execute
clock before capture creation, credential export, and execute-time STS**. Use
no more than six Converse calls, one SDK attempt per call, 3-second
connect timeout and 200-second read timeout. There is exactly one author pass
and no retry, repair, fallback, top-up, alternate batch, or resume. Reserve
each call durably before sending it. Capture original-slot identities,
stage-level rejection reasons, bounded usage/timing, code proof and sanitized
learner fields without credentials or unbounded provider exception text. A
partial or interrupted capture keeps all unfilled slots in the denominator.
The capture's official `execute_elapsed_seconds` is measured from that same
origin through completion; if it exceeds 240 seconds, all returned slots are
late and uncredited. Compare the unrounded monotonic duration with 240;
rounding is only for the displayed metric. The prior provider job took about 128 seconds, so 240
seconds is a reasonable precommitted ceiling; it must not be extended after
seeing output.

## Prespecified result gate

Official success requires **5/5 of original slots 0–4 returned**, with the
three numerical rows carrying local quantitative policy revision 8 and the
two closed agreement rows carrying the newly reviewed policy revision 10.
The solver and teaching reviewer must still accept the immutable key,
validity, support, and issue flags. For a revalidated closed agreement row,
only model difficulty 2 or 3 is admissible under the proposed policy; 1, 4,
5, missing or malformed ratings must veto. The returned rows must satisfy the
exact 3:2 assignment, call and time limits, independently solved keys, six
distinct choice pairs per item, accurate shuffle-safe explanations and
per-choice feedback, objective fit, and zero unresolved content uncertainty.
No diagnostic or pre-review candidate can fill a rejected original slot.

After committing the capture SHA before reading answers, create a separate
reviewer-only worksheet with opaque IDs, random item and display-choice order,
and explicit unavailable placeholders for all unfilled original slots. Keep
the private key/slot map, source proof, model ratings, rejection reasons and
authored explanations outside that reviewer directory. Two independent
reviewers answer every item and judge all six pairs, self-containment,
level-2 difficulty, objective fit and within-batch novelty. Both review files
and their hashes must be locked before unblinding. Then inspect original
authored teaching and every feedback entry for unsupported claims and
display-position references, recompile all learner fields from the captured
tasks, and join the private map. A separate post-hoc worksheet of pre-review
candidates may diagnose failures, but cannot change the official 5/5 count.

`offline-replay.json` is a clearly labeled regression diagnostic: the three
retained provider responses from the prior capture (SHA-256
`2bcb9b577d165b508debe70cf6d42b2cf749f006c03922650b9d154eab8ca251`)
were replayed through this source with sockets blocked. The prior official
result stays **3/5 FAIL**; the new verifier returned all five in the replay,
with policy revisions 8, 8, 8, 10, 10 and **zero fresh AWS calls**. This confirms
the targeted source regression only. It has no credit toward the fresh trial
gate, independent content review, or reliability claim.

One passing batch would establish only this bounded qualification sample, not
deterministic population reliability or deployment authorization.
