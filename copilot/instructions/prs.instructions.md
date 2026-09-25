When you create a PR, in the PR description:

- sound human, be concise and do it from my name
- use the standard PR body template, if present

Never include Copilot session IDs in commits, PRs, comments, or other output.

Don't wrap text in PR description or comments.

Never use 'Co-authored-by' statements anywhere.

When you create a PR on Github, poll for Copilot bot feedback and address it. Also check for CI/CD status and fix the failures if any. After addressing Copilot feedback, request new review (if it is not triggered automatically on push) from the bot and repeat the process until the leaves no further feedback after a successful review. If you make any further changes after that, request a new review from the bot (if it is not triggered automatically on push) and repeat the process until there is no further feedback after a successful review again. Don't post commit/changes summary comment on the PR body when you address Copilot feedback. Request new copilot review only if there is no review session running yet and no unresolved feedback available.

Prefer a readable commit history over one perfect commit. Add a new commit for each round of changes instead of amending and force-pushing the previous one, so the history shows what each round of review actually changed. Amend only to fix something in the commit you just made and have not pushed. Squashing, if wanted, is the merge's job.

