# Question Context Strategy

Status: the small-document bridge and protection-readiness safeguards described below are implemented. Retrieval, citations, and non-quiz progress gates are recommendations for the next product phase.

## Product Principle

Checkpoint should optimize for **sufficient, useful context with the least user effort**, not for the largest prompt. The user is trying to make progress, not configure an assessment system.

For an ordinary learning goal, the useful minimum is:

1. A concrete learning target.
2. Three to six skills or topics, supplied by the user or visibly inferred.
3. A coarse starting level or a short statement of what feels easy and hard.

That is often only 20 to 80 structured words. A clear goal plus one optional setup answer should be enough for most users. Answer history should then become the main personalization signal.

## Context Ladder

| Level | Information | When it is enough | Product behavior |
| --- | --- | --- | --- |
| 0 | Goal title only | The subject and target are already concrete | Infer a draft skill map and start a short calibration set |
| 1 | Goal, focus topics, current level | Most public, well-known subjects | Generate the first ready set and adapt from answers |
| 2 | One to three substantive excerpts | A class, certification, job rubric, private curriculum, or source-specific goal | Ground facts and answers in the supplied material |
| 3 | A larger source collection with retrieval | Books, long courses, or many files | Index, retrieve relevant chunks per batch, and retain source links |

Do not require a file for a goal that can be assessed well from Level 1. Offer files as the shortest route to specificity when the source itself is the curriculum.

## Seamless Setup

The recommended setup interaction is progressive:

- Ask for the goal first.
- Infer a proposed learning target and three to six skills in plain language.
- Ask at most one high-value follow-up, such as “What already feels easy or hard?” Show the inferred skills so the user can edit them instead of filling out a long form.
- Offer “Add study materials” as optional. Explain that extracted text is saved with the goal and sent to the question service.
- Prepare and validate five questions before app protection can turn on.

A second mandatory clarification is justified only when the goal is genuinely ambiguous, conflicts with the supplied source, or names an execution outcome that cannot be assessed honestly with multiple choice. At least 80% of ordinary educational goals should need zero or one clarification.

## What Counts As A Useful Source

Word count alone is a poor measure. A source is useful when it contains at least five distinct, testable claims, rules, examples, mechanisms, constraints, or reasoning steps that match the goal.

Examples of high-value material include a syllabus with substantive objectives, lecture notes, a study guide, a rubric, a standards document, or a worked example set. A title page, assignment calendar, motivational outline, or list of links is not enough by itself.

The implemented bridge accepts up to five text or text-based PDF files and sends no more than 24,000 normalized characters across them. Short documents keep their full text; longer documents share the remaining budget, preserving their beginning and end. This is roughly 4,000 to 7,000 model tokens, or about 8 to 12 dense pages. It is appropriate for a 5-to-20-question batch, not for a textbook.

Scanned PDFs currently require OCR before import. Other rich formats should be added only with reliable extraction and clear user-visible failure states.

## Why Not Raise The Raw Prompt Limit

Large raw prompts create four problems at once:

- Relevant facts are harder to retrieve consistently.
- Cost and latency rise on every refill.
- Prompt-injection and conflicting-instruction surface area increases.
- The app cannot show which source passage justified a question.

The next step for larger collections is upload, extraction, chunking, retrieval, and citation—not a larger string field. Store a source version, retrieve only a few goal-relevant chunks for each generation batch, and retain the supporting chunk IDs on every generated question. Changing a source should invalidate or re-verify affected questions.

## Quizability Is A Product Decision

Multiple choice is valuable for knowledge and constrained application goals. It is not an honest proxy for every kind of progress.

- **Knowledge goals**: definitions, facts, concepts, rules, and distinctions. Multiple choice works well.
- **Applied reasoning goals**: diagnosis, code tracing, source interpretation, scenario choice, and trade-off analysis. Multiple choice works when stems include enough evidence and constraints.
- **Execution goals**: write a chapter, run three times a week, apply to jobs, or ship a feature. A trivia question about the activity does not prove progress.

For execution goals, the future gate should request a small verifiable action or artifact: choose the next concrete step, complete a timer, log a result, paste a short excerpt, or confirm evidence. Until that exists, setup should explain that Checkpoint can test supporting knowledge but cannot verify completion of the goal itself.

## Question Quality Pipeline

A source-aware batch should pass all of these gates before becoming available:

1. **Blueprint**: distribute items across distinct skills, claims, and misconception types.
2. **Grounding**: when sources are present, every correct answer must be supported by them; the stem must contain any passage needed to answer independently.
3. **One-best-answer validation**: exactly four distinct choices, one defensible answer, and plausible distractors.
4. **Goal relevance**: the item tests the subject, not productivity, motivation, app blocking, or study planning unless those are the actual target.
5. **Difficulty validity**: harder levels require application, constraints, or multi-step reasoning rather than a higher numeric label.
6. **Independence**: avoid paraphrasing an existing item or reusing the same answer mechanism.
7. **Readiness**: cache at least the full configured checkpoint size before protection starts.

Source text and filenames are untrusted reference data. Neither the client nor backend should follow instructions embedded in them. Truncated or absent material must never be inferred as if it were present.

## Adaptation From Answers

The first set is calibration, not a confident diagnosis. A practical confidence ladder is:

- Five varied answers: provisional overall level.
- Three answers per skill at two difficulty levels: provisional skill targeting.
- Eight or more answers per skill: routine adaptive targeting, still with uncertainty.

Use recency-weighted accuracy, difficulty, and misconception patterns to choose the next batch. Re-test misses soon, then space successful items. User feedback such as “wrong answer,” “irrelevant,” or “too easy” should retire the item and influence the next blueprint.

## Reliability And Release Gates

Suggested product targets:

- Zero protection starts without a complete cached checkpoint.
- The blocked-app interception path performs no network request; it consumes only a ready cached set.
- Setup median under 45 seconds and 95th-percentile first-set readiness under 120 seconds on a healthy connection.
- At least 85% of questions judged on-target by users or review samples.
- At least 97% factual correctness and 98% one-best-answer validity in a stratified evaluation set.
- Source-backed items retain support references, with unsupported-claim rate below 1% before broad release.
- Abandoned or interrupted checkpoints resume or receive the same failure consequence; force-quitting must not reset the gate.

Simulator tests cannot establish the Screen Time loop. A signed physical-device matrix remains mandatory across supported iOS versions, including shield presentation, handoff into Checkpoint, unlock, force-quit recovery, and automatic re-lock.

## Privacy And Security Requirements

The current implementation keeps extracted source text in the encrypted-on-device goal snapshot and sends it in the question-generation request. Public release should additionally require App Attest-backed authentication, server-side tenant isolation, strict no-body logging, transport encryption, clear erasure behavior, and App Store privacy disclosures that explicitly cover user-provided study materials.

If future versions retain uploaded files server-side for retrieval, they also need per-user storage authorization, encryption at rest, short documented retention, deletion and source-replacement workflows, and a way to inspect which files are active for a goal.

## Recommended Sequence

1. Finish and physically verify the cache-only shield-to-quiz loop.
2. Add lightweight goal classification and one-question clarification when needed.
3. Measure source and question quality using the targets above.
4. Add question-level source support references and a “challenge this question” path.
5. Add chunked retrieval only after real users exceed the small-document bridge.
6. Introduce progress/evidence gates for execution goals rather than stretching multiple choice beyond what it can measure.
