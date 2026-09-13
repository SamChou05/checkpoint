# Historical displayed-only experiment — superseded

The policy 4/5 proposal removed all source facts from independent solving. It was
superseded by [source-supported policy 6/7](QUESTION_SOURCE_SUPPORTED_POLICY_20260912.md)
because it unnecessarily rejected valid recall from uploaded study materials.
The earlier claim that four source-dependent questions were necessarily
unanswerable was wrong and is withdrawn.

The historical native comparison returned 8/8 with reference context and 4/8 with
displayed-only context, using two calls in each arm (24.529 s and 19.652 s).
The four surviving questions restated their rules. This proves a source-visibility
effect, not four removed false acceptances. One survivor still had false arithmetic
teaching. An intermediate prompt also borrowed a rule from a neighboring question.

The original captures remain unchanged: [source controls](evidence/correctness-audit-20260912/source-matched/plan.json),
[intermediate](evidence/correctness-audit-20260912/displayed-matched/displayed_solver_full_reference.json),
and [native comparison](evidence/correctness-audit-20260912/context-final/plan.json).
Historical explicit `solver_context="displayed"` remains reproducible and stamps
4/5. It cannot acquire current provenance by changing a constant. No deployment
or inventory migration used this proposed policy during the investigation.
