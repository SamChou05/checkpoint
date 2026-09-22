# Small matched verifier model comparison

This prospective diagnostic asks whether Opus 4.6 improves specific reviewer
failures while staying inside the existing 75-second call limit. The only paired
request difference is modelId: Sonnet 4.6 versus Opus 4.6. Both explicitly disable
thinking, use temperature 0.2 and 6,000 output tokens, and receive the same current
native reviewer prompt/schema and exact selected historical question/solver text.
No author, new solver, repair, model-agreement activation or production mutation
is part of this experiment.

Four calls are planned: batch 0 Sonnet then Opus; batch 1 Opus then Sonnet. Each
batch contains three items. This keeps output and simultaneous reasoning load
smaller than the prior five-item pipeline batches without introducing a second
axis within the paired comparison. It does not establish that smaller batches
alone improve correctness or that the model meets full worker throughput.

Batch 0 contains the unchanged bus question (both 25 and 26 rides make the pass
cheaper; the question does not ask for the minimum), the unchanged semicolon
question with multiple defensible sentences, and a valid 30 mpg control. Batch 1
contains the valid blue:white paint ratio, the valid population-growth item with
a 17.4% distractor, and a valid 78.4 weighted-grade control. The first two require
negative decisions; the other four require correct positive decisions and sound
main/all-choice teaching. The paint and population items are feedback defects,
not wrong-key questions. `controls-draft.json` records exact source captures,
objects, hashes, expected decisions and independently reviewable counterexamples.

Only top-level indexes are changed to local 0..2. Every historical prompt, choice,
choice order and solver reason/judgment is preserved. These solver records were
actually produced in earlier trials and include known errors; they are not new
independent evidence. A common explicit mixed-topic goal removes irrelevant
single-domain scope mismatches. All items are self-contained; no source document,
previous-question coverage, authored answer/explanation, old reviewer feedback or
gold assessment is sent to either model. This controlled recombination is shared
between arms and is not a byte-for-byte replay of an old complete request.

Qualification requires all four responses to complete normally within the frozen
transport limits, strict native JSON/schema and exact index/choice coverage, both
bad items correctly rejected, and all four valid items retained with exact keys
and fully sound bounded feedback. Difficulty judgments and downstream floor
acceptance are recorded separately. Any material ambiguity or unsound main or
choice explanation fails content qualification; correct keys alone do not pass.
The negative format provides no reason, so a matching negative disposition cannot
prove the reviewer explicitly identified our intended counterexample. Format or
coverage failures receive no semantic-detection credit.

Independent gold review must be saved before freezing requests. Independent final
review will compare every returned explanation against the predeclared rubric.
All original outcomes remain visible. No post-output label changes, retries,
replacement calls or unused-slot transfers are permitted. Stop the entire trial
on a provider error, non-end_turn or structural validation failure; preserve the
full four-call/six-item-per-arm denominator and any unknown timeout usage. Each
SDK request has connect 3 seconds/read 75 seconds/total_max_attempts 1. No model
warm-up or access-probe generation is added outside those four calls. Save final
JSON and usage, but omit provider reasoningContent text and signatures.

This is a finite model-selection diagnostic, not production qualification,
population accuracy, or proof of deterministic reasoning. Compare exact paired
outcomes and per-call latency/tokens, including failures. If both arms pass, report
that no quality improvement was demonstrated; if either fails, keep the failure.
A successful candidate still needs actual pipeline yield/deadline qualification.

## Why this candidate is feasible, not already proven

The account previously completed Opus 4.6 calls in the September 8 evidence. In the
old two-item author comparison, disabled Opus had five of six independently
supported keys versus Kimi's two of six, but neither arm qualified; this is about
authorship, not proof of reviewer superiority. An older adaptive Opus complete-
solver experiment completed sixteen calls in 3.436–11.881 seconds on mostly
single-item controls, under different legacy prompts and 100-second read limits.
Another adaptive full-pipeline run timed out. These findings justify a bounded
trial, not a model switch or an assumption about new three-item native latency.
The saved Opus 5 comparison plan still records an unaccepted model agreement; this
trial proposes no account action or Opus 5 use.

AWS currently lists Opus 4.6 as active, with native structured outputs and Converse
on bedrock-runtime, including the US cross-region ID used here.
[Official Opus 4.6 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-4-6.html).

The shared native request uses Converse outputConfig.textFormat. AWS documents
that unsupported schemas fail validation, new grammar compilation can take minutes,
and compiled grammars are cached for 24 hours. Thus a first native request can
still fail this trial's unchanged 75-second operational bound; there is no hidden
warm-up allowance. Schemas encode transport constraints, while semantic and batch
identity checks remain separately measured.
[Official structured-output documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html).

AWS supports adaptive reasoning for both models; this comparison explicitly uses
disabled thinking to isolate model identity under the existing low-latency
configuration. Adaptive/high is not repeated after the failed pipeline switch.
[Official thinking-mode documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/claude-messages-adaptive-thinking.html).

The current local native-model allowlist excludes Opus 4.6. The evaluator derives
the baseline request through actual production request construction, clones it and
changes only modelId for the experimental provider call. This is not a runtime
allowlist change. A later production candidate would require a separately tested
allowlist addition; documentation of provider support does not bypass that gate.
