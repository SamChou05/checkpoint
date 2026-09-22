# Deployment observed on September 22

The read-only check at **06:18:33 UTC** found that the TestFlight stack in
`us-east-1` still uses its September 11 deployment. The selected settings and
module hashes are retained in [deployment-current.json](deployment-current.json).
Credentials and downloaded ZIPs stayed in memory; no function, model, bank, or
deployment was invoked or changed.

| Setting | Synchronous API | Asynchronous worker |
| --- | --- | --- |
| Author | Nova Lite | Kimi K2.5 |
| Skill-map model | Kimi K2.5 | Not configured separately |
| Solver and reviewer | Sonnet 4.6 US profile | Sonnet 4.6 US profile |
| Structured transport | `legacy` | `legacy` |
| Kimi / Claude thinking | disabled / disabled | disabled / disabled |
| Ordinary output cap | 6,000 | 6,000 |
| Read-timeout ceiling | 20 seconds, packaged default | 75 seconds |
| Lambda timeout | 30 seconds | 240 seconds |
| Connect timeout / temperature | 3 seconds / 0.2, defaults | 3 seconds / 0.2, defaults |
| Feedback contract | `reviewer_written`, default | `reviewer_written`, default |
| Provider calls / generation attempts | 6 / 3 | 6 / 3 |
| Generation chunk | Not configured | 5 |

Both functions use Python 3.12 and have no fallback model. The configured
16,000-token thinking cap and Claude `high` effort do not enable thinking; both
thinking switches are disabled. Missing environment values are explicitly null
in the snapshot and are distinguished from the packaged effective defaults.

Both downloaded packages match Lambda's reported SHA-256. All seven inspected
runtime modules match commit `7d9cc6a`; five differ from current main `6ec14ed`.
This establishes the source of these modules, not an exact whole-repository
deployment commit. The deployed verification policy is the complete-choice
policy 2; it contains no policy-4 constant. The actual deployed configuration
still asks models for JSON in prompts and does not send native output schemas.

Activating the already-main structural changes requires **both** deploying the
current code/template and explicitly setting
`QuestionBankWorkerStructuredOutputMode=native`, with the global
`BedrockStructuredOutputMode=legacy`. Keep the API legacy because its Nova Lite
author is outside the native capability allowlist. The currently deployed stack
does not yet have either new worker-only transport/thinking override parameter.
Changing the old package's mode alone cannot select the new author slots, solver
slots/pairs, or count-bound reviewer identities. Thinking is a separate decision;
native transport does not enable it.

Release qualification and deployment review remain separate from code landing.
A future client minimum of policy 4 must be coordinated with a worker that
actually emits it; existing policy-2 inventory must not be relabeled. This check
does not establish which app binary is installed on a particular device.
