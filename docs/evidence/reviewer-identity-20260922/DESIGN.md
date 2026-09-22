# Inactive reviewer identity prototype

A closed object with required keys `"0"` through `"N-1"` removes the model-written
index. Each value retains the existing v1 review fields except `index`. The
adapter validates the entire raw object, restores indexes from trusted keys, and
then uses the unchanged v1 adapter. It never drops unknown rows or fills missing
reviews. The candidate is not registered or selected by production.

The observed v1 failure is permitted by its schema: an integer accepts `-1`, and
an array does not express unique complete coverage of the requested identities.
The adaptive responses contained `[-1,-1]` and `[-1,0,1,2,3,4]`; both were rejected
by the existing local envelope check. The requests supplied only indexes 0–4.
Why the model chose a phantom sentinel is unknown; schema permissiveness is the
confirmed structural gap.

A fixed enum such as 0–39 excludes negative indexes but still admits out-of-batch
IDs. A count-specific enum excludes those IDs but still permits missing and
duplicate rows. Required closed object properties express complete identity
coverage. The prototype uses a finite family for counts 1–20; the worker's
normal chunks need only counts 1–5. Schema bytes depend on count, never question
text, avoiding a fresh grammar for every question.
An eventual runtime integration must cover the supported API maximum of 40;
this evidence prototype intentionally remains limited to 20 and tests count 5 live
only if separately authorized.

AWS documents object schemas with required properties and `additionalProperties:
false`, scalar enums, and Converse structured outputs. It does not support numeric
bounds; new grammars can take minutes to compile, with identical schemas cached
for 24 hours. These documented capabilities support the design; the prototype
still needs an actual provider qualification. See [AWS structured-output
reference](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html).
A count family creates multiple cold-schema cases; testing count 5 alone does
not qualify every count or establish cold-start latency for all of them.

Nine offline tests exercise all 20 counts, numeric ordering, unknown/missing/
duplicate keys, forbidden embedded indexes, malformed values and JSON, exact
feedback preservation, and negative nonadmission. Both original phantom-array
captures remain invalid; no recovery is attempted. The old reviewer v1 schema
hash remains `77c15c631555d0d83bfaa2e0ba1c19478c51d2573586220cce2ce94684bfe2fe`.

The first candidate changes only outer identity. Its `choiceFeedback` array still
allows model-written choice strings, wrong counts and duplicate choices, and its
answer remains free text. Existing local checks must continue rejecting those
cases. A later separate contract could bind four feedback slots to trusted exact
choices and use a four-slot answer enum, as the author contract does. That would
constrain feedback identity and answer membership, but could not establish that
the selected answer or explanations are true. Such a change is deliberately
excluded from this prototype and trial.
