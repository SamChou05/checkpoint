# Trial 05: five verified returns; blind content review pending

The independently approved [frozen plan](plan.json) SHA-256 is
`308cfdef571eb58e01b873ba0b2416eb5725c5fa3c5b1ecc239f1ea0435bd9e7`.
Its request, author wire, model, settings, and limits match Trial 04; source
commit `21cbbb7` adds the narrow code-owned expected-money diversity filter.
The fresh AWS launch precheck matched account `239342516379`. The one-shot
[capture](capture.json) SHA-256 is
`57c84372e55ae818035e1ad0ab69a7a7be979ae060f098d2b7d40da2cac8b6c3`.

The full worker finished in **72.303 seconds** with five one-attempt Converse
calls: author7, solver4, reviewer4, solver2, reviewer1. All calls returned
`end_turn`. Seven source rows were authored; source ordinal 4 did not pass
sanitization and ordinal 6 did not pass verification. Five verified rows at
ordinals `0,1,2,3,5` survived the deterministic gate unchanged and were
returned in source order. This sample did not contain a pair matching the
narrow expected-money signature, so it tests that the gate leaves unlike
verified items alone, not that it removes a repeat in live production.
There was no retry, fallback, top-up, second job, or deployment.

The source- and return-order-blind [worksheet](worksheet.json) of the five
returned items is frozen at SHA-256
`b8f233a36e2367b3f3b56734a5eb88bff7aa32c60ff016e8809667e0e9da5776`.
Its private source/key map is outside Git with mode `0600`. Two independent
keyless reviews and a post-lock teaching audit are pending under the
predeclared [rubric](BLIND_REVIEW.md). This is a machine-positive one-batch
result, not yet a content pass or repeated-bank qualification.
