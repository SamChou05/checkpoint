# Fresh questions with an authored worked solution

September 8, 2026. Prospective protocol; no calls or results in this trial yet.

This trial tests fresh generation through the opt-in `authored_solution` path:
the author completes the main worked explanation, the complete-choice solver
checks the answers without seeing that explanation or the key, and the final
auditor assesses the unchanged question and main explanation. The auditor cannot
write replacement teaching. It does not receive the solver's judgments or reasons;
the explanation itself can reveal the intended answer, so this audit is not
answer-blind. Application-enforced agreement and unchanged text do not prove truth.

## Frozen goals and source scope

The [fixture](evidence/authored-solution-fresh-fixture-20260908.json) requests two
MCQs per goal, with minimum difficulty 3, in this order:

| Goal | Source | Intended application depth |
| --- | --- | --- |
| Houseplant propagation decisions | UMN and Iowa State Extension | Combine species, retained tissue and root/growth observations to justify a next step |
| English articles in context | Cambridge English Grammar Today | Interpret shared reference, countability and intended meaning across a short context |
| Topographic contour profiles | USGS Topographic Map Symbols | Combine fully stated contour labels and spacing to distinguish terrain profiles |

These are short, explicitly labeled assistant paraphrases of primary sources read
on September 8. URLs, source locations, hashes and omitted-material limits are
recorded separately. They are neither invented quotations nor automatic full-page
acquisition records. `truncated: true` discloses intentional source abridgement;
the complete supplied summaries survive normalization unchanged. No ready-made
question, key or worked example is supplied. Only each case's `payload` enters
model requests; prospective assessment and provenance metadata remain external.

## Calls and preservation

Use Kimi K2.5 for authoring and Sonnet 4.6 for both checks, explicitly disabled
thinking, temperature 0.2 and 6,000 output tokens. Set one generation attempt and
a three-call allowance per goal: at most nine calls overall. Retain read75/connect3,
one SDK attempt and a separate 240-second operation window per goal. Each serialized
request has a 32 KiB input limit; the total is at most 288 KiB. Bytes are not tokens.

Freeze implemented source/dependency hashes, this fixture, normalized requests,
exact initial author requests and the plan hash before dispatch. Persist every
dynamic request before calling. Retain exact responses, usage or explicit unknowns,
stop reasons, stage decisions and cleanup observations. An operational, binding,
persistence or cleanup failure stops remaining work. No fallback, transport retry,
replacement goal, resume or added repair/top-up capacity is permitted. Any existing
runtime JSON-repair attempt consumes the same three-call allowance and makes the
full favorable criterion fail.

Preserve every raw candidate and all contract, semantic and difficulty rejections.
Bind raw, sanitized and returned text variants with exact item/choice joins. The
main explanation must survive acceptance unchanged. The author instruction limits
it to 320 characters; runtime validation permits up to 420. Record both, and require
the tighter author bound for the full favorable result. Stem and choice limits
remain 320 and 140. `choiceExplanations` must be absent or an empty object:
**nonempty or wrongly typed choice feedback is a construction-contract failure**,
not optional material to delete. Preserve such rejected text in the evidence.

## Assessment and decision

Freeze independent stem/choice assessments before exposing keys, teaching or model
verdicts. Then assess each exact main explanation. Check unique warranted answers,
complete premises, three distinct plausible distractors, goal fit and independent
difficulty. A worked main must supply the decisive reasoning and necessary
qualifications; a correct key or named rule alone is insufficient. Preserve
disagreements and distinguish falsehood, unsupported strengthening and conventional
model assumptions. Missing content is unobserved, not correct.

For a fully favorable result, all six items—two per goal—must satisfy those checks
at actual difficulty 3 or higher in the first unrepaired pass. Method lookup,
isolated article-sound recognition and simple elevation subtraction do not meet
that threshold by themselves. No unseen map, unstated grammatical reference or
invented propagation observation may supply a missing premise.

Partial yield and specific defects remain reportable but do not meet this criterion.
Even six successes establish only selected-goal feasibility, not a general error
rate, calibrated difficulty, learning benefit or release readiness. This changes
construction and audit responsibilities; it is not a matched causal comparison
with the earlier five-question batch. No production default, inventory or deployment
changes follow automatically.
