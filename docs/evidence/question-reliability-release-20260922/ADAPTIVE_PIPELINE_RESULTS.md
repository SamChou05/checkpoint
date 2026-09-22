# Adaptive worker pipeline failed the frozen qualification

The fresh run admitted **5 of the planned 30 questions**. It stopped after the
English solver's 75-second read timeout, exactly as prospectively required. No
replacement jobs or extra provider calls were made. The preceding twenty-control
adaptive solver success remains a component result; it did not establish reliable
full-pipeline delivery.

The frozen plan is `pipeline-adaptive-plan.json`, SHA256
`5408ae80e7c2275cd1de00c181ffa43808ad5b5c5039b5fccd9e27e93bac31e8`.
The final capture is `pipeline-adaptive-capture.json`, SHA256
`e869ab380e711854ef4ed68c83325d94ace6dc6e7ac2334ccbe10beab413f79f`.
The exact unchanged criteria required at least three admitted per domain, at least
27/30 overall, no transport/schema/stage-coverage failures, and every admitted
item to pass independent content and teaching-feedback review.

| Domain | Calls | Accepted / planned | Job seconds | Disposition |
| --- | ---: | ---: | ---: | --- |
| Arithmetic decisions | 6 | 0/5 | 186.905 | Both reviewer batches failed exact index coverage |
| Python 3 expressions | 3 | 5/5 | 75.580 | Admitted; independent content audit recorded separately |
| English usage | 2 | 0/5 | 89.989 | Solver ReadTimeoutError; no solver response or reviewer |
| Quantitative evidence | 0 | 0/5 | — | Unattempted after the frozen stop rule |
| Fictional access rules | 0 | 0/5 | — | Unattempted after the frozen stop rule |
| Physical quantities | 0 | 0/5 | — | Unattempted after the frozen stop rule |

Ten of eleven dispatches returned end_turn and passed native transport/schema
validation. There was no observed truncation. The missing timeout response is not
counted as valid JSON or a successful semantic judgment. Four author calls yielded
twenty drafts; three completed solver calls assessed fifteen items. Three reviewer
calls returned thirteen rows for fifteen requested items, but only one batch had
exact coverage. These are observed counts, not a claim that the remaining drafts
would have been accepted.

The first arithmetic reviewer returned two rejected rows indexed `-1,-1`, instead
of indexes `0..4`. The second returned six rows indexed `-1,0,1,2,3,4`. Both outputs
were schema-valid: the native review contract permits arbitrary integer indexes
and does not encode the request's exact batch identity. The local parser correctly
rejected each entire batch. This is a concrete schema-versus-identity failure,
separate from whether the underlying arithmetic judgments were right. The saved
raw outputs and independent jobs 0–1 audit preserve that distinction.

The English solver timed out after **75.169 seconds** with approximately 225 seconds
remaining at dispatch and 150 seconds remaining after failure. This was a per-call
socket timeout, not exhaustion of the 240-second job deadline. All three attempted
jobs ended within 240 seconds; each SDK call had exactly one total attempt, and no
job exceeded six provider dispatches. Every actual configured timeout fit the
remaining worker time. All observed reads were 75 seconds because no dispatched
call reached the shrinking threshold. Offline tests exercised actual runtime
shrinking at 60 and 10 seconds remaining (53.999 and3.999-second read limits), rejection
before SDK setup at 5 seconds, rejection after a simulated setup delay, and the
seventh-call ceiling. The live run does not demonstrate a successful late shrunk
call.

Returned responses reported **30,705 input tokens and 22,664 output tokens**
(53,369 total): Kimi 7,841/2,608 across four successful calls; Sonnet 22,864/20,056
across six successful calls and one timed-out attempt with no usage returned.
Those are observed usage only; the timed-out request's billable work is unknown.
No dollar-cost estimate is asserted. Total recorded provider time was 352.280
seconds; summed job time was 352.474 seconds. Seven provider reasoning blocks were
omitted from saved responses, including text/signatures. The runtime received each
original response unchanged.

`pipeline-adaptive-summary.json` contains the mechanical per-call/job and coverage
counts. `pipeline-adaptive-replay-checks.json` records a zero-network replay using
the exact frozen runtime: all eleven requests matched the captured request objects,
admitted rows and quality diagnostics matched byte-for-byte as parsed objects,
and the recorded timeout reproduced the same application error. Deadline, SDK
attempt, call-ceiling and reasoning-redaction checks passed. Mechanical bounds and
exact feedback-key coverage pass for all five admitted Python items. Those checks
do not establish semantic correctness; independent audits are separate artifacts.

No production default was changed by this experiment. This result does not support
promoting adaptive/high verification as a complete reliability fix under the
75-second per-call limit. Native batch identity and factual/choice reasoning require
separate investigation; widening a timeout or relabeling partial yield would not
satisfy the frozen qualification.
