# Checked-example transfer source packets

Prepared 2026-09-09 before author calls for `fresh-author-checked-examples-v1`. The fixture is `backend/bedrock-question-service/evals/fixtures/question_author_examples.json`. It contains exactly three fresh goal/source payloads, each requesting two questions at minimum difficulty 3. The transfer subjects are Excel cell references, map scale/distance, and food-web energy flow. They differ from the planned demonstrations about fictional parcel routing, experimental design and pronoun reference. Broad subject families are not claimed previously unseen: geography, biology and related reasoning have appeared elsewhere in this project.

Only `cases[].payload` supplies the transfer goal and source context to the author. The experiment adds demonstrations separately. The source preparation handoff leaves `demonstrations: []` for that work; the hashes below distinguish the transfer payloads from the later complete fixture. Assessment notes and this document are not author inputs. Payloads contain rules and subject context, with no question stems, answer choices, keys or worked questions. They do not prescribe which question the model must write.

## Source representation

All cited instructional sections were read using the web tool on 2026-09-09. The five supplied source documents are short, explicitly labeled assistant paraphrases with real URLs. They are not downloaded pages, quotations, independent retrieval records or evidence that a generated question is correct. `truncated: true` records intentional abridgement; normalization preserves the entire supplied text. No diagram, exercise, answer key or worked source example is reproduced.

