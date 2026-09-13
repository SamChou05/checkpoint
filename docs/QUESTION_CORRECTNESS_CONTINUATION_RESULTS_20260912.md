> Current combined findings, policy 8/9 defaults and final fresh qualification: [final report](QUESTION_CORRECTNESS_ROOT_CAUSE_RESULTS_20260912.md). This document records its named milestone.

# Corrected findings and fresh qualification

> **Completion correction:** policy 6/7 also lost learned facts supplied in goal/skill prose. It is superseded by [subject-reference policy 8/9](QUESTION_SUBJECT_REFERENCE_POLICY_20260912.md). The final three-call control brings this phase to 48 calls; the 45-call counts below describe the earlier milestone.

The continuation corrects two audit conclusions and makes two general changes:

- **Retain learned study facts.** The earlier displayed-only proposal rejected valid recall from uploaded material. Its claim of four proven false accepts is withdrawn. Production solving now retains sources, excludes hidden goal/objective intent, and distinguishes source rules from missing case data. Author instructions recognize learned recall. Revisions 6/7 replace the proposed 4/5 without relabeling history.
- **Separate verifier transport from author compatibility.** `BEDROCK_VERIFICATION_STRUCTURED_OUTPUT_MODE` can select native Sonnet JSON while the API's Nova author remains legacy. SAM, deployment scripts and workflow carry the option to both functions. Default is `inherit`; no deployed setting was changed.
- **Correct deployed map attribution.** The API author is Nova Lite, but `SKILL_MAP_MODEL_ID` is Kimi K2.5. The earlier Nova map inference was a local override, not deployed-map qualification. API/worker code hashes and modification dates are unchanged in the fresh read-only check.
- **Reject the proposed teaching-prompt change.** Direct-contrast instructions repeated false SQL explanations and introduced a reversed division description. The runtime reviewer stays unchanged. Its initial local report also omitted saved solver responses; a zero-call replay correction replaces those counts without changing the live captures.

The valid stimulus-preservation fix and earlier shared-answer, strict parsing,
literal-content, budget, and history fixes remain intact. **The full pipeline is
still not reliably correct.** The work addresses demonstrated mechanisms without
claiming that schema compliance or model agreement proves truth.

## Matched controls and fresh results

| Experiment | Outcome | Actual calls |
| --- | --- | --- |
| Four-domain source boundary | Valid source recall/application: displayed 0/8, source-supported 8/8. Both block 4/4 missing-case items. Fully stated controls return 3/4 and 4/4; the extra veto has no stated reason. One source-arm survivor still has false distractor arithmetic. | 16 |
| Four exact prior teaching inputs, nine items per arm | Both return eight items through the corrected local contract replay, with different survivors. Candidate has no demonstrated general benefit and is not adopted. | 8 |
| Four new requests, each with Nova and Kimi author | 18 authored drafts including a malformed two-item envelope and its repair; 16 requested slots; 7 returns with supported keys/teaching, one of uncertain requested difficulty. | 21 |
| **Continuation total** | **45 of 48 allowed calls.** No call after transport failure, no new rejection layer or retry. | **45** |

The original investigation's 102 calls remain separate. Combined actual inference
count is **147**. Three calls remain unused in this continuation's ceiling; no
extra trial was invented to spend them. Source/teaching comparisons held model and
transport fixed. Fresh pairs hold request and final verification design fixed
while changing author; they are not a causal before/after test of source removal.

| Fresh request (two slots per author) | Nova calls / seconds / returns | Kimi calls / seconds / returns | Independent assessment |
| --- | --- | --- | --- |
| Multistep fractions/rates, source-free, level 4 | 3 / 13.144 / 0 | 2 / 21.107 / 0 | Nova offers numerically equivalent choices; solver catches that. Its other item is correct but level 2. Kimi's tank reason exceeds 600 characters; its other problem assumes equal distances for a different return path. Structural rejection is not evidence of detecting that ambiguity. |
| Python aliasing/slicing, source-free, level 3 | 3 / 10.275 / 0 | 3 / 21.158 / 2 | Nova emits malformed JSON, then keys strings when the stem asks for lists; solver repeats the type conflation. Existing repair exhausts the three-call experiment cap before review. Kimi's exact snippets execute to both keys; final review repairs one false solver aside and returns supported teaching. |
| English counterfactual time, sourced, level 3 | 1 / 2.698 / 0 | 3 / 25.079 / 1 | Nova outputs answer letters instead of exact choice text and repeats source examples. Kimi returns a correctly explained mixed conditional; pattern classification may be only level 2. Its second correct item is explicitly filtered as level 2. |
| Private archive handbook, sourced, level 1 | 3 / 8.153 / 2 | 3 / 9.351 / 2 | Both authors produce legitimate recall without repeating the answer. All four keys and every final explanation match the fictional handbook. Parallel named rooms/staff give plausible alternatives. |

