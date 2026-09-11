# Root reconciliation of the frozen assessments

This record does not revise either assessor's files or promote a disputed item
into the confirmed-useful count. The computed join reports agreement only.
All references below were read during assessment/reconciliation, after the live
capture; no new evidence was retroactively supplied to the captured pipeline.

## Supported calculations and factual defects

The six [root calculations](root-calculations.json) independently recompute the
numeric sound cases. They state their assumptions; arithmetic alone cannot
establish microphone calibration, source arrival phase or a physiological cause.
In raw q006, under the ordinary accepted reading of in-phase contributions at
the observation point, pressures add and the level is
`80 + 20 log10(2) = 86.0206 dB`. Merely making sources in phase would not imply
in-phase arrival at an arbitrary point; that interpretation limitation remains
explicit. Both blind assessors accepted the ordinary reading before keys were
revealed. The author's 83 dB calculation used the incoherent intensity rule.

Raw q001/client q008 asks about intensity level with a common intensity reference
in the supplied study context. Its authored main and solver maintain that
quantity. The final main introduces SPL. At common pressure reference,
`L_p = 20 log10(p_rms / p_ref)` gives equal levels for equal pressures. The
customary underwater pressure reference is 1 μPa versus 20 μPa in air, a
26.02 dB offset in the other direction for equal pressure. Acoustic impedance
changes power flow at equal pressure, not this pressure ratio. The
[National Research Council appendix](https://www.ncbi.nlm.nih.gov/books/NBK236684/)
supports these distinctions. This confirms a new final-teaching error, without
changing the supported intensity-level key or treating all decibel quantities
as interchangeable.

Client q005's loading explanation is not justified by already having a voltage
measurement. An independent electrical counterexample uses open-circuit
sensitivity `S`, source resistance `R_s` and load resistance `R_l`:
`V_loaded = S p R_l / (R_s + R_l)`. With `S=0.01 V/Pa`, `R_s=100 Ω` and
`V_loaded=0.1 V`, loads of 100 Ω and 900 Ω imply pressures of 20 Pa and
11.111... Pa respectively. Thus observed voltage does not eliminate loading
from calibration. This is a counterexample to the categorical teaching rule,
not an assertion that either load was present in the question. Shure's
[sensitivity explanation](https://service.shure.com/articles/en_US/Knowledge/how-do-i-compare-the-sensitivity-of-two-microphones)
distinguishes open-circuit measurement from a loaded power rating. Two attempts
to retrieve the separate Shure impedance page cited by the assessors timed out.
The sensitivity documentation was available in the search result, although its
subsequent direct page open also timed out. The explicit voltage-divider
derivation independently supplies the counterexample; no claim relies on
unretrieved page contents. The frozen best-listed frequency-calibration answer
is preserved.

Client q007's categorical claim that root pressure is too weak/slow to contribute
to recovery lacks species, height and hydraulic evidence. A primary
[Sorghum study](https://www.frontiersin.org/journals/plant-science/articles/10.3389/fpls.2021.571072/full)
observed root pressure after drought and rewatering. This supports the objection
to categorical exclusion, without proving root pressure caused recovery in the
unspecified potted plant or resolving its relative contribution. The standard
best-mechanism xylem key remains the assessors' prior judgment. The author main
already overstated this exclusion; final review softened the main but repeated
it in a choice explanation.

Client q001/choice 0 says both directions in the distractor are inverted,
thereby asserting a direction of actual carbon-dioxide uptake. Partial closure
reduces conductance while increased ambient carbon dioxide can increase the
concentration gradient; those facts alone do not determine the direction of
their combined effect. Both assessors identify that extra teaching assertion
as unsupported. Their disagreement about ordinary qualitative adequacy of
uptake in the main/key remains separate and unresolved.

## Interpretations deliberately left unresolved

| Raw / client item | Preserved distinction |
| --- | --- |
| q008 / not returned | A fee waiver with an exception does not explicitly provide the complete default fee schedule. Both assessors judge ambiguity; neither the authored answer nor the solver's three positive fee claims supplies the missing policy. |
| q010 / q001 | B accepts ordinary qualitative elevated-CO₂ physiology; A considers adequate uptake unestablished for this case. No measured adequacy threshold resolves this disagreement. Both reject the separate uptake-direction assertion in choice feedback. |
| q013 / q003 | The current revocation outcome is supported under either exception scope because preregistration is absent. A disputes categorical teaching about the trailing exception's general scope; B accepts its ordinary local attachment. The key is agreed, the complete teaching is not. |
| q019 / q010 | Both retain uncertainty about sustained local misting effects and higher turgor after several hours. The intended trend is plausible; the frozen judgment is not proof that the opposite occurs. |
| q022 / q009 | A sees a globally contradictory prohibition/override rule and a second answer; B reads the override as a specific exception and answers the actual disengaged case. Root considers the ordinary exception reading defensible, but does not treat that preference as evidence resolving all wording/teaching concerns. |

Raw q020 and q021 offer cannot-determine choices. Missing category or component
information can warrant those answers. Root therefore does not mechanically
require every `premise_status` field to equal `sufficient`: the relevant
requirement is enough information to warrant the actual keyed answer. q020's
author intended mandatory acceptance, which both assessors reject in favor of
the offered indeterminacy choice; no deliberate author intent to test
insufficiency is inferred there. q021's author keyed indeterminacy correctly
and it reaches client q004.

Assessed difficulty and distractor plausibility also differ on some items.
No post-hoc threshold change or decisive expert calibration was introduced.
The joint useful count requires both assessors to meet the originally defined
threshold, including applicable cannot-determine questions.
