# Trusted pair endpoints and requested-meaning qualification

The previous fixed-slot trial completed structurally but failed semantic criteria:
80/80 correctness labels, 118/120 pair labels, ten valid retained, and one defective
item admitted. Its two pair errors had distinct explanations: a reason discussed
the wrong pair's options, and an arrival-time question was treated as asking about
written notation. All previous inputs, gold and results remain unchanged. The
exact tested solver module is archived as
`slot_original_complete_question_solution.py` with SHA256
`06088bb4b1c1aee71b5092149ce67e4655a7a249ed6d2027c6d1e8979e3f9c1c`.

## Joint candidate change

Keep the fixed `complete_choice_solver_v3` schema byte-identical. Input now also
contains a trusted `choicePairs` object: each of `ab,ac,ad,bc,bd,cd` supplies the
exact leftChoice/rightChoice strings for that pair. The model compares those
explicit endpoints; output remains the same fixed reason/relation slots. This
reduces the need to reconstruct six references from four lettered choices.
Caller-supplied pair metadata is ignored. Tests verify byte-preserving endpoints
and unchanged payloads under every authored-key and input-order variation.

The existing representation exception is narrowed in the slot prompt: merely
explaining how an answer is parsed or displayed does not make equivalent answer
meanings distinct. Literal differences matter when the stem explicitly asks the
learner to distinguish that written form. When the question asks for a value,
claim or action, compare that underlying meaning. This is a general task rule,
with no control answers or case-specific hints in the prompt. The original
same-wrongness distinction remains unchanged. Legacy/default prompts are unchanged.

This combines two changes to address two observed defects. It is not an isolated
causal test of either change, and no successful result will be attributed to only
one of them.

## Frozen evaluation and stop rules

Four candidate native calls, one per unchanged original five-item batch, on the
same twenty independently reviewed cases. Gold labels and wording remain exact;
these are reused diagnostic controls, not new held-out cases. No author key, gold,
or case identifiers enter the model request. No baseline/author call is added.
Use the actual production builder, native v3 schema/adapter, slot decoder, strict
JSON/native validation and existing veto logic.

Sonnet 4.6, temperature 0.2, thinking disabled, 6,000 output tokens, 75-second read
timeout, three-second connect timeout, one SDK attempt. No retries, repairs,
replacements, after-output relabeling or additional calls. Stop immediately after
transport, abnormal completion, strict JSON/schema, coverage/identity or reason-
bound failure. Preserve unattempted cases in the four-call planned denominator.
Continue after semantic errors to retain the complete frozen semantic denominator.

Qualification requires four contract-valid calls, ten valid controls retained,
ten defective controls rejected for the expected reason, eighty correct choice
labels, 120 correct pair labels, no uncertainty, and actual reason-before-verdict
order for all eighty choice and 120 pair objects. Record explicit endpoint
coverage, slot identities, reasons, labels, usage and call latency. Report every
failed item even when its final eligibility happens to be right.

Source/input/schema/gold and prior-capture hashes are frozen before dispatch.
`endpoint_experiment.py` defaults to synthetic-gold validation without provider
calls. Parent approval is required before `--run`. One sample per reused batch
cannot establish broad accuracy, deterministic semantics or fresh-author yield.
