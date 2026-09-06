# Checkpoint Question Generation Evals

This eval suite measures whether AI-generated checkpoint questions are usable, on-target, and safe to store before a prompt change ships.

The design follows the same shape recommended by current eval guidance:

- define the task success criteria
- use a representative dataset with normal, edge, and adversarial cases
- apply deterministic graders for objective requirements
- keep subjective item-quality review separate
- compare results across prompt/model variants
- grow the fixture set as production reports reveal new failure modes

## Files

- `fixtures/question_generation_cases.jsonl` - prompt-eval fixtures using the backend request contract.
- `checkpoint_question_eval.py` - CLI for capturing Bedrock outputs and scoring response JSONL.
- `../tests/test_prompt_eval.py` - unit tests for the scorer.
- `../tests/test_cross_domain_prompt_contract.py` - verifies that the same generic prompt and quality gate handle unrelated learning goals.

The default fixture set deliberately spans LSAT reasoning, MCAT science, Spanish language learning, modern world history, coding, mathematics, fitness, study skills, and a raw backyard-beekeeping goal. The beekeeping request omits derived fields such as `learningTarget`, `contentTopics`, and `questionDirective`; it proves that a plain goal plus optional focus areas and current level still reaches the generic topic-derivation flow. These are evaluation cases only—there are no corresponding subject branches or authored question banks in production.

## Score Captured Responses

Responses must be JSONL with a `case_id` matching the fixture and a `questions` array:

```jsonl
{"case_id":"lsat_logical_reasoning_medium","run":1,"questions":[{"prompt":"...","expectedAnswer":"...","choices":["...","...","...","..."],"explanation":"...","topic":"Logical Reasoning","difficulty":3,"format":"Multiple Choice"}]}
```

Run:

```bash
python3 evals/checkpoint_question_eval.py score \
  --responses evals/responses/current.jsonl \
  --output evals/reports/current.json \
  --markdown-output evals/reports/current.md
```

The command exits non-zero when any case fails. Add `--no-fail` when you want a report without failing a local script.

## Capture Real Bedrock Outputs

This command invokes the configured Bedrock backend prompt directly. It requires the same AWS/Bedrock environment the Lambda expects.

Install the local eval dependencies first:

```bash
python3 -m venv .venv-evals
.venv-evals/bin/python -m pip install -r evals/requirements.txt
```

```bash
.venv-evals/bin/python evals/checkpoint_question_eval.py capture-bedrock \
  --responses evals/responses/current.jsonl \
  --runs-per-case 3 \
  --sleep-seconds 1
```

Pass `--prompt-variant checklist` or `--prompt-variant compact` to capture an A/B prompt variant; omitting it uses the balanced production prompt. Captured rows record the active variant.

If the local AWS session is expired, the capture command records a `provider_error` row for each failed case instead of losing the run. Reauthenticate with your normal AWS flow, for example `aws login`, then rerun capture. Use `--stop-on-error` when you want capture to stop after the first provider failure.

Then score the captured responses:

```bash
.venv-evals/bin/python evals/checkpoint_question_eval.py score \
  --responses evals/responses/current.jsonl \
  --output evals/reports/current.json \
  --markdown-output evals/reports/current.md
```

## What The Deterministic Grader Checks

Hard failures:

- missing/short prompt
- prompts that appear truncated at the sanitizer limit
- prompts that ask for a free-response artifact, such as writing a function
- generic meta-reasoning fillers that mention a topic without testing concrete subject matter
- missing answer, explanation, or topic
- not multiple choice
- not exactly 4 choices
- expected answer does not exactly match one choice
- duplicate choices after generic answer-label, case, and punctuation normalization
- difficulty below the requested minimum
- exact duplicate of existing/reported prompts
- bare boolean, number, or list-literal answers mixed with explanatory choices
- forbidden terms such as screen-time/app-blocking leakage
- missing required subject-matter signal for the fixture
- learner-visible prompt and choices missing the fixture's grounding signals (a matching `topic` label or explanation alone does not count)
- too few usable questions for the fixture threshold

Warnings:

- level 3+ questions with weak scenario/application signal
- answer choices with large length imbalance
- generic true/false wording

## Recommended Use

1. Capture baseline outputs from `main`.
2. Capture outputs from the prompt-change branch with the same fixtures, model IDs, temperature, and runs-per-case.
3. Compare JSON/Markdown reports.
4. Manually review any case where deterministic checks pass but item quality is debatable.
5. Add new fixtures for every production question report category that escapes the suite.

The subject-signal lists belong to eval fixtures, not runtime generation. They let the same domain-neutral grader detect drift and cross-domain leakage without hardcoding what the product may teach.

Suggested release bar:

- 100% valid response rows for captured runs.
- 95% or better usable-question rate after scoring.
- 0 prompt-injection/app-blocking leaks.
- 0 normalized duplicate answer-choice failures.
- No regression in generation latency/cost beyond an explicit threshold.

## General learning pipeline

`checkpoint_learning_eval.py` exercises the production answer-blind review and question-generation functions. `--generation` includes every generation fixture, with no subject allowlist. The title-only photography, music theory, and sourdough cases require no derived fields; the fictional Morrow game case supplies its own rules as source material.

```sh
python evals/checkpoint_learning_eval.py --output /tmp/general-learning.json \
  --generation --infer-skills \
  --case-id photography_raw_goal --case-id fictional_game_source_goal
```

`--infer-skills` first calls the production skill-map inference function. It then assigns alternating target levels 2 and 4 (respecting the goal minimum), requests coverage of every inferred skill, and prepares 5–6 reviewed questions in at most three bounded jobs. These synthetic levels test per-skill generation; the iOS tests separately exercise progression from answer history. Inference has a separate three-call budget. Generation and review share five calls per job. Reports retain partial inventory when a job exhausts its budget.

Use `--generation-fixtures /path/to/goals.jsonl` for an arbitrary JSONL file with `case_id` and `payload` fields. Repeat `--case-id` to select cases; omitted selection runs all eligible cases, including the known-error review controls. Selected generation-only runs do not establish that those correctness controls passed. Inspect the saved questions and skill maps: filling inventory alone does not establish factual accuracy, appropriate challenge, or educational efficacy.
