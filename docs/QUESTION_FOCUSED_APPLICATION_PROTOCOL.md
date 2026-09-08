# Focused application authoring — September 8, 2026

## Hypothesis and intervention

The [author-model comparison](QUESTION_AUTHOR_MODEL_COMPARISON_RESULTS.md) found that model substitution alone left missing premises, weak distractors and unsupported teaching. Some choices bundled the requested result with an additional claim; some explanations strengthened case evidence into a general rule. These are observed defects, not proof that the current instructions caused them.

The opt-in `CHECKPOINT_PROMPT_VARIANT=focused_application` replaces the existing construction steps and, in `authored_solution` mode, the worked-teaching paragraph. It asks for one precisely specified result or decision, with every choice answering the same request in the same dimensions. Joint outcomes, option-dependent tasks and negative answers remain available. The explanation derives that case result with all necessary qualifications, without adding unrelated claims. The existing difficulty rubric, adaptive targets, allocation, source rules, display limits and verification stages are unchanged. This is a construction hypothesis, not a new semantic guarantee or permission to generate easier questions.

This differs from the earlier compact/checklist variants: it does not require a one-sentence stem, replace reasoning with isolated recall, or merely add another accuracy checklist. The default prompts remain byte-identical. There is no new reviewer, metadata format, answer rewriting or production promotion.

[NBME's item-writing guide](https://www.nbme.org/sites/default/files/2021-02/NBME_Item%20Writing%20Guide_R_6.pdf), pages 12–14 and 32–39, recommends focused questions, comparable options and application of relevant scenario evidence. Its guidance concerns health-science assessment; extending those construction principles to Checkpoint's general subjects is an inference to test. We do not adopt a universal options-hidden rule, because legitimate option-dependent tasks must remain possible. A focused result can still require several reasoning steps.

## Frozen matched run

Reuse the three exact goal/source payloads in [the existing fixture](evidence/authored-solution-fresh-fixture-20260908.json), byte SHA256 `6fe797f70ab10c8d6418743c213337b406d15448f75ffb4bebe0abdb2fb2693d`. Both arms generate new questions; prior candidates, known errors, arm labels and assessment notes stay outside model context. The domains are previously examined, so this is a targeted feasibility comparison, not a new-domain holdout.

The existing runtime evaluator accepts exactly `{"experiment":"authored-solution-focused-application-v1"}`. It constructs balanced then focused for plants, focused then balanced for English, balanced then focused for contours. Each operation requests two questions at minimum difficulty 3, for 12 planned slots. Kimi K2.5 authors every operation; Sonnet 4.6 performs complete-choice solving and the immutable teaching audit. All calls use disabled thinking, 6,000 output tokens and temperature 0.2. First requests must differ only in the author system text, and that text must actually differ. Source payloads, models, sampling and limits must match.

Retain one generation attempt, three calls per operation, 18 calls overall, separate 240-second operation windows, read75/connect3, one SDK attempt, 32 KiB per request and 576 KiB total. The prior fixture's six-slot/nine-call limits are origin provenance only; the paired plan freezes the active limits. Existing JSON repair consumes the same budget and is recorded distinctly. No added repair, top-up, fallback, retry, replacement or resume is permitted. An operational, unfinished-response, cleanup or persistence failure stops later operations. Ordinary content rejection is recorded separately.

Commit verified source before preparing or dispatching. Freeze source/dependency hashes, exact normalized requests, initial provider requests, all budgets and the fixture origin. Persist every dynamic request, final response, usage, stop reason, lifecycle observation and runtime decision. Use the existing isolated observer and offline replay, with no deployed Lambda invocation or question-bank writes.

## Assessment and decision

Assess every raw candidate, including runtime exclusions. Shuffle to opaque IDs and withhold arm, authored key, main explanation, model difficulty and runtime verdict. Two independent assistant assessments first solve the unchanged stems and evaluate all choices, then freeze their records. Only then reveal the exact main explanations, still withholding arm and retention. Save both second-phase records before unmasking. Style may reveal clues; these are assistant judgments, not human expert or learner calibration.

Record whether the intervention was followed: a precise requested outcome; the same requested dimensions across choices; additional answer claims unrelated to the requested task; and extra general or causal claims in teaching. These are descriptive mechanism observations, not substitutes for accuracy. Preserve legitimate requested explanations and joint outcomes; do not count every conjunction as a defect.

Separately report warranted unique keys, sufficient premises, three plausible distinct distractors, substantive goal fit, actual difficulty, complete supported teaching, exact bounds and runtime yield. Give exact per-arm raw and returned denominators. Preserve assessor disagreements and distinguish an unsupported inference from a proved-false claim. Length exclusions do not earn factual-rejection credit; shorter or easier questions alone are not an improvement.

Keep the prior strict favorable criterion: all six focused items returned in their first unrepaired pass, within displayed bounds and the 320-character author-main instruction, with supported keys and complete teaching, actual difficulty at least 3 and plausible distractors. Report partial improvements even if that criterion fails. A qualifying selected run would justify broader fresh-domain testing, not automatic deployment or a general correctness claim. Do not keep resampling until the criterion passes.
