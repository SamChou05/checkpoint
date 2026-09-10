# Preserve subject meaning before question generation

The input path could change the subject before any model saw it. This change
preserves meaningful whitespace, notation and Unicode in new learning-goal
requests. It addresses a demonstrated context defect; it does not establish a
general MCQ correctness improvement or resolve questions whose premises already
reach the model intact. No model, token allowance, agreement or deployment changes
are included.

## Reproduced changes in meaning

| Input | Previous transformation | Corrected behavior |
| --- | --- | --- |
| `Distinguish "a  b" from "a b".` | Backend goal normalization made the quoted strings identical. | Preserve the two literal strings. |
| Indented code in focus or learner context | Newlines, tabs and repeated spaces collapsed into prose. | Preserve internal layout in JSON and rendered learner-context guidance. |
| `Learn A minor` | The app removed `A` as an apparent article, producing `minor`. | Retain `A minor` after the goal verb. |
| `Learn -1 < 0` or `Learn .5 versus 5` | The app stripped boundary punctuation, changing the sign or decimal. | Retain subject punctuation. |
| Focus examples differing in spacing, case or Unicode representation | Derived provider topics could collapse or merge distinct examples. | Preserve their exact content in provider topics. |

These are generic text transformations, not subject-specific rules. The app
still recognizes existing leading goal phrases such as “study for the” and
“learn.” Its UI topic summaries may group labels by case; provider context uses
exact subject identity. Focus-area list splitting remains comma/semicolon/newline
based, and the complete focus field retains its layout.

The [before/after normalization evidence](evidence/goal-context-preservation-20260910.json)
records the same synthetic request through both actual backend normalizers at
the previous source milestone and this correction, with source-file hashes.
All six supplied goal fields retain their subject content after the correction.
This is a local input-preservation reproduction, not a model-accuracy result.

Optional skill-name suggestions have a different identity contract from subject
examples. When distinct examples collide as canonical skill names, the app sends
no optional suggestions and retains the complete goal for inference. Explicit
invalid duplicate names still fail backend validation. The change does not
silently merge the meanings or bypass skill-name validation.

## Boundaries covered

The app preserves the learning target in both setup interpretation and request
context, and preserves learner prose in its local-model prompt as well as the
question directive. Encoded question-generation and skill-inference requests keep
the original subject fields. Backend generation and skill-map normalization
preserve title, learningTarget, focusAreas, questionDirective, currentLevel and
explicit contentTopics. Evolution uses the inference normalizer. The author's
rendered learner-level guidance uses the same preserved text as its JSON.

Existing field types and character limits remain enforced; spaces now count
without first being collapsed to fit. Existing subject cleanup still normalizes
line endings, removes empty boundary lines and replaces unsupported control
characters while retaining tabs and internal newlines. Category remains ordinary
metadata. Existing bank requests that already lost content cannot reconstruct it
without a fresh request.

Regression tests exercise actual normalization and orchestration through legacy
and native authoring, solving, reviewing, skill inference and skill evolution,
including supported retry paths. All 15 scripted provider boundaries assert the
decoded subject fields exactly. Network connections and SDK client creation are
forbidden in these tests. Simulator tests check actual encoded app request bodies,
local prompt text, topic identity and inference-suggestion handling. These checks
prove input preservation on those paths, not model factual accuracy.

## Verification

- The full backend suite passed 1,107 tests. After the final optional-suggestion
  regression was added, all 12 tests in the two new backend modules passed.
  Backend production code did not change between these runs.
- The affected iOS simulator suites passed 142 tests: question validation, goal
  creation, backend engine contracts and skill maps.
- Ruff passed for the affected backend code and tests, and `git diff --check`
  passed. Independent code review found no further actionable issues after the
  learner-context and optional-skill-name integration corrections.

No paid model calls were made for this correction. These checks do not measure
question accuracy, learner outcomes, or deployed behavior.

## Remaining investigation

The earlier [simple-prompt experiment](QUESTION_PROMPT_EXPERIMENT.md) already
found errors without adaptive plans or question history, and without output
exhaustion. Fixing context damage does not explain every recorded failure.
The newly audited verifier also omits a candidate's free-text objective from its
checking payload, and its source-use wording differs from the author's. Those
issues are separate from this slice. Their effects should be tested without
repeating the completed context-removal experiment or assuming a newer model is
necessary. Per-stage attribution of fresh question and teaching errors remains
unfinished.
