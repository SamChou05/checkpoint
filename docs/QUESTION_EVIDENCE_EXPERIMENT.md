# Evidence-assisted answer review — September 6, 2026

Providing relevant evidence to the existing reviewer did **not** resolve the two persistent correctness failures in this controlled feasibility test. Both valid controls were retained, but both invalid controls were also accepted, with and without evidence. The result changes the next experiment: test whether checking individual claims preserves evidence limitations better than a single overall judgment. No new reviewer or model configuration is qualified for deployment by this test.

## Experiment

The same four questions were reviewed in two arms: the current independent solver plus reviewer, and that unchanged pipeline supplied with additional reference documents. Opus 4.6 adaptive/high used a 16,000-token allowance. Eight complete reviews consumed 16 provider calls; none failed or timed out. Order was randomized with seed 9062026. Exact questions, reference packets, prompts, responses, settings, and diagnostics are in the [saved evidence](evidence/evidence-review-feasibility-20260906.json).

The controls are deliberately selected regressions, not a representative production sample. Each evidence packet was supplied to both an invalid question and a valid nearby question. The model never received expected acceptance labels, author keys, or author explanations. Source selection and summaries were prepared and inspected by the assistant, so the test evaluates evidence use, **not automated evidence acquisition**. A single run cannot establish stable accuracy.

| Control | Expected | Without evidence | With evidence |
| --- | --- | --- | --- |
| Enumerate all matching pairs in O(n) time | Reject | Accepted | Accepted |
| Return only whether a matching pair exists, expected hash operations | Accept | Accepted | Accepted |
| Uniquely optimal recovery sequence for unspecified RAW clipping | Reject | Accepted | Accepted |
| Camera Raw preserves original data while storing adjustments separately | Accept | Accepted | Accepted |

## What the evidence contained

For the pair questions, Python enumerated matching distinct-index pairs for arrays of zeroes with target zero. Lengths 2, 4, 8, 16, and 32 produced 1, 6, 28, 120, and 496 pairs. Each count agrees with n(n−1)/2. Boolean existence remains true at every size; enumerating the output is a different task. These are executed examples and a closed-form count, not an implementation timing benchmark.

For photography, official Adobe documentation distinguishes raw data from its rendered preview, describes nondestructive adjustment storage, allows flexible Develop adjustment order, and describes limited highlight reconstruction. See [Camera Raw introduction](https://helpx.adobe.com/camera-raw/desktop/get-started/overview-and-setup/introduction-camera-raw.html), [Develop adjustments](https://helpx.adobe.com/lightroom-classic/desktop/help/applying-adjustments-develop-module-basic.html), and [color and tone controls](https://helpx.adobe.com/camera-raw/desktop/using/make-color-tonal-adjustments-camera.html). These references do not establish whether the particular photograph retained recoverable data or a uniquely optimal adjustment order.

## Observed failure mechanism

The solver recognized that enumerating all index pairs can exceed linear time. The reviewer nevertheless treated the bound as excluding output work and approved the original linear-time claim. Its final explanation dropped the necessary output-size limitation. This is evidence being overridden, not evidence being unavailable.

For RAW editing, the solver acknowledged that recovery is limited and adjustment order is flexible. The reviewer reinterpreted the question as a request for a reasonable workflow, despite its stronger claim about maximizing recovery, and approved an explanation that presumes near-clipped recoverable data. The literal question and a more defensible rewritten question are different items.

An explicit solver “impossible” or “underdetermined” flag alone is not a safe universal rejection rule: those conclusions can themselves be correct offered answers. Any stronger gate must still allow a well-posed question whose unique answer is that the information is insufficient.

## Follow-up under test

A separate offline experiment audits the necessary claims in every unchanged choice against the provided premises and evidence. Its parser requires complete coverage and exactly one supported choice, with the other three refuted; unsupported is not treated as false merely because a source omits it. This changes the decision structure rather than simply adding another unaided critic. It must retain valid controls as well as reject invalid ones, and it remains a feasibility experiment until fresh questions and automatic evidence acquisition are tested.

This direction is informed by research on [external tool feedback](https://arxiv.org/abs/2305.11738), [independent verification questions](https://aclanthology.org/2024.findings-acl.212/), and [checking individual factual claims against sources](https://aclanthology.org/2023.emnlp-main.741/). Those studies motivate experiments; their benchmarks do not qualify Checkpoint's current implementation.

## Follow-up results

The [separate claim-by-claim audit](QUESTION_CHOICE_AUDIT_EXPERIMENT.md) also remains unqualified. Its four primary calls all failed a stricter JSON-format rule than the production parser uses. Separately labeled diagnostics after removing outer Markdown fences found support-with-limitations contradictions, citation gaps, and inconsistent claim labels. These failures are not credited as successful detection. They show that evidence coverage and overall answer judgments still need independent scrutiny.

An additional bounded probe used the **same original solver and reviewer prompts** with Opus 4.6 adaptive/**max** and the same 16,000-token cap on the four unaided controls. It again accepted both invalid and both valid questions. All eight returned responses contained a reasoning block, all ended normally, and the largest used 3,179 output tokens. Total: 6,977 input tokens, 10,542 output tokens, 181.953 seconds. The [probe capture](evidence/max-reasoning-probe-20260906.json) preserves raw decisions and metadata. This is evidence against a missing thinking setting or exhausted output cap explaining these particular failures; it is not a comprehensive model benchmark.

The opt-in maximum effort setting is supported for the known Opus 4.6 identifiers per [AWS's adaptive-thinking documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-adaptive-thinking.html). Defaults remain unchanged. Diagnostics record only whether reasoning blocks were returned, not their contents.

The comparison CLI now supports selecting an arm, effort, and earlier prompt snapshot. For example, from the backend service directory:

```bash
python evals/checkpoint_evidence_eval.py --arm unaided --effort max \
  --prompt-snapshot ../../docs/evidence/evidence-review-feasibility-20260906.json \
  --output /tmp/new-max-probe.json --aws-cli-credentials
```

This creates a new bounded run; it does not overwrite or reinterpret the original observations.
