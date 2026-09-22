# Actual mixed compiler and immutable-main trial

**Failed: 4 of 15 requested questions returned, against the frozen minimum of 14.** All three independent jobs ran. No compiled question was released, so the numerical and mixed-subject quotas also failed. The author-only result did not predict usable full-pipeline yield.

| Job | Returned / requested | Calls | Job seconds |
| --- | ---: | ---: | ---: |
| Quantitative | 0/5 | 5 | 234.209511 |
| Python | 4/5 | 4 | 226.354971 |
| Mixed arithmetic/English | 0/5 | 1 | 100.260749 |

All ten calls were within the eighteen-call trial ceiling; every job stayed within six calls and 240 seconds. Seven calls returned normal, native-schema-valid output. Three timed out: the late quantitative solver, the Python top-up author, and the mixed author. Reported usage totals 29,146 input and 32,260 output tokens. Usage for the three timeouts is unavailable, not zero.

The first numerical author produced five valid specifications, all of which passed the solver. Its final audit took 88.259 seconds. Four audit rows rejected the correct numerical mains for lacking worked derivation: they requested common-denominator, multiplication/reduction or reciprocal steps. A fifth row declared its explanation supported but emitted `issues: ["", " ", " "]`. Those strings satisfy the provider schema but violate the local nonblank-issue contract, invalidating the whole audit envelope. The local validator enforced its existing rule; it did not mistakenly credit blank diagnostics as approval.

This exposes a real gap between the two format contracts. The native schema requires an array of strings; local validation additionally limits the number and length of issues and rejects blank strings. Bedrock does not support JSON Schema `minLength` or `maxLength`, so simply adding those keywords is not a supported fix. A closed set of issue flags can express the decision without free-text diagnostic formatting. [AWS structured-output schema support](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html).

The normal numerical top-up generated five further valid specifications, but its solver call had only a 2.075-second read allowance left and timed out. Python retained four verified questions when its fifth-question top-up timed out. The independent mixed job still ran and timed out in authoring. No timeout extension, replacement job, repaired output or extra model judgment rescued this run.

The [independent structural review](STRUCTURAL_REVIEW.md) reproduced all ten exact provider requests and the actual runtime outcomes offline. All ten raw compiled specifications reproduce their five recorded learner fields, but none reached release. Each of the four released prose mains exactly matches its original author text, has empty optional choice feedback, and carries policy 7. The explicit keys remain authoritative across answer shuffling.

Root and the [independent content reviewer](independent-review.md) locked blinded reviews before reading the keys and teaching. Both found four unique correct keys and supported mains in their exact contexts, with a wording caveat for the Boolean example: its closed subexpressions can be simplified to the stated result, while actual short-circuit execution skips the right subtree. An independent literal-and-type check confirmed every key. All four meet the requested minimum difficulty.

The fifth Python draft was a false solver rejection. For the exact result of `0 or 'hello'`, the model equated the wrong choices `0` and `False` because they compare numerically equal. They are distinguishable integer and Boolean results for this task. The pair gate correctly enforced the model's declaration, but that declaration was wrong. This is separate from the blank-field failure and does not justify globally treating all differently written choices as distinct.

This result does not qualify deployment, arbitrary-topic accuracy, worker queue/inventory behavior or deterministic model judgment. The underlying source fixes remain opt-in improvements; production defaults were not changed. Worked numerical explanations, the diagnostic-format mismatch and call latency are separate follow-up workstreams.

Bindings:

- Frozen plan: `db7f3d506a6f76954b54102fa215beba266be0602030e23cd39fa6cfe44d6a13`.
- Capture: `8107bf285c2125c89e0ddb654b0ada756a6a943d05cb6d22c0c7ce5cc9465523`.
- Structural review JSON: `f62cbdba74283af2938287adf0e83ea986462aaea620f913ac88d70aa566d0cd`.
- Blinded worksheet: `c2e0fcf7600fdd98be2ca3fdde6f314da30c08b828e635f319f4e6d8c69e939a`.
- Root blinded review: `49c017691b58509d2416fb427b21f2176f966744351220567a9bbcf1a291f60b`.
- Root content review: `5bf3f8337a6f123787784cf7a71cd2894612d83bff4cbffd163e4c478a77de0f`.
- Independent content review JSON: `2aa6ca25d463e82c3998e4e75da790a5cb989bbd632768be701f6a53d08a8f4b`.

The exact source remains in the original frozen integration worktree. Subsequent runtime implementation must use another checkout so these absolute source pins remain replayable.
