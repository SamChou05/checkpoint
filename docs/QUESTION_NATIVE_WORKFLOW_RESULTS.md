# Fresh native workflow: complete capture and assessment

The September 10, 2026 trial completed, but **does not qualify the current
pipeline for correctness or the requested learning challenge**. All 18 provider
calls ended normally below the 6,000-token ceiling. Twelve questions reached the
bank and the real Swift delivery path. Two independent assessors agreed on nine
unique supported keys, five items with supported keys and complete teaching,
and one useful item under the prospectively fixed level-three criterion.
Uncertainty and assessor disagreement are preserved; exclusion from these
agreement counts does not mean every other item is definitely false.

The trial exercised source revision `661751de3fa0a55fc990be155cb3f6dad5246849`,
whose runtime matches candidate `2aa085a`. It used native structured output,
Kimi K2.5 authorship, Sonnet 4.6 solving/review, disabled thinking, temperature
0.2, and reviewer-written teaching. It did not change production settings,
verification policy or deployment. The full [prospective protocol](QUESTION_NATIVE_WORKFLOW_QUALIFICATION.md)
and original [frozen plan](evidence/native-workflow-20260910/plan.json) remain
available. This is one bounded run across three selected goals, not a production
error-rate estimate or a controlled comparison against the previous revision.

## Generation, delivery and learning quality are separate

| Goal | Requested | Raw drafts | Returned / bank / client | Supported key and all teaching, both assessors | Useful at requested challenge, both assessors |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sound intensity and decibels | 5 | 8 | 4 / 4 / 4 | 2 | 0 |
| English conditions and scope | 5 | 10 | 3 / 3 / 3 | 1 | 0 |
| Plant water transport | 5 | 7 | 5 / 5 / 5 | 2 | 1 |
| Total | 15 | 25 | 12 / 12 / 12 | 5 | 1 |

The runtime path was 25 raw occurrences → 24 sanitized → 22 final-review inputs
→ 12 returns. One stem exceeded 320 characters, two items had multiple declared
supported choices, and ten failed the assessed difficulty floor. There were no
unparseable author calls, transport failures, unknown-dispatch calls or unknown
usage. Partial delivery remains three unfilled requested slots; it is not a
full-bank success.

All 18 responses stopped with `end_turn`, using 414–1,793 output tokens each.
Known usage was 52,500 input and 18,352 output tokens. Serialized request size
peaked at 21,486 bytes against the 32,768-byte limit. Observed SDK intervals
ranged from 4.41 to 24.40 seconds; those are per-call measurements, not complete
user-perceived latency. Every isolated worker was reaped and its process group
cleaned. The [operational audit](evidence/native-workflow-20260910/operational-audit.json)
retains individual observations.

The native schema changes were actually exercised: all 25 author rows emitted
prompt, explanation, answer, then choices; all 96 solver choice rows emitted
choice, reason, then judgment. This confirms the intended field order on this
run, without demonstrating that it improved correctness. JSON syntax and
structure were not the limiting failure here.

Exact network-disabled replay matched the whole capture. The offline bank
helper exercised preparation, atomic claim and repeat claim. A real Swift
capture test then passed with one executed test and no skips: decoding,
whole-batch sanitization, persistence/restore, and feedback composition retained
all twelve questions and exported all 48 actual composed displays. The exported
attachment binds the exact bank-fixture hash. This checks the client data path;
it does not exercise screen rendering, AnswerGrader execution, blocking apps,
or deployed queue/refill operations.

## Independent assessment

Both assessors saved raw-stem and choice judgments before seeing authored keys,
explanations, solver/reviewer outputs or item survival. They separately assessed
the client stems/choices before seeing their keys and teaching; that client
packet necessarily disclosed retention. They then assessed every authored
key/main and every final main and composed display. Assessor A began without
parent history. Before raw phase one, B knew the protocol and aggregate
operational counts but no item-level answers or outcomes. All four phase-one
files were frozen before phase two. These are independent agent assessments,
not a human subject-expert panel; shared errors remain possible.

The [exact assessment join](evidence/native-workflow-20260910/assessment-join.json)
preserves every raw occurrence and ties each client item to runtime operation
and return index, exact stem, choice multiset, key and teaching. Raw and client
IDs are separately shuffled; equal `qNNN` labels across packets do not identify
the same question. Its [reproduction script](evidence/native-workflow-20260910/join-assessments.py)
checks packet/input hashes and complete item/choice coverage. No assessment
was overwritten during reconciliation, and no root adjudication increased
the agreement-based numerator.

For raw keys, both assessors found 19 uniquely supported, two wrong and two
ambiguous; two others had a disagreement. For the twelve client keys, nine
were agreed uniquely supported, one agreed ambiguous and two disputed. Five
client items also had supported complete teaching for both assessors. Across
48 displays, both supported 30, both marked seven unsupported and four uncertain,
and seven had differing judgments. These display observations are correlated:
the same main explanation appears in all four displays for an item.

Useful practice additionally requires goal relevance, distinct plausible
alternatives and assessed difficulty at least three. Only client **q004**
(raw q021), opposing water-potential components, met every criterion for both
assessors: **1/12 retained and 1/15 requested**. Its missing component magnitudes
are intentional evidence for the unique cannot-determine answer, not a reason
to reject it. A judged nine of twelve items uniquely keyed but eleven below
level three; B judged eleven uniquely keyed but eight below level three.
Difficulty remains a rubric judgment, not measured learner performance.

