# Evidence-based choice audit feasibility — September 6, 2026

This offline experiment did **not qualify a replacement verifier**. A more
structured audit exposed useful contradictions, but the model still promoted
unsupported claims and used citations that did not establish its conclusions.
Nothing from this experiment was added to runtime or deployed.

## Question and design

Could claim-by-claim evidence checking avoid the existing reviewer's tendency
to approve a familiar answer after noticing that the actual question lacks
necessary conditions?

The experiment used the same four unchanged questions and manually curated
evidence packets as the [evidence comparison fixture](../backend/bedrock-question-service/evals/fixtures/question_evidence_feasibility.json):
two persistently invalid questions and two nearby valid controls. It made one
serial call per question to `us.anthropic.claude-opus-4-6-v1`, requesting adaptive
thinking with high effort, 16,000 output tokens and a 100-second read timeout.
Choice order was randomized. The model received the unchanged stem, choices
and supplied evidence; it received no author key, explanation, expected verdict,
case identifier or goal context. There were no retries or second repeat.

The prompt asked the model to list stem requirements, split each proposed
answer into necessary claims, and classify every claim as supported, refuted
or undetermined. It explicitly prohibited treating missing evidence as
refutation, replacing the literal question with a familiar one, or choosing a
plausible answer by elimination. Every positive or negative claim required an
exact quotation and a short deduction. Code required complete **declared**
requirement coverage for every choice, one fully supported choice, and three
choices with a refuted necessary component. Uncertainty alone never refuted a
choice. Code checked quotation integrity and structural consistency; it could
not establish semantic entailment or discover requirements the model omitted.

## Results and formatting confound

All four provider calls completed normally. They consumed 4,733 input tokens,
17,118 output tokens, and 236.920 seconds in total. Every response wrapped its
JSON in Markdown fences despite the request for JSON only. The frozen parser
therefore recorded four format failures and **zero evaluable primary
decisions**. These failures do not count as detecting invalid questions.

This parser is stricter than runtime's `_extract_json_object`, which accepts
an outer Markdown fence. Formatting is consequently a confound in any attempt
to compare primary acceptance rates with the current runtime verifier.

To inspect the substantive result without more model calls, a separately
recorded post-run diagnostic removed exactly one outer fence and applied the
unchanged remaining checks. No inner JSON, citations, claims or primary scores
were edited.

| Control | After removing only the outer fence | Substantive observation |
| --- | --- | --- |
| Invalid: enumerate all matching pairs in linear time | Audit still fails: supported/refuted claims lack evidence | The hash-map answer remains undetermined because index pairs and distinct value pairs have different output bounds. Several claims have no citations, and one purported quote truncates and closes a list that continues in the source. |
| Valid: Boolean pair existence with expected constant-time hash operations | Structural gate accepts the correct choice | Some true complexity assertions are labeled “refuted” because the *method* fails the time requirement. The comparison-sort bound is recalled knowledge; quoting the requested time limit does not establish that bound. |
| Invalid: RAW processing sequence that maximizes recovery | Audit still fails: “supported” claims retain unresolved limitations | The model calls the intended option supported by elimination while admitting missing recovery conditions and missing evidence for the optimal order. It treats aggressive processing as necessarily worse without supplied evidence establishing that result. |
| Valid: nondestructive RAW editing | Structural gate accepts the correct choice | Original-data retention is supported. However, a distractor refutation treats lack of a recovery guarantee as proof that universal recovery is false; that inference alone is invalid. |

The two diagnostic audit failures are not evidence that the model conclusively
detected bad questions: one concerns missing evidence fields and the other
contradictory support labels. The checks blocked those particular outputs,
but that does not establish reliable semantic rejection. The valid controls'
structural acceptance likewise does not certify the truth of every intermediate
claim or the adequacy of its citation.

## What this changes

The audit made important limitations inspectable, and preserving uncertainty
avoided the all-pairs forced answer at the claim level. Nevertheless, a longer
prompt and more elaborate model-produced evidence structure did not eliminate
the underlying interpretation error. Citation presence and an exact quotation
are insufficient: the quoted fact must actually establish the claim, and the
claim's status must classify that claim consistently.

This small failed feasibility test supports evaluating a simpler separation
between the factual assertion, its evidence, and the decision rule before any
runtime promotion. It does not support adding this expensive audit to every
question. The longest call took 98.282 seconds, already beyond the existing
75-second worker read timeout. Manually selected documents also do not qualify
automated evidence acquisition, broad learning goals, bank-fill performance,
or production reliability. Inspection here was performed by the assistant,
not by independent human subject experts.

## Reproduction and evidence

- [Raw four-call capture](evidence/choice-audit-feasibility-20260906.json) preserves exact prompts, context, requested provider settings, raw output, usage, elapsed time, and primary failures.
- [Separate post-run diagnostics](evidence/choice-audit-diagnostics-20260906.json) preserve the fence-only normalization, remaining structural results, inspection notes, and the capture and harness hashes.
- [Offline harness](../backend/bedrock-question-service/evals/checkpoint_evidence_choice_audit.py) performs no deployment and stops on a provider failure. A new output path is required so previous attempts are not overwritten.
- [Eleven targeted tests](../backend/bedrock-question-service/tests/test_evidence_choice_audit.py) check blinding, exact text and citation coverage, multiple supported answers, unresolved distractors, retained limitations, and exclusion of operational failures from detection scores.

```sh
cd backend/bedrock-question-service
python evals/checkpoint_evidence_choice_audit.py \
  --output /tmp/checkpoint-choice-audit-new-run.json --dry-run
```

The dry run plans four calls without invoking the model. The live run used
`--aws-cli-credentials` instead of `--dry-run`; credentials remained in process
memory and are absent from the saved evidence. Local verification passed the
then-current 290-test backend suite, Ruff on the new files, and `git diff --check`.