| Transfer subject | Primary source read | Scope checked |
| --- | --- | --- |
| Excel | [Microsoft: Overview of formulas in Excel](https://support.microsoft.com/en-us/excel/get-started/overview-of-formulas-in-excel) | A1 reference style; relative, absolute and mixed references. The page lists Excel for Microsoft 365 and several desktop versions. The packet scopes tasks to copying/filling ordinary cells on one unchanged worksheet. |
| Map scale | [Ordnance Survey: Map reading made easy](https://www.ordnancesurvey.co.uk/documents/resources/map-reading-made-easy.pdf) | “What is scale?” and “How do we measure distance?” on PDF pages 9–11. Same-unit ratios, direct versus winding-route measurements, numerical conversion and scale bars. No map graphic or exercise is supplied. |
| Map reproduction | [Penn State: Graphic Map Scales](https://www.e-education.psu.edu/natureofgeoinfo/c2_p6.html), [Scale as a Verb](https://www.e-education.psu.edu/natureofgeoinfo/c2_p8.html) | Co-resized bars versus representative fractions, linear resizing versus area, geographic accuracy and nonuniform projection scale. Course materials by David DiBiase and contributors, Penn State College of Earth and Mineral Sciences. |
| Food-web structure | [OpenStax Biology 2e §46.1](https://openstax.org/books/biology-2e/pages/46-1-ecology-of-ecosystems) | Food chains and webs, species feeding across levels, food-to-consumer arrow convention, decomposers, heat loss and limits of conceptual models. Authors: Mary Ann Clark, Matthew Douglas and Jung Choi; publisher OpenStax, Rice University. |
| Trophic production | [OpenStax Biology 2e §46.2](https://openstax.org/books/biology-2e/pages/46-2-energy-flow-through-ecosystems) | Trophic-level transfer efficiency and ecological pyramids, especially the distinction between biomass at an instant and energy production over time. |

The summaries add explicit scope qualifications and simple dimensional implications of the cited rules. For example, comparing production requires matching area/time bases; an enlarged bar must share the map's resizing; ordinary formula-copy behavior is not a claim about moving cells. These are assistant clarifications, not verbatim statements from the sources. Penn State and the accessed OpenStax pages display Creative Commons Attribution-NonCommercial-ShareAlike licensing; this packet supplies brief factual paraphrases with attribution.

Source checking also found material deliberately excluded from the summaries. A separate [Microsoft reference-switching page](https://support.microsoft.com/en-us/excel/switch-between-relative-absolute-and-mixed-references) describes a down-one-row example as a rightward move; the overview page and that article's reference table agree on the actual rules. OpenStax's Silver Springs worked figures differ across passages, so none of those figures, worked calculations or the more problematic assimilation/NPE wording is supplied. USGS map-scale PDF fetches returned 403; their snippets are not the basis of this packet. These observations reinforce that citing a reputable page is not sufficient without checking the exact proposition.

Penn State access was inconsistent across URL routes: clicking from its `courses.ems.psu.edu` chapter initially returned both complete instructional pages, but later direct opens of those URLs returned 404. Both official `www.e-education.psu.edu` URLs in the packet returned full page text when rechecked, including a reported redirect for the graphic-scale page. The packet uses those successfully fetched entry URLs; it does not claim current origin availability independent of the web tool's returned content. Changing these URLs left the factual summaries unchanged.

## Prospective assessment caveats

- Excel: independently apply the row and column displacement to every reference. A formula must satisfy its intended behavior over the whole requested destination range. References that happen to return equal values in one cell are not generally interchangeable. Copying a cell, pasting raw formula text and cutting/moving cells are distinct operations. No live Excel execution was performed during packet preparation.
- Maps: distinguish original and resized copies, direct separation and route length, and linear and area factors. The learner goal explicitly assumes the stated scale is uniform over the measured local region; this is not a general claim about global maps. A co-resized bar preserves its calibration under uniform resizing. Unrepresented slope or detours cannot be inferred from map distance alone.
- Ecology: check feeding paths and each efficiency's numerator/denominator. A whole-level efficiency cannot be assigned independently to overlapping branches without an allocation model. Never substitute an exact universal ten-percent rule for supplied efficiencies, infer precise population changes from links alone, or equate standing biomass with energy production. A species feeding on multiple levels need not have one exclusive trophic role.

Minimum difficulty 3 remains an assessment requirement, not a label established by requesting it. Naming an anchor type, making one direct scale multiplication, identifying a producer or calculating one transfer percentage is insufficient for these learners. The selected subjects can support compact application questions; completeness, meaningful difficulty and three plausible distinct distractors must still be demonstrated in each generated item.

## Validation and identity

On 2026-09-09, Python 3.12 invoked the actual `request_contract._normalize_request` on each payload. All three normalized successfully, retained `targetCount == 2` and `minimumDifficulty == 3`, and preserved `sourceDocuments` exactly. Each case has only `case_id`, `payload` and `assessment_scope`; each payload has only `goal`, `targetCount`, `minimumDifficulty` and `sourceDocuments`. Every source text is below 1,000 characters. This is data-contract validation, not model-quality evidence.

At source preparation handoff after the Penn State URL correction, the fixture with empty demonstrations was 10,240 UTF-8 bytes. Its byte SHA-256 was `cd48d28155855e7409d1897fd08fa71501cb810e2a3f2fc1507f2bb060a41659`; its canonical SHA-256 was `a9b286bb9a53c8b260e6224e98b26d7a4e372abdeb7fff48b40ace11eebe9cfd`. Adding demonstrations changes both whole-fixture hashes. The per-payload identities below remain the check on unchanged transfer inputs.

Canonical JSON uses sorted keys, separators `(',', ':')`, `ensure_ascii=False`, UTF-8 and no trailing newline.

| Payload | Canonical bytes | Canonical SHA-256 |
| --- | ---: | --- |
| `excel_reference_copy_constraints` | 1,566 | `b01d9858892c90c6d13f5e7d295657cca86a42c21684b16c96c1a54cc0abf9b8` |
| `map_scale_distance_resizing` | 2,485 | `304c03f456c62de1146fd2e68a9137daff7eb785865bef4eb4ee0e8e1a78b8fe` |
| `food_web_energy_constraints` | 2,550 | `95ddab7d0f64501c83a9a7eaa7fea3d89b4c1d8cc7277912fef0496c612759f1` |

| Supplied source text | UTF-8 bytes / characters | Summary words, excluding label/URL | SHA-256 of exact text |
| --- | ---: | ---: | --- |
| Microsoft reference rules | 800 | 94 | `49a9147360992767e32f63f0ea04920ce4d8c79e678da2123d08c5862450adfb` |
| Ordnance Survey map distance | 815 | 87 | `c269fb2919150eaa747849ec768cb200700c906ac0e843e5d9fc78ed719d6e7c` |
| Penn State map reproduction | 810 | 93 | `9f845331a722847c89aee587ebb734d3e3cd9222811d5bfea79910096736d5cf` |
| OpenStax food-web structure | 832 | 98 | `011209160890fc88f5321d316622d4d5a4a3e9d4d3a0c351e12225d4709cde79` |
| OpenStax trophic production | 857 | 85 | `29319d93c38c19ceed6ed86ae512d0aa0a983773152eae868169ae5c32b40817` |
