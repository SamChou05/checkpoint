# Scoped immutable-feedback component: failed qualification

The candidate failed its frozen primary criterion. All four fixed batches were attempted once: the first two passed native and strict local validation, while the last two returned `ReadTimeoutError` without model output. Continuing the fourth planned batch after the third timed out followed the prospectively approved independent-batch policy. There were no retries, replacements, rescue calls, or unattempted batches.

| Batch | Elapsed seconds | Outcome | Correct admissions / planned | Input tokens | Output tokens |
| --- | ---: | --- | ---: | ---: | ---: |
| 0 | 84.228181 | Strict valid | 6 / 6 | 3,173 | 7,406 |
| 1 | 85.651857 | Strict valid | 6 / 6 | 2,858 | 7,146 |
| 2 | 100.003574 | Read timeout; no output | 0 / 6 assessed | Unavailable | Unavailable |
| 3 | 100.171258 | Read timeout; no output | 0 / 6 assessed | Unavailable | Unavailable |

The full denominator remains **2/4 structurally valid calls and 12/24 assessed admission decisions**. The 12 observed decisions all matched unchanged gold: six sound controls retained and six defective controls excluded. The other 12 controls received no output and no semantic credit. This is neither a 24/24 pass nor evidence that the missing controls were semantically wrong. The primary criterion still requires four valid bounded calls, all 24 decisions correct, all 12 sound controls retained, and all 12 defective controls rejected.

All six selected learner payloads match their exact originals, including the prompt, four choices, key, main explanation, and four choice explanations. The actual runtime's adapter, validator, `accepted_indices`, and immutable selector were replayed without network access. No learner strings were repaired or rewritten. No question-bank writes or deployments occurred in this component trial.

The two returned batches contain 72 visible task/feedback reasons, all emitted before their judgments. Independent factual and exact-item review is complete for all 72: 62 reasons were grounded, four endorsed false claims, three rejected true statements for missing uniqueness, one reflected an interpretation-dependent exclusion, one used unsupplied history, and one had an imprecise justification. The other 72 planned reasons were not returned and remain unassessed. Label matches alone do not establish grounded reasons. Against the unchanged diagnostic annotations, the observed batches matched 11/12 task labels, 12/12 answer declarations, and 52/60 feedback labels. Across the complete plan those denominators remain 24, 24, and 120. One observed feedback annotation was explicitly interpretation-dependent before dispatch. These annotation comparisons are separate from the primary admission outcome.

Some private judgments were materially unreliable despite correct admission. The weighted-grade defective main explanation was endorsed as having “directionally accurate” distractor claims, and three causal-feedback fields were endorsed despite unsupported claims in the supplied teaching. The defective parallel-timing task was rejected as a duplicate of its sibling control even though the supplied prior-coverage history was empty. Other label disagreements involve true but incomplete mathematical explanations versus their implications for uniqueness; the original annotations and their caveats remain unchanged. The completed independent review records these distinctions rather than converting every label mismatch into the same type of error. The imprecise weighted-grade task reason also refers to four distractors although there are three.

Total provider elapsed time was **370.054870 seconds** across the four independent component calls. Known usage was 6,031 input and 14,552 output tokens, or 20,583 reported tokens; usage for the two timed-out calls is unavailable, not zero. Three provider reasoning blocks were omitted from capture, retaining their count only. No monetary cost estimate is made. The failed calls provide no AWS code/message, HTTP status, or request ID beyond the safe `ReadTimeoutError` class.

This was a joint scope/input/prompt and timeout candidate. It used the corrected audit v3, exact new assignment/history input fields, and a 100-second read/elapsed bound. All 24 learner payloads, gold decisions, ordering, model and thinking settings, and native assessment schema bytes were preserved. It is not a latency-only comparison or proof about cold versus warm compilation. The earlier v2 trial remains failed at 0/4, and the separate v2 latency-only draft remains inactive.

These controls have empty assignments and history, so this trial cannot establish model behavior with nonempty skill/objective assignments or prior coverage. The runtime context integration had passed its separate offline tests. The trial also does not qualify the author or solver stages, difficulty policy, the full three-stage architecture, fresh learner content, production defaults, or worker yield. The unchanged 240-second worker deadline would need an actual fresh worker trial; the four independent component durations are not a single worker execution.

The scoped runtime passed 1,223 backend tests and 54 focused tests before this trial. The harness's 23 fake-client tests and the replay's six tests pass, including continuation after ordinary batch failures, global integrity/setup stops, exact request and original-content preservation, and complete denominators. Synthetic oracle rows are test fixtures, not additional provider evidence.

Frozen plan SHA256: `560d42a8576ff6b19923f649879a4bae19061d30defd18e06137d4063f6d2d8d`.

Frozen capture SHA256: `181a2370ecbdecb0fc0cedf59661f7157d05a6a96e893f7a362c997288962d1b`.

Independent audit SHA256: `9f53dbd5e4ed01d7f654ffa22773be02acfe010033e488111bfc98d303703acc`.

Native `experimental_authored_feedback_audit_v3_n6` schema SHA256: `a61fad5fd95ee8829c390e93f7aee534babae6a6ea1e66afb71ebdcbd90089d0`.

`replay.py` verifies the frozen sources, every exact request, both strict assessments, all failed-call outcomes, and the complete denominator without credentials or network access. Before recording the completed independent review, it checks the audit against the exact plan/capture hashes, all reason and structural counts, every unique case/field/reason-hash association, the original judgments, and the category totals. Its derived summary records 72 independently assessed reasons; the unchanged capture retains the zero audit count recorded before independent review. Binding tests reject mismatched plans, captures, counts, duplicate findings, altered reason hashes, or inconsistent category totals without granting review credit. `runtime-reconstruction.json` and `runtime-source.patch` preserve all 26 frozen modules, including the three new authored-feedback files. Reconstruct an isolated checkout at Git base `8cad9d3c19b114c9fe2e0730e1445aacf4271c27`, apply `git apply --unidiff-zero runtime-source.patch`, and verify every source hash. Independent reconstruction matched all 26 hashes. No frozen source, plan, request, capture, or old evidence was changed while preparing this report.
