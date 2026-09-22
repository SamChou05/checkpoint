# Opus 4.7 runtime access failure

The fixed diagnostic dispatched its first request once and stopped globally on
`AccessDeniedException` (HTTP 403) after 0.306832 seconds. Bedrock Runtime said
this model was not available to the account. The earlier read-only availability
and active-profile statuses were insufficient to establish inference access.

No model response was returned. One of five calls was attempted; all 24 controls
remain unassessed and earn no credit. Token usage was unavailable, not zero.
There were no retries, remaining-batch calls, account changes or semantic results.
This cannot establish whether Opus 4.7 would improve the observed content errors.

- Frozen plan SHA-256: `8ddf17879bab8fdc70262c6f74cbd3a3b53c4705cd063d64e560770dcca1c127`
- Capture SHA-256: `e685072ffaea57ea366bcdee28a6106395ef6a198c3ee55ee974cd1c3331aa86`
- Capture request ID: `70660d56-0e88-4a19-bf54-d14bb6d68cde`

The original plan, controls, gold and capture remain unchanged. The pending
Opus 5 commercial decision is separate from this failed access attempt.
