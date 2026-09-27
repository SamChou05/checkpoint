# Independent blind review rubric

Read only `worksheet.json` until both reviews are locked. The worksheet contains all five sanitized candidates, including the candidate omitted from the worker's returned set. Its item order and A–D labels are deterministically shuffled. Do not inspect the capture, preparation script, private answer map, source tasks, model output, or another review while rating.

For each Q01–Q05, solve from the prompt and the four offered choices. Record one key letter, or mark ambiguous/no-answer. Name every additional defensible key. Rate difficulty from 1 (very easy) to 5 (very hard) against the target of 2–3, with a short reason. Judge all six unordered pairs of A–D within each item for meaningful distinctness and explain any pair that is not distinct. This yields 5 item judgments and 30 choice-pair judgments.

Judge all ten unordered cross-item pairs separately for solving-method repetition and response-format repetition on this scale: `none`, `low`, `moderate`, `strong`. Give one overall rating and explain every pair rated strong. A similar-looking stem can repeat format even when the solution operations differ; a shared operation can repeat method even when the requested answer format differs. State any other ambiguity, misleading feedback implied by the question, or weak distractor you notice.

Keep the review answer-blind. The answer/slot map is stored outside Git and must be opened only after both independent reviews are locked.
