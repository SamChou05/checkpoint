# Broad pass: several independent causes

No runtime change was selected until all twelve fresh requests completed and all
49 raw drafts and actual provider responses had been read. Main and deployed
TestFlight application code match. The worker settings were held fixed: Kimi
K2.5 authors, Sonnet 4.6 solves/reviews, disabled thinking, legacy JSON, six-call
job budget. This pass used **51 calls**, **24 requested slots**, **49 drafts**,
and returned **10 questions**. The exact evidence is in
[the trace directory](evidence/correctness-audit-20260912/baseline/plan.json).

| Requests | Drafts | Returned | Calls |
| --- | ---: | ---: | ---: |
| Arithmetic / conditional probability / real algebra | 12 | 1 | 14 |
| Python / SQLite / algorithm guarantees | 12 | 2 | 10 |
| English grammar / articles / Spanish mood | 12 | 4 | 12 |
| Astronomy / historical chronology / ecology | 13 | 3 | 15 |

The [49 item assessments](evidence/correctness-audit-20260912/assessment.json)
separate key support, authored teaching, distractors, earliest defect and later
stage behavior. These are manual assistant judgments, not a formal blinded
expert panel or a production accuracy estimate. Independent
[calculations and SQLite execution](evidence/correctness-audit-20260912/independent-checks.json)
check specific claims. Language nuance and historical hypothetical artifacts
retain explicitly stated uncertainty. No semantic credit comes merely from a
verification stamp or parser rejection.

## Ranked hypotheses and discriminating evidence

1. **Actual response contract failures account for substantial lost output.**
   Thirteen sanitized candidates are lost when Sonnet writes analysis before
   its JSON, four more to final-review JSON/envelope defects, and one to changed
   minus signs in feedback keys. Probability and SQLite solvers give correct
   answers/calculations before their whole responses fail. Correctly enforcing
   the response contract is necessary; extracting an approval from surrounding
   text would revive a previously fixed bug. Test the already-implemented native
   schema mode on identical questions, including defective controls, rather
   than weakening parsing or adding more retries.
2. **Authoring introduces substantive defects, especially at higher requested
   difficulty.** Algebra loses an inequality branch, ecology equates intake
   shares to production shares, Spanish omits a necessary verb, and algorithm
   questions assert incompatible resource/output constraints. These mistakes
   occur in raw responses before normalization. Six algorithm and six ecology
   drafts also exceed the stem limit. Eighteen of 49 drafts fail structural
   admission (16 length, two choice length); this is not evidence that semantic
   verification would have caught their errors. Prior capacity/example trials
   already show that longer prompts and demonstrations are not established fixes.
3. **Verification fills in an intended problem or reports confidently wrong
   facts.** The returned bronze and olive-oil article questions permit alternative
   readings. Solver and reviewer silently impose a generic-reference intention,
   then teach that competing readings are wrong. One solver even approves bare
   singular `Tiger` as generic standard English. The astronomy review inserts
   a maximum tilt/June-solstice condition absent from the stem. Some source notes
   explicitly contain the qualifications the model ignores. Test hidden context
   versus learner-visible premises using matched fictional rules in four domains.
4. **A deterministic transformation deletes real stimulus.** Four independent
   [boundary probes](evidence/correctness-audit-20260912/stimulus-transformation-probes.json)
   lose their poem, measurements, program output or travel sequence because the
   last four lines equal the choices. The backend mistakes content equality for
   proof of redundant answer echo. Test unchanged raw items with and without
   this transformation; preserve valid echoed-option controls too.
5. **The final reviewer can introduce unsupported teaching, independently of the
   key.** For `-3+5`, the reviewer attributes `-2` to subtracting 5 from -3 (which
   gives -8). For `(-4)*(-2)` it repeats the solver's false denial that -6 is their
   sum. Other drafts have incorrect author explanations which solving repairs.
   Thus switching wholesale to authored explanations is not justified: the SQL
   retries have correct keys but invented join rows in the author mains.

These mechanisms coexist. Schema enforcement can improve yield while preserving
confidently wrong content; a length exclusion can hide a semantic failure; a
correct answer can carry false teaching. Return count alone is not correctness.

## Representative stage paths

- **Probability, first pass:** complete rates in request → two correctly keyed
  drafts (one authored arithmetic typo) → intact stem/choices → solver correctly
  calculates 26.9% and 16.6% → surrounding prose violates the strict contract →
  neither reaches review → replacement repeats the envelope failure. Four calls,
  zero return. No source clipping occurred.
- **SQLite, retry:** complete table rows → correct keys `(1,1)` and `(4,4)` but
  author invents extra NULL join rows → sanitizer preserves question content →
  solver independently enumerates the correct three/five joined rows → correct
  solution is envelope-rejected → zero return. Exact queries reproduce the keys.
- **Articles, retry:** source explicitly permits mass nouns used as types → author
  drafts ambiguous bronze/oil blanks → solver declares a unique generic reading
  and incorrectly disallows alternatives → reviewer repeats those assumptions
  and writes false teaching → both returned with policy revision 2.
- **Sequence probes:** complete four-line stimulus and an exact positional key →
  sanitizer removes all four necessary lines → rotated choices no longer carry
  the original sequence → downstream question is no longer the authored task.

## End-to-end and reference checks

Swift request construction sends structured goal/source fields, not the local
diagnostic `sourcePrompt` string. Backend source normalization preserves literal
text and marks clipping; fair-share head/middle/tail selection can still omit a
needed passage. No actual broad-pass source was clipped. User source content is
not shown beside the question in the attempt view, so hidden fictional rules
cannot substitute for a self-contained stem. The complete solver currently sees
goal and sources; the final reviewer also sees the solver judgments. These are
information-flow facts to test, not proof that every sourced question is wrong.

Bank preparation adds an ID, and stored `questionJSON` is encoded/decoded without
choice/key rewriting. Swift decodes those fields directly; verified admission
preserves stem and teaching, shuffles choices, and grades exact UTF-8 answer
identity. Current tests found no positional-key transport defect. **1,050 baseline
backend tests, four new trace tests, and 181 selected iOS tests passed.**

Primary reference checks include [NASA's seasons explanation](https://spaceplace.nasa.gov/seasons/en/),
[National Archives chronology](https://www.archives.gov/founding-docs/timeline),
[RAE mood selection](https://www.rae.es/libro-estilo-lengua-espa%C3%B1ola/el-modo-indicativo-o-subjuntivo),
and [Cambridge article guidance](https://dictionary.cambridge.org/grammar/british-grammar/a-and-the)
(search excerpt accessible; direct page returned 403). Sources support scoped
facts/rules, not every generated claim. The specific invented historical records
remain unverified, and the conventional elementary seasons wording is separately
flagged for a stricter literal interpretation.

## Frozen follow-up

The matched runner supplies recorded author drafts and makes at most two real
calls per job. Source/stimulus/algebra controls total at most 12 calls within the
16-call diagnostic allowance. Native/legacy comparisons on probability, SQLite
and articles total at most 12 calls. Reserve the remaining 24 intervention calls
for four fresh full-pipeline requests (one per domain), holding all other
settings fixed. Inspect every returned item and teaching, and report actual
calls, latency, valid controls retained and invalid items accepted. No production
setting or deployment is changed by these experiments.
