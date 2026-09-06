# Objective execution evidence for questions — September 6, 2026

Direct AWS AgentCore Code Interpreter is a feasible, narrow way to check the literal Python in some questions. Checkpoint can select the exact source and fixed inputs, execute an application-owned verification harness, and attach the resulting evidence to review. This investigation did **not** start an interpreter session, invoke a model or tool, create resources, change permissions, or deploy anything. Execution latency, effective execution permissions, cancellation behavior, runtime version, and actual cost remain unmeasured.

The recommendation is an optional evidence adapter in the existing asynchronous question-bank worker, initially evaluated without changing acceptance decisions. It is not a replacement for semantic review, a reason to execute all questions, or a guarantee of MCQ correctness. The [author experiment](QUESTION_AUTHOR_SCHEMA_EXPERIMENT.md) showed why the literal displayed artifact matters: plausible answers sometimes described a repaired program that the learner had never been shown.

## What execution can establish

| Check | Useful evidence | Limit |
| --- | --- | --- |
| Parse and compile exact Python | Syntax validity or a compiler error class/location under the recorded runtime | Compile success does not establish output, answer uniqueness, explanation correctness, or pedagogical quality. |
| Execute a complete deterministic snippet with explicit literal inputs | Captured standard output, returned value under a specified serialization contract, or an observed exception | One execution does not prove algorithmic correctness for all inputs, complexity, nondeterministic behavior, or an unstated environment. |
| Compare an observed result with choices | A contradiction when the displayed program's actual result is absent or the declared key has a different exact value | Mapping prose choices to results can itself require semantic judgment. Tool success alone cannot approve the item. |

Use both `ast.parse` and `compile` where needed: Python documents that obtaining an AST does not ensure that the source will compile. Record `sys.version` and the selected `exec` or `eval` mode. AgentCore's documented Python runtime selector does not expose a Python minor-version pin, so version-dependent questions need an explicit compatibility decision. [Python AST documentation](https://docs.python.org/3/library/ast.html), [Python compile documentation](https://docs.python.org/3/library/functions.html#compile), [AgentCore runtime selection](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/code-interpreter-runtime-selection.html).

A `SyntaxError` is an observation, not automatic evidence of an invalid quiz. For example, a question asking what happens when `def f(): if True: return 1` is parsed may correctly offer `SyntaxError`. A question offering only numeric outputs for that same literal program is a different case. Do not silently substitute a valid source document, add missing imports or inputs, change indentation, repair quotes, normalize Unicode, or run an author's intended replacement program. The [content contract](QUESTION_CONTENT_CONTRACT.md) must survive extraction and execution.

The first eligibility boundary should accept only complete, unambiguously delimited Python artifacts or exact source spans with fixed, explicit inputs. Ambiguous inline fragments, prose/pseudocode, missing setup, unsupported versions, and external dependencies receive `unsupported`, without rejecting the question as incorrect. A narrow AST-supported subset can reduce operational exposure, but is an eligibility rule rather than a security sandbox or a general ban on legitimate subject matter.

## Direct AgentCore lifecycle and SDK support

AWS supports calling the interpreter directly through Boto3 without an agent framework. The built-in resource is `aws.codeinterpreter.v1`; no custom interpreter, Gateway, or AgentCore Runtime deployment is required for this path. Its system ARN in the project's region is `arn:aws:bedrock-agentcore:us-east-1:aws:code-interpreter/aws.codeinterpreter.v1`. [Direct-use guide](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/code-interpreter-using-directly.html), [resource management](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/code-interpreter-resource-management.html).

The following JSON illustrates the three Boto3 request shapes, **not an implemented runner**. `arguments.code` would contain a reviewed, bounded harness carrying the exact candidate artifact as data; it must never be a model-rewritten solution. Use a fresh session for each candidate, consume the returned event stream, and stop in `finally`. Reuse the same start idempotency token when retrying an uncertain start; do not create another session blindly.

```json
{
  "StartCodeInterpreterSession": {
    "codeInterpreterIdentifier": "aws.codeinterpreter.v1",
    "name": "checkpoint-objective-evidence",
    "sessionTimeoutSeconds": 60,
    "clientToken": "00000000-0000-4000-8000-000000000001"
  },
  "InvokeCodeInterpreter": {
    "codeInterpreterIdentifier": "aws.codeinterpreter.v1",
    "sessionId": "SESSION_ID_FROM_START",
    "name": "executeCode",
    "arguments": {
      "language": "python",
      "runtime": "python",
      "code": "BOUNDED_TRUSTED_HARNESS_TO_BE_IMPLEMENTED"
    }
  },
  "StopCodeInterpreterSession": {
    "codeInterpreterIdentifier": "aws.codeinterpreter.v1",
    "sessionId": "SESSION_ID_FROM_START"
  }
}
```

