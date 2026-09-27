# Combined v12 full-worker qualification: failed 4/5

The one frozen live job returned **four of five original slots** and therefore
failed its prespecified five-slot gate. It made three Bedrock Converse calls in
98.275 seconds, below the six-call and 240-second limits. There was no retry,
top-up, bank write, fallback model, or post-hoc change to the capture.

The author produced five schema-valid closed tasks. All five compiled and
survived sanitization; the three numeric keys were independently recomputed.
The answer-blind English solver supported the one code-owned key and judged
all six choice pairs distinct for both English questions. The final reviewer
marked all five valid, agreed with their keys, reported supported explanations,
and raised no issue flags. It rated original slot 4, a full-sentence agreement
question, difficulty **4**. The current proof-scoped policy admits only
reviewer ratings 2 or 3 for code-owned level-2 agreement questions, so it
rejected that slot as `review.difficulty_target`. The other four returned.
The [read-only rejection diagnostic](rejection-diagnostic.md) traces the exact
path and preserves the frozen failure.

After the live capture was locked, two independent answer-blind reviewers
read the same [worksheet](blind-candidates/worksheet.json), SHA-256
`21371050818585c2e443e58763e0082a1633fc22a3ea6d387f979eb9ca0a2ae6`.
Neither saw the key map, capture, or the other's review before locking their
judgments. [Review A](blind-candidates/review-a.json) and
[review B](blind-candidates/review-b.json) each selected the code-owned key
for **all five** candidates, found no alternative key, judged all **30 of 30**
within-item answer-choice pairs meaningfully distinct, and rated all five at
the requested 2–3 range. Both rated the rejected full-sentence item **3**.
They found no strong repetition among the ten within-batch question pairs;
review B marked four moderate overlaps, mostly shared numeric answer format
or the broad agreement objective. The private key map was opened only after
both reviews were written. These judgments support the content of the
rejected item but **do not turn the live worker result into 5/5**.
The [post-lock teaching audit](blind-candidates/teaching-audit.json) judged
all five main explanations and all 20 per-choice feedback entries sound;
one numeric wrong-choice entry was accurate but minimally diagnostic.

The same full-sentence item appeared in an earlier locked bank worksheet;
both independent reviewers there also rated it 3. Across four full-sentence
scene families, prior blind samples rated three selected-answer constructions
2 and two nearer-subject `neither…nor` constructions 3. Three of eight
scene/order variants have no direct blind difficulty rating. Thus the
constructor's current blanket level 2 is not calibrated for the rejected
variant, while a blanket level 3 or blanket acceptance of reviewer rating 4
would go beyond the evidence. The route is still opt-in and inactive by
default. A prospective, scope-aware calibration and a separately frozen
full-worker trial are required before claiming improved yield.

The immutable [capture](capture.json) has SHA-256
`fe66f66fe9bc1b8eefa62c167447e73a62d41cf362850a3db8cbc912298af31d`.
The frozen [plan](plan.json) has SHA-256
`bbac67ed6255db66c20404f37470a5c92a53e86d1a49a0ca41c90015f8f5217b`;
the [mechanical audit](mechanical-audit.json) separately checked five
candidate provenance records, the three numeric proofs, and all literal
choice pairs. Source commit `01439703d647ab17246c4f9c821a4dd05b5b2a99`
and the 2,357-byte v12 schema were pinned before the call.

The trial concerns one five-item batch. It does not establish reliability
over a 20-, 40-, or 80-item bank; chronological offline replay still shows
strongly repetitive pairs even with distinct exact stems.
