# Native observation of two saved artifacts

Status: separate native follow-up completed September 8, 2026 UTC. The prospective plan below was frozen before dispatch; results are recorded after it.

The [original four-slot authoring trial](QUESTION_ARTIFACT_AUTHORING_RESULTS.md) stopped after its HTML author timed out. That trial remains failed and is not resumed or reclassified. This separate follow-up observes only its two unchanged, returned Python artifacts; it makes no author, solver, reviewer, feedback-repair or HTML call and introduces no replacement question. The earlier content assessments and their reservations remain in force.

The narrow question is whether the exact displayed artifacts and invocations can obtain a completed, correlated native result and a uniquely matching offered answer. The native operation receives no choices, proposed feedback, expected key or manual assessment. This is an observation/binding test, not an independent sample of authoring quality or a demonstration of support for arbitrary subjects.

The [manifest](evidence/artifact-native-followup-manifest-20260908.json) binds the original capture and offline-preparation bytes, current source hashes and ordered original slots. Independent read-only preflight reproduced both prepared objects exactly from the raw author response, including their source, arguments, display and harness. The preserved stems are 179 and 203 characters; no normalization, source repair, feedback change or inferred input is allowed.

The [managed execution plan](evidence/artifact-native-followup-plan-20260908.json) has canonical SHA256 `c86a42458260ed0c71280b36fd8f0e12f500e237cbdd5d55058d0ab3eddb45c2` and byte SHA256 `5d11e6a6745a765b7a5ddf40d6301eb560afeaf5882009c9e4317c6a9db4d100`. The existing runner operates from isolated source revision `d5262211348d0c264ae0e8cb421f578da2a653e0`, with the recorded Python/boto3/botocore dependencies. Dry preflight made zero service calls and confirmed two eligible jobs.

Limits are two sessions and two invokes total, one observation per saved candidate, no retries; 90 seconds total and 30 seconds per candidate including five seconds reserved for cleanup. Each service session has its own 60-second TTL. Each operation permits at most 16 events and 32 KiB of retained capture. The existing child harness enforces two seconds wall/CPU, 256 MiB memory, 4 KiB output/result and 64 KiB transport. Local cancellation does not prove remote cancellation: a confirmed Stop response and the session TTL are separate safeguards. Any operational/correlation/cleanup failure stops further dispatch and remains a partial result; missing usage is unknown.

After the run, the existing lifecycle replay helper must reconcile the exact plan, each start/invoke/stop, session identifier, invoked harness and parsed result. Only a confirmed complete lifecycle can pass its service result to the Python artifact binder. Both reported runtimes must match CPython 3.12.13; a mismatch is unsupported and cannot be relabeled. Native key uniqueness, exact unchanged display binding, runtime and cleanup are reported separately for both original slots. A failure cannot be repaired or counted as a detected factual error.

A complete pass would mean two measured keys matched the exact original choices and the previously frozen manual answers. Full teaching feedback remains unassessed by execution, both prior feedback/difficulty reservations remain visible, no verification version is emitted and no inventory or production setting changes. The original four-question feasibility criterion remains unmet regardless of this follow-up's outcome.

## Observed results

The existing managed runner completed in 6.002998 seconds with exactly two sessions, two invokes and six recorded start/invoke/stop operations. Both sessions have confirmed Stop responses, no case was left unattempted, and no operational failure was recorded. This follow-up made zero model or HTML calls. Managed service billing/CPU usage remains unknown; wall-clock duration is not a billing measurement.

The [raw capture](evidence/artifact-native-followup-capture-20260908.json) has byte SHA256 `feb393cd199f9632a8be102ae6549fe4258c2038232daec178d049a9aa2348ad`. The [bindings](evidence/artifact-native-followup-binding-20260908.json) preserve the exact original display and proposed feedback, together with correlated observed typed values and native-derived keys:

| Original slot | Native-derived exact answer | Runtime | Result |
| --- | --- | --- | --- |
| Python 1 | `Returns [[1, 2, 9], [3, 4]] (list)` | CPython 3.12.13 | One matching option; frozen manual answer matches |
| Python 2 | `Returns 5 (int)` | CPython 3.12.13 | One matching option; frozen manual answer matches |

Root and an independent read-only replay reconciled the frozen plan/source hashes, raw author/preparation joins, all six lifecycle operations, exact invoked harnesses, runtime records and cleanup. Both binders reconstructed the archived result exactly. Neither question acquired a production verification version or entered inventory.

This establishes native answer binding for these two saved artifacts. It does not fix Python 1's ambiguously worded distractor explanation or Python 2's low assessed challenge and disputed distractor quality. The original author trial still has two unavailable HTML slots and a timeout. Generalized factual correctness, reliable author latency, teaching quality and production integration remain unproven.
