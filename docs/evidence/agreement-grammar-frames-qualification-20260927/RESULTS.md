# Strengthened agreement frames: bounded live qualification result

**Official outcome: FAIL content qualification.** The fresh one-shot worker
returned all five original slots in exactly three Converse calls, but only
four of five items met the prespecified minimum difficulty of 2 **from both
independent blind reviewers**. Reviewer B rated original arithmetic slot 1
at level 1; reviewer A rated it 2. This is a 4/5 strict content result even
though the worker's difficulty metadata and its model reviewer rated that
item 2. No post-hoc override, extra model call, top-up, deployment or route
activation occurred.

## Frozen trial and mechanical result

- Candidate source: `db3e10e4098f5fdad13ceb73616603417ef6fde1` on main,
  executed in isolated branch `codex/agreement-grammar-frames-qualification`.
  This changes the closed agreement frames and native author prompt/schema.
- Historical mixed five-slot request: canonical SHA-256
  `212cea7d53ddefe17fbe8f2459705b46b871793e62e0e58b56cc11e3626e63ae`;
  three exact-arithmetic slots and two standard-written-English agreement
  slots at minimum difficulty 2. Same request, model transport and settings
  as the prior calibration trial; agreement route opt-in only in this run.
- Frozen plan SHA-256
  `23c3c0bca2ecfc185ca5998812c3c32bd89e1bec5a939260f6877e449664e742`;
  harness SHA-256
  `553d9ae9e49270dc198dd25fe082eed8238f4261b648022cb43046935758b321`.
  Root and an independent reviewer approved the exact hashes before AWS.
  The launch precheck passed with 898 seconds credential lifetime and one
  read-only STS request. Execute made its one permitted STS request.
- Original slots **0–4 all returned**. Three actual Converse calls were the
  mapped native author, answer-blind English solver and authored-teaching
  reviewer, in that order. Six call slots were reserved; the last three
  stayed unattempted. There was one author pass, no fallback, retry, repair,
  top-up, second job or resume. Whole execute time, starting before capture
  creation and credential export, was **93.522787 seconds** under 240.
  Reported usage was 10,570 input and 8,133 output tokens across three
  calls. Capture SHA-256:
  `de6c6c160fbf36772e78317f060062f8955433f0d850f384f879482f3536dc4f`.
- The native author schema was 2,757 bytes, SHA-256
  `2a11817d040fe0fb34a413604b9b8ee3118fb631944c2bbf038c54076a95156d`.
  JSON Schema Draft 2020-12, local botocore Converse input-shape validation,
  43 frozen source-file hashes and all 12 socket-free harness tests passed.
  These offline checks are provenance checks, not a second live success.

The earlier difficulty-calibration live run remains **5/5 mechanically and
4/5 blind level-2 consensus, FAIL**. Its capture SHA-256 is
`f8a912da0c29df783303d9afca5f0af0b559408f80ff6b37eae7755a285ff145`.
This run is separate and does not turn that failure into a pass.

## Locked answer-blind content review

The reviewer-only worksheet had five readable items, randomized opaque IDs,
item order and displayed choice order. It contained no keys, source slots,
model ratings or explanations. The private mapping was sealed until both
reviews locked. Worksheet SHA-256 was
`92a3be8c3a9508866ce0114111adf5083f61aa1806fc66619f1923fe84607ad0`;
review A SHA-256 was
`13e10433e5a94ae09854aeb4d2b435a150b34550591a35b4c0aeeb2e34c9534a`;
review B SHA-256 was
`da3d43136d149009c0b2d71487f9e58ba5ceeb815e00892baa5874eaf974e22e`.

| Original slot | Task | A difficulty | B difficulty | Both ≥2? |
| --- | --- | ---: | ---: | --- |
| 0 | Fraction addition then multiplication | 2 | 2 | Yes |
| 1 | Fully parenthesized integer expression | 2 | **1** | **No** |
| 2 | Minimum integer satisfying a strict inequality | 2 | 2 | Yes |
| 3 | Singular/plural subjects with nearby nouns | 2 | 2 | Yes |
| 4 | `Every` subject and compound subject with nearby nouns | 2 | 2 | Yes |

Both reviewers independently selected the code-supported answer on all five
items, found all **30 of 30** unordered within-item choice pairs meaningfully
distinct and judged every stem self-contained. Reviewer B's level-1 judgment
for slot 1 is plausible: despite four arithmetic operations, the expression
states the exact order with full parentheses and its distractors derive from
simple substitutions at the last operation. Difficulty is subjective, but
the prespecified per-reviewer gate does not allow us to discard that rating.
The model teaching reviewer rated slots 0–4 at 2, 2, 3, 3 and 3, while both
blind reviewers rated slots 2–4 at 2. This sample shows that the model
reviewer's numeric difficulty judgments did not reproduce the blind
ratings, and its level-2 rating did not catch B's level-1 judgment on slot
1. The model rating therefore cannot substitute for the locked gate.

The worksheet did not disclose the trusted objectives. After lock, the audit
verified exact trusted assignments: slots 0–2 match *Evaluate an exact
rational expression or explicit bounded condition*; slots 3–4 match *Apply
subject-verb agreement or unambiguous pronoun reference*. The two English
items test the agreement side of that `or` objective. The blind reviewers'
visible-objective judgments were favorable, but those judgments alone could
not establish the hidden assignment; the post-lock source check did.

## Answer, teaching and novelty audit

`audit_locked_capture.py` recompiled **all five learner fields for each of
five items** from the captured trusted quantitative specs or selected closed
agreement tasks and matched both the returned learner payload and its
provenance. It independently evaluated the quantitative keys as 10, 20 and
7, and checked the agreement keys as `checks; practice` and
`receives; prepare`. Each key appears once among its four choices. Every
per-choice feedback map covers the four literal choices, and no explanation
or feedback refers to a displayed position label; teaching survives choice
shuffling.

The main explanations and all 20 per-choice feedback entries are supported
by the stems and trusted rules. For slot 0, the fraction calculation and
described numerator/denominator mistakes are correct. For slot 1, the
subtraction, addition, division and multiplication yield 20; its three wrong
answers do follow the stated final-operation substitutions, although both
reviewers noted that some distractors have weak diagnostic plausibility.
For slot 2, 3x + 7 > 25 first holds at integer x = 7 in the stated domain;
the explanation checks every smaller domain integer. For slots 3–4, the
nearby `near ...` nouns do not control the verbs: `coach` and `Every guest`
are singular; `players` and `Maya and Theo` are plural. Each wrong pair's
feedback identifies the mistaken clause or clauses without making an
unsupported exclusion.

Batch novelty remains limited. Both blind reviewers identified roughly
three visible task forms among five items: slots 0–1 share the same
`Let q ... exact value` framing and fully parenthesized expression process;
slots 3–4 share a two-blank agreement pair with a `near` phrase in each
clause; slot 2 is a different inequality/minimum-integer task. Slot 4 adds
`Every` and a compound subject, so its rule set is richer than slot 3, but
the visible syntax and tested nearby-noun trap still repeat. The two
agreement source scenes are distinct and the recorded novelty selector did
not exhaust its variants. The request had empty prior bank history, so this
run cannot establish history-driven bank diversity or resistance to
repetition across future batches. We report this separately from the
prespecified per-item difficulty failure.

The opt-in route is **not qualified** for activation from this evidence.
The fresh run shows the strengthened grammar frames can return two
unambiguous, level-2 agreement items in this sample, but does not establish
deterministic quality or a 5/5 content pass for the full mixed worker.
