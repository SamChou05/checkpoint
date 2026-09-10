# Pause handoff — September 9, 2026

## September 10 preparation and user steering

Current work is in `/tmp/checkpoint-current-model-comparison-20260910`, on
`codex/current-model-comparison`. The new
`evals/checkpoint_current_model_comparison.py` prepares eight fixed subjects for
Sonnet 4.6 and Opus 5 under the current complete-choice/reviewer-written gates,
with matched legacy JSON transport and adaptive/high thinking. No inference,
commercial agreement acceptance or production change has occurred. Read
`QUESTION_CURRENT_MODEL_COMPARISON_PROTOCOL.md` and its case note before use.
The independent subject audit identifies four valid controls, three defective
items and one ambiguous all-pairs item; preserve the ambiguity distinction.

The user then asked whether output tokens or a prompt/architecture issue explains
the failures, and challenged the assumption that newer models are necessary.
Prior evidence already includes a same-model short-prompt comparison: 24/30
supported keys for the simple prompt versus 26/30 for the then-current author
prompt, with no output exhaustion. All six contexts lacked skill maps, adaptive
plans and question history. This neither exonerates the full architecture nor
supports repeating a simple-prompt comparison unchanged. Read
`QUESTION_PROMPT_EXPERIMENT.md`, `QUESTION_COMPLETE_SOLVER_RESULTS.md`, and
`QUESTION_REVIEWER_INDEPENDENCE_RESULTS.md` before selecting further work.
Track correctness of the raw authored item, generated final teaching and actual
returns separately; do not mistake format/difficulty exclusions for factual
errors or successful catches. The prepared model comparison remains optional;
no AWS permission question is pending.

The account's Opus 5 commercial agreement was still unavailable in the observed
read-only check at 2026-09-10 06:50:56 UTC. Recheck before any future authorized
trial. Its activation requires explicit user authorization, separate from the
existing authorization for bounded paid experiments. Do not start or repeat a
paid run merely because this preparation exists. The broader correctness goal
remains incomplete.

## Previous completed trial

The active goal resumed after the user's latest progress/pause check. Current
work is in `/tmp/checkpoint-premise-witness-20260909`, on
`codex/premise-witness`. Read `docs/QUESTION_REVIEWER_INDEPENDENCE_RESULTS.md`
before following any historical next steps below. The new ten-call comparison
is terminal: handle 58234 exited zero, and every worker was reaped. Its frozen
source milestone `040d0e5` is committed and pushed. Do not restart this capture.

The new experiment tests a previously unisolated information flow: supplying
versus withholding the prior solver records from the default reviewer, with
otherwise identical current native instructions. Both arms still return the
unequivocally defective spreadsheet item. Withholding also supplies incorrect
ecology feedback and loses a five-item batch to invalid review records. It is
not qualified for production. Source preparation passed 82 targeted tests;
source/policy/export audits and both assessment phases are saved in
`docs/evidence/reviewer-independence-20260910/`. Production settings remain
unchanged. The prior native-stage diagnostic at `751bdaa` is also complete.

Next, prepare a stronger-model comparison using the current complete-choice
and teaching contracts, rather than adding another equivalent assumptions
critic or repeating context removal. The existing Opus 5 runner still uses the
historical stem-only/legacy contract and needs a prospective update. Its AWS
commercial model agreement remains unaccepted; do not accept it without the
user's explicit authorization. Other preparation can proceed independently.
Fresh generation, broader subject coverage, normal-runtime delivery, native
author/skill-map qualification and learning gains remain unproven. The broader
goal is active and incomplete; this handoff does not change its app-managed
status or promise background work after the user pauses it.

The user requested current progress and a suitable pause point. The latest live
comparison, independent assessments, and local bank/client checks are complete.
No runtime qualification, native qualification, or simulator test process was
running at the pause check. All listed subagents had completed their work. Do
not start another experiment merely to finish this handoff.

## Completed and saved

Worktree: `/tmp/checkpoint-delivery-feedback-20260909`.
Branch: `codex/delivery-feedback-comparison`.

Three verified milestones are committed and pushed:

- `6768a5a`: normal-workflow comparison harness, tests, and prospective protocol.
- `1fd45a4`: local bank/client delivery checks and procedure.
- `e0cb325`: real comparison results, frozen independent assessments, raw
  synthetic evidence, manifests, and operational/final audits.

Read `docs/QUESTION_DELIVERED_QUALITY_RESULTS.md` and its linked evidence before
resuming. The live comparison made 29 calls across six five-question requests,
returning seven questions from 30 requested slots. Both assessors supported six
answer keys; the remaining ecology item has a convention ambiguity, not a
demonstrated arithmetic error. Only two returns met every joint content
criterion including requested difficulty. This selected sample does not
establish general correctness, production reliability, or learning gains.

Seven of 16 downstream responses failed strict JSON parsing because prose
preceded fenced JSON. No response exhausted its output budget; the maximum was
2,201 of 6,000 tokens. Increasing tokens is not supported by this run.

All seven returned questions survived the local bank/claim and actual iOS
admission/persistence checks. All 28 composed feedback displays matched the
assessment packet. These checks used local test state, not a deployed service.
The app derives its learning target from its title, so these checks do not
establish exact backend/client request-context equivalence.

The completed capture is `/tmp/checkpoint-delivery-live-20260909/capture.json`;
its preserved copy is under `docs/evidence/delivery-feedback-20260909/`.
Do not restart the completed capture or reinterpret it using changed runtime
code. No production deployment or default was changed by this experiment.

## Next concrete step

Native structured-output implementation has now merged into `origin/main` at
`a4e3bf1` through PR #5. Its authoritative qualification document is
`docs/NATIVE_STRUCTURED_OUTPUT_IMPLEMENTATION.md` on that ref. It remains
opt-in with legacy mode as the default. Its automated tests do not establish
live provider compatibility or question quality.

Resume by reading that committed implementation and its qualification gates,
then integrate it into an isolated experiment checkout. The shared main
checkout is five commits behind that remote-tracking ref and contains unrelated
uncommitted iOS and native-output work. Do not pull, reset, stage, or overwrite
those shared changes. Use the merged implementation rather than rebuilding
native output from the stale shared working files.

Qualify the exact provider/model/schema combinations within the documented
bounded plan before measuring useful delivery again. Preserve the existing
correctness and difficulty checks. Native formatting alone does not establish
factual correctness. The documented synchronous Nova Lite role also remains
outside the native capability allowlist; do not flip the shared production flag
or automatically change that model to obtain a passing qualification.

The broad correctness goal is unresolved. This handoff records a safe stopping
point; it does not mark the goal complete or change its app-managed status.

## Local artifacts and tools

Untracked simulator projects, derived data, reports, and result bundles remain
in the isolated worktree. The reviewable evidence is already committed. Do not
commit generated build artifacts or another task's working-tree changes.

Python: `/tmp/checkpoint-live-review-venv/bin/python` (3.12.11).
The prior run used boto3/botocore 1.43.89; the merged native implementation pins
1.43.91, so verify the applicable runtime before preparing new evidence.
