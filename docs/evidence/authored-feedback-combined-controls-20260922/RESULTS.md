# Combined verifier qualification failed

The actual solver → immutable audit composition admitted two unchanged defective questions and failed to complete two other batches. It does not meet the prospective release criteria.

All **10 authorized stage calls** ran, without retries or replacements. Only **3/5 batches** completed: **15/24 original items were scored, 13 decisions were correct, 7/12 sound originals were retained, and 6/12 defective originals were excluded with batch credit**. Nine items belong to failed batches and earn no semantic credit. The nine selected learner responses are byte-identical in all learner fields to their frozen originals; two are defective.

| Batch | Original items | Solver / audit seconds | Outcome |
|---|---:|---|---|
| 0 | 5 | 28.946 / 100.152 | Audit of five survivors timed out; no model text or batch credit. |
| 1 | 5 | 37.988 / 74.005 | 4/5 decisions correct; defective bus question admitted. |
| 2 | 5 | 28.136 / 50.492 | 4/5 decisions correct; defective semicolon question admitted. |
| 3 | 5 | 60.294 / 19.515 | 5/5 decisions correct. |
| 4 | 4 | 64.996 / 40.728 | Audit of two survivors returned native-valid JSON, but one reason was 253 characters against the 240-character local maximum; whole batch failed. |

The bus item asks which ride count makes a $60 pass cheaper than $2.50 per ride. Both 25 and 26 satisfy the literal condition. The solver and audit independently added an unstated minimum preference, declared 25 unique, and admitted the original. The semicolon item allows both semicolon-before-however and comma-however-semicolon. Both stages imposed the false necessity that the semicolon precede however; the final audit also approved the original false main and alternative-choice teaching. These are demonstrated learner-facing failures, separate from private diagnostic wording errors.

The solver did veto multiple square roots, equivalent wrong “2”/“two” choices, equivalent numeric half representations, the underdetermined triangle, a converse-rule wrong key, and duplicate Discard actions. That partial coverage does not erase the unsafe admissions or failed batches. The final audit correctly rejected the false “11 = 4 + 7 + 3” teaching; it also invoked a paired item's duplicate stem/choices as a task defect, a companion-context effect separate from the original per-item field expectation.

All 24 solver records were locally valid. Their labels match the approved diagnostic draft in **90/96 choice positions** and **143/144 pair positions**. Of six choice mismatches, one compares against an explicitly uncertain grammar expectation and three confuse possible triangle lengths with a determined answer. The incorrect pair equates Discard with Rename while its reason describes the two Discard paraphrases; the correctly identified duplicate pair separately vetoes that item. The final audit requested 17 survivors: 12 raw rows returned, ten passed local validation, five lacked output after timeout, and two were invalidated together by the reason bound. Seven solver-rejected controls received no audit.

The independent audit reads all **312 available short reasons**: 240 solver reasons plus 72 audit reasons, including the 12 reasons in the failed final batch. It records factual errors, overbroad wording, interpretation issues and contextual effects separately. In particular, private statements that no arithmetic path yields 14 overlook 4+7+3; one exact-ID pair reason falsely says the matching “042” differs from the stored ID. These diagnostic findings are not a new private-reason-perfection admission criterion. Two original field uncertainties remain unchanged. Difficulty is reported separately and never rescues content failure.

[replay.py](replay.py) makes no network calls and reproduces all ten exact production requests with recorded provider responses, actual native adapters and the actual composed verifier. [replay-summary.json](replay-summary.json) confirms unchanged admission results and learner hashes. [independent-output-audit.json](independent-output-audit.json) binds every original payload and whole gold by hash and enumerates every available reason by exact-text hash. All frozen runtime, harness and control-source pins were checked; original gold, learner text, capture and plan remain unchanged. Provider reasoning text/signatures were omitted; timeout token usage is unavailable, not zero.

The 24 known controls were prospectively regrouped into 5+5+5+5+4. Their original scopes are identical; only empty `skillMap: []` became `null`, the runtime's no-map representation, in both stages. Both scope representations and hashes are pinned. Regrouping and repeated controls prevent a causal comparison with prior trials, and no earlier failed trial is rescued. This is not fresh author generation, worker-yield qualification, deployment, or a claim of deterministic semantic correctness.

Preparation checks: 16 fake test groups, Ruff and whitespace checks passed. Final no-network replay reproduced every recorded dispatch and actual admission. No additional provider call, production edit or commit was made by the independent auditor.

Frozen plan SHA256: `8d8a35f2f4f93c69faa05a32216ae4115623c38ba63605b8012ba12b3ae0d71f`.

Frozen capture SHA256: `d6c70bc9590ba0f1c8e48b2c7beb5443970405f622db2257c127862085d0d653`.

Independent audit SHA256: `659279573a597dee7fca4ae488cf8a9a42cad734736d0db2eaf80bb8452305d7`.

Reuse the existing [scoped runtime reconstruction manifest](../authored-feedback-scoped-qualification-20260922/runtime-reconstruction.json) and its [zero-context patch](../authored-feedback-scoped-qualification-20260922/runtime-source.patch). Its complete 26-module source hash map exactly matches this frozen plan; all 26 current runtime files and the patch hash were independently rechecked. The manifest SHA256 is `6d897a2095679496df2a12e922837b9c52404d5fdcc870225e8fb6432667e2e9`; patch SHA256 is `121a1505671fbd30ede522eb0d1abc03466cc1567624abbb5d15e8054eff357e`. Reconstruct an isolated checkout at `8cad9d3c19b114c9fe2e0730e1445aacf4271c27`, apply the patch with `git apply --unidiff-zero`, and verify all listed hashes. This milestone does not duplicate or alter that reconstruction.
