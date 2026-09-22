# Independent structural and provenance review

Capture SHA256: `8107bf285c2125c89e0ddb654b0ada756a6a943d05cb6d22c0c7ce5cc9465523`.
Frozen plan SHA256: `db7f3d506a6f76954b54102fa215beba266be0602030e23cd39fa6cfe44d6a13`.

All source/plan pins matched. Independent offline replay through actual generation reproduced all ten exact provider request bodies, the saved failures and final returns, using only captured visible responses and errors. No provider was called, and the capture, plan, harness and runtime were not changed. Timing was checked separately against the actual captured transport and job accounting.

| Job | Calls/reservations | Elapsed seconds | Returned |
| --- | ---: | ---: | ---: |
| Quantitative | 5 | 234.209511 | 0 |
| Python | 4 | 226.354971 | 4 |
| Mixed | 1 | 100.260749 | 0 |

All jobs remained in the fixed 15-item denominator. Each used at most 6 calls and 240 seconds; total calls/reservations were 10, within 18. Every request used Sonnet 4.6, adaptive/high, maxTokens 16000, no sampling, connect 3 seconds and one SDK attempt. Captured read timeouts stayed within 2–100 seconds and shrank to 2.075 seconds for the late numerical solver request.

Seven responses completed with `end_turn`; all seven satisfy their exact native schemas. Both solver responses also pass strict local decoding. The Python main-audit response passes local decoding. The first numerical audit is native-valid but locally invalid: row 3's issue strings have lengths 0, 1, 1 and include blank/whitespace-only entries. Its provider schema constrains issues only to an array of strings; the local contract also requires nonblank strings, at most 600 characters each, and at most 8 issues. The application correctly rejected the whole local envelope. Four other rows declared the main explanation unsupported for lacking worked derivation; this structural review does not independently endorse or refute those teaching judgments.

Three `ReadTimeoutError` outcomes were retained: the late numerical solver (2.238660 seconds, read limit 2.075), the Python top-up author (100.162980 seconds, read limit 100), and the mixed author (100.190097 seconds, read limit 100). Python retained its four previously verified items after its top-up failed. Usage reports total 29,146 input and 32,260 output tokens; usage for the three failed calls is unavailable, not zero.

All three parsed author passes were independently prepared and sanitized again. All ten raw compiled specifications reproduce their exact five recorded learner fields. None was released, so there is no successful compiled-release evidence in this trial. All four returned prose items bind to their actual per-pass sanitized and verifier observations and exact raw authored mains; their final main text is unchanged, choice feedback is empty, and policy revision is 7. Both completed solver/audit pass outcomes were independently replayed, including their exact dense provider prompts and results.

The trial fails its prospective yield and compiled-yield requirements: 4/15 returned, versus 14/15 required, with no compiled returns. Structural correctness and provenance do not establish learner-content truth, adequate worked teaching, or reliable model judgments. Independent semantic adjudication remains separate; this report supplies no new correctness approval or reconstructed qualification credit.
