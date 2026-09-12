# Question-generation correctness: root causes, fixes and limits

> **Corrected findings:** the four source-dependent controls did not prove false acceptances. The source-supported continuation replaces displayed-only solving and restores valid study-material recall. See the [corrected contract and matched evidence](QUESTION_SOURCE_SUPPORTED_POLICY_20260912.md). Counts below describe the original 102-call investigation. The continuation used 48 calls; [the final reference correction](QUESTION_SUBJECT_REFERENCE_POLICY_20260912.md) supersedes the intermediate source-only policy.

Required stimulus is preserved. Solver context was qualified in the continuation with learned
source facts retained and hidden lesson intent excluded. **The broader pipeline
is still not reliably correct.** Author errors, unjustified interpretations,
confidently wrong verifier judgments and false teaching remain. A verification
stamp or higher return count is not a correctness result.

The investigation used **102 actual provider calls**, within the frozen **124-call
ceiling**, and made no deployment or learner-bank writes. All 65 newly authored
questions were read, including rejected drafts and retries: 49 in the initial
broad pass, then 16 fresh drafts. Repeated fixed-author controls were assessed
separately. All experiments retain exact synthetic requests, actual provider
prompts/responses, intermediate transformations and final dispositions.

## What was inspected

Current main at the start and final fetch was `7d9cc6a`. A separate worktree
preserved the user's dirty original checkout. The previous audit and its
shared-answer-vocabulary and prose-prefilter fixes were reviewed and retained.
The four-question grammar smoke was not used as general correctness evidence.

The read-only [deployment snapshot](evidence/correctness-audit-20260912/deployment.json)
shows all 23 application Python modules match main in the API, worker and outbox.
There is no application-code deployment mismatch explaining these failures.
Actual configurations differ by path: Nova Lite authors on the API, Kimi K2.5
on the worker; both use Sonnet 4.6 verification, disabled thinking and legacy
JSON. The broad experiments used worker settings. They call Bedrock through local
runtime code; measured times are not queue-to-device service latency.

| Path | Inspection and result |
| --- | --- |
| User goal and request | Swift sends structured goal/source/map fields. A separate normal-language Python goal was sent through local map inference with a Nova Lite override (the deployed map model is Kimi; see the correction): five skills and 15 objectives survived normalization; indentation and the distinction between `a  b` and `a b` remained intact. Some inferred skills overlap; no correctness fix was inferred from that one sample. |
| Source selection | No broad-pass source was clipped. A 43,209-character synthetic source became 24,000 characters with head/middle/tail selection; `truncated=true` stayed true for previously false, true and unknown flags. Some passages necessarily disappear. The marker is omission provenance, not proof the retained context is sufficient. |
| Author and initial key | Raw responses already contain wrong keys, missing alternatives, invented conditions and weak distractors. These precede sanitizer or transport changes. Higher difficulty frequently produces oversized and semantically defective drafts. |
| Parsing and normalization | Strict whole-response JSON and exact choice/feedback identity correctly fail closed. They also expose repeated provider envelope/length violations. A separate deterministic echo heuristic was deleting necessary stimulus and is now fixed. |
| Solver and reviewer | The original source-removal interpretation was too broad: learned facts may be recalled. The corrected solver retains sources but excludes hidden goal/objective intent. Models can still ignore uncertainty, change interpretation, or write false teaching. |
| Filtering and replacement | Every failed attempt is captured. The 51-call broad run requested 24 slots, authored 49 drafts and returned 10. A structural exclusion does not count as detecting an underlying semantic error. No retry or rejection layer was added. |
| Bank and transport | Actual bank preparation and JSON roundtrips retain content, plus existing offline worker/claim/replay tests. No live learner storage was touched. Old policy stamps are not upgraded on read. |
| iOS display and grading | The attempt screen displays topic, stem and shuffled choices, not source documents or objective metadata. Exact UTF-8 grading, feedback keys, persistence and all four option rotations were checked. The corrected client requires policy 8 for fresh practice; historical wire-version-1 grading stays intact. |

[Goal/source trace](evidence/correctness-audit-20260912/goal-source-path/inference.json)
and [truncation probes](evidence/correctness-audit-20260912/goal-source-path/truncation.json)
cover ingress separately from the generation matrix. This was not a live
inferred-map-to-bank-to-phone session; those later boundaries were exercised
locally and in client tests.