Fresh job elapsed times sum to **110.965 seconds**. They are local provider-path
measurements, not Lambda/queue/device latency or a latency distribution. Native
verification produced **12/12 valid JSON envelopes** while preserving legacy
request format for all nine author calls. One native solver response still
violated the application's 600-character reason limit (744 characters), and
well-formed judgments still contain substantive mistakes. Keep the override
opt-in: this small sample supports compatibility, not a deployment-wide benefit
or a general model-ranking claim.

Seven returned items have supported keys and final teaching under their actual
stems and sources. Six clearly meet the requested minimum difficulty; one
conditional-classification item has a plausible level-2/3 dispute. That distinction
matters: 7/16 returned slots and 7/21 returns per call count output, whereas secure
requested-difficulty yield is **6/16** and **6/21**. These are not population rates.
Both level-4 jobs return zero. No new author model or reviewer responsibility was
promoted on this evidence.

## Trace-level findings and checks

Every actual response was read, including failed JSON and replacements. The
[18-draft ledger](evidence/correctness-continuation-20260912/fresh-assessment.json)
links each item to its author call and index, records the earliest error, later
judgments, distractor/difficulty assessment and final disposition. The
[independent checks](evidence/correctness-continuation-20260912/independent-checks.json)
execute the inspected Python snippets, use exact fractions, and execute the
teaching-control SQL in SQLite. For example:

- `3/2 = 6/4` demonstrates Nova's duplicate correct answers.
- Tank fill rate is `21/40` per hour and first capacity occurs at `12/7` hours. Zero extra minutes is defensible under normal overflow. The trace's unbounded `23/20` volume and unstated overflow behavior require care; this is not labeled a proved wrong key.
- With outward distance D and return distance R, cycling time is `7D/100 + R/15 = 5`. Both `(30,43.5)` and `(40,33)` satisfy it. `1500/41` follows only from the added equal-distance assumption.
- Actual Python list values are `['modified']` and `['changed']`, not the offered string values. The solver's own reasons show the list but approve the string; a budget stop must not be credited as catching this.
- The SQL control returns three rows. Removing the right-side filter gives four, not the distractor five the reviewer tried to explain.

The actual solver payloads contain only exact indexed topic/stem/choices plus
normalized sources; sources match the request exactly. Author key/feedback and
hidden intent are absent. Reviewer payloads retain the original goal and sources.
Sanitization preserves stems and exact choice values while reordering choices,
truncating long topic labels, and removing unassigned map tags. Two oversized
Kimi author explanations are shortened before solving, but author teaching is
hidden from both default verification stages; no shortened text reaches a learner
in these cases. All seven final stems, keys, options and feedback survive real
bank preparation and JSON transport unchanged. No live inventory was written.

## Verification and remaining limits

All **1,068 backend tests** and **seven focused iOS policy/history tests** pass.
Ruff, Python compilation, deployment-script checks, SAM lint/build, and isolated
SDK validation for all three packaged functions pass. All 60 original evidence
hashes and 31 continuation evidence hashes were verified. CI first
caught an omitted shell-fixture update after adding the transport parameter; the
56-argument forwarding checks now cover default inheritance and all explicit
verification modes without changing author mode. The Python suite had already
passed on that CI run. The earlier full iOS run passed 1,034 tests with one
existing skip after excluding two unsigned-simulator app-group tests reproduced
on unchanged main. Current CI status is recorded separately at handoff.

Release API claim support and **all generating workers before the client requires
policy 6**. Historical 1/2/3 and displayed 4/5 paths keep their own stamps; opt-in
authored teaching uses 7. No deployment, merge, app install or learner-bank migration
was performed. Work remains isolated from the original dirty checkout.

Unresolved mechanisms are recurring author contract/semantic errors, confident
solver type or assumption changes, false reviewer teaching, and difficulty/length
losses. Per-item independence remains an instruction, not provider isolation.
Excluding goal/objective prose may still discard a learned rule supplied only in
those fields; the fresh source controls do not quantify that case. The new source
boundary is qualified for supplied study documents, not every possible private
subject description. No broad false-rejection or accuracy rate can be estimated
from these small synthetic samples. This evidence does not justify another
subject-specific exception, phrase rule, relaxed parser, extra retry, or a claim
that the correctness problem is solved.

The source correction, independent transport option, and rejected prompt candidate
are reviewable on draft [PR #9](https://github.com/SamChou05/checkpoint/pull/9).
The [manifest](evidence/correctness-continuation-20260912/manifest.json) hashes all
continuation JSON evidence; original evidence hashes remain unchanged.
