# Claim-directed evidence comparison

September 8, 2026. This eval-only experiment adds an actual discovery → public
page acquisition → unchanged-question review round. Earlier supplied-source
experiments selected sources before the model inspected the generated question.
This trial lets discovery target one exact claim and locate sources itself.

## Frozen comparison

The fixture is `backend/bedrock-question-service/evals/fixtures/question_claim_evidence.json`.
Its four raw questions and original goals are copied exactly from archived
teaching/stem packets, with hashes and candidate locators. Existing curated
source documents are excluded identically from both review arms. No assessor
answer, source URL, truth label, or suggested correction is supplied to discovery.

| Case | Independently assessed control role |
| --- | --- |
| `dough_reference` | Defect: key/main explain the first introduction although the stem asks about the second occurrence. Do not reject through a false claim that “a dough” is always ungrammatical. |
| `hotel_reference` | Supported contextual reference, key and main. Avoid an unconditional second-mention rule. |
| `butter_reference` | Supported key, defective generic-reference teaching: the recipe introduces an unspecified quantity, not butter as a class. |
| `plant_tissue` | Supported available-tissue choice and main for Monstera and African violet. Avoid universal claims about all leaves or guaranteed propagation success. |

Both archived assessors agree on these material classifications. All four are
independently level 2; their mains exceed the author instruction's 320 characters
but fit the 420-character runtime bound. This diagnostic explicitly uses a
minimum of 2 in both arms. It does not change the production difficulty floor,
qualify advanced learning, or relabel the historical request.

## Mechanism and limits

1. Nova 2 Lite, with its native `nova_grounding` tool, identifies one exact field
   quotation to check and searches for primary evidence, including exceptions.
   The author key/difficulty are hidden; the unchanged main can reveal intent.
2. Only native citation `location.web.url` entries can initiate acquisition.
   Model prose URLs and quotations are never fetched as citations or supplied as
   captured evidence. Fetch the first two distinct cited URLs, using the existing
   HTTPS/DNS/redirect/body safeguards. Retain acquisition failures.
3. Select at most one unchanged 8,000-character window per acquired page through
   a general lexical query/target matching rule. Preserve hashes, offsets,
   representation limits, truncation and omitted-text flags. No model creates or
   rewrites the selected passages.
4. Sonnet 4.6 reviews the complete unchanged question and main twice, with the
   same challenge, system prompt and context. Only `acquiredSources` differs;
   the runner enforces that before dispatch. Arm order alternates by case.
   The shared discovery hypothesis may already reflect hidden search results;
   this tests the incremental value of actual passages, not complete information
   independence. All model declarations remain fallible.
5. Bind quoted evidence to unique exact source substrings and echo the exact
   challenged field. A target contradiction or unresolved target cannot earn
   evidence eligibility. Record the full-item declared judgment separately:
   the empty-source control can never earn evidence eligibility, so comparing
   eligibility alone would be misleading. No question is rewritten or stamped.

At most 12 single-attempt model calls and eight page acquisitions. Discovery
uses a 2,048-token allowance; review uses 6,000 tokens, temperature 0.2 and disabled
thinking. Both workers use read75/connect3 and a 90-second local deadline with
existing bounded cleanup. Native search count has no enforceable ceiling inside
one Nova call. Fetch I/O is budgeted at 20 seconds per page; blocking system DNS
and parent persistence are not hard real-time. No response does not mean remote
cancellation or zero billing.

Every actual request is persisted before its worker starts. Source/dependency/
fixture hashes bind the plan. Output directories are exclusive: no retry, repair,
resume, fallback, source replacement or rerun of a timed-out dispatch. A provider,
unfinished-response, cleanup or persistence failure stops later calls. A malformed
discovery ends its case; failed acquisition cannot count as a correctness catch.

## Prospective interpretation

Require both defective complete items to be rejected for supported reasons and
both valid controls to retain their exact supported keys and main content. Inspect
all alternatives, not only key agreement. Count incremental catches over the
matched baseline and record any new false rejection. Distinguish target selection,
source relevance/acquisition, exact quotation fidelity, semantic judgment, output
format, and difficulty. An unrelated true quotation is not proof of entailment.

A promising result requires an incremental defect catch without losing a valid
control, plus faithful relevant passages. Even that would only justify testing
fresh generation across more goals; this selected four-item comparison is not a
production accuracy estimate, learning-outcome study or release qualification.

Human assessment references remain outside model inputs: [Cambridge articles](https://dictionary.cambridge.org/grammar/british-grammar/a-an-and-the),
[UMN Monstera propagation](https://extension.umn.edu/garden-and-home/yard-and-garden/gardening-in-minnesota/propagating-monstera-deliciosa),
and [Iowa State houseplant propagation](https://yardandgarden.extension.iastate.edu/how-to/propagating-houseplants).
Contextual application of article guidance is an assessment, not a quoted answer
key. [CRITIC](https://arxiv.org/abs/2305.11738) motivates testing external feedback;
it does not establish MCQ accuracy. [AWS Nova grounding](https://docs.aws.amazon.com/nova/latest/nova2-userguide/web-grounding.html)
and [Converse](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/bedrock-runtime/client/converse.html)
document the native interface; citations still need separate acquisition and
semantic checking.

The implementation milestone passed 928 backend tests, Ruff, Python compilation,
the whitespace diff check, and independent review. Fixed callbacks validate the
bounded transport, source/request bindings and exact-content contracts; they do
not establish factual accuracy. No provider call or deployment was part of that
source milestone.
