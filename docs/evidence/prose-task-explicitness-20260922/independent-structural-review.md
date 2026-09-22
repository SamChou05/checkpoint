# Independent structural review

**The four-call comparison passes its structural checks.** The actual frozen runtime replays all four captured responses with exact requests, raw rows, complete local assessments, reservations and statuses. Socket connections were blocked; no provider, credential, repair, solver or reviewer call was made. All 34 source/artifact pins match, including the clean source checkout at `0e4619f1696b848073f1a4d551c364ed3fbfbeb0`.

The order is baseline/candidate/candidate/baseline. Requests repeat exactly within each arm. The candidate request differs only by two newline characters and the exact approved addition appended to the final native system prompt. The user input, native schema, model, inference settings and all other fields are identical. Every captured request matches its frozen request and digest.

| Call | Arm | Native rows | Seconds | Input / output tokens |
|---|---|---:|---:|---:|
| 0 | Baseline | 5 | 16.251067 | 2,858 / 1,006 |
| 1 | Candidate | 5 | 6.905741 | 3,143 / 688 |
| 2 | Candidate | 5 | 8.591779 | 3,143 / 692 |
| 3 | Baseline | 5 | 10.942648 | 2,858 / 977 |

All calls ended with `end_turn`, within the actual 100-second read/elapsed bound. Transport records one SDK attempt and a three-second connection timeout. All use Kimi K2.5 with disabled thinking, 6,000 output tokens and temperature 0.2. The native contract is `question_author_constructed_v1`. Wire-schema validation and the actual native adapter pass for all four responses and all 20 prose rows. There are four matching one-call reservations, no failures, extras, missing rows or unattempted slots. **The fixed denominator remains 20: ten per arm.**

The actual diagnostic sanitizer retains all 20 rows. No prompt or main explanation changes; four choice lists change order while preserving their exact key mapping. That normalization is recorded as a diagnostic and earns no semantic or repair credit. Every original row satisfies the runtime lengths and the separate 320-character author-main instruction: prompts span 133–203 characters, mains 163–305, and choices 2–132. Original raw rows and their recorded hashes remain unchanged.

The saved blinded worksheet and mapping exactly equal a fresh projection from the unchanged capture: 20 unique opaque IDs, all 20 requested slots, exact raw stems, and exact choice rotations. Keys, explanations, arm and call grouping are absent from the worksheet. An independent mutation of only keys and teaching leaves its visible items, IDs and rotations unchanged. The projection's `capture_sha256` is its **canonical JSON digest**, not the file-byte hash; both are separately bound in the detailed review.

Usage totals **12,002 input and 3,363 output tokens**, with no missing usage or native reasoning blocks. Baseline totals are 5,716/1,983 tokens over 27.193715 seconds; candidate totals are 6,286/1,380 over 15.497520 seconds. Overall recorded provider time is 42.691235 seconds. These are descriptive observations from different generated items and two calls per arm, not a causal latency or accuracy estimate.

Replay used Python 3.12.11 and the pinned `author_probe.run_calls`, replacing only the SDK factory with exact recorded responses while blocking sockets. Its real `check_plan` ran 27 times. All four actual requests, reservations, raw rows, assessments and final status/summary fields match. Replay clocks are intentionally not equated to original call timings. Separate checks used the wire JSON schema, actual native adapter, actual immutable-preserving sanitizer and saved worksheet generator.

Bindings:

- Frozen plan file SHA256: `17711d5ee7cbab20584187d277be9038b5dd40ff1cb1a2d3bb0dd165b41fdb3c`.
- Frozen capture file SHA256: `332fb1c24d08b32710a2c5ee230991827b876c5e8145104b548e9580c4774bef`.
- Blinded worksheet SHA256: `dba0ac4c80dbb6aac54a330f1c099a023f46251615f746f392a7534495ca444d`.
- Unblind mapping SHA256: `699f46eb0fe40d55b96b9c43af603c41cc56ac717169244502b3dcd0a95610cf`.
- Canonical capture digest used by the projection: `be69731e5a210dc0c3dd6d20808fe4043349094e5037f0a0a8c5ec9014acf3ca`.

This review gives **no semantic or prompt-promotion qualification**. Literal task adequacy, unique correct answers, all six pair meanings, teaching, variety, excluded-example copying and difficulty remain the separate reviewers' responsibility against their locked blind judgments. Author-only structure and length success do not establish full-worker or deployed reliability. Frozen source, plan, capture and projections were not changed.
