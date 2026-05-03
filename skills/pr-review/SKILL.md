---
name: pr-review
description: |
  Code review a pull request using parallel review agents with confidence scoring.
  Use this skill when the user asks to: review a PR, code review a pull request,
  check a PR for issues, or give feedback on a pull request.
argument-hint: <PR number or URL>
disable-model-invocation: false
allowed-tools: Bash(gh issue view:*), Bash(gh search:*), Bash(gh issue list:*), Bash(gh pr diff:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh api:*)
---

# PR Review

Usage: `/pr-review <PR number or URL>`
Example:

- `/pr-review 5671`
- `/pr-review 5671 and verify it with ALGE-1234` (This is useful when a PR is linked to a JIRA ticket)

Provide a code review for the given pull request.

## What constitutes a false positive

Before starting the review, internalize these criteria. They apply to every agent in the pipeline — reviewers, scorers, and presenters alike.

False positives include:

- Pre-existing issues (problems that existed before this PR)
- Something that looks like a bug but is not actually a bug
- Pedantic nitpicks that a senior engineer wouldn't call out
- Issues that a linter, typechecker, or compiler would catch (e.g., missing or incorrect imports, type errors, broken tests, formatting issues, pedantic style issues like newlines). No need to run these build steps yourself — it is safe to assume that they will be run separately as part of CI.
- General code quality issues (e.g., lack of test coverage, general security issues, poor documentation), unless explicitly required in CLAUDE.md or its referenced documentation
- Issues that are called out in CLAUDE.md, but explicitly silenced in the code (e.g., due to a lint ignore comment)
- Changes in functionality that are likely intentional or are directly related to the broader change
- Real issues, but on lines that the user did not modify in their pull request

## Steps

Follow these steps precisely:

### Step 1 — Eligibility check

Use a Haiku agent to check if the pull request (a) is closed, (b) is a draft, (c) does not need a code review (e.g., because it is an automated pull request, or is very simple and obviously ok), or (d) already has a code review from you from earlier. If so, do not proceed.

### Step 2 — Discover project conventions

Use a Haiku agent to give you a list of file paths to (but not the contents of) any relevant CLAUDE.md files from the codebase: the root CLAUDE.md file (if one exists), as well as any CLAUDE.md files in the directories whose files the pull request modified. The agent should also extract any documentation file paths referenced within those CLAUDE.md files (e.g., paths in tables, markdown links to best-practices docs, testing docs, styling guides, etc.) and return those paths alongside the CLAUDE.md paths.

### Step 3 — PR summary

Use a Haiku agent to view the pull request and return: a summary of the change, the list of modified file paths, and the total number of changed files.

### Step 4 — Parallel review (6 agents)

Launch 6 parallel Sonnet agents to independently review the change. All agents should review from the perspective of a senior engineer. Beyond catching bugs, flag structural issues a senior engineer would call out in review: violations of SOLID or DRY, poor abstractions, unclear naming, or patterns that will cause maintenance problems.

Pass each agent the false positive criteria from above so they can self-filter during review.

Each agent should return a list of issues with: file path, line number (or range), issue description, and the reason it was flagged (e.g., CLAUDE.md adherence, bug, code quality, historical git context, etc.).

#### Agent #1 — Convention compliance

Audit the changes to make sure they comply with the CLAUDE.md and any documentation files referenced within the CLAUDE.md files (from Step 2). The agent should read these referenced docs (e.g., best-practices, testing guides, styling guides) and check the PR changes against those best practices as well. Note that CLAUDE.md is guidance for Claude as it writes code, so not all instructions will be applicable during code review.

#### Agent #2 — Deep contextual review

Read the changed files in full (not just the diff hunks) to understand the surrounding function/module context. Reason about whether the change is logically correct given what the code is supposed to do. Look for:

