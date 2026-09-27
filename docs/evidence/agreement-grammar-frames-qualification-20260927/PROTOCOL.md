# Strengthened agreement frames: one-shot full-worker qualification

This is a **new, unlaunched trial** of source commit
`db3e10e4098f5fdad13ceb73616603417ef6fde1`. The previous calibration
trial returned 5/5 original slots but **failed content qualification**: both
blind reviewers rated its compound-agreement slot level 1 against a minimum
of 2. This trial has its own source, plan, capture and blind reviews. No prior
output counts toward its result.

The [request](request.json) is byte-independent but value-identical to the
historical normalized five-slot request (canonical SHA-256
`212cea7d53ddefe17fbe8f2459705b46b871793e62e0e58b56cc11e3626e63ae`):
three exact arithmetic slots followed by two standard-written-English slots,
with the same goal, assignment, level floor, empty history and source fields,
models and settings. The opt-in agreement route is enabled only in this
isolated worker execution. Source `db3e10e` changes the closed compound
agreement frames, the native author schema/prompt and dormant bank-history
selection; it does not change the trial request. The author schema is 2,757
bytes, SHA-256
`2a11817d040fe0fb34a413604b9b8ee3118fb631944c2bbf038c54076a95156d`.
The initial system prompt SHA-256 is
`016e595b20d7b2b1a6c8b94880ea4f3800de9105a740b35263a1521f380bed5a`,
the user prompt SHA-256 is
`358316024851b745bc5ecb525f562ce52d33d3e330f0fba7c353d4b4ba646c6d`,
and the exact initial author wire SHA-256 is
`44a7f9e7235fea136d41ca6fc94103e1d0079ff3a4099be3f53878cb0f94924c`.
Validate the source-generated schema with JSON Schema Draft 2020-12 and the
outgoing Converse request with the local botocore service model before any
AWS operation. Those local checks do not count as live qualification.

Freeze a new immutable plan with the full source commit and SHA-256 of every
relevant runtime file, fixture, protocol, test and harness. Root and an
independent reviewer must approve the **same** frozen plan and harness hashes
before any AWS precheck. The launch lock must name those hashes and the source
commit. Source, plan, schema, prompts, wire, model transport and credential
identity are rechecked before dispatch; any mismatch ends the attempt.

The reviewed launch allows exactly one read-only STS identity request in the
precheck and one at execute time, each with one SDK attempt and the fixed STS
endpoint. A failed freshness precheck ends the attempt without repair or
refreeze. The 240-second monotonic execute clock starts **before capture
creation, credential export and execute-time STS**. Compare the raw duration
to 240 seconds; rounding is for display only. If setup consumes the budget,
make no late STS or Converse request, and credit no late returned slot.

Reserve one original five-slot job and six possible Converse call slots
durably before dispatch, matching the historical reservation ceiling. A
successful one-pass path must make **exactly three actual Converse calls** in
order: mapped author, answer-blind solver for the two agreement rows, and
authored-teaching reviewer. The author runs once. There is no retry, fallback,
repair, top-up, alternate batch, second job or resume. If the source makes a
fourth call, preserve it in the bounded capture and mark protocol failure;
never reinterpret that call as a new attempt. Six is a safety ceiling, not a
success target. Persist bounded/redacted provider responses, usage, stage
rejections, original-slot identities and proof provenance; never persist
credentials or unbounded provider exception text.

**Official success requires all five original slots 0–4 returned** within the
execute deadline, policies 8/8/8/10/10, exact requested 3:2 allocation,
three-call stage order, and two fresh independent blind reviewers finding a
single correct key, all six within-item choice pairs meaningfully distinct,
self-contained stems and **difficulty at least 2 in every item**. After both
review files and hashes lock, independently re-solve keys, recompile all five
learner fields per item, check exact target-objective fit and audit every main
explanation and per-choice feedback entry for factual support and shuffle
safety. Any unresolved content uncertainty fails the gate. Unfilled original
slots remain explicit placeholders; pre-review or diagnostic candidates
cannot replace them. Report cross-item and bank novelty separately. The
request has empty bank history, so a fresh five-slot pass does not exercise
history-driven scene selection or prove future bank diversity.

Make the official reviewer worksheet in a separate reviewer-only directory
with opaque IDs and randomized item/choice order. Do not place capture,
private map, keys, source slots, model ratings or teaching in that directory.
Keep those hidden until both blind reviews lock. One passing batch would show
only this bounded sample, not deterministic population reliability or
authorization to deploy the opt-in route.
