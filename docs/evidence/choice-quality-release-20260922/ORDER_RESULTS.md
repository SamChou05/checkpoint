# Choice ordering comparison: stopped after structural failure

The frozen eight-call trial stopped after its third call under the prospective
stop rule. The first paired batch was fully correct in both arms. The second
reason-first response added a seventh pair comparing `Hold the parcel.` with
itself; the archived production-candidate validator rejected the whole batch with
`CompleteSolutionFormatError: Expected all six choice pairs.` The remaining five
planned calls were not attempted. No retry, replacement, repair or gold change
occurred. This trial does **not** qualify the candidate or establish a semantic
benefit from ordering.

| Call | Batch | Arm | Strict JSON/native schema | Full local contract | Full gold |
| --- | --- | --- | --- | --- | --- |
| 0 | 0 | baseline | Pass | Pass | 5/5 |
| 1 | 0 | reason-first | Pass | Pass | 5/5 |
| 2 | 1 | reason-first | Pass | Fail: seven pairs including a self-pair | Not scored as admissible |
| 3–7 | 1–3 | mixed | Unattempted | Unattempted | Unattempted |

The native schema declares arrays without an exact length, so the seven-pair
response satisfies that schema while violating the application contract. The
strict local validator correctly rejects it. The pair schema was byte-identical
between the two arms. This single failure therefore does not show that reordering
choice fields caused the extra pair.

## Ordering and frozen denominators

Baseline emitted `choice → judgment → reason` for all 20 returned choice rows.
The reason-first arm emitted `choice → reason → judgment` for all 40 returned
choice rows, including the rejected batch. The field-order intervention was
achieved in the available outputs. Pair rows retained the baseline order
`leftChoice → reason → relation → rightChoice` in both arms.

Each arm's frozen denominator remains four calls, twenty items, ten valid items,
ten defective items, eighty choice judgments and 120 pair relations. Both arms
have only one admissible five-item batch: two valid retained, three defective
excluded for the expected reason, twenty correct choice labels and thirty correct
pair labels. Missing/rejected batches are not removed from planned denominators
or silently scored as passing. The available paired batch has no semantic
performance difference; the original three contradictory-label items were not
reached. All prospective qualification criteria remain unmet.

The automated [summary](order-summary.json) records observed order separately
from admissible semantic scoring. It includes the structurally rejected response's
20 ordered choice rows in the observed-order count, while excluding its items
from completed-contract and semantic-success counts. The raw capture is unchanged.

## Usage and provenance

| Arm | Attempted calls | Input tokens | Output tokens | Summed call seconds |
| --- | ---: | ---: | ---: | ---: |
| Baseline | 1/4 | 2,028 | 2,127 | 18.501 |
| Reason-first | 2/4 | 4,089 | 4,333 | 41.159 |
| Total | 3/8 | 6,117 | 6,460 | 59.660 |

All three responses ended normally without truncation. Model/settings were the
frozen Sonnet 4.6, temperature 0.2, thinking disabled, 6,000 output tokens,
75-second read timeout and one SDK attempt. No cache tokens were reported. Usage
is not a pricing estimate; summed individual call durations are not application
latency. Arm usage is not directly comparable because attempted-call counts differ.

The exact frozen plan SHA256 is
`4b5b4dccaaa44d0659de97ca1f744febf14a14adb209b5b53227a39474216342`.
The final capture SHA256 is
`041dfaee87f998cf04dfca9e9adcc2ae7508cfa1b5eeac71f9a2e96d9a1f629a`.
The earlier four-call qualification and twenty reviewed gold labels remain
unchanged. An independent agent checked all eight planned requests before dispatch:
prompts, cases, model/settings and pair schema were identical, with only the
choice-row property/required serialization order changed.

Recompute without provider calls:

```sh
python docs/evidence/choice-quality-release-20260922/summarize_order.py
```
