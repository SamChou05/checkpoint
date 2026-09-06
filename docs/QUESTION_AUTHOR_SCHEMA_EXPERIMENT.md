# Provider-enforced author JSON — September 6, 2026

Provider-enforced JSON produced bare schema-compliant responses, but this small experiment did **not** demonstrate a correctness improvement or a production-ready latency profile. Both ordinary responses were also usable by the existing parser. Five of twenty questions contained invalid displayed code despite having plausible intended answers. No model, output-schema setting, or deployed timeout was promoted.

## Controlled author-only comparison

Four real Bedrock calls requested the same five Python questions: two ordinary responses and two schema-constrained responses. They ran from clean revision `fb673b3`. Every Converse request was identical after removing `outputConfig`: same system and user prompts, source document, goal, difficulty, Opus 4.6 model, adaptive/high thinking, and 16,000-token allowance. No solver, reviewer, skill inference, learner simulation, or deployed worker ran. There were no repair calls or hidden SDK retries.

Both arms used a 300-second client read deadline to observe potential schema-compilation latency; this did not change the application's 100-second maximum or its deployed worker settings. Native schema support was checked with boto3/botocore 1.43.89. AWS documents the [Converse schema interface and limitations](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html). The provider did not expose grammar-cache state, so the first and repeated schema calls cannot be described as confirmed cold and warm measurements.

The [evidence archive](evidence/author-schema-feasibility-20260906.json) preserves the plan, exact requests, raw final text, settings, token usage, original blind records, later key/explanation checks, and independently reproduced syntax failures. Reasoning text and credentials are excluded. All twenty content hashes and the immutable blind-review hash were checked before joining keys. The reviewer selected answers and estimated difficulty without seeing arm labels, keys, explanations, or provider metrics; Python execution supplemented the assistant judgments.

| Observation | Ordinary | Schema-enforced |
| --- | ---: | ---: |
| Calls completed normally | 2 / 2 | 2 / 2 |
| Bare JSON responses | 0 / 2 | 2 / 2 |
| Responses accepted by runtime parser | 2 / 2 | 2 / 2 |
| Responses matching the declared schema | 2 / 2 | 2 / 2 |
| Supported keys for the literal displayed question | 8 / 10 | 7 / 10 |
| Invalid displayed code definitions | 2 | 3 |
| Blind difficulty at least 3, with usable presentation | 3 / 10 | 5 / 10 |
| Original sanitizer retention | 10 / 10 | 9 / 10 |
| First / second call elapsed | 85.990 / 121.582 s | 145.725 / 139.276 s |
| Reported input / output tokens | 3,490 / 15,396 | 4,398 / 18,160 |

The ordinary arm used outer Markdown fences, which the runtime already accepts. They are not credited as runtime-format failures. All four responses ended normally with returned reasoning blocks; none exhausted the 16,000-token allowance. Three calls exceeded 100 seconds. Total observed time was 492.573 seconds. Two samples per arm from one goal cannot establish stable accuracy, a causal latency estimate, or broad model quality.

## The answer can be right for code the learner was never shown

Five stems printed a definition shaped like:

```text
def words(text, explicit=False): if explicit: return text.split(' '); return text.split()
```

That is invalid Python. An `if` compound statement cannot occupy the function's same-line simple suite. The exact displayed fragment raises `SyntaxError`; the separately supplied multiline source parses. This was an author error, not transport whitespace corruption. See the [Python compound-statement grammar](https://docs.python.org/3/reference/compound_stmts.html).

All twenty intended calculations agreed with the author keys **only after conditionally substituting the valid source for those five broken definitions**. That substitution is explicitly excluded from the primary correctness score. Their explanations omit the necessary syntax qualification. The other fifteen explanations had no additional identified computational error. One clear prose/pseudocode description was retained as prose, with a presentation caveat; it was not judged as literal executable Python.

A schema can require an array of strings while allowing a string that contains invalid code. Source facts, syntax, literal output, unique answer adequacy, and explanation correctness remain separate validation requirements. Deliberately invalid code can also be valid quiz material when the answer correctly identifies the error; blanket rejection of any syntax error would be inappropriate.

## A separate deterministic filter defect

The original sanitizer rejected one supported schema-arm question because its two legitimate method calls, `.strip()` and `text.split()`, triggered a heuristic for empty checkbox options. The literal calculation returns `['a|b', 'c']`. The iOS variant also rejected equivalent calls with spaces inside parentheses. This is a false rejection, not an author correctness failure. Matched backend/iOS correction `df3c1db` now retains that exact captured question under its original request, with 337 backend and 59 iOS checks passing. The historical retention score above is unchanged.

A separate author-prompt change (`e62ce68`) now asks for meaningful line breaks and indentation, or consistent prose, with the answer matching the exact content shown. Its fresh-output qualification is pending. Schema enforcement alone does not address the observed code defects, the earlier bad controls, or the [isolated review experiment's feedback defects](QUESTION_ISOLATED_CANDIDATE_EXPERIMENT.md).
