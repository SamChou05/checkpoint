# Neither verifier model solved the selected defects

Both Sonnet 4.6 and Opus 4.6 accepted the two nonunique questions and retained the
four valid keys. Both repeated the false paint-ratio explanation. The candidate
therefore fails the prospectively frozen all-six content criterion. No production
allowlist, model selection, prompt or stored questions changed.

All four calls completed end_turn with native schema, exact index, choice-feedback
coverage and local bounds valid. Their 8.527–12.741-second durations fit the existing
75-second limit. Opus native inference is feasible for these three-item requests,
but structural success and short measured latency do not establish semantic
improvement or full worker yield.

| Observation | Sonnet 4.6 | Opus 4.6 |
| --- | ---: | ---: |
| Planned / completed calls | 2/2 | 2/2 |
| Correct rejection of nonunique items | 0/2 | 0/2 |
| Positive reviews of valid controls, exact keys | 4/4 | 4/4 |
| Valid controls also meeting separate difficulty 2 floor | 3/4 | 3/4 |
| Full content passes under frozen uncertainty-fails rule | 1/6 | 2/6 |
| Sum of provider seconds | 18.425 | 22.580 |
| Longest call, seconds | 9.898 | 12.741 |
| Reported input/output tokens | 5,170/1,443 | 5,170/1,323 |

Both reviewers explicitly acknowledge that 26 rides makes the bus pass cheaper,
then reject it as a choice because 25 is the minimum. The unchanged stem does not
ask for the minimum. This is observable substitution of a familiar intended task
for the literal question, even while the system prompt forbids silent repair.
It is not an index problem or an arithmetic failure.

Both reviewers impose a uniquely correct semicolon-before-however pattern and
reject the alternative where however attaches to the end of the first clause,
before the semicolon. That alternative is defensible under the independently
sourced gold rubric. A conventional classroom example was treated as an exclusive
grammar rule. The exact control, primary-source support and interpretation limits
remain in `independent-gold-review.json`; no label changed after generation.

For paint, both retain 10 liters correctly but claim 9 liters with 15 liters blue implies
3:3 or 1:1. The actual ratio is 5:3. This copies a concrete false statement already
present in the historical solver evidence. For population growth, both retain 15%
but deny that 13% is derivable from the given figures. Dividing the increase by the
final population gives 12,000/92,000≈13.043%, which rounds to 13%. The main correct
percentage calculation does not excuse false teaching about a distractor.

Both now give an approximately 69,000 denominator for 17.4%. That numerical
counterexample is possible (12,000/69,000≈17.391%), but only Opus marks it as a
possible mistaken base. Sonnet presents it as the cause despite no such base in
the task. This distinction is preserved for independent feedback adjudication,
not treated as complete correctness of the population item.

Both rate the valid 30 mpg calculation difficulty 1. The frozen protocol separates
factual validation from a later difficulty floor, so this is a correct positive
key decision with a hypothetical inventory exclusion at minimum 2. The experiment
ran no actual generation or learner-inventory admission path.

Independent output adjudication in `independent-output-audit.json` inspected all
twelve reviews and sixty main/choice explanations. Sonnet had one full pass, four
failures and one uncertainty counted as failure; Opus had two full passes and four
failures. Sonnet's additional uncertainty is weighted-grade feedback proposing
swapping the weights as a possible cause of 79.2, although swapping 30/70 gives 81.6.
The Opus weighted explanation avoids that claim. This narrow wording difference
does not meet either arm's all-six qualification criterion. The raw capture
remains immutable with its original pending-audit status. `summary.json` is a
mechanical summary and does not overwrite gold or infer teaching truth from keys.

The frozen plan hash is
`97e0c4882d6706d0f9725b61921ed727d5df5cc5557eb37b2714e181b11da28d`;
the completed capture hash is
`7885bcfc1d09ea40dccbde4ccdb1ffe17c0305b3706b26407aae34284e71e93c`.
Counterbalanced order was Sonnet→Opus for batch 0, Opus→Sonnet for batch 1. The paired
requests differ only modelId. Both disabled thinking, temperature 0.2 and 6,000-token
caps remained fixed. Total observed usage was 10,340 input and 2,766 output tokens;
all four usage records were returned. No reasoningContent blocks, unknown-usage
calls, retry, warm-up, repair or replacement occurred. No dollar estimate is made.

The current production allowlist rejects Opus 4.6. The evaluator used an exact
runtime-built Sonnet request clone with only modelId changed, supported by the
AWS-documented Opus capability. That limited provider experiment neither changes
nor bypasses a deployed production gate. Its successful native calls close a
feasibility question, not the semantic qualification gap.

Nine no-network runner tests passed. A separate zero-network replay rebuilt the
exact plan and all request objects, replayed four final responses through the
actual native adapter and local checks, and reproduced every assessment. SDK 1,
connect 3/read 75, strict coverage and all original source/gold bindings were
verified. Ruff and diff checks passed. These six reused diagnostics do not measure
general model accuracy, arbitrary topic diversity, empirical question difficulty,
full pipeline throughput or a latency distribution. The prior adaptive failures
and reviewer-data-omission failures remain unchanged.
