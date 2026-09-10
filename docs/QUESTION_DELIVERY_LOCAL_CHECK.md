# Local checks of captured question delivery

`backend/bedrock-question-service/evals/checkpoint_delivery_check.py` accepts a
terminal runtime capture and writes an offline bank/claim report. It calls the
actual preparation and claim functions with existing in-memory test doubles,
disallows network connections, and keeps each complete operation batch together.
The original returns, preparation losses, exact claim and idempotent replay,
original goal/source context and source hashes are retained.

Run it from the backend service directory:

```sh
python evals/checkpoint_delivery_check.py --capture CAPTURE.json --output DELIVERY.json
```

The bank is a synthetic completed finite bank containing only that operation's
prepared inventory, with no earlier history. This checks serialization and claim
behavior; it does not exercise deployed storage or scheduling/refills. An empty
operation remains a zero-item denominator. App admission is a separate check.

`CheckpointTests/QuestionDeliveryCaptureTests.swift` consumes the resulting report.
It uses real payload decoding, whole-batch app sanitation, Codable persistence,
and feedback selection for every retained choice. It checks UTF-8 content and
choice identity across shuffling and exports a JSON attachment containing
runtime, claimed and client-retained counts, losses and composed displays.

This optional capture test is intentionally registered only in a temporary copy
of `Checkpoint.xcodeproj`, leaving the normal project unchanged. Add the test
file to its CheckpointTests group and Sources phase; update the copied scheme's
container references and set its TestAction environment variable
`CHECKPOINT_DELIVERY_FIXTURE_PATH` to the absolute delivery-report path. Select
`QuestionDeliveryCaptureTests/testCapturedOperationsThroughRealClientDelivery`
when running the copied project. A missing fixture skips this optional test and
must not be reported as a successful delivery check. Export the resulting JSON
attachment with `xcrun xcresulttool export attachments`.

Preparation passed four Python tests, including loss preservation, context
binding, empty output and exact claim replay. Two targeted simulator runs also
passed without skips: the synthetic feedback control and the synthetic report
file. The latter retained two questions through all boundaries and exported
eight exact composed feedback displays. These controls do not establish the
quality or delivery of live-generated content; that requires running the helper
and capture test on the exact terminal experiment capture.
