# Separate citation discovery and structured review

This separately frozen follow-up addresses the [first trial's missing citation
handoff](QUESTION_CLAIM_EVIDENCE_INTERFACE_RESULTS.md). It reuses the exact four
questions, goals and model-selected challenge records from that terminal capture.
It does not regenerate targets, repair questions, reuse old review verdicts, or
replace the failed result.

The fixture `evals/fixtures/question_citation_discovery.json` is checked against
the archived capture hash before planning and execution. A changed question,
context, origin or challenge fails before dispatch. The experiment tag is
`frozen-claim-citation-discovery-v2`; the original v1 prompt/request behavior
remains available under its prior tag and source-bound historical capture.

Nova discovery now asks for ordinary brief prose with native source citations
about the frozen target. It does not need to fit a semantic JSON envelope.
Generated prose is retained solely as a discovery observation and is never fed
to either reviewer. Only native citation URL fields may trigger the existing
bounded public-page acquisition. Selection still uses exact unchanged lexical
windows, not model-authored quotes. Targets remain fallible: the earlier butter
challenge questions an ordinarily correct definite reference and includes an
incorrect generalization in its rationale. Both reviewers must treat that shared
rationale as an untrusted hypothesis and audit the complete item/main.

Both fresh Sonnet 4.6 reviewer requests additionally use the same static native
JSON schema through top-level `outputConfig.textFormat`. This directly targets
the outside-JSON responses seen in v1. No question, source ID or choice-specific
enum changes the schema between calls. The application still enforces string
bounds, exact keys/quotes, cardinalities, indexes, supported teaching and material
issues. Native structured output constrains form, not truth; refusal, incomplete
output and invalid application content remain failures.

AWS documents [Sonnet 4.6 structured-output support](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-sonnet-4-6.html)
and the [Converse schema interface and compilation behavior](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html).
Native Anthropic citations are not enabled on review calls: source IDs and exact
quotations are ordinary application JSON fields. The native browser tool remains
on the separate Nova discovery calls. The existing [author schema experiment](QUESTION_AUTHOR_SCHEMA_EXPERIMENT.md)
already demonstrated that schema compliance does not establish correctness.

The comparison still allows at most 12 model calls and eight page acquisitions.
Discovery uses read75/connect3 and a 90-second local worker. Both review arms
use a 300-second read timeout and local worker allowance to observe a cold schema
compilation, which may take minutes. Review generation remains disabled-thinking,
6,000 tokens and temperature 0.2. The same schema is reused for both arms and all
cases. These offline windows do not establish compatibility with the production
75-second read limit. Record each call's latency, usage, completion and cleanup;
local timeout does not establish remote cancellation or zero billing.

The two new review requests for a case must still differ only in acquiredSources;
shared prompts, frozen challenge and native output schema stay equal. Score
incremental factual catches over the fresh baseline separately from format and
citation success. Preserve supported controls, inspect all alternatives and main
claims, and report any new false rejection. Empty-source baseline eligibility
cannot be compared directly to evidence eligibility. Acquisition failure is not
a correctness catch. Both arms retain the explicit diagnostic minimum of 2;
this does not qualify advanced question generation or learning outcomes.

Full captured page text remains local unless redistribution is appropriate.
Any published summary must distinguish exact raw hashes, transformed/redacted
records and independently assessed claim support. No model/default promotion,
production stamping, deployment or bank writing is part of this experiment.

Source validation passed 937 backend tests with no skips, Ruff, Python compilation,
the whitespace diff check and independent review. Native request fields were
checked against botocore 1.43.89 without constructing a client; JSON-schema tests
also ran with jsonschema 4.26.0. Those checks validate structure and orchestration,
not live model access, citation availability or factual accuracy.