Start accepts an absolute session lifetime of 1–28,800 seconds, defaults to 900 seconds, and recommends at least 60 seconds. Ongoing activity does not extend that lifetime. Omit additional filesystem mounts. The invocation returns a stream: inspect error events and `result.isError` as well as structured stdout, stderr, and exit code; HTTP success alone is insufficient. [Start API](https://docs.aws.amazon.com/bedrock-agentcore/latest/APIReference/API_StartCodeInterpreterSession.html), [invoke API](https://docs.aws.amazon.com/bedrock-agentcore/latest/APIReference/API_InvokeCodeInterpreter.html).

Offline inspection of the existing evaluation environment confirmed Boto3/Botocore **1.43.89** contains `StartCodeInterpreterSession`, `InvokeCodeInterpreter`, `StopCodeInterpreterSession`, and the documented event-stream shapes. AWS CLI **2.33.15** on this Mac recognizes session start/stop but does not expose `invoke-code-interpreter`. The default local Python interpreters lack Boto3; the existing evaluation environment already has it. These observations do not establish the SDK version bundled in a deployed Lambda. A future integration should package and verify its SDK explicitly.

## Isolation, permissions, and bounds

AWS documents one dedicated microVM per session, with isolated CPU, memory, and filesystem. Files persist inside that session and are cleaned up when it ends; memory is sanitized. The same page also specifies a **30-day retention TTL for session data**, without reconciling its scope with cleanup. Do not promise immediate deletion of all service-held data based on microVM teardown. Submit only the code and fixed inputs needed for verification. [Session characteristics](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/code-interpreter-session-characteristics.html).

Sandbox network mode is **not complete disconnection**: AWS documents limited external access, including S3. Public mode permits internet access; VPC mode permits customer-network access. Do not supply application secrets or attach the question-service execution role to a custom interpreter. When an interpreter has an execution role, any code inside its VM can retrieve that role's temporary credentials through the metadata service, independently of network mode. Caller permissions and code-execution permissions are separate boundaries. [Network modes](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/code-interpreter-resource-management.html), [credentials management](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/security-credentials-management.html).

For the proposed built-in path, the caller needs `bedrock-agentcore:StartCodeInterpreterSession`, `bedrock-agentcore:InvokeCodeInterpreter`, and `bedrock-agentcore:StopCodeInterpreterSession`, scoped to the built-in interpreter ARN; `GetCodeInterpreterSession` can support diagnostics. These actions support interpreter resource scoping. Do not copy tutorial-wide create/delete or role-passing permissions into the application role. Actual effective permissions, including organization controls, still require verification before a future execution trial. [IAM action/resource reference](https://docs.aws.amazon.com/service-authorization/latest/reference/list_bedrock-agentcore.html).

Optional S3 Files/EFS mounts can persist and share data across sessions; omit them for this adapter. If a future requirement demands controlled network egress, assess a custom configuration and VPC policy separately. This proposal does not claim the built-in resource has zero egress or access to no AWS-managed credentials. [Filesystem configuration](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/code-interpreter-filesystem-configurations.html).

AWS's published ceilings are much larger than a quiz verifier should use: **2 vCPU/8 GB memory and 10 GB disk per session**, a **15-minute synchronous request timeout**, and **100 MB request/response payloads**. Default concurrency is 1,000 sessions, with start/invoke/stop limited to 30 requests/second each. These are published defaults, not measured account quotas. [AgentCore quotas](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/bedrock-agentcore-limits.html).

`ToolArguments` exposes **no per-execution timeout or output-byte cap**, which the local SDK model also confirms. A network read timeout does not prove that remote computation stopped. The adapter therefore needs its own input/AST limits, a bounded child-process harness inside the microVM, bounded capture of stdout/stderr, a total application deadline, explicit stop, and the absolute session TTL as a final backstop. [Tool argument schema](https://docs.aws.amazon.com/bedrock-agentcore/latest/APIReference/API_ToolArguments.html).

Proposed trial limits are 8 KiB of source plus inputs, two seconds of child computation, 4 KiB of captured output, one 60-second session, and a 20-second total caller deadline including cleanup reserve. These are engineering targets, **not demonstrated service guarantees**; startup or stop latency may require adjustment. Do not execute candidate code in the credentialed Lambda process. Do not interpolate it into a shell command. Timeout, truncation, memory exhaustion, permission failure, malformed evidence, and uncertain cancellation yield `inconclusive`. Record cleanup failures and stop admitting work if the session budget or remaining worker time cannot cover cleanup.

## Minimal Checkpoint integration

The current `verify_questions` entry point already separates structural filtering, optional independent solving, and semantic review. Add an optional objective-evidence dependency after structural filtering, keyed by a stable candidate identifier, and supply its immutable result to review. Preserve identity through the existing filtering/reindexing steps. Keep the author key out of the execution harness. Treat candidate stdout as data, separate from harness metadata; never accept a candidate-printed pass/fail claim as a verifier result. The proposed evidence record needs:

- Exact source and input UTF-8 hashes, source offsets or a delimited artifact identifier, harness version, runtime version, and execution mode.
- Bounded output/exception observations, truncation/timeout flags, limits, session/request identifiers, and cleanup outcome.
- A status such as `observed`, `unsupported`, or `inconclusive`; a separate result comparison may establish `contradiction` only when choice interpretation is unambiguous.

Bind the evidence to the final displayed artifact. Any subsequent code or input change invalidates it. Do not let explanatory prose or an independently rewritten solution inherit the evidence. A supported observation remains only evidence about that artifact, and semantic review must still assess the stem, all four choices, declared key, explanation, relevance, and difficulty.

Start with the existing asynchronous worker: its source template allows 240 seconds, while the synchronous function allows 30 seconds. Neither value is spare execution budget; generation/review already consume time, so admission must check the remaining deadline and cap total sessions per refill. No iOS schema change is needed for an initial internal evaluation. This integration point is a proposal; no runtime, IAM, or template change accompanies this note. See [verification flow](../backend/bedrock-question-service/question_verification.py) and [function configuration](../backend/bedrock-question-service/template.yaml).

Before allowing evidence to affect acceptance, qualify exact-source extraction, intentional syntax errors, indentation and Unicode distinctions, quoted spaces, wrong keys, absent correct choices, duplicate-equivalent prose choices, missing context, version dependence, excessive output, nontermination, service errors, and cleanup on every exit. Record false approvals and false rejections separately. Run complete reviewer fixtures too: executable output does not make an incorrect explanation correct.

## Nova's built-in interpreter

Nova 2 also exposes a managed `nova_code_interpreter` system tool through Converse. Its documented response includes the model-selected `toolUse.input.snippet` and a result containing `stdOut`, `stdErr`, `exitCode`, and `isError`. The existing Boto3 model supports `toolConfig.tools[].systemTool.name`. AWS lists IAD, PDX, and NRT availability and advises Global CRIS for routing; its documentation calls out additional `InvokeTool` permissions when using Bedrock API keys. No Nova tool call or account-permission check was performed here. [Nova tool documentation](https://docs.aws.amazon.com/nova/latest/nova2-userguide/using-tools.html).

This is a smaller configuration change for model-assisted calculations, but the model chooses the submitted snippet. Treat its result as evidence about a question only if the returned snippet and inputs match the exact artifact, or a strictly defined application-validated harness embedding it, with tool/result correlation intact. A model that repairs invalid Python and then runs the repair has not checked the learner's program. Missing tool use, unverifiable inputs, truncated results, or a mismatch is inconclusive. Direct AgentCore is preferable for this first correctness adapter because Checkpoint controls artifact selection, the harness, admission, and session termination. Neither route certifies a whole MCQ merely by being enabled.

## Cost and read-only availability evidence

The official pricing page checked on September 6, 2026 lists Code Interpreter at **$0.0895 per vCPU-hour plus $0.00945 per GB-hour**. Billing is per second with a one-second minimum, based on actual CPU and peak memory consumed up to each second, with a 128 MB memory minimum. Boot, initialization, overhead, and memory across the session lifetime matter; idle CPU savings do not imply free retained memory. Network transfer can add charges. No per-question estimate is justified until startup, execution, and cleanup are measured. [Current AgentCore pricing](https://aws.amazon.com/bedrock/agentcore/pricing/).

Two read-only control-plane calls succeeded with the current local AWS identity in `us-east-1`:

| Call | Observed result | What it establishes |
| --- | --- | --- |
| `ListCodeInterpreters`, maximum five results | Empty custom-configuration list | Authentication, regional endpoint, and list permission work. |
| `GetCodeInterpreter` for `aws.codeinterpreter.v1` | Built-in interpreter `READY`, with the system ARN above | The built-in configuration is readable and available in this region. |

These checks neither create nor start an interpreter. They do not prove data-plane start/invoke/stop authorization, runtime properties, reliability, latency, or cost. The JSON request shapes above were checked offline against the installed SDK service model. No effective-policy simulation, paid session, policy change, resource creation, or deployment was performed.

## Subsequent managed-session trial

A later [execution experiment](QUESTION_EXECUTION_EXPERIMENT.md) tested the bounded eval-only runner. Its seven attempted controls produced the expected observations and successful session cleanup; a runner classification defect left the eighth control unattempted. The discussion above records the preceding read-only feasibility investigation, not the later measured results.
