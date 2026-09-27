# Seven-candidate generic reserve: trial 02

**The seven-row author succeeded, but the full worker failed.** Under frozen
plan SHA-256
`6effccce724caaf54285b171d4152c5e6d3162a86d1c492c47a4ec215350013e`,
AWS accepted the 1,117-byte native author schema and returned seven rows.
Checkpoint sanitized all seven. The author Converse took 136.449 seconds and
used 3,368 input / 9,644 output tokens. The subsequent seven-row native
complete-choice solver request reached Bedrock but returned a
`ValidationException` in 10.405 seconds. The worker marked the whole original
job failed and returned **0/5** in 149.820 seconds, with two Converse
dispatches/reservations and no reviewer call. The terminal immutable capture
SHA-256 is
`680d6fd8939a2fbc99eda4d0b523cd890a96399140fb6e91d222f62298c85ea4`.

The capture records `native_request_invalid` for solver contract
`complete_choice_solver_v5_n7` (schema SHA-256
`06c56f02a2535d09c86445f98cd0e9383fc3c875520ed3f88830b4197afdf8c8`).
It does **not** retain the provider's free-text error, and the runtime did not
classify it as its exact `native_grammar_too_large` phrase. The cause could be
schema complexity or another native validation rule; this trial alone does
not distinguish them. The author-only success does not establish that the
seven asserted keys, distractors, explanations, difficulty, or novelty are
sound. No final question passed the answer-blind solver/reviewer chain.

The one-shot trial ID is terminal; its plan, precheck, and capture are
unchanged. The feature remains opt-in and disabled by default. A successor
must either qualify a valid seven-row solver contract or verify the seven
candidate identities in smaller bounded chunks while preserving original
ordinals, reviewer vetoes, the shared deadline, and a five-survivor
fail-closed gate. It also needs a content review of the returned items;
replaying the seven authored rows offline is a diagnosis, not a successful
worker trial.
