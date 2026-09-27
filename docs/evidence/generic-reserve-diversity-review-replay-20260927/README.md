# Trial 04 second-reviewer diversity replay

This diagnostic sends exactly one previously captured second-chunk reviewer
request, with the opt-in generic reserve's new batch-diversity instruction
appended to its system prompt. The baseline request, model, native schema,
inference settings, user prompt, and prior-question coverage remain the same.
The request already contains a pair of expected-value items that both blind
reviewers later called a strong repeat. The replay tests whether the changed
reviewer instruction causes the model to flag that second item. It cannot
establish full-worker yield or statistical reliability.

The [probe](probe.py) pins the source and baseline capture hashes, requires a
reviewed plan hash, verifies the AWS account, reserves the single call before
dispatch, disables SDK retries, and saves only filtered response fields. Do
not retry this probe ID after a terminal or uncertain call.

Run from the repository root with the project's pinned Bedrock probe
dependencies and both backend module directories on `PYTHONPATH`. For this
workspace, the tested prefix is:

```sh
PYTHONPATH=/tmp/checkpoint-count-crt-deps:/tmp/checkpoint-reliability-jsonschema-deps:/tmp/checkpoint-probe-pinned-deps:backend/bedrock-question-service:backend/bedrock-question-service/evals:. \
  /tmp/checkpoint-reliability-20260921-venv/bin/python -B \
  docs/evidence/generic-reserve-diversity-review-replay-20260927/probe.py
```

Pass `prepare` or `execute --plan-sha256 <reviewed hash>` after that prefix.
The default `python3` environment does not contain the pinned botocore probe
dependencies or resolve these local modules.
