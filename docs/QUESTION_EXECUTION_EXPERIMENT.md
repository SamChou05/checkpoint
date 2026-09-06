# Managed execution evidence — September 6, 2026

Direct AgentCore returned the expected evidence for all **seven attempted controls**, and all seven sessions were stopped successfully. The planned eight-case evaluation is **incomplete**: the runner classified a valid timeout observation as an operational failure and skipped the final output-limit control. This supports a narrow execution-evidence capability; it does not demonstrate improved MCQ correctness or qualify the production learning system.

The [immutable evidence archive](evidence/execution-feasibility-20260906.json) preserves the original failed-run classification, frozen plan, prospective expectations, exact submitted harnesses, decoded service events, observations, cleanup results, and independent adjudication. The root supervisor confirmed the actual process terminated with exit code 1; completion was not inferred from a capture file.

## Frozen trial and observed results

The trial ran from clean revision `3495443`, with the [eight-case fixture](../backend/bedrock-question-service/evals/fixtures/question_execution_observations.json) and plan frozen before execution. It allowed at most eight sessions and eight invokes, with one new `aws.codeinterpreter.v1` session per case in `us-east-1`. There were no SDK retries, replacement cases, model calls, policy changes, or deployment. The original canonical plan hash is `8e0655fccac51844c658aab7eec2460cefd251273a9772c3894e5a3bffa81021`.

Each session had a 60-second absolute TTL. The caller reserved five seconds for cleanup within a 20-second case budget and a 180-second run budget. The harness limited child wall time and CPU time to two seconds, output to 4,096 bytes, and address space to 256 MiB. Source and explicit inputs were supplied as data to an application-owned harness; expected results stayed outside dispatched jobs.

| Frozen control | Actual observation | Assessment |
| --- | --- | --- |
| Multiline `words` definition, default splitting | `['a', 'b']` | Matches the exact source and input. |
| Invalid flattened definition | `SyntaxError` | Reports the displayed defect without substituting repaired code. |
| Same multiline source, `explicit=True` | `['a', '', 'b']` | Preserves the same source while binding different explicit inputs. |
| Decomposed Unicode literal | Length `2` | Preserves the two code points rather than composing them. |
| Quoted internal spaces | `'a|b  c'` | Preserves the remaining double space. |
| Top-level `return 1` | `SyntaxError` | Compile checking catches a defect that AST parsing alone permits. |
| Nonterminating loop | Correlated `child_deadline`; child exit `-9`, reaped | Expected bounded, inconclusive observation; session cleanup succeeded. |
| Output exceeding 4,096 bytes | Unattempted | No live evidence for this control in the original run. |

All 21 service operations completed: **seven Starts, seven Invokes, seven Stops**. Session identifiers matched across each lifecycle, every cleanup result was `stopped`, and there were no provider, transport, parser, or cleanup failures. Six cases produced conclusive computational or compiler observations; the seventh correctly retained uncertainty after hitting a resource boundary. A syntax error can itself be the correct answer to a quiz, and an inconclusive execution result does not establish that a question is wrong.

The runtime reported CPython **3.12.13**, built with GCC 11.5.0. The four terminating code cases completed in child processes reporting isolated Python mode and optimization level zero. They ran past the harness's resource-limit setup, including its address-space limit. This establishes that those setup calls succeeded in this managed runtime; it does **not** stress-test memory exhaustion, measure actual peak memory, establish complete network disconnection, or certify resistance to sandbox escape. No filesystem, credential-access, or network probe was attempted.

## Why the run stopped

The original runner had one rule for every parser result whose status was `inconclusive`: mark the whole run as an operational failure and stop. The nontermination control returned a well-formed observation tied to the exact source and inputs, with `timed_out=true`, `transport_truncated=false`, and `child_reaped=true`. The service invocation itself succeeded, and its session was stopped. Treating that observation as a broken service call prevented the output-limit control from running.

The archive keeps `outcome=failed` and `operational_failure=true` exactly as the original runner emitted them. The independent assessment identifies the classification defect separately; it does not revise the historical run into an eight-case success. The prospective manifest already distinguished expected child limits from provider failures, so this is an implementation mismatch rather than a post-result relaxation of expectations.

The next correction should separate envelope validity and operational failure from the observation's epistemic status. A valid, safely terminated resource-bound observation may remain inconclusive without stopping unrelated cases. Malformed evidence, unknown harness failures, provider failures, or failed cleanup must still stop the run. That distinction should be generic and independently tested, without special exemptions for fixture names or expected answers. After qualification, only the missing output-limit control needs a separately capped one-session trial; the seven completed cases need not be repeated.

## Evidence integrity, timing, and limits

Independent checks verified the fixture and source-file hashes against the frozen revision, the original plan hash, all eight prepared payloads against exact fixture UTF-8 and explicit inputs, and all seven submitted harnesses against the corresponding prepared jobs. Every parsed observation matched its captured service stdout and the job's source/input identities. The source capture can be reconstructed byte for byte from the archived object using its recorded serialization rule and SHA-256. The fixture's six computational/compiler expectations were also checked independently using local Python grammar and elementary string operations; the nonterminating program was not run locally for that review.

AgentCore returned the documented `structuredContent.stdout`, `stderr`, and `exitCode` fields, with `isError=false`; it supplied no optional task metadata. The archive retains the original decoded event rather than only a summary. The API's [structured-result documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/APIReference/API_ToolResultStructuredContent.html) describes `executionTime` as milliseconds, while these raw values were roughly 0.08–0.11 for simple cases and 2.07 for the two-second timeout case. That unit discrepancy is unresolved; this report does not convert those values into latency or billing estimates.

Measured whole-run elapsed time was **20.773537 seconds**, including seven fresh session lifecycles and local capture work. One attempt per case does not establish reliability, cold-start behavior, or a latency distribution. Billed session time, CPU, memory, and dollar cost remain unknown. The child timeout is not recorded as zero service usage, and an acknowledged Stop does not establish immediate deletion of every service-held record.

No question author, semantic reviewer, prose-to-code extractor, choice mapper, adaptive learner, or iOS flow participated. The trial shows that the managed execution path can preserve and observe these specific artifacts, including their defects. Whether a reviewer uses that evidence correctly when judging all four choices and writing teaching feedback remains a separate experiment. The earlier [execution feasibility note](QUESTION_EXECUTION_VERIFICATION.md) describes the proposed integration and its boundaries.
