# Closed pronoun-role constructor prototype

This standalone, offline prototype turns the two independently reviewed
[pronoun-role formats](../pronoun-role-format-probe-20260927/RESULTS.md) into
code-owned multiple-choice questions. It is **not** imported by the provider
schema, adapter, worker, selector, or production route.

`pronoun_role_task_constructor.py` accepts only `kind=pronoun_role_v1`, one of
eight reviewed scene IDs, and `order=forward|reverse`. Four single-speaker
scenes vary objects and actions in a quoted `I/my/you/your` plan; four
two-speaker scenes vary a proposed action and offered tool. Each scene has two
clause or turn orders, for **16 prompt variants**. An ordinal only rotates the
four choices. The compiler owns the prompt, four explicit role-map claims,
exact answer, main explanation, and literal-choice-keyed feedback. The main
explanation names all three wrong role patterns without referring to choice
letters, so reordering does not change its meaning.

The single-speaker choices say an actor *would* act, because a timing clause
does not prove the addressee independently intends to act. In the speaker-shift
format, the `I will` line supports *plans to* for that speaker; the other
speaker *offers* a tool. No choice reports that either action happened.

The focused tests cover strict task validation, all 16 prompts, four distinct
role tuples and one exact key per variant, answer-position rotation, feedback
alignment after rotation, display limits, choice-label safety, and absence of
completed-action claims. These are structural and code-semantic checks. The
two seed formats were blind-rated difficulty 3/5 and 2/5, respectively; this
expanded bank has **not** had a blind difficulty or repetition review. It
does not establish production acceptance, live worker yield, or quality over
repeated banks. Production wiring should wait for independent answer-blind
review of the compiled worksheet and contract qualification.
