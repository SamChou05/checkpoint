# Source-aware answer and teaching checks with separated inputs

The [previous acquired-evidence trial](QUESTION_CITATION_DISCOVERY_RESULTS.md)
completed retrieval but did not establish better factual detection. Its review
input also forwarded a model-selected target, search query and rationale. The
butter rationale contained a false generalization and targeted a correct claim;
the reviewer attacked that claim while missing the misleading introductory one.
That is consistent with influence from the supplied hypothesis, not proof that
the hypothesis caused the mistake. Both prior arms saw it.

This experiment changes the information flow. A source-aware complete-choice
solver sees the exact question and choices, goal and captured passages, with no
authored key, explanation, difficulty, search hypothesis or earlier verdict. An
independent teaching call sees the unchanged full explanation and same item and
evidence, with no first-solver output or search hypothesis. The server combines
their judgments; the second call cannot waive a first-call veto. These mirror
the existing answer/teaching stages rather than adding an approval vote.

The candidate uses the existing complete-choice reasoning instructions and a
fixed A–D response object. Evidence is referenced by small IDs assigned by the
server. Every ID maps to unchanged consecutive text with its original source
offsets and hash. Joining the units reproduces each previously selected span
exactly, in order. Source extraction limitations and omitted text stay visible.
No model must retype a long target, choice or source quote. A valid reference
proves identity, not that the passage supports the stated judgment.

Two primary research results motivate, but do not qualify, this intervention.
[Anagnostidis and Bulian](https://arxiv.org/html/2408.11865v1) found that supplied
answer advocacy influenced MCQ predictions in Llama2, Mixtral and Falcon even
when its explanation was incorrect; critical prompting was insufficient in
their experiments. [Chain-of-Verification](https://aclanthology.org/2024.findings-acl.212/)
separated verification answers from draft content and reduced hallucinations on
its factual QA and generation tasks. Neither study tests this application, these
model versions, or this exact acquired-source teaching procedure.

## Frozen comparison and scoring

Use all four unchanged v2 controls and the exact already acquired records and
selected offsets from its terminal local capture, byte SHA256
`f136a693f4fef8e72a6217924d1984021c0bbab1a46d3b4853fc60fe4d2f5a27`.
There is no new search, fetch, passage selection, question repair or generation.
The prior capture supplies data, never a previous review verdict as a new result.

Each case receives one fresh old-review call and two independent candidate
calls. The old request is unchanged from the actual v2 source arm. Alternate
whether it runs before or after the candidate pair. All calls use Sonnet 4.6,
disabled thinking, 6,000 output tokens, temperature 0.2 and their frozen native
schemas. Retain the 300-second offline allowance for possible schema compilation;
this does not qualify the production 75-second read window. Cap at 12 calls,
65,536 serialized input bytes per call, no retries and zero acquisitions. Reuse
the existing observer, durable progress capture and terminal-failure rules.

Prospective success on this diagnostic requires all of the following:

- Reject the dough's authored key for the actual second-reference defect.
- Retain the butter's correct key while identifying its misleading
  generic-versus-unspecified-reference teaching, without objecting to the correct
  later definite reference.
- Retain the supported hotel and plant questions with supported full mains.
- Supply defensible judgments for all four choices and the material teaching
  claims; erroneous objections do not receive factual-catch credit.

The application separately records malformed output, uncertainty, declared
rejections, key disagreement, main support, material issues and difficulty.
Acceptance requires exactly one supported choice, every rival refuted, exact
authored-key agreement, supported main, empty issue lists and diagnostic
difficulty at least 2. Independent assessment checks the actual reasoning, not
just these labels. Run both candidate checks for this diagnostic even when the
first vetoes; neither depends on the other's output. There are no verification
stamps or question-bank writes.

This is a combined workflow comparison, not a rationale-only ablation or a
cost-matched comparison: the candidate changes input isolation, output references,
task separation and call count. Previously selected passages may themselves
reflect biased discovery. Empty reference lists are recorded, not fabricated or
treated as source-backed proof. Any supported improvement on these four selected
level-2 controls would justify fresh-content testing across additional goals and
challenge levels, not a production promotion or a general accuracy claim.

Plans and captures containing source passages remain local. Public results must
distinguish a derived summary from raw evidence, preserve exact original hashes,
and report semantic findings separately from output-format success. No deployment
or production model/default change is part of this experiment.

## Source validation

The full backend repeat passed 954 tests with no skips, including 17 new tests
for isolation, exact source units, declared vetoes, frozen requests, failure
handling and replay. The initial full run had one error in the unchanged
`test_trusted_child_stderr_and_transport_flood_fail_closed`: its diagnostic stdout
was empty. That test passed on its own and the unchanged full repeat passed; the
initial failure's cause has not been established. Ruff, Python compilation,
independent code review and the whitespace check passed. Both new native schemas
and Converse request structures validated offline against jsonschema and botocore.
An actual-origin dry check reconstructed all 44,915 selected source characters
and their original offsets/hashes, with 274,952 serialized request bytes in total.
These checks establish local contracts, not live semantic correctness.
