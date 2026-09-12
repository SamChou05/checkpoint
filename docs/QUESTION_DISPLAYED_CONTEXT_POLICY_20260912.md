# Solve the question the learner can see

Production generation now checks answerability using only each item's displayed
`topic`, `prompt`, and exact `choices`. Goal directives, source documents, the
skill map and objective metadata remain available to authoring and final review;
they cannot supply an omitted premise to the independent solver. The solver's
stage responsibility explicitly treats each item separately so a neighboring
question does not establish a fictional rule for this one. No new call, retry,
semantic filter, subject exception or model is added.

## Evidence and the unsuccessful intermediate version

Four matched missing-premise questions asked about a fictional game's scoring,
a programming operator, a translation and a museum opening day. Four controls
put their complete rules in the stem. The learner's attempt screen displays no
source reference beside the question.

- In the initial legacy-transport control, full references caused **8/8** to pass,
  including all four unanswerable questions. Removing references from both
  verification stages retained exactly the **4/4** complete controls.
- A production-shaped intermediate version removed only solver references, but
  retained the old stage instructions. It borrowed the scoring rule from the
  neighboring control, allowing one invalid item to reach final review. That
  review then emitted an invalid JSON envelope, so **0** were returned. This is
  neither successful semantic detection nor useful-yield improvement.
- The final version removes hidden solver context and explicitly defines each
  item's boundary. A matched comparison used native transport in **both** arms
  to remove the JSON-envelope confound. The full-reference arm accepted all
  eight. The displayed-item arm rejected the four missing-rule items and kept
  all four complete controls. Both made **two** provider calls; elapsed times
  were **24.529 s** and **19.652 s** respectively. One run per arm does not
  establish a latency distribution.

Exact traces: [original source control](evidence/correctness-audit-20260912/source-matched/plan.json),
[unsuccessful intermediate](evidence/correctness-audit-20260912/displayed-matched/displayed_solver_full_reference.json),
and [final matched comparison](evidence/correctness-audit-20260912/context-final/plan.json).
A zero-call preflight failure is also retained separately: the diagnostic initially
reserved fewer than the three runtime stages. The corrected runner reserves the
normal pass while separately capping actual SDK calls at two for fixed authors.

This is an answerability improvement, not a teaching-quality certificate. The
final displayed arm's reviewer still says the distractor `2` matches no standard
arithmetic on operands 5 and 3, although `5-3=2`. Only three of the four complete
controls have fully supported final feedback. The source-free solver can still
invent facts, misreason, or borrow another item's premise despite instructions;
there is no hard per-item provider isolation. Fresh difficult examples continue
to expose these limits. See [the complete audit](QUESTION_CORRECTNESS_ROOT_CAUSE_RESULTS_20260912.md).

## Provenance and compatibility

Wire `verificationVersion` remains **1**. Existing content and grading identities
are preserved. Policy revisions identify the checks actually performed:

| Revision | Independent solver | Teaching contract |
| --- | --- | --- |
| 1 | Historical stem-only path | Reviewer-written |
| 2 | Complete choices plus reference context | Reviewer-written |
| 3 | Complete choices plus reference context | Opt-in authored explanation audit |
| 4 | Displayed-item context | Reviewer-written; production default |
| 5 | Displayed-item context | Opt-in authored explanation audit |

Historical direct verification and replay entry points retain revisions 1/2/3.
They cannot acquire a current stamp by changing a constant. Production explicitly
selects `solver_context="displayed"`; successful solving and review stamp 4/5.
The client requires revision 4 for fresh verified practice. Old inventory is not
relabeled, and historical wire-version-1 answers still use exact UTF-8 grading.

Release API claim support and all generating workers **before** an app requiring
revision 4. Otherwise new clients will reject old inventory and may be unable to
refill. Use the existing refill flow; do not rewrite previously accepted content
or its provenance. No deployment, bank migration or app installation was performed
as part of this audit. Native output mode also remains opt-in: the existing global
switch cannot safely be enabled for the deployed Nova Lite API author.

## Implementation verification

All **1,061 backend tests** pass. They cover the actual author/solver/reviewer
transports in legacy/native and reviewer-written/authored modes, retained source
and objective content at the appropriate stages, exact displayed literals,
missing-premise vetoes, old/current provenance, storage/replay, budgets and prior
shared-answer and literal-content regressions. Client tests exercise old policy
2/3 rejection for fresh practice, current 4/5 admission, retained historical stamps,
choice rotation, persistence and grading. The final iOS run executed 1,034 tests
with one existing skip and no failures after excluding two app-group tests that
also fail on unchanged main in this unsigned simulator. The initial full run
exposed an old echo-list test expectation; it now checks preservation of a
matching list and rejection of an unmatched extra option. No unrelated Screen
Time code or test was changed.
