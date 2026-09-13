> Follow-up requested after this audit: [one-call simplification trial](QUESTION_SIMPLE_SINGLE_CALL_RESULTS_20260912.md), with 12 separately bounded calls. The 172-call accounting below belongs to the preceding audit.

# Question correctness: supported improvements and remaining failures

The audit supports three general changes: preserve the complete question stimulus,
preserve learned subject facts across request fields, and separate verifier JSON
transport from author compatibility. They fix demonstrated losses of useful
content. **They do not make the broader pipeline reliably correct.** Authors still
make wrong choices and inconsistent cases; solvers contradict their own reasons;
reviewers sometimes introduce false teaching or reject valid questions.

This report is the current conclusion. Earlier reports and captures remain as
historical evidence, with explicit corrections below. The work used **172 actual
provider calls** in three separately bounded windows: **102/124**, **48/48**, and
**22/24**. No deployment, merge, app installation or learner-bank write occurred.
The draft [PR #9](https://github.com/SamChou05/checkpoint/pull/9) contains the verified
milestones. The user's unrelated original checkout is preserved.

## Corrections to earlier findings

1. **Depending on study material is not automatically a defective question.** A
   learner can be asked to recall a private rule or handbook fact. The earlier
   claim that source removal fixed four proven false acceptances is withdrawn.
   Displayed-only policy 4/5 rejected legitimate learned-fact questions. Its
   source-only replacement 6/7 repeated that mistake for facts carried in goal or
   curriculum prose. Current policy **8/9** retains normalized subject references
   in all these fields while hiding authored item keys, feedback and tags.
2. **The deployed map model is Kimi, not Nova.** The API uses Nova Lite for question
   authoring, but `SKILL_MAP_MODEL_ID` is Kimi K2.5. The original single Nova map
   inference was a local override, not qualification of the deployed map model.
   The [read-only recheck](evidence/correctness-continuation-20260912/deployment-recheck.json)
   supplies the omitted setting. API/worker package hashes remained unchanged.
3. **The teaching replay's initial zero-return counts were wrong.** The offline
   replay had omitted saved independent solutions. The corrected sidecar feeds
   the actual saved solutions and recovers eight admissions per arm, with
   different survivors and false teaching in both. Original captures are unchanged;
   no extra inference was used for the correction. The candidate was not adopted.
   [Teaching comparison and correction](QUESTION_TEACHING_CONTRAST_RESULTS_20260912.md).

## Evidence and supported causes

The [broad diagnostic pass](QUESTION_CORRECTNESS_BROAD_PASS_20260912.md) was committed
before choosing runtime changes. It covered twelve requests across arithmetic,
algebra, probability, Python, SQL, complexity, English, Spanish, astronomy,
ecology and history, including source-free and sourced requests at varied levels.
It authored 49 drafts in 51 calls for 24 slots and returned ten. Every draft,
failed attempt and replacement was read. Six returns had supported keys/teaching
under their stated scope; four of those had weak distractors. A four-question
beginner grammar smoke was never treated as general qualification.

Ranked mechanisms supported by the broad pass and subsequent comparisons:

- **Provider response-contract failures waste solvable output.** Of 31 initial
  sanitizer survivors, 13 were lost at solver envelope validation, four at reviewer
  JSON validation and one at exact feedback-key validation. Native JSON recovered
  some useful output on matched drafts. It does not enforce index correlation,
  application length bounds, or truth; all three limitations remain observable.
- **Authoring introduces substantive defects before normalization.** Examples
  include algebra with an excluded root, missing correct alternatives, SQL join
  reasoning, linear treatment of repeated dilution, and a transit route whose
  lines do not connect. Later format rejection must not be credited as a semantic
  diagnosis of these errors.
- **Verification can check an intended scenario instead of the actual question.**
  Article ambiguity, solstice timing and an implied whale identity show this in
  the earlier traces. In the final transit run the solver notices the missing
  connection, then speculates that an undescribed direct route might exist,
  despite an exhaustive handbook. Retaining facts fixes omission, not reasoning.
- **A deterministic sanitizer deleted necessary stimulus.** Trailing lines that
  matched the choices were treated as disposable, even when their sequence was
  the information being tested. The same defect affected code output,
  measurements, poetry and travel sequences.
- **Solver labels and teaching are fallible even when calculations are correct.**
  Multiple final solver reasons explicitly refute the very choices labeled
  supported. The reviewer sometimes catches these, sometimes adds a new mistake.
  Prior immutable-teaching, model/thinking, isolation and prompt experiments did
  not justify a general replacement; the latest direct-contrast teaching prompt
  also failed. No phrase blacklist, extra reviewer, rejection layer or retry was added.

The [initial 102-call report](QUESTION_CORRECTNESS_INITIAL_RESULTS_20260912.md)
retains the complete earlier matrix, ranked hypotheses and calculations. The
[48-call continuation](QUESTION_CORRECTNESS_CONTINUATION_RESULTS_20260912.md)
and [reference-carrier correction](QUESTION_SUBJECT_REFERENCE_POLICY_20260912.md)
record the later controls. These are deliberately small diagnostic samples,
not blinded expert assessments or production error-rate estimates.

## Changes and matched results

| Mechanism tested on matched inputs | Before | After | Calls / timing |
| --- | --- | --- | --- |
| Required sequence stimulus | 0/4 answerable returns after line deletion | 4/4 correct with supported teaching after preservation | 1 → 2 calls; 8.627 → 10.337 s |
| Learned source facts, four domains | Displayed-only loses all 8 valid recalls/applications | Source-supported retains 8/8; both block 4/4 missing-case items | Four paired two-stage runs per arm; 16 calls total |
| Same reference facts carried in goal prose | Source-only loses all 4 valid recalls | Subject references recover 3/4; both block 4/4 missing-case items | 1 solver call per arm, then 1 candidate reviewer call; 3 total |
| Eight fixed broad drafts, legacy vs native verification | 0 returns | 5 correct-key returns, 4 with fully supported teaching | 4 → 7 calls; 51.850 → 61.278 s |

The goal-reference control's fourth valid recall was falsely rejected when the
solver used the Fern museum's Friday fact for the Vale museum. This is an observed
subject mismatch; a particular batch-contamination cause is unproven. The source
control also retained one false distractor explanation. Neither higher admission
nor a matching key certifies full teaching quality. Timing differences include
existing later stages becoming reachable; they are not latency distributions.

**Stimulus preservation** keeps exact cleaned subject content through solving,
review, bank preparation and iOS. Echo recognition works on an inspection copy;
existing length limits and unmatched-option validation remain. Shared fixtures
exercise all four choice rotations, persistence, feedback identity and grading.
[Implementation and fixed-input traces](QUESTION_STIMULUS_PRESERVATION_20260912.md).

**Subject-reference verification** sends each exact topic, stem and all choices,
plus normalized goal, skill-map and source references. It omits the author's key,
feedback, difficulty, history and generated item tags. The model must distinguish
learned facts from lesson intent and missing case data; deleting an entire field
cannot establish that semantic distinction. Policy 8 records the current default
review checks; 9 records the optional authored-teaching audit. Old stamps remain
unchanged. [Contract and exact controlled replay](QUESTION_SUBJECT_REFERENCE_POLICY_20260912.md).

**Verifier-only native JSON** is the proposed SAM/deployment/workflow default for
Sonnet solving and review. Nova/Kimi authors and map calls keep legacy transport.
Explicit `inherit` and `legacy` overrides remain; an unset standalone process
retains historical inheritance. The global native switch is not imposed on Nova.
Strict parsing, exact choice matching, budgets and application checks stay intact.
The eight-draft matched control and 12/12 native envelopes in the intermediate
fresh run supported this transport correction; the final run adds 14/14 native
schema-valid responses but still includes a duplicate-index and a length failure.
This is a shape/compatibility improvement, not a reasoning-quality guarantee.

## Fresh qualification of the finished configuration

The final [protocol](QUESTION_FINAL_QUALIFICATION_PROTOCOL_20260912.md) and four
fixtures were committed at `925f34f` before inference. Each request ran once with
the Nova API author and Kimi worker author, using actual policy 8, legacy authors,
native Sonnet verification, full per-choice teaching, one pass and a three-call
ceiling per job. No semantic override, retries after failure, or reruns to obtain
a passing matrix. The intermediate 21-call source-only matrix is contextual
evidence; it is not substituted for this final qualification.

| Fresh request / minimum level | Nova calls / seconds / returns | Kimi calls / seconds / returns | Independent result |
| --- | --- | --- | --- |
| Repeated mixtures / 4 | 3 / 8.775 / 0 | 3 / 35.825 / 1 | Nova omits both exact answers. Kimi's first key is 27.5% under the conventional mixture interpretation, but final distractor teaching is unsound; its second stem is internally inconsistent. |
| Python binding and scope / 3 | 3 / 17.887 / 2 | 3 / 17.517 / 2 | All four literal snippets produce their keyed output. Nova authored teaching is repaired. One Kimi review invents a transient `i=3`; the other three final explanations and full feedback are supported. |
| Relative-clause meaning / 3 | 3 / 13.140 / 0 | 3 / 17.485 / 0 | Both authors offer restrictive `that` and `which` as competing correct choices; solver blocks both. Nova's valid second item is level 2. Kimi's valid second item is lost when review returns two rows with index 0. |
| Private transit handbook / 2 | 2 / 13.561 / 0 | 2 / 14.388 / 0 | Nova misses route connectivity and miskeys the busiest day; solver repeats intention-based repair and exceeds its reason bound. Both Kimi no-route answers are valid, but contradictory solver labels falsely reject them. Exact skill/objective facts were present. |

Totals: **16 drafts, 16 requested slots, 22 calls, 138.578 seconds, five returns**.
All five keys are supported within the stated interpretation; **three** have
supported main and complete choice feedback (0.136 such returns per call).
Two of those three use generic error/insufficient-information distractors, limiting
specificity. Even the better default-binding item has weaker ordering/off-by-one
alternatives. This is not five wholly satisfactory questions or a broad accuracy
improvement. The prompts vary from the original baseline, so pooled before/after
accuracy percentages and author rankings would be unjustified.

All eight author outputs were valid JSON; all fourteen native verification outputs
were schema-valid. No transport failures or JSON repairs occurred in this final
window. The duplicate review index remains an application-contract violation,
and an oversized solver reason rejects a batch. There are two clear semantic
false rejections in the Kimi transit batch and one valid grammatical item lost to
review correlation. The below-level Nova grammar rejection is separately recorded.

## Representative stage-by-stage traces

- **Dilution:** complete quantities → author keys 8% and 18% with wrong arithmetic
  → intact stems/choices → solver calculates 8.192% and 15.36%, yet labels refuted
  alternatives supported → one multiple-supported block and one reviewer veto.
  [Actual Nova trace](evidence/correctness-final-20260912/final_mixture_replacement_api_nova.json).
- **Feedback introduced after solving:** literal loop → correct `101010` key and
  accurate solver statement that `range(3)` yields 0,1,2 → reviewer falsely claims
  `i` briefly equals 3 → false feedback survives bank preparation and JSON transport.
  [Actual Python trace](evidence/correctness-final-20260912/final_python_closures_worker_kimi.json).
- **Valid question unnecessarily rejected:** exact line/day facts in skill and
  objective detail → correctly authored no-route keys → references survive intact
  → solver reasons establish impossibility but labels contradict them → both valid
  items filtered, reviewer not called.
  [Actual transit trace](evidence/correctness-final-20260912/final_private_transit_worker_kimi.json).
- **Contract failure after a sound solution:** contextual bee-colony question →
  intact content → solver finds the unique nonrestrictive construction → reviewer
  emits contradictory rows with duplicate index 0 → whole response rejected.
  [Actual grammar trace](evidence/correctness-final-20260912/final_relative_clauses_worker_kimi.json).

Every final draft has an [item-level assessment](evidence/correctness-final-20260912/assessment.json),
including distractors, difficulty, earliest defect and downstream outcome.
[Independent checks](evidence/correctness-final-20260912/independent-checks.json)
use exact fractions, execution of the literal Python snippets, and finite transit
reachability/day enumeration. Python semantics are checked against the
[Python FAQ](https://docs.python.org/3/faq/programming.html#why-do-lambdas-defined-in-a-loop-with-different-values-all-return-the-same-result);
relative-clause judgments use supplied notes and
[Cambridge Grammar](https://dictionary.cambridge.org/grammar/british-grammar/relative-clauses-defining-and-non-defining).
Earlier checks include SQLite execution and NASA, NOAA, RAE and National Archives
references, linked in the historical report. Language/difficulty/plausibility
judgments retain qualitative uncertainty.

## Complete-path audit and verification

| Objective requirement | Evidence, result and limit |
| --- | --- |
| Current main, deployment, previous audit | Main `7d9cc6a`, downloaded deployed modules and read-only configuration snapshots inspected. The earlier shared-answer-vocabulary and prose-prefilter fixes are preserved. No application-code mismatch explained this audit's failures; author/map configuration differences are explicitly recorded. |
| Goal, source, request, context/truncation | Swift/request construction inspected; literal goal/skill/objective/source tests pass. One local map inference and explicit 43,209→24,000-character truncation probe retained. No final source was clipped; sources are learned references, and omitted case data remains a semantic question. This is not a live deployed map-to-phone session. |
| Author, parser, normalization and key transformations | Exact provider requests/responses, raw JSON, sanitizer outputs, choice rotations and key correspondence saved. All 99 new authored drafts across the three windows were assessed, including malformed/repaired drafts in the intermediate run; repeated fixed-author controls are counted separately. |
| Solver/reviewer, filtering, retries and replacements | Actual complete inputs, native schemas, every choice reason, review feedback and final dispositions read. Broad retries and failed attempts retained. Final one-pass cap is declared; higher survival is not counted as truth and structural rejection is not counted as semantic detection. |
| Bank, transport, presentation and grading | All five final items retain exact reviewed content in real bank preparation and JSON roundtrip. Shared iOS fixtures cover display admission, all four rotations, exact UTF-8 grading and history. No live learner storage or real-phone end-to-end run. |
| Controlled original failures and fresh varied qualification | Stimulus, source and goal-reference matched controls; rejected teaching candidate; final fresh four-domain/two-author matrix above. Calls, latency, ambiguity, teaching, distractors, difficulty and false rejections recorded separately. |
| Preserve work and deliver reviewable milestones | Isolated branch, descriptive commits pushed after relevant checks; no force push or unrelated changes. Current results and original captures linked; no deployment or app installation. |

Final code passes **1,071 backend tests**, Ruff, deployment shell contract checks,
SAM lint/build, and isolated native SDK validation for all three packaged functions.
The focused iOS policy/history suite passes seven tests. Earlier full local iOS
validation passed 1,034 tests with one existing skip, excluding two unsigned-simulator
app-group tests whose same three assertions reproduced on unchanged main. No Screen
Time code changed. GitHub runs the full iOS tests, Release build and analysis on the
final branch; inspect PR checks for their current status rather than treating a
cancelled superseded run as success.

The [final boundary checks](evidence/correctness-final-20260912/boundary-checks.json)
verify actual system prompts against the frozen runtime, exact references, omitted
author metadata, intact stems/choices/keys, exact final feedback and bank transport.
All 60 original and 35 continuation manifest hashes were rechecked unchanged. The
[final manifest](evidence/correctness-final-20260912/manifest.json) covers captures
and assessment sidecars; hashes prove preservation, not factual correctness.

**Release order:** API claim support and every generating worker must support
policy 8 before distributing a client that requires it. Historical inventory,
wire-version-1 content and attempts retain their original policy and grading.
The SAM default does not alter existing deployed settings until deployment; a
different verifier model requires compatibility qualification.

The investigation and supported fixes are complete, with the broader reliability
problem explicitly unresolved. The latest failures do not justify another prompt
patch, a reason-text blacklist, relaxed parsing, more retries, or suppressing
per-choice feedback to improve a score. A hypothesis that output order contributes
to label/reason contradictions remains untested; these traces establish the
contradiction, not that cause. No further live calls are scheduled by this audit.
