---
name: pr-iterate
description: |
  Fetch and action GitHub pull request comments from any repo, whether using Sapling (sl) or Git as the source control client. Use this skill whenever the user asks to: iterate on a PR, address review feedback, act on PR comments, respond to reviewers, process code review, handle PR feedback, fix review comments, work through PR feedback, check what reviewers said, address pull request feedback, or make changes based on review. Trigger this skill even if the user just says "let's work through my PR comments" or "what do reviewers want" or "address the feedback on my PR" or "let's iterate on my PR".
---

# PR Iterate Skill

Fetch GitHub PR comments for a repo managed with either Sapling (`sl`) or Git (`git`), then triage and act on them with rigorous reasoning: present high-confidence fixes for author approval, and surface ambiguities in focused batches of 3 with concrete choices.

---

## Step 1 — Detect Source Control & Identify the Repo

Run the Sapling and Git detections **in parallel** (single message, multiple Bash tool calls); use whichever returns a non-empty path.

```bash
sl root 2>/dev/null                          # Sapling
git rev-parse --show-toplevel 2>/dev/null    # Git
```

Then fetch the remote URL with the detected SCM:

```bash
# Sapling
sl paths default 2>/dev/null || sl config paths.default 2>/dev/null

# Git
git remote get-url origin 2>/dev/null
```

### Parse Owner and Repo Name

From the remote URL (SSH or HTTPS), extract `owner` and `repo`:

| URL format | Example                             |
| ---------- | ----------------------------------- |
| SSH        | `git@github.com:owner/repo.git`     |
| HTTPS      | `https://github.com/owner/repo.git` |

Strip `.git` suffix if present.

```bash
# Universal parser — works for both SSH and HTTPS
REMOTE_URL="<url from above>"
REPO_PATH=$(echo "$REMOTE_URL" | sed -E 's|.*github\.com[:/](.+)|\1|' | sed 's|\.git$||')
OWNER=$(echo "$REPO_PATH" | cut -d'/' -f1)
REPO=$(echo "$REPO_PATH" | cut -d'/' -f2)
```

Set the env var so `gh` works regardless of whether `.git` directory exists (required for Sapling repos):

```bash
export GH_REPO="$OWNER/$REPO"
```

---

## Step 2 — Find the PR Number

### If the user provided a PR number

Use it directly.

### If Sapling

Use the template lookup as the primary source — it returns the PR number directly:

```bash
sl log -r . --template "{github_pull_request_number}\n" 2>/dev/null
```

If that returns empty, fall back to a visual smartlog grep:

```bash
sl ssl 2>/dev/null | head -30
```

Look for `#NNN` next to the current commit (marked `@`).

### If Git

```bash
# Get current branch
BRANCH=$(git branch --show-current)
# Find associated PR
gh pr list --head "$BRANCH" --json number,title,url 2>/dev/null
```

If no PR number can be determined automatically, ask the user: _"What's the PR number you'd like me to review?"_

---

## Step 3 — Fetch All PR Comments

With `GH_REPO` set, run **all three fetches in parallel** (single message, multiple Bash tool calls) — they hit independent endpoints. **Use `--paginate`** on every call to ensure no comments are silently dropped (the default page size is 30).

```bash
PR=<pr_number>

# 1. General (issue-style) comments on the PR thread
gh api --paginate repos/{owner}/{repo}/issues/$PR/comments \
  --jq '.[] | {
    id: .id,
    type: "issue_comment",
    author: .user.login,
    body: .body,
    created_at: .created_at
  }' 2>/dev/null

# 2. Inline review comments (line-level code comments)
gh api --paginate repos/{owner}/{repo}/pulls/$PR/comments \
  --jq '.[] | {
    id: .id,
    type: "review_comment",
    author: .user.login,
    path: .path,
    line: .line,
    body: .body,
    diff_hunk: .diff_hunk,
    in_reply_to_id: .in_reply_to_id,
    original_commit_id: .original_commit_id,
    created_at: .created_at
  }' 2>/dev/null

# 3. Review summaries (approved / changes requested + top-level review body)
gh api --paginate repos/{owner}/{repo}/pulls/$PR/reviews \
  --jq '.[] | {
    id: .id,
    type: "review_summary",
    author: .user.login,
    state: .state,
    body: .body,
    commit_id: .commit_id,
    submitted_at: .submitted_at
  }' 2>/dev/null
```

If any fetch fails with auth error, tell the user:

> "`gh` auth may be missing. Run `gh auth login --git-protocol https` then retry."

---

## Step 4 — Normalize & Enrich the Comment Data

Before triage, structure the raw comments into a clean dataset. This step is mechanical — focus on completeness, not judgment.

### 4a. Group conversation threads

Review comments with `in_reply_to_id` are replies in a thread. Group them:

