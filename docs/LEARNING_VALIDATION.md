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
- After generalizing review and the evaluation runner, the backend suite passed:
  238 tests. Ruff and Python compilation passed. Deployment script tests and SAM
  template validation had passed for the unchanged deployment configuration.
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

The current implementation combines independent review with subject-neutral
checks: exact answer/choice bounds, truncated duplicate detection, and
shuffled-letter feedback rejection. Reviewed difficulty must respect the
learner's minimum and exact adaptive target. The earlier goal-triggered formal
logic requirement and all-pairs wording filter were removed. Neither is an
appropriate requirement for a general learning system; the formal translation
also caused false rejections of valid questions. Their observed errors remain
in the live regression fixtures instead of becoming special product branches.

The latest general reviewer passed five of the nine correctness controls. It
accepted all three valid controls, including the named-person inference formerly
rejected by the proof requirement, but still accepted four known-invalid items.
This is a quality limitation, not a list of unsupported subjects.

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

## General-goal live evaluation

The same inference and generation functions were exercised with title-only
photography, music theory, and sourdough goals, plus an invented tabletop game
whose rules were supplied as source text. No case needed a production branch.
The model inferred relevant skills and produced subject questions, including
questions applying the invented rules. Initial music and sourdough runs returned
provider errors; isolated inference and a fresh full run succeeded in creating
their maps.

Mixed-difficulty inventory did not pass: photography, sourdough, and the invented
game each retained 3 of 5 requested reviewed questions; music retained 2 of 5.
The retained items were level 2; requested level-4 coverage remained unfilled.
Completed attempts used three bounded jobs and about 161–191 seconds per goal.
Manual inspection also found photography wording dependent on unstated camera
conventions. This confirms general subject handling, but exposes a shared
challenge-calibration and answer-quality gap. It does not establish reliable
adaptive generation at higher levels.

## Reproduce and release

The product contract is one pipeline for any learning goal. AI infers the skills
and objectives from a raw goal, uses persistent per-skill evidence to choose the
next challenge, generates fresh applications, and explains the learner's answer.
Source uploads are optional context, especially for private or user-defined
material; teaching a new subject must not require a new code path or curated
subject pack.

The next quality work should improve general generation/review reliability,
challenge calibration, and coverage using unseen goals and varied difficulty
levels. Keep known-error controls alongside fresh examples, and evaluate model
choices and prompt changes across the whole set. Two models agreeing is still
not proof that an answer is correct.

From `backend/bedrock-question-service`, configure AWS credentials, `AWS_REGION`,
the intended `BEDROCK_MODEL_ID`, and `BEDROCK_VERIFICATION_MODEL_ID`, then run:

```sh
python evals/checkpoint_learning_eval.py --output /tmp/learning-eval.json --generation
```

Use synthetic goals. The tool saves reviewer output and questions for inspection,
checks known bad items and valid controls, and simulates finite inventory top-offs
across all generation fixtures with at most three jobs of five provider calls each.
Use `--case-id` for a subset, `--generation-fixtures` for arbitrary goals, and
`--infer-skills` to infer a skill map before exercising alternating per-skill
target levels. Those targets are synthetic; device-side progression is separately
covered by the iOS tests. It uses the production
generation/review functions, but does not exercise deployed API authentication,
queue delivery, or device-to-service integration.

Before distribution, evaluate unseen questions at several difficulty levels,
inspect question-to-skill alignment and transfer rather than cosmetic novelty,
and run repeated learner sessions. Resolve remaining coverage failures and
review any ambiguous assumptions. Configure the reviewer's explicit invocation
permissions, deploy and smoke-test the backend, and then validate activation in the
client. Each Pro goal adopts reviewed learning when verified inventory first
arrives; legacy service responses remain usable until that transition. The local quiz remains fast once its
reviewed reserve is ready.
