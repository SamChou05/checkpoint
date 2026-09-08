# Split sourced review still rationalizes a false premise

The [frozen split-review comparison](QUESTION_SPLIT_EVIDENCE_PROTOCOL.md)
completed all 12 calls but failed its prospective correctness criterion. Removing
the search hypothesis and authored explanation from answer solving did not stop
the dough solver from defending a premise it had identified as defective. It
also rejected supported controls for notes that were not material item defects.
The butter explanation's known misleading claim remained undetected.

The input separation and short source references worked as implemented. They
did not establish improved factual judgments or production readiness. No runtime
integration, model/default promotion, bank write or deployment follows.

## Independently assessed outcome

| Case | Fresh old sourced review | Split candidate |
| --- | --- | --- |
| Dough | Retains the wrong authored key while noticing the second-reference defect; response fails exact target/quotation checks. | Solver supports wrong A and refutes warranted C, reasoning that the question implies its premise is correct. The separate teaching call identifies the actual error but exceeds its reason-length limit. No valid complete catch. |
| Hotel | Supported key/main, lost to quotation fidelity. | Correct key and supported main, but an intentionally false distractor is reported as an item defect. The issue veto excludes the valid control. |
| Butter | Admits the correct key and misleading main explanation. | Correct key; the teaching call still misses generic versus unspecified reference. Solver invents a missing-sentence concern despite all three being displayed and itself says this is not a defect. Rejection for that issue is not a correct catch. |
| Plant tissue | Supported narrow key/main, lost to quotation fidelity. | Correct key and supported main, but the solver flags the intended available-tissue constraint and an unrelated source qualification. The issue veto excludes the valid control. |

All 16 candidate choice judgments and four full-main assessments were examined,
including their reasons and cited source units. The dough solver acknowledges
the second reference and nevertheless defends the authored explanation of the
first reference. Hiding that authored main therefore did not remove the observed
failure to challenge the question's presupposition. The choice text and stem can
still suggest an intended answer.

The candidate's correctly selected hotel, butter and plant keys do not establish
fully correct internal reasoning. Some countability claims are overbroad; the
plant reasoning repeats the supplied page's inconsistency about node-free roots.
The narrower plant key and main remain supported. Valid unit IDs identify what
was supplied, not which deductions follow from it. All four items remain
independently assessed at level 2.

The candidate returns no eligible item: one format rejection and three
`solver_issues` vetoes. The fresh baseline admits only the defective butter main;
its other three responses are format-invalid. These are selected diagnostic
outcomes, not general accuracy rates. Neither a blanket rejection nor a correct
key paired with misleading teaching satisfies the user's intended learning flow.

## Format, evidence and operational findings

All 12 responses satisfy their native static schemas. Eight also satisfy the
application response contracts. The four application failures are:

- Old dough review changes the frozen target and alters source quotations.
- Candidate dough teaching reason has 1,361 characters against the frozen
  1,200-character limit. The response ends normally; it is not token-truncated.
- Old hotel and plant reviews contain nonmatching source quotations.

The new source IDs remove quotation-copying failures from the candidate. All 28
units reconstruct the six previously selected source spans, totaling 44,915
characters, in their original order with exact offsets and hashes. No source
was fetched or reselected. Unitization did not repair source quality or remove
the influence of the earlier discovery on passage selection.

All 12 calls ended normally with known usage and confirmed worker/group cleanup.
Usage was 79,570 input and 6,069 output tokens. SDK intervals sum to 123.053812
seconds and worker intervals to 131.035137 seconds; neither sum is an independently
measured end-to-end duration. Individual SDK intervals ranged from 3.911 to
22.385 seconds. No output-token ceiling was reached. The two-call candidate is
not cost-matched to the one-call baseline, and this combined intervention cannot
isolate the causal effect of removing the search rationale.

Independent no-client replay reproduced the entire terminal capture exactly.
All 38 source hashes match commit `7746cfdee5964507d8f994b9e3e2fc4a08f68a31`;
the frozen plan's canonical SHA256 is
`a2570e1383e62eec1c67621eb52c1b2d0b4cd7ddaf780241e8ccbab7dbd4c5c9`.
The original local capture is 851,824 bytes with byte SHA256
`13e4993d3d16c15695c42081b7ba1b7c9132067058b09d423c520f43657a0a7a`.
The [public derived summary](evidence/split-evidence-summary-20260908.json)
omits source passages, source-bearing requests, model quotations and reasoning
text. It is not a raw capture or standalone replay archive. The full source
validation record, including the initial transient test error and the successful
954-test repeat, is preserved in the protocol.

The next change must distinguish actual item defects from expected wrong
alternatives and irrelevant qualifications, while treating a question's implied
premise as a claim to check. Simply relaxing the internal reason-length limit
would expose the correct dough teaching objection but leave the wrong solver
judgment, missed butter error and false exclusions. The present result does not
justify another approval vote or a production promotion.
