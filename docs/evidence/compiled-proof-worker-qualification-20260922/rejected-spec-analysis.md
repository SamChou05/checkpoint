# Numerical draft rejection diagnosis (read-only)

Snapshot: `/tmp/checkpoint-compiled-worker-numerical-failures-snapshot-20260922.json`, SHA256 `8ebfa9507d782b908ca08039008e1d77a5d27353c5fdb2bff7660917afadd554`. Exact replay and embedded task specifications: [rejected-spec-analysis.json](rejected-spec-analysis.json). Only the three completed quantitative author passes and their compile/sanitizer failures were inspected; accepted/returned learner content and keys were excluded. The original snapshot was read-only. Its rejected source tasks and compile/sanitizer records were subsequently checked byte-for-value against final capture `7d458b0f433018df5fa20c7d47c49f7c143c63f7201340a644df6ca31d37b0d3`; all match. Each rejected task is embedded in the derived JSON, so reproduction does not require the temporary snapshot. The original live trial and all frozen files remain untouched.

Thirteen typed drafts (5/4/4) produced three compiled candidates (2/0/1). Ten were correctly rejected: seven `no_answer`, three `invalid_spec` (each an unreachable literal at node position 2). No compiled survivor was lost in the sanitizer. All ten rejected specs had four distinct rational choices; there were no equivalent-choice rejections. Counts concern raw draft attempts, not the original five requested slots or any reviewer admission.

| Rejected source (pass, row) | Exact independent proof |
|---|---|
| 0,0 | (3/4 + 2/5) × 5/6 = 23/24; absent from all four choices. |
| 0,1 | (1.25 − 0.75) ÷ 0.4 = 5/4; absent. |
| 1,0 | (2/3 − 5/6) × 3/4 = −1/8; absent. |
| 1,1 | 4x + 3 − 15 ≤ x on integers 1..20 gives 1..4; explicitly requested minimum is 1, absent. |
| 1,2 | (7/8 + 2/5) ÷ (3/10) = 17/4; absent. |
| 1,3 | 5x − 12 + 8 ≥ x on integers −10..10 gives 1..10; explicitly requested maximum is 10, absent. |
| 2,0 | (2/3 × 5/6) − 3/4 = −7/36; absent. |
| 0,2 | Unused literal 15. Its reachable declared condition is 3x ≤ 3x + 50; every offered value satisfies it, contrary to unique any-satisfying selection. |
| 2,1 | Unused literal 15. Reachable condition 4x + 3 − 50 ≤ x on 1..20 gives 1..15; minimum 1 is absent. |
| 2,3 | Unused literal 8. Reachable condition 5(x + 6) − 100 ≥ x on 5..25 gives 18..25; maximum 25 is absent. |

All ten errors were reproduced through the unchanged runtime compiler, with an independent `Fraction` evaluator and exhaustive bounded-integer enumeration. Reachable arithmetic of invalid graphs is a diagnostic countercheck, not deletion, normalization, repair, or approval of those graphs.

## Alternatives considered when the snapshot was analyzed

The following was a paper proposal during the running trial, not a change to its source or results. The pure constructor was implemented later in a separate worktree as commit `518a34b`; that later work cannot repair this trial or its historical specifications.

A reasoning-enabled author is supported by existing evidence but remains probabilistic. The earlier Sonnet 4.6 adaptive/high author-only trial compiled all eight typed tasks across the same three job scopes, compared with the current Kimi disabled author producing 3/13 compilable quantitative attempts. These are different generations/configurations and denominators, not a causal comparison. Earlier author latencies were 76.761s quantitative and 64.909s mixed, versus the approximately 13–18.5s author times root reported in this trial. Reasoning may improve arithmetic/graph formation while consuming more of the fixed 240s worker deadline; it cannot structurally guarantee correct offered answers. No additional call is proposed as already approved.

The stronger deterministic mechanism is a NEW task-only contract: the model supplies the mathematical task and assignment metadata; code derives the key and all four offered numbers. It directly removes the seven observed no-answer failures from the model's responsibility. Keep existing invalid-graph rejection: the remaining three invalid graphs do not become valid merely because choices are generated.

A minimal first subset can retain the existing bounded flat graph, units and roots while removing provider `choices`; scalar tasks initially require the existing explicit bounded integer interval (not the choice-dependent offered domain). A pure constructor validates the complete task before choosing options. For exact values it calculates the exact result and forms a finite, documented candidate pool from one-operation substitutions, operand reversal only for noncommutative operations, and omitted-step results. It filters undefined/oversized results, the true value and rational equivalents, and fails closed unless three distinct task-relevant error results remain. No arbitrary distractor filler or fabricated learner-error attribution is needed.

For scalar conditions it exhaustively evaluates the stated domain. Any-satisfying uses one satisfying value and three non-satisfying domain values, failing when that pool is insufficient. Minimum/maximum derives the actual extremum, then takes distinct competing domain values around the true boundary and other satisfying nonextreme values, validating all against the *complete* explicit selection operation. Insufficient bounded domain or no solution fails. Deterministic ordering uses only the validated task and final option bytes, not a provider key.

The constructor then invokes the existing compiler with its own four options. Its private provenance retains the final closed spec; sanitizer/final-release recompilation and the immutable auditor remain unchanged. This guarantees exact answer inclusion, one selected answer and distinct numerical meanings for the admitted closed subset; it does not guarantee pedagogical quality, appropriate difficulty, arbitrary mathematical coverage, or broad prose correctness. Those remain prospective review requirements.

Likely touchpoints after separate approval: a small new pure choice-construction module with semantic tests; `quantitative_authoring.py` for a separately named task-only wire variant and trusted construction; `native_output_contracts.py` for its nonrecursive shared schema; a clearly opt-in `question_generation.py` route. Keep historical mixed_v1 behavior and frozen specs untouched. No changes are needed to loosen existing compiler, solver/auditor or release gates. A later separate compact affine-condition variant could remove graph-reference burden, but is not necessary to test the missing-choice mechanism and should not be bundled without review.

Meaningful offline checks: exact rational coverage for all four operations/nesting/sign/zero; mutation candidates cannot contain the answer or equivalents; bounded pool exhaustion/overflow/undefined arithmetic fail closed; strict/inclusive/equality/inequality and minimum/maximum proofs over every small domain; multiple satisfying values allowed only as wrong *nonextreme* choices under explicit extrema; any-satisfying requires three actual false options; invalid graphs remain rejected; all five generated fields and private provenance survive the real sanitizer/audit/release path. Any subsequent live qualification needs newly generated tasks and independent pedagogical review, without rescuing this failed trial.
