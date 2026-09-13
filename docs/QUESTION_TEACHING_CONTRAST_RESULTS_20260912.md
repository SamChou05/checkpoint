# Direct-contrast teaching control: candidate not adopted

Four actual previous final-review inputs were replayed with the same Sonnet model,
native transport, fixed independent solutions, and no author/solver inference.
The candidate replaced the explanation responsibility with direct rule/result
contrasts and prohibited invented error stories or changed scenarios. Eight calls
covered nine items per arm. Both arms produced valid JSON envelopes.

The candidate did not establish a general improvement:

| Input | Current responsibility | Direct-contrast candidate | Independent assessment |
| --- | --- | --- | --- |
| Signed arithmetic (2 items) | Says −6 is no standard result of −4 and −2. | Narrows that statement to multiplication, but the next main says parentheses are evaluated before “division by 12.” | −4+(−2)=−6; 12÷(3−5) divides 12 by −2, not by 12. The candidate moves the teaching defect rather than eliminating it. |
| Explicit source rules (4 items) | Returns all four, with an unsupported claim that operator distractor 2 ignores both operands. | Also returns all four and repeats that claim despite its new instructions. | 2 can be 5−3; it is wrong because the stated operator yields 13. An asserted story about its origin is unwarranted. Other rule translations and keys are supported. |
| SQL outer join (1 item) | Explains distractor five by allowing all B rows to match. | Again explains five using all B matches plus unmatched rows. | Actual query yields 3. Removing B.y>15 yields 4, not 5: two rows for id=1, one for id=2, one unmatched id=3. Both keep the recurring faulty counterfactual. |
| Solstice/equinox (2 items) | Vetoes the sunrise item without reason; accepts equinox. | Accepts sunrise, invents a local-solar-time interpretation, and generalizes earliest/latest sunrise to solstices. Equinox is reviewed as level 2 and falls below the request's level 3 floor. | Stem says “local time,” not solar time. Latitude/season alone does not establish clock time. The prior NOAA clock-time calculation also contradicts the exact earliest-sunrise generalization. The paired equinox key is supported at the stated ±40° latitudes; blanket all-latitude wording remains overbroad. |

Both arms have eight contract-admitted items, but they are not the same eight.
This is not evidence of unchanged correctness or improved useful yield. The
arithmetic and query checks are direct calculations, not model agreement. The
astronomical distinction follows the exact input and the prior independently
saved NOAA calculation; a named real location can provide outside knowledge, but
it does not justify falsely calling the stem's clock convention solar time.

## Reporting correction

The first local replay incorrectly omitted the saved independent solutions and
therefore reported zero accepted items for every call. That was a harness error,
not a live provider or content rejection. The original traces remain unchanged.
The [corrected replay](evidence/correctness-continuation-20260912/teaching-contrasts/corrected-replay.json)
feeds the exact `independentSolutions` already present in each saved review input
through the actual contract validators. It required **zero additional calls**.
It uses historical provenance and does not claim new independent verification.
The runner now supplies those saved solutions for future local reporting.

[Plan, systems, and actual inputs](evidence/correctness-continuation-20260912/teaching-contrasts/plan.json)
and the eight adjacent captures preserve all outcomes. The application reviewer
prompt is unchanged. A prompt that sounds more precise but repeats false teaching
and introduces another error is not qualified for promotion.