## Supported causes, ranked before implementation

The [broad-pass report](QUESTION_CORRECTNESS_BROAD_PASS_20260912.md) was committed
before choosing the runtime interventions.

1. **Response contracts repeatedly lose otherwise solvable output.** Of 31
   sanitizer survivors, 13 are lost at solver envelope validation, four at
   reviewer JSON validation and one at exact feedback-key validation. Probability
   and SQL reasoning is often correct in the surrounding prose. Native schema
   controls recover some valid output, but do not constrain reasoning truth or
   all application length limits. Parser leniency would revive an earlier defect.
2. **The author introduces substantive errors.** Examples include omitting a
   parameter interval in algebra, confusing parameter values with number of
   roots, mixing consumed biomass with prey production, inconsistent algorithm
   bounds, missing a Spanish verb, and keys that contradict the author's own
   calculations. Eighteen of 49 broad drafts fail size constraints before these
   defects can be semantically assessed. More rejection is not a repair.
3. **Verification can supply an intended problem instead of checking the actual
   one.** Ambiguous articles, solstice assumptions, and the whale example show
   unjustified interpretation. The fictional source controls do not establish
   this failure: source facts can legitimately support recall. A neighboring-item
   inference remains observable in an intermediate source-removal experiment.
4. **A deterministic sanitizer deletes required content.** Four trailing lines
   matching choices were treated as redundant even when their order was the
   stimulus. The same mechanism affects code output, measurements, a poem and
   a travel sequence. Preserving those lines restores the actual task.
5. **Final teaching can become wrong after a correct answer is found.** Reviewers
   invent explanations for distractors, sometimes introducing an arithmetic or
   join error absent from the authored main. Conversely, SQL authored mains are
   sometimes wrong and review repairs them. A wholesale switch to frozen author
   teaching is therefore not justified by this evidence or the previous trials.

## Representative complete traces

| Case | Earliest failure and downstream behavior | Evidence |
| --- | --- | --- |
| Conditional probability | Complete rates → correctly keyed drafts, one arithmetic typo in authored teaching → intact questions → solver calculates about 26.9% and 16.6% correctly → prose around JSON rejects the whole batch → replacement repeats the failure. Native matched verification later returns both with supported teaching. | [Broad](evidence/correctness-audit-20260912/baseline/math_probability.json), [native](evidence/correctness-audit-20260912/native-matched/math_probability_native.json) |
| Ordered measurements | Author gives four ordered readings and asks for one position → old sanitizer removes all readings → solver cannot establish original order from shuffled choices → no return. Preserved stimulus → correct solution and teaching → unchanged bank/transport content. | [Before](evidence/correctness-audit-20260912/stimulus-matched/current.json), [after](evidence/correctness-audit-20260912/stimulus-matched/preserve.json) |
| Fictional scoring | Source rule supports four-token arithmetic. Removing sources blocks this learned-fact application; this was wrongly classified as fixing an invalid question. The continuation explicitly compares valid source recall with missing case data. | [Historical reference arm](evidence/correctness-audit-20260912/context-final/reference_native.json), [corrected controls](evidence/correctness-continuation-20260912/source-recall/plan.json) |
| Algebra with excluded root | Raw question excludes `x=2`; author invents an `a=9` boundary and keys one parameter value. Solver treats the excluded `x=2` as valid and also supports one. Another item's oversized reason rejects the entire batch, hiding this confidently wrong agreement. Independent analysis gives no parameter value with exactly one allowed root. | [Fresh native math](evidence/correctness-audit-20260912/fresh-paired/fresh_math_native.json), [calculations](evidence/correctness-audit-20260912/followup-independent-checks.json) |
| SQL ON/WHERE | Author keys three rows correctly but invents join matches in its main. Prototype solver self-corrects, then exceeds the reason-length bound. Final recheck returns the correct key and a sound main, but invents an explanation for distractor five: allowing all B matches would produce four rows, not five. | [Fresh author](evidence/correctness-audit-20260912/fresh-paired/fresh_sql_native.json), [final review](evidence/correctness-audit-20260912/final-recheck/fresh_sql_native_recheck_native.json) |
| English articles | Source allows type readings of mass nouns → author creates bronze/oil blanks with alternatives → solver imposes an unstated generic reading → reviewer repeats the exclusion and falsely disallows `an oil` → accepted. | [Broad article trace](evidence/correctness-audit-20260912/baseline/language_articles.json) |
| Whale reference | Stem asks why confusion *might* arise, without establishing different animals → author/solver/reviewer treat two distinct whales as fact. The suggested explanation is plausible, but the main and feedback overstate what the stem supports. Still accepted after the boundary change. | [Final recheck](evidence/correctness-audit-20260912/final-recheck/fresh_language_legacy_recheck_native.json) |

