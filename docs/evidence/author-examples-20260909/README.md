# Checked-example transfer evidence

See the [results](../../QUESTION_AUTHOR_EXAMPLES_RESULTS.md),
[prospective protocol](../../QUESTION_AUTHOR_EXAMPLES_PROTOCOL.md),
[demonstration review](../../QUESTION_AUTHOR_EXAMPLES_DEMONSTRATIONS.md) and
[source notes](../../QUESTION_AUTHOR_EXAMPLES_SOURCES.md).

- `private-mapping.json` is now the **unmasked** join of all ten raw objects from
  strict responses to their jobs and arms. “Private” described its role during
  assessment, not confidential user data. It preserves raw object and response
  hashes and records the whole-response format failure separately.
- `malformed-job-5.txt` preserves the complete final raw response with repeated
  explanation fields. Neither value was selected, deleted or repaired.
- `stems.json` and `teaching.json` are the exact masked assessment packets.
- The four `stem-assessment-*.json` / `teaching-assessment-*.json` files contain
  separate assistant judgments. The two `phase-*-freeze.json` files record hashes
  before teaching and arm/key disclosure, respectively.
- `summary.json` derives counts and lengths across all twelve requested slots.
  Two slots have a response-format failure rather than content approval.
- `operational-audit.json` checks source/request fidelity, usage, stop reasons,
  duplicate-key preservation and exact replay without provider clients.
- `summary-audit.json` independently checks the count/length joins and calculations.
- `native-checks.json` contains scoped exact arithmetic and coordinate checks,
  including a counterexample to the quarterly-sales explanation. It is not an
  Excel application run or an ecology simulation.
- `root-stem-notes.json`, `root-teaching-notes.json` and
  `root-post-unmask-notes.json` preserve separate root inspection. Root knew the
  experiment's examples and is not counted as one of the fresh masked assessors.
- `format-diagnostic.json` distinguishes ordinary JSON decoding from strict
  duplicate-member rejection.

The original 251,917-byte capture remains at
`/tmp/checkpoint-author-examples-live-20260909/capture.json`; the frozen plan is
`/tmp/checkpoint-author-examples-plan-20260909.json`. Their hashes are recorded
in the results and audits. These artifacts preserve question content and
assessment provenance without committing the full source-bearing transport.
They do not form a standalone replay archive. No credentials or provider
authorization headers are included. No production question bank was read or
written, and no human expert or learner calibration was performed.
