# Adaptive thinking passed the frozen label criteria, with higher latency

All four adaptive-thinking calls completed normally with strict native JSON/schema,
fixed slot/index coverage and exact trusted-text decoding. All eighty correctness
labels and 120 pair labels matched the frozen gold. All ten valid items remained
eligible, and all ten defective items were rejected for the expected reason.
The prospectively defined formal qualification therefore passed on these twenty
reused controls. This does not establish broad accuracy or deterministic semantics.

| Frozen measure | Result |
| --- | ---: |
| Structurally valid completed calls | 4/4 |
| Valid items retained | 10/10 |
| Defective items rejected for expected reason | 10/10 |
| Correctness labels | 80/80 |
| Pair labels | 120/120 |
| All-gold items | 20/20 |
| Choice reasons before judgments | 80/80 |
| Pair reasons before relations | 120/120 |
| Uncertain choice/pair labels | 0 / 0 |

No output was truncated, retried, repaired or replaced. The actual production
runtime consumed exactly four `ProviderCallBudget` slots. All four responses
included a reasoning-content block; only its presence was counted, and no reasoning
text or signatures were retained. Final JSON reasons are retained for assessment.

## Final reasons are not perfectly faithful

Manual review of all eighty choice reasons and 120 pair reasons found no
wrong-pair reference or reason that contradicted its typed verdict in this sample.
It did find three inaccurate explanatory embellishments:

- `meters_to_kilometers`, choice `1500 km`: the decisive comparison
  `1,500 km = 1,500,000 m` is correct, but “Multiplied instead of divided” does not
  accurately describe retaining the original 1500 numeric value while changing
  its unit. The choice is correctly refuted despite this attribution.
- `club_age_boundary`, pair `age < 18` versus `age <= 18`: the reason correctly
  identifies boundary inclusion but additionally says their directions differ.
  Both comparisons point toward lower ages; only inclusion of 18 differs.
- `membrane_water_direction`, pair `Only salt moves from A to B.` versus
  `Net water flows from A to B.`: the reason correctly distinguishes the moving
  substance but also says their directions differ. Both proposed directions are
  A to B. The pair is correctly distinct despite that extra claim.

These notes do not alter the predeclared label criteria or erase the earlier
failed trials. They prevent an unwarranted claim that every word of model reasoning
is reliable. Solver reasons remain private evidence, not certified learner feedback.

## Latency and token cost

| Call | Input tokens | Output tokens | Elapsed seconds | Full-gold items |
| --- | ---: | ---: | ---: | ---: |
| 0 | 4,217 | 3,223 | 49.392 | 5/5 |
| 1 | 4,229 | 3,187 | 30.715 | 5/5 |
| 2 | 4,237 | 4,095 | 42.834 | 5/5 |
| 3 | 4,158 | 2,732 | 23.680 | 5/5 |
| Total | 16,841 | 13,237 | 146.621 | 20/20 |

The earlier disabled-thinking endpoint trial used the same 16,841 input tokens,
7,219 output tokens and 72.782 summed seconds. This run used 6,018 more output
tokens (1.834×) and 2.015× the summed call time. Average adaptive call time was
36.655 seconds, with a maximum of 49.392 seconds, versus a disabled maximum of
20.194 seconds. Total reported tokens rose from 24,060 to 30,078. There were no
cache tokens. No dollar-price assumption or unsupported reasoning/final token
breakdown is included; provider output usage may combine both.

This is a descriptive comparison with a prior run, not a concurrent paired causal
experiment. The current runtime's adaptive/high mode also removes temperature and
raises the shared reasoning-plus-final cap from 6,000 to 16,000 tokens. Prompt,
exact input, gold, native schema and model were unchanged. No production default
was toggled. Four isolated solver calls do not prove that the full author's and
reviewer's work will fit the worker's 240-second limit. That requires an end-to-end
run using the real remaining-time and shrinking socket-timeout behavior.

## Verification and immutable evidence

Requests were constructed through the actual `_generate_with_bedrock` route before
freezing. Offline checks established that a fifth call is rejected before the
client and that the production SDK client has exactly one attempt, three-second
connect timeout and 75-second read timeout. Strict JSON/native adapter, current
slot decoder and archived/current veto scoring agree. A separate no-network replay
rechecks the complete capture. No labels, criteria or requests changed after output.

Frozen plan SHA256:
`bb44d41a7f5414b741343c0f3de3f1e80c437062c7c9b83b26684e73297de946`.
Final capture SHA256:
`52b04a1adb4aabee1d5958a3a09558af151b50bf6e3e0e283351d4ba2389b3d4`.
Full data: [adaptive-plan.json](adaptive-plan.json),
[adaptive-capture.json](adaptive-capture.json), and
[adaptive-summary.json](adaptive-summary.json).
All earlier failed captures and reviewed gold remain unchanged.

Recompute summary without provider calls:

```sh
python docs/evidence/choice-quality-release-20260922/summarize_adaptive.py
```
