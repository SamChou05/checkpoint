# Choice semantics investigation, September 21, 2026

The main distinction is between **four different strings**, **exactly one true
answer**, and **three meaningfully different distractors**. These are separate
properties. Current deterministic identity checks enforce the first. The
complete-choice solver enforces its own declarations about the second. Neither
enforces the third, even when the solver reasons perfectly.

For `What is 2 + 2?`, the options `4 / 5 / 5.0 / 6` have one correct answer and
three false answers. A truthful solver therefore passes this item. Two wrong
options are the same proposed number. This was reproduced offline and in actual
model review, rather than inferred from an unusually difficult subject.

## Source and scope

The final offline replay and fresh live experiment use current upstream revision
`7d9cc6ad93128893fb52f1a0183fea620b3b00ac` in the isolated investigation worktree.
The original user checkout was 28 commits behind and contains unrelated edits;
none were changed by this subtask. The source hashes in the JSON evidence identify
the actual runtime modules. Old reports about deployed policy 1 must not be used
as today's deployment state; the parent investigation has a fresh AWS snapshot.

No production file, deployed function, question bank, or learner state was changed.
No external messages were sent. Four live calls were made; no retries or follow-up
calls occurred. This subtask supplies reproducible diagnostics, not a prompt or
model promotion.

## Fresh controlled reviewer experiment

[Frozen plan](reviewer-plan.json) and [unaltered capture](reviewer-capture.json)
contain exact requests, control ground truth, source hashes, settings, raw
responses, usage, and strict-parser results. Eight fixed cases test arithmetic,
equivalent wrong numbers, equivalent wrong verbal choices, equivalent right
answers, multiple true properties, no correct answer, case-sensitive Python
literals, and operator-sensitive expressions.

The experiment uses the current `_REVIEW_CORE_PROMPT` in isolation, followed by
the same prompt plus a specific instruction to reject equivalent wrong options
while preserving meaningful literal differences. It does **not** include the
production suffix that presumes an independent solver, invented solver outputs,
an author call, or a minimum-difficulty filter. Call order is baseline, treatment,
treatment, baseline; Sonnet 4.6, disabled thinking, temperature 0.2, max 6,000
tokens, read timeout 75 seconds, and one SDK attempt per call.

**The primary format result is failure in all four calls.** Each response includes
analysis before fenced JSON, so the current strict parser rejects all eight items
in each call. One treatment also emits a malformed JSON object, announces a syntax
correction, and emits another object. These responses ended normally rather than
hitting the token limit. Adding more semantic wording did not fix the output
contract.

Separately, [post-hoc content inspection](reviewer-content-diagnostic.json)
records the judgments the model actually wrote. It inspects every fenced block
and labels the malformed block; no output is repaired or admitted to production.

| Raw semantic declarations, two repetitions per arm | Current core | Explicit diversity |
| --- | ---: | ---: |
| Equivalent **wrong** options incorrectly approved | 4/4 | 0/4 |
| Valid controls retained | 6/6 | 6/6 |
| Multiple/zero-answer controls correctly rejected | 6/6 | 6/6 |
| Whole responses satisfying current strict parser | 0/2 | 0/2 |

There are eight distinct cases, not 32 independent cases. Both duplicate controls
are simple, selected examples; the results do not establish population accuracy,
advanced distractor quality, or a deployable prompt improvement. The case and
operator controls help rule out the obvious regression of rejecting every pair
with similar text. They cannot certify all subject-specific distinctions.

Total usage: 4,840 input tokens and 5,602 output tokens. Call durations were
15.559, 18.371, 14.908, and 16.088 seconds.

## Offline deterministic boundary experiments

[Probe source](../../../backend/bedrock-question-service/evals/checkpoint_choice_reliability_probe.py)
and [results](offline-results.json) contain ten explicit controls:

- Exact duplicate wrong text is rejected before semantic review.
- Two equivalent wrong-option sets pass with truthful solver declarations.
- Two supported choices, zero supported choices, and a different supported key
  trigger the appropriate complete-solver vetoes.
