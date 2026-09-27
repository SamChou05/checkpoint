# One-shot pairwise diversity diagnostic

The frozen [request](request.json) sent only the prompts and four visible choices from verified source ordinals 1–6 in the [source capture](../generic-reserve-seven-probe-v4-20260927/capture.json). It supplied no answer keys, explanations, reviewer judgments, or private source maps. Sonnet 4.6 received one native JSON Schema request requiring a boolean for each of the 15 pairs. A flag means both the central learner decision or operation and the answer format materially repeat.

The sole Converse dispatch completed under AWS account `239342516379`. It marked **p35 = true** and the other 14 pairs **false**. Source ordinal 3 asks for expected net gain from a two-outcome game, and ordinal 5 asks for expected winnings from a two-outcome lottery; both require an expected dollar amount. This is the specific material repeat identified in the earlier blind reviews, which were inspected only after this capture was locked. The result supports this pairwise diagnostic on this six-question case; it does not establish broader recall or false-positive rates.

| Frozen or captured artifact | SHA-256 |
| --- | --- |
| Source capture | `da76d3c3a1dcfb9faebbc4da9345f2b73188c121ca46e2697233d29f948b0e8f` |
| Probe harness | `fb8f7e77f5d64706761b0bcccaee0e753e210dfe83df52097e22899ef0cb4572` |
| Exact request | `cceca442cfaee580e3b7fe1606e78476f30a58b6f428e209311dda55fa9b3b24` |
| Frozen plan | `a5fbfa6e57a1891da4638f5e047794491f618572714627b9abc88b96e7f36333` |
| Locked capture | `e6268ed51707f83c3f2b90e4ee812365081f1264f7240e183408514312b54bfc` |

The independent offline payload check confirmed exactly six source-derived question objects with only `id`, `prompt`, and `choices`; four choices each; all 15 required boolean schema fields; and no `correctChoice` or `explanation` in the request. The AWS CLI native Converse input shape precheck also passed before dispatch. The capture records one reserved and one dispatched Converse attempt, an `end_turn` stop, 1,185 input tokens, 79 output tokens, 2.69819 seconds for Converse, and 2.699044 seconds for the whole execute step. The capture retains only visible JSON booleans and bounded usage; no hidden reasoning or credentials were saved.
