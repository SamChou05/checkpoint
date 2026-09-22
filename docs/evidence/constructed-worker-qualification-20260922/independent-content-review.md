# Independent constructed-worker content review

The frozen trial fails its prospective criteria. It returned **14/15** questions (5 quantitative, 5 Python, 4 mixed), but only **3 compiled questions**, below the required 6. The quantitative job returned five prose variants and **0/4 required compiled questions**. Independently supported complete learner content is **13/14 returned, or 13/15 requested**.

Blind stems/choices were locked before keys or teaching at `538f9165ef228e4b23d9287053e2aee85eb93a16aed5b4cbbe42325c3b749dcc`. Initial learner judgments were separately locked before private reasons or other reviews at canonical SHA `0eb335b41120a1d99b6b2f59b52bde7abaf3bae995fd29128252bf9a850d695d`; the JSON includes that complete lock. Capture SHA is `49833e414ec775090b3408ff6b73d5b967c401fd64b6b4294d7533f1ac8c2658`.

All 14 keys match the independent blind solutions; all 84 option pairs are distinct, and the literal tasks, assignments and difficulty are supported. All 12 supplied compiler choice explanations are supported. Thirteen mains are supported. The Python `True or False and False` main gets the result right but says:

> `and` has higher precedence than `or`. First `False and False` evaluates to `False`. Then `True or False` evaluates to `True` due to short-circuit evaluation.

The grouping is correct, but actual `or` evaluation first sees the left `True` and skips the entire right-hand expression. Explicit “First”/“Then” claims incorrectly describe execution of this expression. This is not merely an incomplete universal rule or a harmless value equality. The final audit nevertheless marked this main supported with no issue flags; model agreement is not proof of teaching truth.

Independent offline replay verified all **37 pins**, including **27 runtime modules**, all 11 exact native configurations/responses and strict local decoders, per-pass dense solver/audit inputs, source assignments, top-up history and every returned source binding. All three raw task specifications reproduce their full constructed specifications and five learner fields exactly, with revision 8. Eleven prose rows retain their exact authored main, exact key/choice identity and empty feedback, with revision 7. The mixed top-up correctly retains raw quantitative ordinal 1 as sanitized ordinal 0 after removing a duplicate prose stem.

There were no provider or structural call failures: all 11 calls ended with `end_turn`, used read 100/connect 3/SDK attempt 1, and matched the frozen author/solver/audit settings. Reservations and calls were 3/3/5, within six per job and 18 total; job durations were about 53.4/61.4/92.3 seconds, within 240 each. Reported usage was 33,973 input and 17,322 output tokens, with no missing usage. All 14 returns received the final audit.

The missing mixed slot has concrete local causes: one scalar task required x=12 outside its explicit 1..10 domain (`no_answer`); a prose main referenced shuffled answer labels and failed before the solver; its top-up repeated the same stem and was removed. The valid numerical sibling remained bound to its own sidecar. After five calls, the remaining single call could not fund the runtime’s conservative three-call preflight for another author pass. No rejected question was repaired or counted as supported.

Private diagnostics are separate. All 44 choice judgments and 66 pair relations match the independent answers and distinctness judgments. One Python pair reason adds a garbled index fragment (`index -1/-3 vs 2`) even though its distinct-value conclusion is correct. The solver’s value-equality rewrite of `True or (False and False)` has no explicit execution-order claim and does not cure the faulty learner main. Audit v3 contains flags, not free-text reasons; all 14 records declared support without flags.

These results do not qualify the configuration, demonstrate successful scalar construction, or establish deployed worker behavior. Frozen source, plan and capture were not changed; no provider calls were made for this review.
