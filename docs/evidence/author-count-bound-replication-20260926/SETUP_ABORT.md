# Replicated count trial: setup abort before AWS

The independently reviewed frozen plan (`7599074d82324d8394f584dfb9dd15ac5577d1111a6f41d4f978e1b3a546aeca`) was invoked once. It stopped while loading the named AWS profile because the command's `PYTHONPATH` omitted `/tmp/checkpoint-count-crt-deps`, which supplies `awscrt` for botocore's login credential provider. This was a harness launch error, not a model response.

The immutable [capture](capture.json) has SHA-256 `4d3de5e8b383c12202f1d58def6b58c4ee784e11917664e667f17a0b47cfeecb`. It records `preflight_status: failed`, `preflight_error_type: MissingDependencyException`, `account_id: null`, and zero jobs. There were **zero STS calls and zero Bedrock calls**: the exception was raised by `profile_session.get_credentials()` before either client was constructed. No author answer, structural outcome, or semantic outcome exists for this attempt. Its original five-slot denominators cannot earn favorable credit.

The frozen `plan.json` and capture remain unchanged. A future trial needs a new capture path, a corrected and explicitly checked dependency search path, a separately frozen plan, and independent review. Reusing the same prespecified assignments after this zero-provider-call setup abort does not select on observed model behavior; the abort must remain visible alongside any successor result.
