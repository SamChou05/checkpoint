# Retrieved evidence reached review, but correctness is not qualified

The [citation-discovery follow-up](QUESTION_CITATION_DISCOVERY_FOLLOWUP.md)
completed the missing handoff: native citations led to separately fetched page
text, and both reviewers received matched inputs. All eight reviewer responses
were bare JSON satisfying the static schema. The trial nevertheless did not
establish an additional correct catch of either known defective question.

Evidence helped resolve uncertainty on one supported plant question. The English
reviews still misread the task or supplied evidence, and four responses failed
application checks despite satisfying the native schema. The prospective complete
criterion was not met. No production integration or model promotion follows.

## Results on the unchanged controls

| Case | Without acquired sources | With acquired sources | Independent interpretation |
| --- | --- | --- | --- |
| Dough | Invalid response: shortened frozen target | Invalid response: shortened target and altered source quotations | Both notice the real second-reference problem but retain the wrong authored key and give mixed reasoning. Source-backed objections incorrectly describe countability and miss the supplied recipe example. No valid additional catch. |
| Hotel | Supported key/main; no evidence eligibility | Supported key/main, but one quoted apostrophe differs from the source | Relevant evidence was found. This loses an otherwise supported control through quotation fidelity, not a factual objection. |
| Butter | Incorrectly approves the whole main | Invalid response: two records with duplicate index 0 | The source arm challenges the correct later reference and demands unnecessary explicit rule citation/refutation; it does not identify the actual generic-versus-unspecified-reference error. Its negative flags are not a correct catch. |
| Plant tissue | Uncertain without source support | Eligible with the unchanged supported key/main | One supported evidence-assisted resolution. It does not establish the truth of every surrounding source claim. |

All four questions were independently assessed at difficulty 2 before this run;
model ratings of 3 or 4 do not establish advanced-learning yield. This is a
selected diagnostic, not a production error-rate estimate or learner study.

## What the evidence established

Eight acquisition attempts produced six successful extraction records covering
five distinct pages; Toronto was acquired separately for two cases. A university
Pressbooks page returned HTTP 403. A Toronto PDF returned HTTP 200 but the current
acquirer rejects PDF media. All successful extracted records were untruncated;
five of six selected spans omitted other acquired text. The checker received
44,915 selected characters across the four cases, with explicit omission flags.

[Toronto's article guide](https://advice.writing.utoronto.ca/english-language/definite-article/)
contains both contextual exceptions and a recipe example explaining the mixture
reference. The dough reviewer overlooks that relevant supplied material.
[Test-English](https://test-english.com/explanation/a1/aan-no-article-articles/)
supports the hotel's ordinary discourse reference; the altered source quotation
should not become a fabricated exact quote. [Preply](https://preply.com/en/blog/how-to-use-english-articles/)
is topical secondary instruction, not evidence for a new conceptual state at the
dough's second mention.

Both plant pages came from one commercial publisher, Blooming Expert. Their
[Monstera](https://www.bloomingexpert.com/tips/monstera/propagate/) and
[African-violet](https://www.bloomingexpert.com/tips/houseplants/african-violets/leaf-propagation/)
recommendations support the narrower tissue pairing and agree with the earlier
primary-source assessment. The selected Monstera material contradicts itself
about whether node-free leaves can form roots. Correct support for a new-plant
conclusion does not certify that wider biology or provide independent agreement
between publishers. Asking for primary sources did not ensure their selection.

The native schema eliminated outside-JSON prose in this run. It did not enforce
exact target copying, source quotation fidelity, array cardinality or factual
truth. Both dough records shortened the frozen target from 405 to 246 characters.
The hotel source record changed an apostrophe inside one quotation. Butter
returned two otherwise shaped records sharing index 0. Existing application
checks rejected all four; their format/fidelity failures receive no factual-catch
credit. Exact quotations that do pass still do not prove semantic entailment.

## Operational evidence and limits

The [frozen plan](evidence/citation-discovery-plan-20260908.json) identifies source
`cb41f487f8a9bc2beb6d93bd86ee23593b0b5da7` and canonical plan hash
`6ae4c21692590c48c29d747380572dfd42ba0ff5adfc18fd3f4d4e7874e34fc6`.
The [public derived summary](evidence/citation-discovery-summary-20260908.json)
contains hashes, cleaned page URLs, usage, outcomes and quotation-fidelity
observations. It omits page text, source-bearing requests, model source quotations
and issue text; it is not a substitute raw capture or a standalone replay archive.
The original local capture is 466,891 bytes with SHA256
`f136a693f4fef8e72a6217924d1984021c0bbab1a46d3b4853fc60fe4d2f5a27`.

All 12 calls ended normally with known usage and confirmed worker cleanup. There
were six native tool uses, six successful hidden results and 13 native citation
entries. Total usage was 45,966 input and 4,390 output tokens. SDK intervals sum
to 85.285533 seconds and worker intervals to 92.918154 seconds; these are not
independently measured end-to-end wall time. Individual SDK intervals ranged
from 1.746 to 16.045 seconds, including the first structured review at 12.464
seconds. No output ceiling was reached. This observation does not establish
future cold-compilation time, repeated latency or production readiness.

Independent offline verification checked all 37 committed source hashes, exact
plan/request construction, original challenge bindings, native URL-to-acquisition
joins, extracted text hashes, selected offsets and rederived review outcomes.
Original HTTP bodies are not retained in the capture, so their recorded hashes
were not independently rehashed during replay. Schema compliance was checked
separately from application admission. Source validation passed 937 backend
tests; the evidence audit added no provider calls. No source/target repair,
retry, resumption, question-bank write or deployment occurred.

The implemented retrieval handoff and native schema are usable mechanisms, but
retrieved passages and schema compliance did not establish the required
correctness benefit. The next design must address both unnecessary model
retyping of immutable identifiers/text and the reviewer's failure to use relevant
qualifying evidence. Removing those fidelity failures alone would still leave
the documented semantic errors.
