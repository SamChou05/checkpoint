# Question author prompt experiment — September 6, 2026

A simpler prompt did **not** improve the observed quality of this sample. The current author prompt produced more questions with an unambiguous supported answer and better compatibility with the app. Neither arm established release-ready correctness or difficulty progression. No production configuration was changed or deployed.

## What ran

The experiment generated 60 original MCQs: five questions for each of six goals, using two prompts. Goals were Spanish, photography, music theory, sourdough, modern world history, and a fictional game with a supplied rulebook. This exercised general goals rather than exam-specific implementations.

Both arms used `us.anthropic.claude-opus-4-6-v1`, adaptive thinking at high effort, a 16,000-output-token allowance, and a 100-second read timeout. Each pair received identical normalized request JSON; context hashes match for all six pairs. The short prompt asks for accurate, self-contained MCQs in the required JSON shape. The comparison arm uses the repository's current `_system_prompt()` and `_user_prompt()`, including length, difficulty, and item-writing instructions. Exact prompts, contexts, settings, and all 60 questions are preserved in the [evidence file](evidence/question-prompt-experiment-20260906.json).

The requests target difficulty 3. Only the fictional game supplies substantive reference material. The other goals rely on model knowledge; evaluator reference searches happened afterward and were not supplied to the author. No skill-map inference, independent model solver, final model reviewer, adaptive learner simulation, app interaction, or deployed queue was run. This isolates the author stage, not the whole product.

There were 12 initial calls, of which seven succeeded. Five failed: four quickly and one at the 100-second timeout boundary. The original exception capture did not preserve SDK causes, so the underlying causes are unknown. A bounded, serial retry of only those five cells succeeded in all five cases. Total: **17 attempted calls, 12 completed batches, 60 questions**. Initial failures remain in the evidence; they are not counted as bad MCQs or hidden in latency statistics. Retry timing and concurrency changed, so latency is descriptive rather than a controlled speed benchmark.

## Review method and results

The assistant first selected defensible answers and recorded ambiguity, wording, and estimated challenge without seeing prompt-arm labels, authored answers, or explanations. It then checked author keys and explanations while arm labels remained hidden. Only afterward were the arms compared. Reference texts and independent arithmetic/state enumeration supported adjudication. This is **assistant review, not independent human expert certification**; one batch per goal/arm is a small exploratory sample, not an accuracy estimate or a statistically established winner.

“Supported answer” means one offered answer follows under the ordinary stated reading. Review flags include missing assumptions, subjective criteria, and wording conflicts; they are not all factually wrong answer keys. Explanation findings are separate and can overlap question flags.

| Observed result | Simple prompt | Current author prompt |
| --- | ---: | ---: |
| Raw questions | 30 | 30 |
| Unambiguous supported answer matching the key | 24 | 26 |
| Question review flags | 6 | 4 |
| Clear factual/logical explanation errors found | 3 | 0 |
| Explanations needing qualification | 4 | 5 |
| Supported key and no explanation issue identified | 22 | 24 |
| Supported key and estimated challenge at least 3 | 6 | 8 |
| Retained by existing deterministic sanitizer | 23 | 30 |
| Median successful batch latency | 26.0 s | 58.8 s |
| Input/output tokens across successful batches | 2,256 / 12,520 | 9,410 / 24,084 |

The 50 questions judged to have one supported answer all had matching author keys. The other ten need review or revision; that does not imply ten plainly false keys. Likewise, “zero clear explanation errors found” is not a guarantee that every explanation is correct.

| Goal | Supported answer: simple | Supported answer: current |
| --- | ---: | ---: |
| Spanish | 4/5 | 5/5 |
| Photography | 5/5 | 2/5 |
| Music theory | 4/5 | 5/5 |
| Sourdough | 2/5 | 4/5 |
| Modern world history | 4/5 | 5/5 |
| Fictional game | 5/5 | 5/5 |

## What the evidence identifies

**More output space is not the demonstrated bottleneck.** Every successful call ended normally. The highest output usage was 5,835 tokens out of 16,000. These calls do not justify a further token increase. Thinking was already enabled in both arms; this experiment does not compare thinking on/off or establish which model is best.

**A short prompt still makes knowledge and reasoning mistakes.** The simple music explanation calls A minor the relative minor of A major and says they share a key signature. A minor is relative to C major; A major's relative minor is F-sharp minor. See the [music fundamentals reference](https://viva.pressbooks.pub/cmus120emu/chapter/minor-scales/). A Spanish explanation categorically forbids indicative after *esperar que*, although [RAE explicitly allows future indicative in some contexts](https://www.rae.es/libro-estilo-lengua-espa%C3%B1ola/el-modo-indicativo-o-subjuntivo). The fictional-game minimum-turn answer is four, confirmed by enumerating legal states, but its explanation incorrectly counts a beacon reward as a separate action. The actual minimum uses two moves, one gather, and one exchange.

**Question ambiguity remains a separate problem.** Current-prompt photography examples ask for a “single” change while the answer changes both ISO and shutter speed, imply spot metering automatically changes exposure without specifying exposure mode, or treat a compositional preference as uniquely best. Nikon's [manual-exposure teaching material](https://static.nikonusa.com/pdf/nikonschool/sat.pdf) supports the metering distinction. Baking examples overstate what a cold poke test proves; a baker's [firsthand explanation of the test](https://www.theperfectloaf.com/how-to-use-the-dough-poke-test/) describes its limitations. These are reasons to improve assumptions and qualifications, not label every intended answer nonsensical.

**The requested challenge is poorly calibrated.** In each arm, the blind review rated 21/30 questions as recognition or familiar one-concept application. Those estimates are subjective, not measured learner difficulty. The shared request also says “Medium application: apply concepts to a short scenario with qualifiers and plausible distractors,” while the current system prompt distinguishes level 3 interpretation from level 2 application. The simple arm does not receive that expanded rubric. Thus the experiment compares whole instruction packages, not prompt length alone. The guidance mismatch is a concrete next target; this run does not prove how many questions the production reviewer would reject.

**Some app filters discard useful material.** The simple arm lost seven items before AI review: five overlong stems, one generic content match, and one supposedly duplicate choice set. Three of the length-rejected items had supported keys in blind review. A valid Dm7 question was rejected because `_choice_uniqueness_key` removes the sharp symbol, collapsing distinct pitch sets. A relevant baking question was rejected because `_looks_like_study_strategy` matches “what should you do next” regardless of the actual subject. That baking answer was reasonable, but its explanation also needed qualification: fixing the false filter match alone would not certify the item. These failures show why sanitizer retention must be measured separately from correctness. The comparable client choice-normalization code also needs review before a backend-only correction is shipped.

## Decision and next changes

Keep the current author prompt pending a stronger comparison; do not replace it with the simple arm based on these results. Do not promote this model/thinking configuration as a correctness fix.

The next implementation slice should correct meaning-destroying choice normalization and subject-blind phrase rejection with cross-domain backend/client regression cases. Then align the difficulty guidance across request, author, and reviewer using concrete cognitive tasks. Re-run preserved bad and valid controls through the full solver/reviewer pipeline, and test fresh goals with multiple batches per arm. Select factual retrieval or deterministic checks where the claim requires them; this experiment did not test whether retrieval improves author quality.

The harness now also records bounded exception-cause types and provider error codes without copying provider cause messages, so future service failures can be distinguished. The saved evidence remains a record of the original outputs, including mistakes. Production changes and qualification remain separate work.