- Logic errors that only become visible with full context (e.g., wrong assumptions about input shape, missing edge cases in surrounding control flow)
- State management issues (e.g., mutating shared state, missing cleanup, race conditions)
- Contract violations (e.g., function's callers expect behavior that the change breaks)
- Off-by-one errors, boundary conditions, null/undefined paths

This agent should read broadly — not just the changed lines, but the functions they live in and the callers/callees where relevant.

#### Agent #3 — Surface scan

Read the file changes in the pull request, then do a shallow scan for obvious bugs. Focus just on the changes themselves without reading extra surrounding context. Focus on large bugs, and avoid small issues and nitpicks. Ignore likely false positives.

#### Agent #4 — Historical context

Read the git blame and history of the code modified, to identify any bugs in light of that historical context. Look for patterns like: code that was previously changed for a specific reason (visible in commit messages) being inadvertently undone by this PR.

#### Agent #5 — Previous PR feedback

Search for previous pull requests that touched the same files using `gh pr list --state merged --search "FILENAME" --json number,title --limit 5` for each modified file. **Run these searches in parallel** (cap at 5 concurrent Bash tool calls per message) — they are independent and serial execution scales linearly with file count. Check comments on the most relevant results for feedback that may also apply to the current PR.

#### Agent #6 — Code comment compliance

Read code comments in the modified files, and make sure the changes in the pull request comply with any guidance in the comments.

### Step 5 — Deduplicate

Before scoring, merge findings that describe the same issue from different agents. When two or more agents flag the same line/region for the same root cause, keep the most detailed description and note which agents independently found it (this strengthens confidence).

### Step 6 — Confidence scoring

For each deduplicated issue, launch a parallel Sonnet agent that takes the PR, issue description, and list of CLAUDE.md files (from Step 2), and returns a confidence score.

The agent should score each issue on a scale from 0–100. For issues flagged due to CLAUDE.md instructions, the agent should double-check that the CLAUDE.md actually calls out that issue specifically.

Give the scoring agent this rubric verbatim:

- **0** — Not confident at all. This is a false positive that doesn't stand up to light scrutiny, or is a pre-existing issue.
- **25** — Somewhat confident. This might be a real issue, but may also be a false positive. The agent wasn't able to verify that it's a real issue. If the issue is stylistic, it is one that was not explicitly called out in the relevant CLAUDE.md.
- **50** — Moderately confident. The agent was able to verify this is a real issue. It may be a nitpick, but the analysis holds up under scrutiny. Relative to the rest of the PR, it may not be the most critical finding.
- **75** — Highly confident. The agent double-checked the issue and verified that it is very likely a real issue that will be hit in practice. The existing approach in the PR is insufficient. The issue is very important and will directly impact the code's functionality, or it is an issue that is directly mentioned in the relevant CLAUDE.md.
- **100** — Absolutely certain. The agent double-checked the issue and confirmed that it is definitely a real issue that will happen frequently in practice. The evidence directly confirms this.

### Step 7 — Filter and tier

Filter out any issues with a score below 50. If no issues meet this threshold, report a clean review and do not proceed.

Group the remaining issues into tiers for presentation:

- **High confidence (75–100)**: Present first — these are likely real and impactful
- **Moderate confidence (50–74)**: Present second — these are worth reviewing but may be less critical

### Step 8 — Re-check eligibility

Use a Haiku agent to repeat the eligibility check from Step 1, to make sure that the pull request is still eligible for code review (it may have been closed or updated during the review).

### Step 9 — Present findings interactively

Do NOT auto-post comments or attempt to fix any findings. Follow this flow:

1. Show all filtered findings as a numbered list grouped by tier, each with: brief description, file/line reference, reason flagged, confidence score, and which review agent(s) found it.

2. Walk through the findings in batches of 3. For each batch, ask the reviewer which findings to post as PR comments (they can also edit the comment text before posting).

3. For any findings the reviewer approves, post them as **inline pull request review comments** targeting the specific file and line. Use `gh api` to create a pull request review with inline comments:

   ```bash
   gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews \
     --method POST \
     -f event="COMMENT" \
     -f body="" \
     -f 'comments=[{"path":"<file>","line":<line>,"body":"<comment>"}]'
   ```

4. If the reviewer approves zero comments across all batches, do not post anything.

5. Do NOT post block comments via `gh pr comment`. Always prefer inline comments on the specific lines.

## Notes

- Do not check build signal or attempt to build or typecheck the app. These will run separately, and are not relevant to your code review.
- Use `gh` to interact with GitHub (e.g., to fetch a pull request, or to create inline comments), rather than web fetch.
- Make a todo list first to track progress through the steps.
- You must cite and link each finding (e.g., if referring to a CLAUDE.md or its referenced docs, you must link it).
- Do NOT attempt to fix any findings. Your role is to observe and report — the reviewer decides what action to take.
- When posting inline comments, keep each comment brief, cite the relevant rule source (CLAUDE.md, best-practices doc, etc.), and avoid emojis.
- For large PRs (20+ changed files), have each review agent focus on a subset of files rather than all files, with overlapping coverage to avoid blind spots.