Every new draft has an item-level assessment in the
[49-item broad ledger](evidence/correctness-audit-20260912/assessment.json) or
[16-item fresh ledger](evidence/correctness-audit-20260912/followup-assessment.json).
Calculations and SQLite execution independently check scoped mathematical and
query claims. Primary references include [NASA on seasons](https://spaceplace.nasa.gov/seasons/en/),
[National Archives chronology](https://www.archives.gov/founding-docs/timeline),
[RAE on mood](https://www.rae.es/libro-estilo-lengua-espa%C3%B1ola/el-modo-indicativo-o-subjuntivo),
and [NOAA's solar equations](https://www.gml.noaa.gov/grad/solcalc/solareqns.PDF).
For example, an illustrative NOAA calculation places Cape Town's earliest civil
sunrise before December 21, contradicting a reviewer's solstice generalization.
Language judgments and stipulated historical artifacts retain explicit uncertainty;
these are assistant assessments, not a blinded expert panel or learner study.

## What changed and measured results

**Stimulus preservation** keeps the complete subject text, using echo recognition
only on an inspection copy. iOS recognizes matching labeled lines independent of
choice rotation without deleting them. Unmatched embedded options and existing
length limits still apply. [Implementation and controls](QUESTION_STIMULUS_PRESERVATION_20260912.md).

**Source-supported solving** supersedes the displayed-only policy. Learned source
facts are retained, while authored item tags and feedback are excluded. New production
stamps are 8/9; historical paths retain their own revisions. The original 102-call
results below describe the earlier proposal, not the corrected implementation.
[Current contract and release order](QUESTION_SOURCE_SUPPORTED_POLICY_20260912.md).

| Matched input | Before | After | Calls before → after | Seconds before → after |
| --- | --- | --- | --- | --- |
| Four sequence questions, unchanged author drafts | 0/4 answerable returns | 4/4 correct with supported teaching | 1 → 2 | 8.627 → 10.337 |
| Four source-dependent questions + four stated-rule controls, native in both arms | All 8 accepted | Only the 4 stated-rule controls retained; not proof of four false accepts removed | 2 → 2 | 24.529 → 19.652 |
| Eight fixed broad drafts, legacy vs existing native transport | 0 returned | 5 correct-key returns; 4 with fully supported teaching | 4 → 7 | 51.850 → 61.278 |

The sequence change raises useful output per call from 0 to 2: the extra call is
the existing reviewer becoming reachable. The context comparison preserves all
four stated-rule controls while losing four source-dependent items. **One after-control
still has false distractor feedback**, so only three of those four have fully
supported teaching. The intervention does not solve the independent reviewer
problem. These single draws do not establish statistical latency improvements.

Native transport was a controlled experiment using the existing feature, not a
new runtime/default change. It repaired recurring envelopes but one newly
returned SQL item still had false feedback. The fresh full-native arms returned
zero questions because of invalid author keys, oversized solver reasons or
insufficient difficulty. The global native switch also includes the deployed
Nova Lite API author, which is outside the implementation's supported allowlist.
It remains opt-in; no model, thinking or deployed transport setting was promoted.

## Fresh validation and useful yield

Four new requests covered real parameter equations, SQLite joins, English
reference and solstice/daylight inference. Each requested two questions at
minimum difficulty 3 or 4; two requests were sourced and two source-free.
Each request ran once per legacy/native arm, alternating order: **16 drafts,
19 calls, 154.259 seconds, two returns**. Only the curator question had clearly
supported key and complete teaching; the whale item still overstates a possible
interpretation. The native math and SQL batches also show that well-formed JSON
can exceed the 600-character reason contract or contain incorrect judgments.

Those fresh pairs tested the intermediate displayed-field version before the
final item-independence wording. For final validation, every draft from the
**first-executed arm** of each pair was reused, independent of prior correctness
or survival. The final boundary with native transport returned **4/8** in
**7 calls, 53.183 seconds**. Two had fully supported key and teaching (the
three-root quadratic and curator question), giving **0.286 fully supported items
per call**. SQL's key is correct but distractor teaching is false; the whale's
teaching is unsupported. A valid radical-sum question was correctly solved but
rated below the requested difficulty. Both factual drafts were blocked by key
disagreement; the ambiguous one was not competently diagnosed as ambiguous.

These are deliberately small, difficult qualification samples. The initial
broad run returned 10/24, but three returns have interpretation problems and
another has false feedback. Six have supported key/teaching under the stated
scope (including one stipulated historical scenario); four of those six have
weak distractors, leaving only two comfortably meeting the full standard. The
fresh requests differ from the initial matrix, and some recheck arms also change
transport. **No aggregate before/after production accuracy claim is warranted.**

All calls, latencies and token usage are itemized in the
[run summary](evidence/correctness-audit-20260912/run-summary.json).
Allocation: 51 broad calls, 16 diagnostic-control calls, 35 intervention/validation
calls including the one normal-goal map inference. The cap was 72 + 16 + 36 = 124.
Zero-call preflight failures are retained. No additional live testing is pending.

## Verification, delivery and remaining work

- **1,061 backend tests pass**, along with Ruff and `git diff --check`.
- The final iOS run executes **1,034 tests, one existing skip, zero failures**.
  Two app-group tests were excluded after reproducing their same three assertions
  on unchanged main in the unsigned simulator. No unrelated Screen Time code was
  changed. The earlier full run's additional echo expectation was updated to the
  intended intact-content contract, then passed in the final run.
- Shared fixture tests cover literal text, Unicode identity, all four choice
  rotations, exact feedback keys, stored snapshots, grading and policy admission.
  Existing complete-choice, batch-correlation, shared-answer-vocabulary and
  negation/prefilter regressions remain passing.
- Changes and evidence are committed and pushed on the audit branch. No merge,
  backend deployment, app installation or learner-bank mutation occurred.
  **Deploy API support and all generating workers before a client requiring
  policy 8**, or the new client can reject old inventory without a working refill.

The unresolved risks are substantive: authors can omit a defensible alternative,
solvers can force one answer while their own reasons express uncertainty,
reviewers can introduce false distractor stories, and tight output/difficulty
contracts can waste correct work. Per-item independence is a model instruction,
not separate provider isolation. The continuation confirms that displayed-only solving unnecessarily
rejects valid source recall; it is superseded by the source-supported contract. The current evidence does not justify more phrase rules,
blanket explanation preservation, relaxed parsing, extra retries or a general
reliability claim. Any further model/transport redesign should be qualified on
these retained failures and independently assessed fresh samples before release.

## Reproduction and evidence integrity

The dry-by-default runners are `checkpoint_correctness_trace.py` (12 frozen
requests), `checkpoint_correctness_matched.py` (fixed-author controls), and
`checkpoint_correctness_fresh.py` (four new paired requests). They live under
`backend/bedrock-question-service/evals/`. Execution requires `--execute`; files
are written to a new directory. Actual SDK calls are capped, errors retain only
their types, and no bank is mutated. Inspect each saved `plan.json` before use.

Historical traces record the exact actual provider requests. Broad and original
native/source/stimulus controls ran before the runtime changes; the intermediate
and fresh plans record source-file hashes of their uncommitted prototype. Current
runners execute current code, so rerunning is a new experiment, not reproduction
of the old source by assertion. The original fresh runner had a six-call capture
ceiling with one generation pass; observed jobs used only two or three calls
and stayed within its 24-call batch allowance. The checked-in runner now enforces
three actual calls per fresh job. A later two-call fixed-author preflight was
corrected without invoking any provider in its failed attempt.

Traces use only synthetic task material and omit credentials, SDK headers,
account identifiers, raw SDK error details and separate reasoning blocks. The
recorded provider text includes its actual user-visible prose, because those
extra-envelope responses are part of the contract failure being investigated.
