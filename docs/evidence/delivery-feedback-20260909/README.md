# Normal-workflow delivery comparison evidence

See the [results](../../QUESTION_DELIVERED_QUALITY_RESULTS.md) and
[prospective protocol](../../QUESTION_DELIVERED_QUALITY_PROTOCOL.md).
All generated question text remains unchanged. No rejected draft was substituted
for a runtime return. `manifest.json` contains byte hashes and sizes.

- `plan.json`, `capture.json`: frozen execution plan and all 29 requests,
  observations, raw response texts, operations and counters.
- `operational-audit.json` / `.md`: independent source, bounds, cleanup,
  accounting, exact no-client replay and role-specific parser audit.
- `stems-and-choices.json`, `teaching.json`: the two masked input packets.
- `first-assessment-a.json` / `-b.json`, `teaching-assessment-a.json` / `-b.json`:
  complete independent assessments. Both teaching packets include every composed
  selected-answer display. Assessor disagreements remain intact.
- `phase-one-freeze.json`, `phase-two-freeze.json`, `packet-manifest.json`:
  ordering, source-capture and input/output hash bindings.
- `private-mapping.json`: post-assessment ID mapping, arms and original keyed
  runtime returns; intentionally withheld during assessment.
- `results-audit.json`: independent final validation of counts, masking, sources,
  delivery, disagreements and qualified scope.
- `summary.json`: the frozen joint-credit aggregation, individual counts,
  operation outcomes, provider metrics and coverage. Empty precision denominators
  are null rather than perfect scores.
- `bank-delivery.json`, `client-delivery.json`, `client-attachment-manifest.json`,
  `client-test-summary.json`:
  local storage/claim and actual simulator decoding/admission/persistence/display
  results, with source hashes and separate boundary counts.
- `root-calculations.json`: independent post-unmask coordinate calculations and
  qualified ecological unit-conversion examples. These do not replace the frozen
  assistant scores or constitute native Excel execution.
- `build-assessment.py`, `summarize-assessment.py`: exact packet and aggregation
  helpers. Packet construction uses a fresh random shuffle; the committed packet
  and mapping are authoritative for this run's IDs.

The capture byte SHA-256 is
`b2b4d385fcde8143d8d43ea34cb17d6e4963fb816793cb5feed9a776c02b3049`.
Original temporary paths in captured provenance point to this run's local files;
the copies here are checked byte-for-byte. Generated Xcode build products and
the simulator result bundle are retained locally and are not committed.

Scope clarification for the local delivery reports: "original goal/source
context" means title, current level, focus areas and sources mapped into the
app's supported Goal fields, with an enum/custom category conversion. The app
derives its own learning target; it does not accept the backend fixture's
explicit learningTarget as an assignable Goal field. These checks demonstrate
exact question preservation and admission in that reconstructed local state,
not complete backend/client request-context equivalence. See the results for
the qualified assessment of the ecology item and the feedback disagreement.
