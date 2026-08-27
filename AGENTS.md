# Checkpoint Project Instructions

## Git history and handoffs

- Commit cohesive, verified milestones regularly instead of accumulating large mixed changes.
- Write descriptive commit subjects and bodies that explain what changed, why it changed, and the meaningful verification performed. Treat Git history as the project's detailed changelog.
- Push verified milestone commits to the current tracked upstream promptly unless the user says not to push or the push would publish incomplete, unsafe, or secret material.
- Before committing or pushing, confirm the target branch, run the relevant tests or checks, and run `git diff --check`.
- In shared multi-agent checkouts, stage only files owned by the current task. Never fold another task's unrelated working-tree changes into a commit.
- Never commit credentials, tokens, ignored local configuration, generated secrets, or build artifacts.
- If the upstream has diverged or a safe push would require destructive history rewriting, stop and report the conflict instead of forcing the push.
