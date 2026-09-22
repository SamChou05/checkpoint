# Exact-request diagnostic: compiled grammar rejected

The separately authorized diagnostic made exactly one dispatch of the complete first rejected request. AWS returned HTTP 400 / `ValidationException` after 0.527 seconds:

> The model returned the following errors: The compiled grammar is too large, which would cause performance issues. Simplify your tool schemas or reduce the number of strict tools.

The request ID was `576983a6-cd02-4788-9162-0668062ff497`. This identifies compiled grammar size as the service's stated reason for rejecting this exact request. It does not identify a published numeric grammar threshold or prove that any particular schema rewrite will be accepted. The request uses native output configuration, so the generic reference to tools in the error is not evidence that this experiment sent tool definitions.

No retries, warmups, replacements, or additional calls occurred. The client retained the approved read timeout of 75 seconds, connect timeout of 3 seconds, and SDK total attempts of one. Only bounded, credential-redacted error code/message, HTTP status, request ID, request hash, and diagnostic timestamps were captured. No model output or provider reasoning was retained. Token usage and cost are unavailable.

The original structural qualification remains **failed, 0/2**, with one failed request and one unattempted request. Its capture still contains only the original exception class. This new diagnostic supplements the evidence; it does not alter that historical capture or supply structural or semantic qualification credit.

The next bounded representation candidate can factor repeated assessment and solution schemas through internal references while preserving the logical closed identities and strict validators. That is a proposal to test separately, not a proven production fix. No runtime source, production policy, provider setting, or deployed configuration changed in this diagnostic.

Diagnostic plan SHA256: `db88ebd49476fe21f93ca6c43c55526e64c0a40a5a715fd882606585a8bd8ba7`.

Diagnostic capture SHA256: `9e41fc3b0bdd84ce230483c91a1ed94c7d5cf6d2f5429795ed108184f3ceae1f`.

The six diagnostic tests pass, including exact request reuse, one-dispatch/no-resume behavior, SDK/time bounds, and redaction before truncation. `error_diagnostic_replay.py` verifies the request, original failure, whitelisted error fields, and all relevant hashes without credentials or network access. The reusable safe-error helper lives in the frozen new diagnostic runner; historical runners remain unchanged.
