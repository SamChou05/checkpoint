# Preserve learning objectives at the checking boundary

The question checker omitted each candidate's free-text `objective`. It retained
`objectiveID`, but that ID does not always resolve to an objective in the supplied
skill map. When a skill has no listed objectives, the author is instructed to
provide a concrete label and the sanitizer derives an ID from that label. Both
checking stages then lost the only description of the intended objective.

The shared verifier item now includes the existing objective label when present.
The complete-choice solver's explicit field whitelist also retains it, with a
string type check. Absent objectives remain absent. The historical stem-only
solver, default reviewer and authored-teaching reviewer use the same preserved
item context. Answer keys, author difficulty and author feedback remain hidden
from the solver; the authored-teaching reviewer still receives only the teaching
that its existing contract is meant to audit.

This gives the existing objective-fit review access to the intended skill being
tested. It does not force the model to judge fit correctly, change answer grading,
or establish an improvement in factual accuracy. In particular, a correct
arithmetic question can still be mislabeled as a prime-identification exercise;
this correction makes that label available to the checker instead of silently
discarding it. No subject-specific validator, new model call, model setting or
deployment is included.

Verification: 57 focused tests passed, followed by the complete 1,111-test backend
suite after updating an existing native-payload assertion to require the new
optional label. The regression traverses actual normalization, sanitization and
legacy/native adapters for both teaching contracts, checks dense survivor
reindexing, and keeps the solver's private metadata exclusions intact. Ruff and
whitespace checks passed; independent review found no blocking regression.
Scripted provider replies establish transport and policy behavior only. No paid
model call was made for this correction.

Source-use instructions and per-stage attribution of recorded content errors
are separate investigations. They are not resolved by this context-field fix.
