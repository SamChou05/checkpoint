# Singleton diagnostic stopped after two of six calls

The item-isolation diagnostic failed its unchanged operational and content criteria. The first singleton correctly rejected the equivalent wrong answers `2` and `two`. The second returned a 648-codepoint reason, exceeding the strict 600 limit, and the runner stopped all remaining calls. Its raw verdict also falsely accepted the ambiguous semicolon question and endorsed the same inaccurate punctuation rule seen in the batched trials. That failed response receives no strict disposition credit or admission.

Plan SHA: `d93534641c0f43500af77fb3b407f39888ea3f59c8584ab4b1160d9433cb11b2`. Capture SHA: `a3dcbeba3f4922da7cace58fbb16524ab2ca45f6f2eec13c1fd5478e1c245f93`. The original short auditor prompt, model, settings, task scope, learner bytes and gold were retained. Each request contains one original supplemental payload at trusted ID0 with the same prototype's count-one native schema. No neighboring learner items are included. Earlier trials remain unchanged and failed.

## Complete denominator and observed content

Six calls and six cases were planned. Two were attempted: one passed strict validation and one failed its reason bound. Four calls were unattempted under the frozen stop rule. Both attempted outputs were parseable native-schema-valid closed identity maps and ended with end_turn; the schema constrains identities and types, while the 600-character limit is checked locally. The strict denominator is one correctly rejected defective item out of six planned cases, with no sound retention measurement: all three sound cases were among the four unattempted calls. There were no selected learner payloads. Do not infer safe admission from the vacuous unchanged-content result.

The first reason accurately states that the numerical task gives `2` and `two` the same proposed value despite their different written forms. It has 429 codepoints. This is a concrete successful duplicate-distractor judgment, but this same original short prompt had also rejected that item in the earlier batched Sonnet adaptive-only trial. It does not establish that isolation fixed a regression observed under the different adversarial prompt.

The second raw reason incorrectly says that however must be preceded by the semicolon, calls the comma-however-semicolon option misplaced, and endorses the corresponding feedback. The literal stem does not require the adverb to begin the second clause. Bruce Aune's R2 permits it to attach to the first clause, set off by a comma, followed by the semicolon between independent clauses. Thus at least two offered constructions are defensible. [Primary grammar source, printed page5](https://cse.buffalo.edu/~rapaport/Papers/Papers.by.Others/aune01-punctuation.pdf).

The same semantic error appears when that learner payload is alone. Neighboring paired content is therefore not necessary for this observed error. This does not prove that context never matters: isolation simultaneously changes neighboring context, workload and schema cardinality, and the old baseline was not concurrent or randomized. The long reason and failed semantics remain separate observations; shortening it mechanically would not make the accepted item correct.

Independent audit of both returned reasons confirms the successful numerical-duplicate judgment, the semicolon's false raw acceptance and the exact 648-character local violation. It verified all six planned request reductions, both actual requests and native schemas, unchanged original inputs, zero selection, and the denominator of one strict-valid, one failed and four unattempted cases. Its SHA is `3805f4318645145a7553b165ac8c1eefde44cd4182e713e8f6e21da14161066d`. No raw failed verdict is reclassified as a valid stage result, and no unattempted control is treated as passed.

## Time, usage and verification

| Item | Time | Input tokens | Output tokens | Strict result |
|---|---:|---:|---:|---|
| Equivalent wrong numerical choices | 29.651s | 815 | 891 | Valid rejection |
| Ambiguous semicolon | 12.717s | 1,037 | 1,015 | 648-character reason exceeds 600 |

Total time was 42.368s, with 1,852 input and 1,906 output tokens (3,758 total). Both calls finished inside 75s and all usage was known. There were no SDK retries, warmups, replacements, timeouts, truncations or extra dispatches. Two provider reasoning blocks were removed before saving; no reasoning text/signatures were retained. Both raw rows place reason before verdict; only the first is a strict-valid row.

Exact no-network replay verifies all frozen source/dependency/request hashes, reproduces the successful count-one validation and the 648-character failure, and preserves the six-case denominator. Seven new offline test groups cover payload/gold/order/scope/prompt parity, exactly six maximum calls with no resume, transport/truncation/local failure stops, redaction, unchanged selected originals, and one SDK attempt with the exact timeout configuration. Together with the earlier harness groups, 33 tests pass. This incomplete diagnostic does not qualify a production model, prompt, per-item architecture or call budget. No production edits or additional calls are authorized or performed.
