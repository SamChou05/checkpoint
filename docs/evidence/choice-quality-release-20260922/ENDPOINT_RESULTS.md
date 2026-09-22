# Trusted endpoints: all item decisions correct, strict pair-label criterion failed

All four calls completed with valid native JSON/schema, exact slot/index coverage
and strict local decoding. All eighty correctness labels matched gold. All ten
valid items were retained and all ten defective items rejected for the expected
reason. However, four of 120 pair labels were false equivalences, so the candidate
failed the unchanged prospectively frozen full-label qualification criterion.
These errors are preserved even though they did not alter final eligibility in
this sample. No retries, repairs, replacements or relabeling occurred.

| Frozen measure | Observed | Required |
| --- | ---: | ---: |
| Contract-valid completed calls | 4/4 | 4/4 |
| Valid items retained | 10/10 | 10/10 |
| Defective items rejected for expected reason | 10/10 | 10/10 |
| Choice correctness labels | 80/80 | 80/80 |
| Pair relation labels | 116/120 | 120/120 |
| All-gold items | 17/20 | 20/20 |
| Actual reason-before-judgment choice rows | 80/80 | 80/80 |
| Actual reason-before-relation pair rows | 120/120 | 120/120 |
| Uncertain choice/pair labels | 0 / 0 | 0 / 0 |

## Remaining pair-reference errors

All four incorrect pair labels occurred inside already defective questions that
also had a correctly detected true duplicate:

- `tank_irrelevant_color`: both 80 L versus 40 L pairs were falsely called
  equivalent. Their reasons described two 80 L options and ignored the actual
  40 L endpoint. The real red/blue 80 L duplicate was also detected.
- `jacket_discount_duplicate`: $60 versus $20 was falsely called equivalent.
  Its reason discussed the actual duplicate $20 and “20 dollars” instead.
- `meeting_time_duplicate`: 9:45 a.m. versus 09:35 was falsely called equivalent.
  Its reason discussed the actual duplicate 09:35 and 9:35 a.m. instead. That
  true duplicate was now labeled equivalent, unlike the preceding trial.

The decoder binds pair fields to trusted input, so it correctly reports these as
wrong pair labels rather than reassigning them according to the prose. Explicit
input endpoints did not eliminate the model's tendency to apply a reason about
one pair to another pair. There were no failed valid-item retention or defective-
item rejection decisions in this run, but the pair-reference problem remains.

This trial jointly changed trusted endpoint input and the requested-meaning rule.
It cannot identify which change affected any particular outcome. The fixed v3
schema was byte-identical to the preceding slot trial. Both prior failures remain
unchanged, and repeated use of these diagnostic controls does not create fresh
held-out evidence or establish deterministic semantics.

## Usage, checks, and provenance

| Call | Input tokens | Output tokens | Elapsed seconds | All-gold items |
| --- | ---: | ---: | ---: | ---: |
| 0 | 4,217 | 1,790 | 16.923 | 4/5 |
| 1 | 4,229 | 1,728 | 18.165 | 5/5 |
| 2 | 4,237 | 2,004 | 20.194 | 3/5 |
| 3 | 4,158 | 1,697 | 17.500 | 5/5 |
| Total | 16,841 | 7,219 | 72.782 | 17/20 |

No cache tokens, truncation or abnormal completion were reported. Times sum
individual client calls, not application latency. No dollar-price estimate is
assumed. Settings stayed Sonnet 4.6, temperature 0.2, thinking disabled, 6,000
output tokens, 75-second read timeout and one SDK attempt.

Twenty pair/slot tests passed, including trusted endpoint consistency, ignored
caller-supplied pair metadata, exact Unicode/spacing preservation, every option
permutation and authored key, strict slot/index/type/length handling, and unchanged
legacy prompt behavior. Synthetic gold passed strict schema/adapter/current decoder
and both current/archived veto validation before any model call.

Frozen plan SHA256:
`83e2864a79cc3d4f346a6afdc3fada56c14a85306bf7d334227c73e70d14f11b`.
Final capture SHA256:
`bbeb1d8bf3dcd04b2a42f9fa075062216b4504d933d4e8f0ab6eb691b1873e88`.
The exact requests/source hashes are in [endpoint-plan.json](endpoint-plan.json),
raw outputs in [endpoint-capture.json](endpoint-capture.json), and all counts plus
expanded failed rows in [endpoint-summary.json](endpoint-summary.json).

Recompute without provider calls:

```sh
python docs/evidence/choice-quality-release-20260922/summarize_endpoints.py
```
