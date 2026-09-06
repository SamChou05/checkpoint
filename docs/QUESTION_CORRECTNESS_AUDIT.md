# Question correctness audit — September 5, 2026

## Release status

The repository has stronger validation and better diagnostics, but the correctness issue is **not fully resolved**. No backend deployment or production model promotion was performed during this audit. Model agreement remains insufficient evidence of correctness. Existing app-blocking and break rules were not changed.

September 6 follow-up: [the independent solver's declared outcome is now enforced in code](QUESTION_SOLVER_OUTCOME_GATE.md). A live four-case diagnostic retained both valid keys but still accepted both known invalid questions because the solver incorrectly declared them `resolved`. This closes a control-flow gap without qualifying the system for release. The historical measurements below remain unchanged.

A further [resolved-limitations veto](QUESTION_SOLVER_LIMITATIONS_GATE.md) prevents reviewers from waiving explicitly reported obstacles. The latest recorded invalid cases still have empty limitations and are unaffected. Offline replay also demonstrates a conservative loss for harmless scope notes; no new live accuracy improvement is claimed.

A subsequent [source-first authoring comparison](QUESTION_SOURCE_AUTHORING_EXPERIMENT.md) generated twelve candidates across plant propagation and accessible forms. Giving sources to the author had mixed content results and still allowed unsupported explanations and missing conditions. Neither arm produced a candidate with both complete supported reviewed content and independently assessed difficulty at least 3. This small feasibility experiment does not qualify a release or establish production accuracy.

Further work added an unintegrated [Boolean rule-question constructor](QUESTION_RULE_CONSTRUCTION.md): it renders the complete premises and feedback from one formal object and exhaustively checks the key and counterexamples. This is one additional, bounded inference mechanism. It does not establish real-subject rule accuracy, useful difficulty, general question coverage or a production fix. A separate [web-grounding probe](QUESTION_WEB_GROUNDING_PROBE.md) demonstrated search access while leaving raw passages hidden and still producing an inaccurate explanation.

## What is holding the system back

1. **Confident substitution of a familiar problem.** Reviewers sometimes answer a standard textbook problem instead of the actual wording. One failing fixture asks to enumerate all matching pairs in linear time; the reviewer approves a method for finding whether a pair exists. Another assumes an image-editing order can recover detail without establishing whether the source data still contains that detail.
2. **Author and reviewer mistakes can agree.** More reasoning and a larger available model did not reliably eliminate these shared mistakes. Solving the stem without options helps, but does not guarantee independence of knowledge or assumptions.
3. **Difficulty labels overstate the work required.** Many authored level-3 items are independently rated level 2. Previously, another attempt received excluded stems but no explanation of the rejection, so it repeatedly produced similarly easy items.
4. **The call budget did not fit the new pipeline.** Authoring, independent solving, and final review take three calls. A five-call job could start a retry it could not finish checking. The proposed default is now six calls, with the existing deadline and daily quota still enforced.
5. **Malformed output is a separate problem.** Duplicate JSON keys can silently overwrite an answer; oversized feedback can discard a valid item. These need deterministic parsing and clear length constraints, rather than more model confidence.

## Live comparisons

These are small, deliberately difficult control sets, not estimates of production accuracy. The original set contains seven invalid questions and three valid controls. Each row reports one bounded run; repeated prompt experiments varied.

| Configuration | Original 10 controls | Additional 8 controls |
| --- | ---: | ---: |
| Previous reviewer prompt, Sonnet 4.6, ordinary 6,000-token budget | 6 passed | Not run |
| Previous reviewer prompt, Sonnet 4.6 adaptive/high, 16,000-token budget | 5 passed, including one timeout as failure | Not run |
| Previous reviewer prompt, Opus 4.6 adaptive/high, 16,000-token budget | 7 passed | Not run |
| Revised independent solver + final audit, Opus 4.6 adaptive/high | 8 passed | 8 passed |

The final 18-control run retained all seven valid controls and rejected nine of eleven invalid items. The two remaining false acceptances were `all_pairs_output_bound` and `raw_highlight_recovery_unsupported_sequence`. A subsequent generic counterexample/evidence prompt did not resolve them.

All ten baseline responses ended normally, using 277–1,256 output tokens. That directly argues against the 6,000-token output cap causing these particular correctness failures.

Kimi thinking was also tested with the documented sampling settings. A small fictional-rule generation probe still produced inconsistent answers and duplicate properties. DeepSeek V3.2 was tested on the two unresolved items plus a valid control: ordinary mode passed two of three, and thinking mode passed one of three. Neither established a reliable replacement. Newer GPT and Claude model invocations were denied by this AWS account despite appearing in its model catalog; this was not an expired sign-in.

A final one-job generation smoke test used Opus 4.6/high, five requested items, minimum difficulty 3, and the proposed six-call allowance. Music retained two of five questions after six calls (179 seconds). A fictional-rule goal had three approved questions, then lost them when a top-up failed (247 seconds). That discovered a separate partial-inventory bug, now covered by regression tests: ordinary provider failures preserve earlier verified questions, while durable quota failures still propagate. These runs did not pass the full-bank release criterion, and the final preservation fix was verified locally rather than claimed as another successful live run.

## Changes implemented

- Separate configurable ordinary and reasoning output budgets: 6,000 and 16,000 by default. Kimi and supported Claude reasoning settings are configurable; thinking defaults remain disabled pending a qualifying configuration.
- Reject responses stopped by the output-token limit, even when their text parses.
- Reject duplicate JSON properties instead of silently accepting the final key.
- Solve stems before revealing choices. Require explicit missing-assumption reporting and reject items whose solution needs extra factual premises.
- Audit the supported remainder with hidden author keys, explanations, and difficulty labels; preserve item indexes when filtering a mixed batch.
- Shorter author instructions and bounded teaching feedback; unchanged four-choice client contract.
- Retry feedback carries only this attempt's finite rejection counts. It asks for genuinely harder cognitive work when difficulty is too low, without lowering the learner's target. Feedback currently stays within one invocation, not across separate queue jobs.
- Six-call background-job default supports two complete passes when time permits. Do not spend calls on a pass that cannot complete verification.
- Preserve earlier verified inventory when an ordinary provider failure interrupts a top-up; still fail closed when no verified inventory exists.
- Evaluations retain model settings, prompt hashes, token use, stop reasons, rejection counts, and earlier inventory after a later failure. Invalid JSON or a timeout does not receive credit for detecting a bad question.

## Remaining work before release

A qualifying candidate must reject the unresolved controls, retain valid controls, and fill banks at the requested challenge level across fresh goals and repeated runs. The existing source path supplies selected source text, not independent web retrieval or execution of a solution. Grounded claim checks and deterministic calculation/execution, where applicable, are the next mechanisms to evaluate; they have not been implemented here. Increased model power alone has not passed this release bar.

The tests here exercise live provider calls and local orchestration, not deployed queue delivery or learning outcomes. Some live comparisons used a 100-second read timeout; the worker setting is 75 seconds. A successful local response is therefore not proof of production latency readiness.

Local verification passed 261 backend unit tests, Ruff, deployment-script checks, and SAM template linting.

## Research used

- [Moonshot Kimi K2.5 documentation](https://github.com/MoonshotAI/Kimi-K2.5): thinking-mode sampling settings.
- [AWS Kimi K2.5 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-moonshot-ai-kimi-k2-5.html): endpoint limits.
- [AWS Claude adaptive thinking](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-adaptive-thinking.html): supported reasoning request fields.
- [Anthropic prompting guidance](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices): clear tasks and explicit output requirements.
- [CRITIC](https://arxiv.org/abs/2305.11738): external tool feedback as a mechanism to evaluate, rather than relying only on another model judgment.
- [Large Language Models Cannot Self-Correct Reasoning Yet](https://proceedings.iclr.cc/paper_files/paper/2024/hash/8b4add8b0aa8749d80a34ca5d941c355-Abstract-Conference.html): limitations of unaided self-correction; this is not evidence about the exact models tested here.

Synthetic control fixtures are in `backend/bedrock-question-service/evals/fixtures/question_verification_cases.jsonl` and `question_verification_holdout.jsonl`. The latter covers arithmetic, SQL, sewing, irrigation, and newly supplied fictional rules, without subject-specific runtime branches.
