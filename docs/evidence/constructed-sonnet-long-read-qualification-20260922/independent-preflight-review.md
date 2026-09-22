# Independent longer-read preparation review

**No blocker found.** The draft is ready for the parent's freeze decision; this is offline guard verification, not semantic qualification or authorization to dispatch.

Reviewed draft digest: `b7561e7577d93247f9a7ec69d4ee0c540c4fc9d67073c4d06951f2009a458fc8`. Draft file SHA-256: `16088c1edc1428755d0d7f1297afd286d0598ee429d16c6ecc4aeffdfae5db34`. [The JSON review](independent-preflight-review.json) records the six preparation-file hashes, commands, counts and independent fake results.

The full source comparison permits only `question_generation.py`'s configured read ceiling changing from 100 to 200 seconds and its exact explanatory deadline-comment replacement. The clean candidate checkout is commit `77f794efa8cc24f94123cda61532ae7fe30d3e38`. All other 26 modules and the dependencies, SDK validator and capture helper match the completed Sonnet source. All **44 baseline pins remain active among 81 total pins**; no earlier source or capture was replaced.

The environment and plan limit change only the read ceiling. Jobs, prompts, 11 selected native contracts, Sonnet models, adaptive/high settings, 16,000-token limit, no-sampling request shape, semantic criteria, endpoint, connection timeout and SDK retry count remain unchanged. The actual worker retains 240 seconds, six durable call reservations per job and an 18-call global maximum. Request, source, capture, credential, provenance and returned-object guards remain intact. The existing runtime still owns partial returns and top-ups.

I independently ran **34 offline tests: all passed in 4.163 seconds**. Ruff passed. I then ran two additional actual-runtime replays, blocking socket connection methods and credential acquisition and rebuilding the real plan guard at every boundary:

| Independent fake scenario | Result |
|---|---|
| Author takes 195 seconds; final audit takes 30 seconds | Actual audit read timeout shrinks to 38.999 seconds. First job finishes at 225 seconds with five returns; all three jobs produce 5/5/5 with eight fake dispatches, eight reservations and 23 full plan checks. |
| Author takes 195 seconds; audit client construction consumes seven more seconds | The real post-construction deadline check prevents the audit reservation and dispatch. First job ends with `ProviderDeadlineExceededError`; later independent jobs continue, producing 0/5/5 with seven fake dispatches and 21 full plan checks. |

Both replays preserve the 15-slot denominator and `qualified=false`. No synthetic response is semantic evidence. The existing 34 tests also cover deadline overruns, late-result credit, full 18-call exhaustion, partial results, invalid native configuration, source drift, malformed output, escaped/duplicate-member credential echoes, and immutable compiler/prose fields.

A longer ceiling does not grant every stage 200 seconds or extend the worker deadline. The prior failed nine-of-fifteen trial remains unchanged, and its absent timeout response does not establish a cold-cache cause. I made no provider calls, acquired no credentials, performed no AWS access, and did not freeze, commit, or edit the six preparation files or either runtime source.
