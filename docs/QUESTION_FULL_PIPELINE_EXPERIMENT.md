# Fresh full-pipeline generation smoke experiment

This run does **not** qualify a production configuration. It stopped on a provider timeout after attempting two of six planned goals. All four returned questions have supported keys and feedback in independent review, but two appear below the requested challenge. The earlier known-invalid controls remain unresolved; this fresh sample does not replace them.

## Method and scope

The experiment requested five questions at minimum difficulty 3 for each of six synthetic goals: Python, music, Spanish, sourdough, photography, and a fictional tabletop game. Python supplied exact source code; the fictional game supplied rules. The other goals supplied a title and focus areas. The author, stem-only solver, final reviewer, sanitizer, and bounded generation orchestration were real application code. Bedrock calls were real. No skill-map inference, learner simulation, deployed queue, app blocking, or deployment was exercised.

Settings were Opus 4.6 (`us.anthropic.claude-opus-4-6-v1`), adaptive thinking at high effort, 16,000 output tokens, a 100-second read timeout, and at most six provider calls for one job per goal. The predeclared experiment cap was 36 calls, with the entire run stopping on the first provider failure. It was not resumed. Launch revision was `6127166`; the unchanged runner was subsequently committed as `3d5d96e`. Exact prompts, requests, final response text, metrics, and blind exports are in the [capture](evidence/full-pipeline-smoke-20260906.json). Reasoning text and credentials were not recorded.

Independent assistant reviewers froze their choices and difficulty estimates from stems, choices, goal descriptions, and supplied sources before opening author keys or model verdicts. Python answers were checked by executing the supplied code and exact inputs. Music selections were checked against primary educational references. These are assistant assessments, not a human expert panel or measured learner difficulty. The [adjudication record](evidence/full-pipeline-smoke-adjudication-20260906.json) preserves the original blind records separately from later key and feedback checks.

## Observations

| Goal | Parsed author candidates | Returned questions | Calls | Elapsed | Outcome |
| --- | ---: | ---: | ---: | ---: | --- |
| Python control flow and strings | 5 | 3 / 5 requested | 4 | 235.113 s | Partial; one JSON repair consumed a call |
| Music harmony and transposition | 5 | 1 / 5 requested | 4 | 258.555 s | Partial; top-up author call timed out |
| Spanish, sourdough, photography, fictional game | — | — | 0 | — | Not attempted after stop |

The run made eight calls: seven returned normally, and one raised `ReadTimeoutError` at 100.005 seconds. The seven returned responses reported 11,131 input tokens and 27,357 output tokens; usage for the timed-out request is unknown. All seven reported a reasoning content block and `end_turn`. The largest completed response used 7,325 output tokens, so none of the completed failures was caused by exhausting the 16,000-token allowance.

All ten parsed author keys matched the independently selected answers. This denominator excludes the first malformed Python response and the music timeout. It is not a general correctness rate. One Python candidate represented a distractor using unquoted trailing spaces; boundary trimming collapsed it with the correct choice, and the sanitizer rejected it. The four returned keys and their returned explanations and choice feedback were supported in review.

Difficulty remains inconsistent. Blind estimates put seven of ten parsed candidates below level 3. Of the three estimated at level 3, one was the unusable whitespace-choice item. The model reviewer rejected five candidates for difficulty, but retained a direct string-splitting question and a direct predominant-chord application that independent review rated 2. Two of four returned questions therefore met the requested floor in the blind assessment. This small, subjective sample does not demonstrate calibrated progression.

Raw author explanations had one clear error and one statement needing a pitch-class-versus-octave qualification, both in music. The reviewer generated five false claims in distractor feedback across three discarded music items. For example, it said no consistent transposition could turn G major into F major, although moving each pitch down a major second does so. That transposition is wrong for the question's instrument, but it is not impossible. The [interval reference](https://odp.library.tamu.edu/stepstomusictheory/chapter/more-intervals/) and independent semitone arithmetic support this distinction.

Those reviewer-feedback errors did not reach returned inventory because the items failed the difficulty check. A correct selected answer alone is insufficient evidence that newly generated teaching feedback is accurate; the adjudication record preserves the exact errors and reference checks.

## Concrete failures and implications

The first Python author response was genuinely invalid JSON: it used an expression shaped like `"choices":"...".split("|")` instead of an array literal. It stopped normally after 6,678 output tokens. An outer-fence cleanup would not fix this, and splitting on the delimiter would damage answer strings that themselves contain `|`. The subsequent model repair took another 97.968 seconds. Silently executing or heuristically rewriting the invalid response would not be an acceptable repair.

Provider-enforced JSON is a grounded next experiment for this formatting failure. AWS documents JSON Schema output through Converse for Opus 4.6; this environment's boto3/botocore 1.43.89 recognizes the `outputConfig` field. Such a schema can constrain arrays and field types, while the existing validators must still enforce choice counts, lengths, answer membership, and educational correctness. AWS's supported schema subset omits several of those constraints, and schema compilation may add first-request latency. This capability has **not** been enabled or live-qualified here. See [AWS structured outputs](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html) and [Claude model support](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-structured-outputs.html).

The timeout, difficulty drift, and generated feedback errors are separate problems. Increasing the token allowance cannot be credited with fixing any of them based on this run. Likewise, switching to maximum reasoning did not repair the earlier bad controls, as recorded in the [evidence experiment](QUESTION_EVIDENCE_EXPERIMENT.md).

Before promotion, test any structural-output change as a bounded format/latency experiment, then qualify fresh questions and preserved bad/valid controls separately. Count correct keys, complete premises, defensible distractors, accurate returned feedback, requested challenge, and usable inventory per job. The four unattempted subjects still need evaluation; adaptive learning and app-blocking behavior also remain outside this experiment.
