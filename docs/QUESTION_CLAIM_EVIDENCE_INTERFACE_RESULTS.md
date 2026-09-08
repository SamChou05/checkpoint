# Claim-directed discovery: missing citation handoff

The first live [claim-evidence comparison](QUESTION_CLAIM_EVIDENCE_PROTOCOL.md)
completed its calls but could not test acquired evidence: native searches ran,
yet JSON-only challenge responses contained no native citation URLs. The runner
correctly fetched no pages and skipped all four evidence arms. This is a failed
interface test, not a factual accuracy result.

The unchanged [capture](evidence/claim-evidence-interface-capture-20260908.json)
and [summary](evidence/claim-evidence-interface-summary-20260908.json) bind the
run to source `51b6644edadbe1689265ddda95b40b0c32433801` and canonical plan hash
`4639fcc00ad3287658afcb8c7e5a6b827299d83533f6b941920c8c95e79a4581`.
Capture byte SHA256 is
`ade70260e2bbe9f9366783e70a4d4a2e359c93ffd44b391cf33ee71fff07676c`.

| Case | Native searches | Native citation URLs | Baseline contract result | Evidence arm |
| --- | ---: | ---: | --- | --- |
| Dough | 2 | 0 | Invalid review | Skipped: no acquired evidence |
| Hotel | 1 | 0 | Content declared supported; no evidence | Skipped |
| Butter | 1 | 0 | Invalid review | Skipped |
| Plant tissue | 2 | 0 | Invalid review | Skipped |

All six native tool results reported success but exposed only `[HIDDEN]`.
Eight of the 12 allowed provider calls ran; every call ended normally with known
usage and confirmed worker cleanup. Total usage was 9,869 input and 3,609 output
tokens. Recorded SDK intervals sum to 55.490237 seconds and worker intervals to
60.801984 seconds; neither is an independently measured end-to-end wall interval.
No page was fetched, no evidence review was dispatched, and no model response
reached its output ceiling.

The three invalid baseline responses include prose outside the required object;
additional schema problems also appear in some records. They remain format
failures, not successful detection of the known content defects. Inspection of
the butter response shows that its structured approval still accepts the
misleading generic-reference explanation. The source-free hotel control is
supported, but the reviewer's level-3 rating differs from the prior level-2
assessments. These observations do not qualify any question for production.

Independent offline verification rebuilt the complete plan, checked all 36 source
hashes against the source commit, and recomputed every discovery request,
challenge binding, baseline request and recorded review result. No provider call
was used for that replay. The original capture is preserved byte-for-byte; no
retry or resumption occurred.

The next interface change should separate the structured challenge from a
citation-producing search response. Reuse these exact challenges in a separately
frozen follow-up, request ordinary prose with native citations for discovery,
and keep that prose out of both reviewers. Only separately fetched text may be
used as evidence. This would test the missing handoff rather than count another
model assertion as verification. No deployment or production setting changed.
