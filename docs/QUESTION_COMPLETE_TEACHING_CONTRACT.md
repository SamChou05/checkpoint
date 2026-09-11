# Complete authored teaching: production contract

## Status and evidence

The `authored_complete` path is implemented as an explicit opt-in. It completes
all learner-facing teaching before the last semantic audit, then binds that
contract to generation, queued fills, bank claims and local question selection.
The default remains `reviewer_written` with policy revision 2. There is no new
settings UI, default promotion, deployment or live provider qualification in
this implementation milestone.

The [September 10 native workflow](QUESTION_NATIVE_WORKFLOW_RESULTS.md) exposed
an actual ownership failure: the final reviewer introduced a false sound-pressure
claim after the author and independent solver had correctly handled intensity.
The false main reached all four composed client displays. All 18 provider calls
completed below the 6,000-token limit, so output truncation did not explain that
failure. Native structured output was already working in that trial.

Immutable teaching is an existing hypothesis, not a new proven remedy. An earlier
[fresh complete-author experiment](QUESTION_FRESH_AUTHOR_IMMUTABLE_RESULTS.md)
retained false CSS teaching. An [immutable review follow-up](QUESTION_IMMUTABLE_REVIEW_FOLLOWUP_RESULTS.md)
retained three sound controls and rejected both defective items, but still
contained false support judgments; the issue veto was decisive. The
[main-only implementation](QUESTION_AUTHORED_SOLUTION_CONTRACT.md) also failed
fresh quality qualification. This change adds an enforceable full
content and delivery boundary; it does not establish that model support labels
are true or that arbitrary goals now produce reliable practice.

## Request and delivery selection

An API generation or bank-preparation request can supply the top-level field:

```json
{"feedbackContract":"authored_complete"}
```

This is a selector fragment, not a complete generation request. The usual goal,
learning context and count fields are still required. If present, the selector
must be exactly this string. Null, unknown values and other mode names receive a
bad-request response instead of silently falling back. Omission retains the
existing server behavior; `QUESTION_FEEDBACK_CONTRACT` can still select
`reviewer_written`, `authored_solution` or `authored_complete`. An explicit
request takes precedence over that environment setting.

The iOS `Goal.questionFeedbackContract` optional enum persists this selection;
older stored goals decode with `nil`. Ordinary goal edits preserve it.
`QuestionGenerationRequest` derives its contract from the goal, and both direct
generation and bank preparation encode the top-level selector. The claim asks
for wire version 1 and minimum policy revision 4, even if the legacy verified
question Boolean is false. No new screen enables this experimental selection.

The bank context signature includes the explicit contract. Server bank IDs also
use a distinct HMAC namespace, so reusing a caller context revision cannot reuse
an older bank. Bank metadata records an immutable contract, queued jobs retain
it in their normalized generation request, and workers block a mismatch.
Explicit banks discard lower-policy or structurally incomplete generated items
before they become ready inventory. The bank itself imposes policy 4 on claims,
cached replays and races even when the caller omits or lowers its requested
minimum. Existing pointer/lease fences protect a changed active bank from stale
work. No old question receives a newer stamp on storage or retrieval.

Client selection and batch admission enforce the stored goal contract and
reject damaged revision-4 teaching. Historical questions can remain persisted
without being eligible for new practice under the explicit contract. Omitted
selectors keep the previous context signature and conditional policy floor:
revision 2 when verified questions are required, otherwise 0.

## Three-call content contract

1. **Complete author.** The author produces the stem, four choices, exact key,
   main worked explanation and exactly one explanation for every choice. Native
   transport uses `question_author_complete_v1` and a `choiceFeedback` row array;
   the adapter requires exact coverage and creates `choiceExplanations` without
   changing strings. The native order is stem, main, key, choices, feedback,
   then the existing topic/difficulty/format and optional skill fields.
2. **Independent complete-choice solver.** The existing solver receives the
   exact stem and offered choices, goal, skill and supplied source context. It
   sees neither the author's key nor teaching. Its enforced unique-supported
   choice, uncertainty and disagreement gates still apply. Legitimate negative
   or cannot-determine answers remain possible when warranted by the task.
3. **Frozen complete audit.** The reviewer receives the completed main, all four
   choice explanations and all four exact composed feedback displays. It sees
   neither the explicit author key/difficulty nor previous solver judgments;
   historical keys and teaching are omitted. Teaching can reveal the author's
   intended answer, so this audit is not answer-blind. The review can report
   support, difficulty and defects, but cannot supply replacement teaching.

