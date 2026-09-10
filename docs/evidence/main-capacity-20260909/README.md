# Fresh explanation-capacity evidence

See [results](../../QUESTION_MAIN_CAPACITY_RESULTS.md) and the
[prospective protocol](../../QUESTION_MAIN_CAPACITY_PROTOCOL.md).

- `private-mapping.json` is now the **unmasked** mapping of all twelve raw authored
  question objects to jobs and arms. “Private” described its role during blinded
  assessment, not confidential user data. It contains the exact raw object hashes,
  raw-response text hashes and original capture identity.
- `stems.json` and `teaching.json` are the two exact assessment packets.
- `stem-assessment-a.json`, `stem-assessment-b.json`, `teaching-assessment-a.json`
  and `teaching-assessment-b.json` are independent, frozen assistant judgments.
- `phase-one-freeze.json` and `phase-two-freeze.json` record assessment hashes
  before teaching disclosure and arm/key disclosure, respectively.
- `summary.json` derives all counts, lengths and joins from those records. Its
  artifact hashes refer to unchanged basenames in this directory.
- `operational-audit.json` independently checks capture/replay/request fidelity.
- `summary-audit.json` independently checks the derived content/length summary.
- `native-checks.json` contains scoped arithmetic and portable SQLite observations.
- `root-stem-notes.json` and `root-teaching-notes.json` retain separate root
  inspection, including qualifications rather than silently altering assessments.

These are selected assistant-assessed questions, not human expert or learner
validation. No deployed question bank was read or written.

The original 230,337-byte provider capture remains locally at
`/tmp/checkpoint-main-capacity-live-20260909/capture.json`; the frozen plan remains
at `/tmp/checkpoint-main-capacity-plan-20260909.json`. Their hashes are recorded
in the results and audits. Raw question objects preserve content; this directory
does not contain the full source-bearing provider transport and is not a
standalone replay archive. No credentials or provider authorization headers are
part of these artifacts.
