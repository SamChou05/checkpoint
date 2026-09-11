# Wrong-key gate audit

Read-only audit of the frozen native run at `661751d`; raw IDs below refer to the
v2 blind packet. Assessor B's phase-one and phase-two judgments remain unchanged.
Provider call and item indices are zero-based.

The two agreed wrong authored keys did not reach the app, but this is **not two
successful correctness diagnoses**. One was withheld on an inaccurate ambiguity
verdict; the other never reached a model checker because its stem was one
character over the length limit.

| Raw item | Exact observed path | What the exclusion/admission establishes |
| --- | --- | --- |
| **q006**, coherent speakers; author call 0, item 2 | Sanitizer accepted; solver call 1, row index 2; `solver_multiple_supported` at `complete_question_solution.py:293`; no reviewer or return | Solver marked **83 dB and 86 dB supported**. It justified 83 using an incoherent-source counterfactual, while explicitly recognizing that the stated in-phase case makes 86 correct. The gate withheld the wrong 83 dB key, but the declared multiple-answer reason is false for the phase-one accepted reading. It did not produce `answer_disagreement`. |
| **q020**, day-75 billing complaint; author call 9, item 0 | Sanitizer `prompt_length` at `question_quality.py:228`; no solver, reviewer or return | The exact stem is **321 characters**, above `MAX_PROVIDER_PROMPT_CHARS = 320`. No observed stage assessed the invented exclusion of service-quality overlap or the invalid inference from timely filing to mandatory acceptance. Length rejection supplies no correctness credit. |
| **q008**, service-fee exception; author call 6, item 3 | Sanitizer accepted; solver call 7, row index 3; `solver_multiple_supported`; no reviewer or return | Solver marked $30 expedited, $50 expedited and $75 standard supported. This detects the practical non-uniqueness under a plausible ordinary default-fee reading. Its reasons assert a general fee rule for amounts outside the exemption, although that rule is not explicit. This is a protective exclusion of B's ambiguous item, not proof that all three fees are logically mandated. |
| **q019**, hourly misting; author call 15, item 0 | Sanitizer accepted; solver call 16, row index 0 eligible; reviewer call 17, row index 0 `valid: true`, difficulty 3, accepted; returned operation 2/item 3; client **q010** | Solver uniquely supported lower transpiration/higher turgor and reviewer repeated that account. The reviewer request includes those `independentSolutions`, so the two approvals are not independent evidence about the interpretation. Neither stage identifies the missing persistence/timing/hydraulic information frozen in B's uncertainty judgment. App delivery preserves the assertion; it does not resolve that uncertainty. |

The solver's q006 response is also a **false ambiguity verdict on a valid
unique-answer stem**: the incoherent scenario is not the stated case. Its actual
authored draft already had a wrong key, however, so this run does not show a
solver veto of an otherwise correct keyed draft. The only two solver exclusions
were q006 and q008; there is no observed separate correctly keyed solver false
veto among these captures. Nor does withholding q006 establish a reliable
correctness detector: the code counts declared supported labels, and the
counterfactual rationale was itself treated as support.

The other ten exclusions were reviewer `difficulty_floor`: q023, q017, q007,
q009, q014, q018, q011, q004, q012 and q005. Each reviewer said `valid: true`, kept
the authored answer and assigned difficulty 2. B's prior blind judgments gave
these unique supported answers and difficulty 1 or 2. Their removal is consistent
with the requested difficulty floor, not ten factual catches. This limited check
does not certify the factual correctness or difficulty of all admitted items.

Evidence was cross-checked against actual capture author arrays, serialized
solver/reviewer request rows, response indices and response hashes; the q019
client join uses operation/index plus exact prompt and recorded claim/client
checks. The existing lineage records exact baseline and instrumented replay.
No providers or replay were rerun for this audit, and no runtime or assessment
file was edited.

- [Capture](capture.json): byte SHA-256 `fed7a2261f2baf58bddbc3c6749fef409fd41d7dcf70b91bc27da0047c6848df`.
- [Stage lineage](stage-lineage.json): byte SHA-256 `f00d9c5a15ae88ff8a9e6ce9745e78a1cf1e627a6ff4cc970dc674b33b57096d`.
- [Raw v2 mapping](raw-assessment/private-mapping.json): byte SHA-256 `03c7207eb2070e8a9594b581f33b437c23a1d38ab12aacbb3d2a7f1e44a72837`.