Request context and teaching are snapshotted before callbacks. Callbacks receive
serialized payloads, and mutation of the caller's original request cannot change
the later audit or admission checks. Sanitization never cleans, clips, renames
or silently drops complete learner-facing fields. It rejects malformed content
before the model audit.
Semantic judgments about legitimate negative answers are left to the complete
solver/audit rather than the old phrase-based rejection heuristic.

The frozen field limits remain 320 code points for the stem, 140 for a choice,
420 for the main and 280 for each choice explanation. The author prompt still
aims at its existing 320-character main bound and 120-character choice feedback.
The stem and teaching must contain at least 12 characters after whitespace
trimming as a predicate; retained strings are never trimmed. These limits have
not been validated as sufficient for every advanced subject.

For each selected choice the client displays choice feedback, two newlines,
then the main. When the two strings are canonically equivalent under Swift
String equality, it displays only the exact stored main. The backend composes
the same displays; normalization is used only to decide equality, never to
rewrite retained text. The audit assesses each whole display as well as its
components, because individually supported statements can conflict in context.

## Enforced review and provenance

The strict `complete_teaching_reviewer_v1` response has one indexed record per
item with `valid`, an exact answer or empty answer when no unique result is
established, assessed difficulty, `explanationSupport`, four exact
`choiceFeedbackSupport` rows and `issues`. Each choice row declares both
`feedbackSupport` and `displaySupport`; support is `supported`, `unsupported` or
`uncertain`. Extra fields, missing/duplicate rows, partial index coverage and
unparseable JSON are rejected.

Any unsupported or uncertain main, choice feedback or display is a veto. Any
reported issue is a veto even alongside `valid:true`. Invalid verdicts, key
disagreement and failure to meet the requested/adaptive difficulty also block
admission. A reviewer cannot erase an authored defect by dropping its field,
rewriting it or attaching a verification stamp. Surviving items preserve the
frozen teaching exactly and receive policy revision 4 only after this path.

Revisions identify checks performed: 1 is historical stem-only solving, 2 is
complete-choice solving with reviewer-written feedback, 3 is immutable main-only
teaching, and 4 is immutable complete teaching/display audit. Revision 4 does
not certify semantic truth. The ordinary three-call cycle, provider-call quota,
deadline, top-up limits, fallback model configuration and token ceilings are
unchanged. A top-up failure can return only already fully audited survivors.

## Verification and remaining qualification

Scripted backend tests exercise native transport through author, solver and
reviewer, every support veto, disagreement, malformed/replacement content,
exact text identity, context mutation, partial top-ups, request selection,
queue-to-inventory propagation, claim/replay floors and mode changes. A test
also deliberately accepts false teaching when both scripted model judgments
are falsely supportive. That counterexample records the limit of these gates;
it is not a successful semantic check.

Simulator tests exercise opt-in persistence and goal editing, request and claim
encoding, exact content decoding/sanitization/persistence/composition, older and
damaged inventory rejection, and an in-flight older-bank response after a
contract change. These are deterministic contract tests, not evidence of live
question accuracy or app-blocking effectiveness.

Final verification on September 10, after independent review fixes:

- The full backend suite passed **1,127 tests**, with no skips, using
  `python -m unittest discover -s tests` from the service directory.
- The focused iOS Simulator run passed **150 tests**, with zero failures or
  skips, including all seven new complete-teaching tests, bank async flow,
  backend contracts, goal profiles and existing validation/content/policy/feedback
  preservation suites. The final run fixed an initial test compile error.
- Service-wide Ruff, Python compilation and `git diff --check` passed.
- Independent review checked context mutation, legitimate negative answers,
  solver survivor indexing, bank/client structural parity, delivery selection,
  six unchanged legacy author-prompt byte comparisons and this evidence summary.

No live inference was performed for this milestone. The two new native schemas
still require actual provider qualification before use; support of the previous
schemas does not establish support or semantic reliability of these new ones.

A future prospective content trial must freeze this source and actual settings,
retain every raw draft and rejected item, inspect authored and delivered keys
and complete teaching independently, include difficulty and useful yield, and
report truncation/latency/cost. It must not reuse the earlier plan's execution
claim or select only favorable survivors. It should address a specified missing
capability or comparison, not treat another reviewer prompt as proof of a fix.
