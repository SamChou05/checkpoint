# Bounded fraction-error distractors

Main commit `6afdbaa` changes the finite candidate priorities used by the opt-in numerical constructor. Fraction tasks can now offer mistakes in fraction procedures before generic root operator swaps. Exact solutions, four distinct rational values, key-independent ordering, at most six local candidates per binary node, final compilation and all audit vetoes remain enforced.

For `(3/5) * 25`, the old wrong values were `128/5`, `-122/5` and `3/125`. The new wrong values are `5`, `75` and `3/125`, corresponding to omitted numerator, omitted denominator and applying the multiplier to the denominator. The correct value remains `15`. This addresses candidate selection; it does not infer the reason for the earlier model veto.

The [complete comparison](comparison.json) preserves old/new pools and learner fields for seven captured tasks. All remain constructible. Across 885 defined signed-rational cases, constructible cases increase from 780 to 800 with no losses. All 288 nested cases remain constructible in both versions. These are exact arithmetic and bounded-pool checks, not model-accuracy rates or measured novice plausibility.

The [verification manifest](VERIFICATION.json) records 1,318 passing backend tests, 30 focused groups independently repeated by root, Ruff, a successful SAM build and 516 packaged SDK request shapes. Root checked 87 artifact files and all 29 corresponding integration source/dependency/validator files against isolated commit `1d1963c698237b0f5a8253ad876fac77aebdef50`.

The fraction-error families are informed by IES Recommendation 3; exact priorities and omission variants remain engineering hypotheses. [IES fractions practice guide](https://ies.ed.gov/ncee/wwc/docs/practiceguide/fractions_pg_093010.pdf)

This source change is separate from the longer-timeout trial's frozen source `77f794e`. No historical specification, capture, prompt, schema, model, default, deployment or inventory state was changed. Mathematical soundness is established for admitted closed tasks; full-worker and pedagogical qualification remain separate.
