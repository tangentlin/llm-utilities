---
description: Generate a pull request title and description based on the current changes.
argument-hint: <JIRA ticket ID and/or comment>
---

Generate a pull request title and description based on the current changes.

## VCS Detection

Detect which version control system is in use:

1. Run `sl root 2>/dev/null` - if successful, use **Sapling** workflow
2. Otherwise, run `git rev-parse --show-toplevel 2>/dev/null` - if successful, use **Git** workflow
3. If neither succeeds, inform the user they're not in a recognized repository

## JIRA Ticket

Ask the user for a JIRA ticket ID if not already provided.

- Format: `ABCD-1234` (alphabetical prefix, dash, numbers)
- This is **optional** - user may skip if no ticket exists
- If provided, prefix the PR title with the ticket in brackets: `[ABCD-1234]`

## Base Branch Detection

Auto-detect the base branch (check in order):

1. `main`
2. `master`
3. Default branch from remote (e.g., `git symbolic-ref refs/remotes/origin/HEAD` or `sl config paths.default`)

## Getting the Diff

### Git

Use three-dot diff to compare against the merge-base:

```bash
git diff <base>...HEAD
```

### Sapling

Always diff against the parent commit (current commit only):

```bash
sl diff -r ".^"
```

This ensures PRs are scoped to a single commit, which aligns with Sapling's stacked PR workflow.

## Title Guidelines

- If JIRA ticket provided: prefix with `[TICKET-ID]` (e.g., `[ALGE-1234] Add user authentication`)
- Do **NOT** use conventional commit prefixes (`feat:`, `fix:`, `docs:`, etc.)
- Keep under 72 characters
- Use imperative mood ("Add feature" not "Added feature")

## Description Format

```markdown
[2-3 sentences explaining what this PR does, why, and any benefits]

## Key Changes

- [Max 3 bullet points of key changes]
- [Be specific but concise]
```

## After Generating

Present the title and description to the user, then ask if they want to create the PR.

### If Using Git

1. Check if `gh` CLI is installed: `gh --version 2>/dev/null`
2. **If installed**: Ask user if they want to create/update the PR
   - Create: `gh pr create --title "..." --body "..."`
   - Update (if PR exists): `gh pr edit --title "..." --body "..."`
3. **If not installed**: Inform the user that PRs can be created automatically with the GitHub CLI, and provide installation link: <https://cli.github.com/>

### If Using Sapling

1. Update the commit message: `sl metaedit -m "..."`
2. Submit the PR: `sl pr submit`
