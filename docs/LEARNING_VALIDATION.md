# Adaptive learning validation — September 5, 2026

The adaptive learning changes are implemented in the repository. They have not
been deployed to the service or distributed as an iOS update. Model quality is
still a release gate; passing software tests is not proof of educational efficacy.

## Implementation checks

- The complete iOS simulator suite passed: 876 tests, including goal creation,
  protection and break workflows, persistence, question selection, progression,
  and existing rendering coverage.
- After the final rollout guard, a full 877-test run found two bank-transition
  regressions. Both were fixed; all 29 adaptive scheduling and asynchronous bank
  tests passed on rerun. The other 875 tests had passed in that full run.
- The backend suite passed: 239 tests. Ruff, Python compilation, deployment
  script tests, and SAM template validation passed.
- The Release build stopped at an existing configuration requirement: a real
  `CHECKPOINT_PRIVACY_POLICY_URL` is missing. That check was not bypassed.

The progression tests exercise a learner moving from levels 1 through 5 in one
skill while other skills remain at their own levels, recovery after earlier
mistakes, a step back after repeated difficulty, and exclusion of repeated,
foreign, old, reported, or unverified evidence. They also check that easy cached
inventory cannot hide available harder questions.

## What the live model checks found

The original Kimi K2.5 question author produced concrete defects: an MCAT
equilibrium answer absent from the choices, a request to identify a flaw in valid
reasoning, an invalid LSAT converse inference, and an unqualified linear-time
claim for enumerating all pairs. Self-review was insufficient. A separately
configured Claude Sonnet 4.6 reviewer also shared some of those reasoning errors.

The implementation therefore combines independent review with deterministic
checks: exact answer/choice bounds, truncated duplicate detection, shuffled-letter
feedback rejection, a narrow all-pairs output-size rule, and bounded truth-table
checking for recognized LSAT conditional-inference items. Reviewed difficulty
must respect the learner's minimum and exact adaptive target.

The known bad cases now have explicit regression coverage. The valid named-person
logic control can still be rejected when the model's formal translation is
incomplete or conflates an individual with a universal claim. This is a false
rejection, and causes replacement work rather than teaching an invalid answer.
It also means the live evaluator is not consistently green. The truth-table
checker proves entailment of the supplied symbolic premises; it cannot prove
that those premises faithfully represent the English.

Live local top-offs prepared five reviewed questions for each of LeetCode, MCAT,
and LSAT using two bounded jobs per domain, taking roughly 64–111 seconds in that
sample. Manual inspection of those banks still exposed structural and wording
issues, which led to the additional choice and feedback checks. A full bank alone
must never be reported as a correctness or learning-quality result.

A subsequent run with the additional guards again filled all three five-question
banks in two jobs, taking 82–94 seconds. Manual inspection still found substantive
failures: a BST deletion answer omitted the immediate-successor exception, and an
MCAT item treated continuous DNA labeling over more than a full cell cycle as an
instantaneous S-phase measurement. Both are now retained as additional failing
live-evaluation cases. They are why broad deployment is held; the new reviewer
must not be presented as a guarantee of accurate teaching.

## Reproduce and release

The next quality milestone should ground factual questions in vetted reference
material and use domain checks for calculations, timelines, and algorithm edge
cases. AI should plan the curriculum, identify misconceptions, explain concepts,
and generate varied applications; its agreement with another model should not
be the final authority on an answer. Keep an unseen evaluation set so prompt
changes cannot merely learn the already documented failures.

From `backend/bedrock-question-service`, configure AWS credentials, `AWS_REGION`,
the intended `BEDROCK_MODEL_ID`, and `BEDROCK_VERIFICATION_MODEL_ID`, then run:

```sh
python evals/checkpoint_learning_eval.py --output /tmp/learning-eval.json --generation
```

Use synthetic goals. The tool saves reviewer output and questions for inspection,
checks known bad items and valid controls, and simulates finite inventory top-offs
with at most three jobs of five provider calls each. It uses the production
generation/review functions, but does not exercise deployed API authentication,
queue delivery, or device-to-service integration.

Before distribution, evaluate unseen questions at several difficulty levels,
inspect question-to-skill alignment and transfer rather than cosmetic novelty,
and run repeated learner sessions. Resolve the remaining false rejections and
review any ambiguous assumptions. Configure the reviewer's explicit invocation
permissions, deploy and smoke-test the backend, and then validate activation in the
client. Each Pro goal adopts reviewed learning when verified inventory first
arrives; legacy service responses remain usable until that transition. The local quiz remains fast once its
reviewed reserve is ready.
