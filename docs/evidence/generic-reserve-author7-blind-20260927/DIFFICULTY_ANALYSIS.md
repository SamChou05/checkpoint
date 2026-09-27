# Why the seven probability candidates miss difficulty 2

This is a diagnosis of the **author-only** worksheet, not a verified worker
result. The seven-row solver request failed before independent checking. The
two [blind reviews](RESULTS.md) independently rated G01, G03, and G06 at level
1 despite the request's minimum level 2. Under those judgments, only four of
seven candidates remain for a five-question response even if every later gate
accepts them. The production reviewer could rate differently; this sample does
not prove which verdict it would give.

The [request](../generic-reserve-seven-probe-v2-20260927/plan.json) asks for
introductory probability across counting, conditional probability,
independence, expected value, and interpretation. The common author prompt
defines level 2 as “Apply one familiar rule directly,” asks for variety and
plausible distractors, and caps the stem at 320 characters. It does not give
the author an operational test separating a genuinely applied level-2 problem
from a near-recall exercise. The seven-row reserve asks for two extra candidates
but gives no extra difficulty margin or per-item decision structure. The model
covered different probability operations, yet chose their shortest canonical
versions:

| Item | What the learner actually does | Blind observation |
| --- | --- | --- |
| G01 | Count faces 5 and 6 on a fair die, then divide by six. | Both reviewers rated 1; several wrong fractions are generic guesses. |
| G03 | Multiply two explicitly supplied 1/2 probabilities after the stem explicitly says the flips are independent. | Both rated 1; 1/3 has no clear misconception path. |
| G06 | Subtract one supplied pass probability from 1. | Both rated 1; 0.75 and 0.50 have no clear calculation path. |
| G04 | Average four dollar labels. | One reviewer found an unstated label-to-payout rule; the other accepted the natural implication. Both found at least one weak distractor. |

This is a **calibration and task-design** problem, not a JSON shape problem.
Distinct strings and six distinct within-item choice pairs do not show that
wrong options are plausible misconceptions or that the task hits a cognitive
floor. The current final reviewer can reject a level-1 item or an unsupported
premise, and the five-survivor gate then correctly returns no questions. It
cannot make a thin authored candidate harder or repair G04's stem. The blind
reviews also disagree on G04 self-containment and G05 difficulty, so no single
numeric grade should be treated as ground truth.

## Isolated next experiment

Change only `request.goal.questionDirective` in a **new** frozen probability
trial. This field is already passed as subject guidance to the author and is
limited to 1,000 characters. Keep the generic system prompt, strict reviewer
difficulty gate, solver, native schemas, five-survivor rule, call limit, and
source code unchanged. Suggested replacement text:

> Write self-contained level-2 applications. In each stem, make the learner use
> a stated scenario condition to determine the relevant outcomes, sample
> space, event relationship, or payoff before applying one familiar probability
> rule. Do not use a direct complement of a supplied probability, two fair-coin
> heads with independence already stated, or an obvious one-die threshold count
> as a complete item. State explicitly what every spinner label pays. For each
> wrong option, silently derive it from a different plausible mistake with
> these exact quantities; replace options that are merely nearby guesses.
> Across the batch, vary the decision and answer format, not just the objects.

This asks for an actual application decision without requiring a multi-rule
problem that could overshoot level 2. Its probability-specific examples belong
in the trial request, not the global prompt for unrelated subjects. A prompt
cannot guarantee that the model follows it; it is a hypothesis to measure.

Before any live dispatch, a socket-free test should normalize the new request,
capture the rendered author prompt with a fake provider, and assert that the
exact directive is visible to the author, while the frozen native contracts,
reviewer difficulty floor, and no-partial-return policy are unchanged. An
offline replay using the frozen seven rows and the two blind ratings should
confirm the old batch cannot supply five level-2 rows under those ratings; that
is a regression fixture for selection arithmetic, not evidence of improved
authoring. The new trial then needs a fresh seven-row capture and two
independent keyless reviews of actual candidates. A content qualification
requires at least five candidates independently judged level 2 or higher,
unambiguous and self-contained, with meaningful distractors, **and** a
successful worker result of five after the solver and reviewer. Record reviewer
disagreements; a single sample is directional evidence rather than proof of
stable reliability.
