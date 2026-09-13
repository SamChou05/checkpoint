# Preserve the complete authored stimulus

The backend treated four trailing lines matching the offered choices as a
redundant echo and removed them before verification. In four independent
reproductions, those lines were the information being tested: program output,
measurements, a poem and a travel sequence. Each original had one exact
positional answer; after deletion the solver could not recover the order from
the shuffled alternatives.

The fix keeps the complete cleaned subject text through admission, solving,
review, storage and display. The existing echo helper is used only on an
inspection copy for structural validation. iOS likewise inspects matching
labeled lines without deleting them, recognizing their contents independently
of shuffled choice order. Mismatched embedded answer lists still fail the
existing structural check. No new semantic rejection rule, prompt variant,
model change or retry was added.

| Same four authored questions | Before | Preserve stimulus |
| --- | ---: | ---: |
| Correct, answerable final questions | 0/4 | 4/4 |
| Incorrect/ambiguous final questions | 0 | 0 |
| Provider calls | 1 | 2 |
| Total latency | 8.627 s | 10.337 s |
| Useful output per provider call | 0 | 2 |

The original solver correctly reported missing information for all four; it
even considered treating the shuffled choices as the missing measurement
order before declining. With the same models/settings and retained stimulus,
it solved all four, and final teaching correctly identified each position.
The additional call is the existing final review becoming reachable. Exact
[before](evidence/correctness-audit-20260912/stimulus-matched/current.json) and
[after](evidence/correctness-audit-20260912/stimulus-matched/preserve.json)
traces preserve requests, prompts, responses and transformations. This targeted
content-integrity result does not qualify general model correctness.

Eight shared labeled/unlabeled fixtures fail against the previous backend
source and pass with the fix. All **1,055 backend tests** and **53 iOS question
validation tests** pass. The iOS test checks all four choice rotations through
admission, persistence and exact-answer grading. The complete stem must fit the
existing 360-character limit: a longer echoed stem is now rejected intact,
rather than shortened on the assumption that its final lines are disposable.
No existing learner content is rewritten. This change is not deployed.

Final audit verification expanded beyond the initial 53 selected tests to the
full client suite. It exposed an older expectation that matching labeled option
lines would be rejected; the test now asserts intact preservation and continued
rejection of an unmatched extra option. The final run includes the shared
four-rotation admission/persistence/grading checks and passes (1,034 tests, one
existing skip; two unrelated app-group tests excluded after reproduction on main).