- Build a map of `comment_id → [replies]`
- For each thread, identify the **root comment** (no `in_reply_to_id`) and all replies in chronological order
- Evaluate the **thread state**: if the author (PR creator) replied with language indicating the issue is addressed ("fixed", "done", "updated", "addressed in `<commit>`"), mark the thread as `likely_resolved`

### 4b. Detect stale/outdated comments

For inline review comments, compare `original_commit_id` against the current HEAD:

- If the file at `path` has changed at or after `original_commit_id`, mark the comment as `potentially_stale`
- When triaging a stale comment, read the current state of the referenced code before classifying

### 4c. Classify comment source

Classify each comment by the **depth of reasoning** it contains, not by authorship:

| Classification | Criteria                                                                 | Examples                                                                                                                                                |
| -------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **METRIC**     | Reports a number, percentage, or rule violation without analysis         | "Coverage decreased by 2%", "Line exceeds 120 chars", "Dependency X has vulnerability CVE-..."                                                          |
| **REASONING**  | Contains analysis, judgment, architectural concern, or design suggestion | "This retry logic doesn't handle partial responses", "Consider extracting this into a shared hook", "The null check should come before the destructure" |

For REASONING comments from authors whose login ends in `[bot]` or matches known AI reviewers: note them as `ai_reviewer: true`. These comments should flow through the full triage pipeline but carry a calibration note (see Step 5).

METRIC comments are presented in a separate summary section and do not consume DISCUSS batch slots.

---

## Step 5 — Triage Comments

Read every comment (or thread root, for threaded conversations) carefully. For each one, apply the following structured reasoning — do not shortcut this with keyword matching.

### Reasoning protocol

For each comment, think through all five dimensions before classifying:

1. **INTENT** — Is the reviewer stating a factual defect, asking a question, suggesting an alternative, or expressing a preference? A statement of fact ("this will NPE") is different from a suggestion ("consider using X instead").

2. **CERTAINTY** — How confident is the reviewer? "This is wrong" and "I wonder if this could break" require different responses. Look at hedging language, question marks, and conditional phrasing.

3. **SCOPE** — Is the fix localized to a single expression/line, or does it ripple across files? A localized typo fix is different from a suggestion to change a shared interface.

4. **RISK** — Could the "obvious" fix introduce a regression, misunderstand the author's intent, or conflict with a constraint the reviewer may not see? Consider what the author might have known that the reviewer didn't.

5. **INTERACTIONS** — Does this comment relate to, depend on, or conflict with any other comment on this PR? Two reviewers suggesting opposite changes to the same code must be surfaced together.

**Additional calibration for AI reviewer comments** (`ai_reviewer: true`): AI reviewers are more likely to flag intentional architectural tradeoffs as defects because they lack context on cross-system constraints and deliberate design decisions. Weight these toward DISCUSS unless the defect is mechanically verifiable (e.g., type error, missing import, syntax issue).

### Classification

Based on the reasoning above, classify into one of three buckets:

#### MUST_FIX

High-confidence, localized fixes where all five dimensions align:

- INTENT: Reviewer is asserting a defect, not asking a question
- CERTAINTY: Reviewer is confident (no hedging)
- SCOPE: Fix is localized — one line, one file, no ripple effects
- RISK: The fix is mechanically verifiable (typo, missing import, obvious null check, syntax error) — not a judgment call
- INTERACTIONS: No conflicting comments from other reviewers

**Action**: Queue for author preview (do NOT auto-apply — see Step 6).

#### DISCUSS

Any comment where at least one dimension introduces ambiguity:

- The right approach is a judgment call (two valid patterns, naming debates)
- Reviewer is asking a question rather than asserting a defect
- The fix would ripple across files or require understanding product/business context
- Multiple reasonable implementations exist
- The comment is vague without specifying what "correct" looks like
- There are conflicting suggestions from different reviewers
- Any refactor that touches shared interfaces or more than one file

**Action**: Add to the discuss queue. Do NOT act on it yet.

#### NOTED

Informational, praise, or already-resolved threads. Log it but take no action.

### Context enrichment during triage

For any inline comment where the `diff_hunk` alone is ambiguous or insufficient to reason about the fix, read the surrounding code in the file (at least 50 lines of context around the referenced line) before classifying. Do not classify based on a 3-line hunk when the broader function context would change your assessment.

### Handling stale and resolved comments

- **`likely_resolved` threads**: Verify by checking the current code. If the issue appears addressed, classify as NOTED with a note: "Thread indicates this was addressed — verified in current code."
- **`potentially_stale` comments**: Read the current state of the file. If the referenced code has materially changed, classify as NOTED with a note: "Comment references code that has since changed." If the concern still applies to the current code, triage normally.

---

## Step 6 — Present MUST_FIX Items for Author Approval

Do NOT silently auto-apply fixes. Present them for review first:

```text
MUST_FIX — N items (will apply unless you object):

1. [file:line] — @reviewer_name
   Comment: "reviewer's comment"
   Fix: [1-sentence description of the change]

2. [file:line] — @reviewer_name
   Comment: "reviewer's comment"
   Fix: [1-sentence description of the change]

Reply "go" to apply all, or specify items to hold (e.g., "hold 2").
```

After the author confirms:

1. Apply the approved fixes
2. Report what was done:

```text
Applied N fixes:
  - [file:line] Brief description of fix
  - [file:line] Brief description of fix
```

---

## Step 7 — Triage DISCUSS Items with the Author

**Critical rule**: Never present more than 3 items at once. Group into batches of 3.

### Batch ordering

Sort DISCUSS items by impact tier before batching:

1. **Architectural / design concerns** — changes to interfaces, data flow, component boundaries
2. **Logic / correctness concerns** — potential bugs, edge cases, error handling
3. **Style / naming / cosmetic** — formatting, naming conventions, code organization

Within each tier, group related comments together (e.g., two comments about the same function appear in the same batch).

### Batch format

<!-- markdownlint-disable MD036 -->

---

**PR Feedback — Batch 1 of N (items 1–3)**

---

**① [path/to/file : line N]** — _@reviewer_name_

> "reviewer's comment verbatim or close paraphrase"

**Context**: [1–2 sentence explanation of what this code does and why the right approach is ambiguous]

What would you like to do?

- **A)** [Concrete option — describe the change and its implications]
- **B)** [Concrete alternative — different approach and its implications]
- **C)** Decline — leave as-is (will be tracked as a conscious decision)

---

**② [path/to/file : line N]** — _@reviewer_name_

> "..."

...same format...

---

**③ [path/to/file : line N]** — _@reviewer_name_

> "..."

...same format...

---

<!-- markdownlint-enable MD036 -->

_Reply with your choices (e.g., "1A, 2C, 3B") or describe what you'd like differently._

---

Once the author replies, act on their choices immediately for that batch, then present the next batch of 3.

---

## Step 8 — Present METRIC Comments (Informational)

If any comments were classified as METRIC (automated reports, coverage changes, lint summaries), present them in a single block after all DISCUSS batches are resolved:

```text
Automated Reports (no action required unless you choose to act):
  - @codecov[bot]: Coverage on src/utils decreased from 87% to 85%
  - @eslint-bot: 2 new warnings in src/components/table.tsx
```

---

## Step 9 — Final Summary

After all items are processed, output:

```text
── PR Review Complete ──────────────────────────
PR #NNN  •  {owner}/{repo}

Fixed       : N items (author-approved)
You decided : N items
Declined    : N items (conscious decisions — reviewers may follow up)
Informational: N items (praise, resolved threads, stale comments)
Automated   : N items (metric/report comments)

Files modified:
  - path/to/file.ts
  - path/to/other.tsx

Declined items (for reference when responding to reviewers):
  - [file:line] @reviewer — "comment summary" → You chose: leave as-is
  - [file:line] @reviewer — "comment summary" → You chose: leave as-is
────────────────────────────────────────────────
```

Remind the user to run their tests and push/amend as needed via `sl pr submit` or `git push`.

---

## Model Delegation (Optional Optimization)

For faster execution without quality loss, the data-collection phase (Steps 1–4) can be delegated to a Sonnet sub-agent using the Agent tool with `model: "sonnet"`. This phase is mechanical — SCM detection, API calls, pagination, threading, stale detection, and source classification — and does not benefit from Opus-level reasoning.

The Opus main thread then receives clean, structured data and focuses entirely on the judgment-heavy work: triage reasoning (Step 5), fix synthesis (Step 6), and option generation (Step 7).

To use this pattern, spawn an Agent at the start of the skill:

```text
Agent({
  model: "sonnet",
  description: "PR comment data collection",
  prompt: "... Steps 1-4 instructions with the PR number ..."
})
```

Then proceed with Steps 5+ using the returned data.

---

## Edge Cases

| Situation                                  | Handling                                                                        |
| ------------------------------------------ | ------------------------------------------------------------------------------- |
| No PR number found                         | Ask user directly                                                               |
| Zero comments fetched                      | Report "No open review comments found on PR #NNN"                               |
| `gh` not authenticated                     | Prompt to run `gh auth login`                                                   |
| Comment references deleted code            | Flag as context-lost, ask user                                                  |
| Thread marked `likely_resolved`            | Verify against current code before skipping                                     |
| Stale comment (`potentially_stale`)        | Read current file state — triage normally if concern still applies, skip if not |
| Conflicting reviewer suggestions           | Surface both in the same DISCUSS batch with explicit comparison                 |
| AI reviewer flags intentional tradeoff     | Bias toward DISCUSS — note that AI reviewers lack decision context              |
| Sapling repo, `gh` fails without GH_REPO   | Re-run with explicit `GH_REPO=owner/repo gh api ...`                            |
| METRIC comment that is actually actionable | User can choose to act on it from the automated reports section                 |