- Case and operators remain meaningful in literal-code questions.
- A deliberately wrong but well-formed solver declaration passes the declaration
  gate. This is a constructed boundary demonstration, not an observed model error.

The existing identity contract deliberately does not lowercase, remove symbols,
singularize words, or erase internal spaces. Doing that to catch paraphrases
would corrupt valid distinctions such as `True` versus `true` and `n + 1` versus
`n - 1`. Semantic equivalence must be judged in the question's context.

## Historical raw-output replay

All old model outputs and old human/assistant assessments remain attributed to
their original captures. Their factual assessments are reused, not independently
recertified. No sample is described as a current production error rate.

The September 6 author-only paired experiment already directly tested the
intuition that a simple prompt should work better:

| All saved candidates | Simple prompt | Full author prompt |
| --- | ---: | ---: |
| Raw questions | 30 | 30 |
| Historically assessed as having the unique authored key | 24 | 26 |
| Accepted by today's deterministic sanitizer | 25 | 30 |
| Accepted despite the historical invalid-key assessment | 4 | 4 |
| Historically valid key excluded by today's sanitizer | 3 | 0 |

The three otherwise valid exclusions are all stems over 320 characters. This is
only sanitizer admission; the semantic solver/reviewer can still exclude its
survivors. It shows both that simpler prompting does not guarantee semantics and
that formatting/length eligibility must be separated from key correctness.
The simple prompt lacked the expanded rubric and length instructions, so this is
not a clean estimate of the effect of prompt length alone.

In the separate September 8 author-model comparison, 12 saved candidates were
assessed with answers hidden. Seven had a uniquely warranted choice. Joining
exact stems and exact choice multisets to the saved full author/solver/teaching-
auditor trial gives six returned items, including two independently assessed as
having unsupported keys (`q05` and `q08`). All six failed assessor A's criterion
of three plausible, distinct distractors. This uses the opt-in authored-solution
contract from that trial and must not be presented as current deployment output.
The two concerns are contextual meaning failures: conflating an indefinite
ingredient amount with generic reference, and extending general propagation
guidance to a damaged cutting in water. Agreement across model stages did not
establish that the exact offered action or explanation was warranted.

As a positive control, today's parser revalidates the actual saved Sonnet solver
response on five fixed, simple cases. Its declared supported-choice counts are
`1, 0, 0, 2, 1`, matching all five predeclared cardinalities. The solver can catch
these defects; the issue is neither that the counting gate is absent nor that
every model response fails.

## Implications for the production fix

1. Keep syntax/shape enforcement separate from factual and pedagogical quality.
   The live content diagnosis still had zero usable structured responses.
2. The existing reviewer is the place to test explicit contextual pairwise
   distractor diversity; another model stage is unnecessary for this hypothesis.
   The four calls support that narrower hypothesis but do not qualify it for
   production. Repeat with the actual complete pipeline and native contract,
   including held-out domains and valid lookalike choices, before promotion.
3. Do not broaden string normalization or infer semantic truth from matching
   declarations. Both produce false confidence; lossy normalization additionally
   destroys real answer differences.
4. Keep denominators for raw author validity, structural eligibility, solver
   vetoes, reviewer content, and final admitted items distinct. In particular,
   do not report a semantic win after recovering JSON that production rejects.

## Verification

Current-upstream runs passed 10 choice-identity tests, 16 complete-solver tests,
12 complete-verification integration tests, and four new probe tests. Ruff
`--isolated` passed for both new backend files and the experiment runner.

Offline reproduction (no network):

```sh
cd backend/bedrock-question-service
python3.12 evals/checkpoint_choice_reliability_probe.py --output ../../docs/evidence/choice-reliability-20260921/offline-results.json
python3.12 -m unittest discover -s tests -p 'test_choice_reliability_probe.py'
```

The live runner refuses to overwrite an existing capture or change its frozen
plan. Replaying the saved evidence does not require AWS credentials.
