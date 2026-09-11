# Final-teaching error trace: client q008

The first intensity-to-SPL error appears in **the final reviewer’s generated main and correct-choice feedback**, not in the authored explanation, solver, native adapter, bank, or Swift composition. No later semantic audit of that generated teaching ran in this captured operation. This note traces only client q008 and does not revise either frozen assessment.

## Identity and direct comparison

All code references below are relative to source revision `661751de3fa0a55fc990be155cb3f6dad5246849`; the referenced backend source hashes match `capture.json.plan.source_sha256`, and the two Swift source hashes match `client-delivery.json.source_sha256`.

- `capture.json` byte SHA-256: `fed7a2261f2baf58bddbc3c6749fef409fd41d7dcf70b91bc27da0047c6848df`.
- `bank-delivery.json`: `0274b4ff0f5ed9d5d94f60be482bb5bbb79749507db02e1a741523c9e48ab081`.
- `client-delivery.json` (actual Swift observation): `134c5ca8f191cb6339909aba5bc295907abf3717d699e4dd1f9d0203c620d675`.
- `raw-assessment/private-mapping.json` raw **q001** = operation 0, author call 3, response question 2. `client-assessment/private-mapping.json` client **q008** = operation 0, retained question 3, remote ID `c71ae349-b4c5-5e85-879b-a861f3d0f6c6`. Indices are zero-based.
- Captured settings: `QUESTION_FEEDBACK_CONTRACT=reviewer_written`, `BEDROCK_STRUCTURED_OUTPUT_MODE=native`. Author: `moonshotai.kimi-k2.5`; solver and reviewer: `us.anthropic.claude-sonnet-4-6`.

| Capture call index | Role | Request SHA-256 | Response-text SHA-256 |
| --- | --- | --- | --- |
| 3 | author | `1d3485642e4f43fcb84310ce573fdee372def80e057e8790e8534a6ff5b0105c` | `d5e563faa8c2812a26c5bf34dacaf6b4e67cdf15bfbbac42232384f7ad29f8e0` |
| 4 | solver | `72672ebe7cda3b6d915d30d2ff094caac65c1c5266d134ebdb7f6c85de0f9b1e` | `d178b34676bd135d84eb27f31c32dc3cc4596e3671521948d5a0c45df7e63f47` |
| 5 | reviewer | `021d22584b7f805c7ac36b9375770009c595839f9cb592528258b20552b2db82` | `231e33d772c01f8c47fcbf0243c7564da46543f1fbb6cba5119d533e3d391087` |

Authored main (`calls[3].observation.response.text`, parsed `questions[2].explanation`):

> Intensity I = (Δp)²/(2ρv). Water has higher ρ and v than air, so for equal Δp, I_water < I_air. Since β depends on I, the level in water is lower despite equal pressure amplitude.

The independent solver (`calls[4]`, solution index 2) explicitly preserves the common intensity reference: “Since the same I₀ = 10⁻¹² W/m² reference is used, the dB level in water would be lower.” Its relevant item has one supported choice and three refuted choices. Neither its supported reason nor the authored main says lower SPL.

Final main (`calls[5]`, parsed review index 2):

> Intensity depends on both pressure amplitude and the medium's specific acoustic impedance ρv via I = (Δp)²/(2ρv). Water's ρv is roughly 3600× that of air, so the same Δp produces far lower intensity and a lower dB SPL level.

This replaces an intensity-level conclusion with a sound-pressure-level conclusion. For a common pressure reference, equal pressures give equal SPL; different conventional air/water pressure references also do not support “lower SPL.” The intensity conclusion and keyed choice remain valid under the common intensity reference. [Reference-pressure distinction](https://www.ncbi.nlm.nih.gov/books/NBK236684/).

## Propagation to every actual display

The reviewer request hides the authored main and key; it contains the stem/choices and the independent solver’s records. The reviewer both declares `valid:true` and writes new teaching in the same response. `question_verification.py:344` supplies the solver records, `:356` invokes the reviewer, `:443` selects its generated explanation and feedback, and `:474` stores them with verification version 1 / policy revision 2.

`native_output_contracts.py:163` validates the response shape; `:179` converts `choiceFeedback` rows to the legacy map without changing their text. Subsequent checks enforce validity/key agreement, difficulty, bounds, exact choice coverage and label restrictions (`question_verification.py:414`, `:445`, `:459`). They do not independently evaluate the newly written claims. Call 5 is the final provider call in operation 0; calls 6 onward belong to other operations.

The runtime explanation and feedback match the prepared bank payload and actual Swift-retained strings exactly. Bank preparation adds identity/deduplication (`question_bank_worker.py:415`); policy admission checks typed provenance stamps (`verification_policy.py:22`). Swift validates and preserves reviewed feedback while shuffling choices (`QuestionBatchSanitizer.swift:56`, `:79`). `QuestionModels.swift:193` computes each display as the selected feedback plus two newlines plus the main. Thus the faulty main appears in all four displays:

| Display index | Exact offered choice | Error location | Exact display SHA-256 |
| --- | --- | --- | --- |
| 0 | Lower, because water's higher ρv reduces intensity for the same pressure amplitude. | Also introduces “thus lower dB SPL”. | `187a526c97f29705fbec237d5a0e048ec365c2740d1a1726bb883ec81d81e046` |
| 1 | Equal, because pressure amplitude determines level directly. | Choice-specific text stays about intensity; appended main introduces SPL. | `9e09ed296d3300eade71a0bee35b5347c741a97a83eb9c4506f0bf3bf3a8d843` |
| 2 | Higher, because water's incompressibility increases pressure effects. | Choice-specific text stays about intensity; appended main introduces SPL. | `ec7949f1cbd584b35af654b4bbbb0f9f177d799072d50a45acaf91bf2ac4978c` |
| 3 | Higher, because water transmits sound more efficiently. | Choice-specific text stays about intensity; appended main introduces SPL. | `da7964ed10b4f3ea7edf474b8733011be372b5ed6e7866e68f6dca789d8df1be` |

All four composition equalities and all runtime → prepared → Swift content equalities above were independently checked against the capture/attachments. These establish propagation, not semantic correctness. No runtime changes or model calls were made for this trace.

## One general architecture change

**Freeze the complete learner-facing artifact before the final semantic audit, and make that auditor unable to generate replacement teaching.** In the existing three-call structure, the author could finish the main and any choice feedback first; the solver would remain blind to teaching/key; the final auditor would inspect every exact component and every composed display, returning only support judgments and issues. Bind admission to a digest of those exact strings and the composition policy. Unsupported or uncertain content requires rejection/regeneration; a later text change requires another audit.

This generalizes the existing opt-in `authored_solution` contract, which already freezes the authored main, hides solver judgments from the final audit, rejects unsupported/uncertain main claims or reported issues, and forbids reviewer rewriting (`question_teaching.py:26`, `:37`, `:54`, `:164`; `question_verification.py:346`, `:440`). That option currently supplies only a main explanation and an empty choice-feedback map. It would remove this particular reviewer-replacement path, but its effectiveness on this captured item was not tested.

The proposed full-artifact version retains choice-specific teaching and checks composition interactions; the existing main-only option has fewer claims, smaller payloads, and a simpler audit. Authoring/auditing all feedback can preserve the three model-call stages but increases token demand, latency, review complexity, and potential rejection/shortfall rates. The main can reveal intended answers to the auditor in either version, and correlated model errors can still pass. The architectural benefit is that no learner-facing prose is created after its last semantic audit—not a guarantee of truth and not a subject-specific keyword rule.
