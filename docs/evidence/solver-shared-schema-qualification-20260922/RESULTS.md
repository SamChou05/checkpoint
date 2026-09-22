# Shared-definition solver: count-five structure qualified, semantic error retained

The two approved v5 requests completed with `end_turn` inside the 75-second bound and passed native-schema validation, the actual strict local solver validator, and exact identity/content checks. Structural qualification is **true for these two count-five batches**. There were exactly two dispatches, no SDK or application retries, no truncations, and no failed or unattempted calls.

The provider accepted the 1,489-character schema with shared internal definitions. Its recursive expansion equals the failed 11,798-character v4 schema as a JSON value, preserving every required identity, choice/pair slot, field, and enum. The app's strict expanded validation and local reason limits remain in force. This resolves the observed service rejection for these two requests without relaxing the logical contract. The earlier failed v4 qualification and its separate grammar-size diagnostic remain unchanged.

| Structural check | Passed / planned |
| --- | ---: |
| Bounded `end_turn`, native and strict local responses | 2 / 2 |
| Trusted question identities | 10 / 10 |
| Exact choice slots | 40 / 40 |
| Exact pair slots | 60 / 60 |
| Choice reasons emitted before judgments | 40 / 40 |
| Pair reasons emitted before relations | 60 / 60 |

All exact offered text, pair endpoints, judgment/relation fields, and visible reason strings survived native adaptation and local decoding unchanged. The adapter restores only each trusted question index. Existing local validation may reverse the two endpoints to match the trusted offered list; the exact unordered pair binding remains the same. No strings were normalized, inferred, repaired, or rewritten.

Semantic results are separate: **40/40 correctness labels, 59/60 pair labels, and 10/10 eligibility outcomes** matched unchanged gold. All four eligible controls were retained and all six defective controls were excluded. Only nine of ten items had every label and eligibility outcome correct. These are repeated diagnostic controls, not fresh holdouts or a population accuracy estimate.

The remaining material error is concrete. The dispatch question binds `b` to “Cancel dispatch.” and `c` to “Send the parcel.”, and explicitly supplies those endpoints for `bc`. The model nevertheless marked `bc` equivalent and wrote a reason about **b and d**, the two cancellation alternatives. The returned slot and app decoding are correct; the model associated the wrong choices with that slot's semantic claim. It also correctly marked the actual `bd` cancellation pair equivalent, so rejecting this item remained the correct eligibility outcome. A correct gate outcome does not erase the extra false equivalence or its false reason.

Private reasons also contain narrower precision or speculation concerns: two distinct-pair reasons write `3/9 = 0.333` instead of an approximation, and the pencil distractor reason makes an unsupported broad claim about “any natural misapplication.” Their final labels are correct. These solver reasons are not learner feedback, but they prevent treating structurally valid explanations as automatically accurate or fully grounded. The independent audit read all 100 visible reasons: 96 were grounded, one had the wrong pair reference and relation, two had inexact decimal equality, and one contained the uncertain generalization. These private-reason findings remain separate from the structural pass.

| Call | Elapsed seconds | Input tokens | Output tokens |
| --- | ---: | ---: | ---: |
| First five-item batch | 64.614 | 3,743 | 3,117 |
| Second five-item batch | 32.737 | 3,755 | 3,318 |
| Total | 97.351 | 7,498 | 6,435 |

Total observed usage was 13,933 tokens, with no unknown-usage calls. Both provider reasoning blocks were omitted from capture; only their count is retained. No monetary price estimate was made. The first call's latency was substantially closer to the 75-second bound; this two-call component trial does not establish worker yield or total pipeline latency.

The actual isolated code had passed 1,150 backend tests, Ruff, SAM lint/build, and packaged SDK checks of 90 configurations per artifact across three artifacts. The nine new probe groups and no-network replay pass. Live service qualification is limited to **count five with the frozen Sonnet 4.6 adaptive/high configuration**. Other locally supported counts, broad semantic reliability, production thinking defaults, and end-to-end learner quality are outside this trial. No additional calls were made to improve these results.

Frozen plan SHA256: `3802a77697d39433b3dabe5f349f39c53e3a397e1a57cbc081d8c8edae5ef6a8`.

Frozen capture SHA256: `9764085b7222cccdd675a86a7adef34e39cf704c5ad57e31fa96e1bc292c3b5b`.

Native `complete_choice_solver_v5_n5` schema SHA256: `0949077dd2f0202a8943462ef810bc305b4bb382d2abec366853e9f6db52447f`.

Independent audit SHA256: `495be7e327ae05ace5d966e3aead092dc1727e849805f5755e428f4597edf748`.

`replay.py` reproduces both exact requests and strict assessments without credentials or network access. `runtime-reconstruction.json` and the zero-context `runtime-source.patch` preserve all 23 pinned temporary runtime modules. Reconstruct an isolated checkout at the recorded Git base, run `git apply --unidiff-zero runtime-source.patch`, and verify every hash. The reconstruction was independently performed before handoff and matched all 23 hashes. Do not overwrite unrelated work to reproduce it.