## What the gates actually caught

The two agreed wrong authored keys did not reach the app, but they were not
two accurate correctness diagnoses. The [independent gate audit](evidence/native-workflow-20260910/wrong-key-gate-audit.md)
records their exact paths:

| Raw item | Observed outcome | Interpretation |
| --- | --- | --- |
| q006, in-phase speakers keyed at 83 dB | Solver declared both 83 and 86 supported; code withheld it | Under the accepted in-phase reading, pressure addition gives 86.02 dB. The solver recognized this but also rationalized 83 with an unstated incoherent case. Protective rejection with an inaccurate multiple-answer diagnosis. |
| q020, billing complaint keyed as mandatory acceptance | 321-character stem rejected before any checker | The wrong key was withheld solely on length. No correctness detection credit. |
| q008, fee-waiver exception | Multiple-supported solver veto | Protective against an ambiguous fee policy; its reasons still relied on an implicit default-fee rule. |
| q019, hourly misting and higher turgor | Solver and reviewer approved; reached client q010 | Both independent assessors retained missing-premise uncertainty about timing, humidity and the turgor comparison. |

All ten difficulty exclusions were `valid:true`, matching-key reviews assigned
level two; both blind assessors rated those stems at level one or two. Those
exclusions served the requested challenge floor, not factual correction. No
otherwise correctly keyed draft was separately excluded by the solver in this
capture. That limited observation does not establish a general false-veto rate.

## A reproduced architectural failure

For raw **q001**, the author and solver correctly distinguished sound intensity
from pressure. The final reviewer, call 5/index 2, changed the main explanation
to claim lower **sound pressure level**. That newly generated claim is wrong:
equal pressure has equal SPL at a common pressure reference; different customary
air/water references do not justify its asserted lower SPL either.
[National Research Council reference](https://www.ncbi.nlm.nih.gov/books/NBK236684/).

The key stayed supported, while the faulty main reached every client **q008**
display unchanged. The [complete trace](evidence/native-workflow-20260910/feedback-error-trace.md)
binds author, solver, reviewer, bank and Swift strings. The final call both
approves the item and writes its teaching. Subsequent code checks answer
agreement, structure, length and choice coverage, but no later semantic audit
checks that new prose.

Other agreed teaching defects were a categorical microphone-loading dismissal
(client q005/choice 1), a categorical root-pressure exclusion (q007/choice 2),
and an unestablished direction of carbon-dioxide uptake (q001/choice 0).
Choice indices are zero-based. The [root reconciliation](evidence/native-workflow-20260910/reconciliation.md)
records derivations, primary evidence and remaining interpretive disagreements.
Those differences were not settled by assuming the author intended the key.

## Consequences for further work

Increasing output tokens is unsupported as the remedy for this run: all
responses completed far below the cap. Native JSON ordering and preserved
goal/source context are useful contract fixes, but their correct operation
did not remove unsupported premises, wrong teaching or inflated challenge.

The architectural requirement remains to finish learner-facing content before
its last semantic audit, preserve the exact audited text through delivery, and
enforce all reported objections. This is an existing hypothesis, not a newly
discovered fix: the [immutable teaching experiments](QUESTION_IMMUTABLE_REVIEW_FOLLOWUP_RESULTS.md)
already implement a prototype, and a [fresh complete-author trial](QUESTION_FRESH_AUTHOR_IMMUTABLE_RESULTS.md)
still passed a false CSS explanation. The existing main-only
[`authored_solution` mode](QUESTION_AUTHORED_SOLUTION_CONTRACT.md) also failed
its fresh qualification. Neither switching that flag nor adding another
identical reviewer can be presented as a proven solution.

The next implementation decision must account for those results, preserve
choice-specific teaching, and add an enforceable missing capability rather
than repeat the same prompt experiment. External calculations, literal-case
counterexamples and acquired evidence can provide independent checks where
applicable, but their scope must match the displayed question. This experiment
alone does not qualify any new architecture or establish adaptive progression.

## Verification and provenance

Preparation passed all 1,069 backend tests, relevant evaluator/delivery checks,
Ruff, compilation and an initial synthetic Swift control. This evidence
milestone changes documentation/artifacts only; runtime, helper and test hashes
remained identical to the frozen plan throughout replay and assessment.
The [manifest](evidence/native-workflow-20260910/manifest.json) binds archived
artifacts. Original plan/capture byte hashes are respectively
`479b9ed1d5b5956446991dfdf5e18d5b587eb9b8522aa9d182da6942ec99326f`
and `fed7a2261f2baf58bddbc3c6749fef409fd41d7dcf70b91bc27da0047c6848df`;
canonical plan hash is
`3cd55295f466fff4bbb62ed1f860696f441c6d4d421f30e1553935e2d2a5a02c`.

Separately, draft [PR 7](https://github.com/SamChou05/checkpoint/pull/7) remains
unmerged. Its two CI runs failed on the same compact-dashboard threshold and
Swift type-check issue observed on unchanged main `a4e3bf1` in
[run 34439276913](https://github.com/SamChou05/checkpoint/actions/runs/34439276913).
The affected files were unchanged by that PR. Backend/secrets and release-build
jobs passed; this records the known CI state, not an all-green merge claim.
