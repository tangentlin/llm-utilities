---
name: pr-split
description: |
  Split a large pull request into multiple smaller, logically-grouped PRs that
  each pass the project's CI/CD quality gates. Works in both Git and Sapling
  (sl) repos. Use this skill when the user asks to: split a PR, break up a
  large PR, chunk a PR, decompose a PR, slice a PR, carve a PR into pieces,
  stack a big change, turn one PR into many, or "this PR is too big — let's
  split it". Trigger even on phrasings like "make this PR smaller" or "I want
  to land this in pieces".
---

# PR Split Skill

Take the current branch's diff vs. the base branch and turn it into a sequence
of smaller, logically-grouped PRs. Each split is **stacked** (PR `k+1` is based
on PR `k`), passes lint + type + format gates individually, and the final tip
passes the full `pnpm check:all`. The split is **lossless** — the union of all
splits equals the original diff byte-for-byte.

**Model usage**: Mechanical phases (SCM detection, diff stats, import-graph
extraction, baseline gate) are delegated to a Sonnet sub-agent for speed and
cost. The judgment-heavy phases — split planning, dependency ordering, plan
revision based on user feedback, gate-failure recovery — run on the main
session model (Opus or whatever the user has configured).

---

## Step 1 — Detect SCM, repo, and base branch (Sonnet sub-agent)

Spawn a Sonnet Explore sub-agent for this step. It should return a single JSON
object with the fields below — nothing else.

```text
Agent({
  subagent_type: "Explore",
  model: "sonnet",
  description: "PR-split SCM + base detection",
  prompt: "Detect SCM, repo identity, and base branch as described in
           pr-split SKILL.md Step 1. Return JSON only."
})
```

### What the sub-agent does

#### 1a. Detect SCM

Run both detections; whichever succeeds wins.

```bash
sl root 2>/dev/null            # → Sapling if returns a path
git rev-parse --show-toplevel  # → Git if returns a path
```

#### 1b. Resolve `owner/repo`

Get the remote URL, then parse owner and repo (works for SSH and HTTPS):

```bash
# Sapling
REMOTE_URL=$(sl paths default 2>/dev/null || sl config paths.default 2>/dev/null)
# Git
REMOTE_URL=$(git remote get-url origin 2>/dev/null)

REPO_PATH=$(echo "$REMOTE_URL" | sed -E 's|.*github\.com[:/](.+)|\1|' | sed 's|\.git$||')
OWNER=$(echo "$REPO_PATH" | cut -d'/' -f1)
REPO=$(echo "$REPO_PATH" | cut -d'/' -f2)
export GH_REPO="$OWNER/$REPO"   # required for gh in Sapling repos
```

#### 1c. Detect the base branch (try in order)

1. `main`
2. `master`
3. Remote default — `git symbolic-ref refs/remotes/origin/HEAD` (Git) or
   `sl config paths.default` (Sapling)

#### 1d. Return JSON

```json
{
  "scm": "git" | "sapling",
  "repo_root": "/abs/path",
  "owner": "...",
  "repo": "...",
  "gh_repo": "owner/repo",
  "base_branch": "main",
  "current_branch": "feature/foo",   // git only; sapling returns null
  "head_commit": "abc123..."
}
```

If neither SCM is detected, abort with: _"Not in a Git or Sapling repo. Aborting."_

---

## Step 2 — Pre-flight guards

Hard-fail with an actionable error if any guard fails. Do NOT proceed.

| Check                | Git command                                         | Sapling command                                                 |
| -------------------- | --------------------------------------------------- | --------------------------------------------------------------- |
| Clean working tree   | `git status --porcelain`  (must be empty)           | `sl status` (must be empty)                                     |
| HEAD ahead of base   | `git rev-list --count "$BASE..HEAD"` (must be > 0)  | `sl log -r "$BASE::. - $BASE" -T "{node}\n"` (must be non-empty)|
| Base is fetched      | `git fetch origin "$BASE"`                          | `sl pull`                                                       |

Failure messages:

- **Dirty tree**: _"Working tree has uncommitted changes. Commit or stash, then re-run."_
- **No commits ahead**: _"Current branch has no commits ahead of `$BASE`. Nothing to split."_

---

## Step 3 — Baseline quality gate

From the repo root, run:

```bash
pnpm check:all
```

If it **fails**:

> ⚠️ Quality gates fail on the current branch *before* any split.
> Splitting cannot guarantee clean PRs while the source is broken.
> Please fix `pnpm check:all` first, then re-run this skill.

Print the failure summary verbatim and **abort**. Do not touch any branches.

If it **passes**, continue. (Tests have already run here, so we will not need
to re-run the full `check:all` until the final stack tip.)

---

## Step 4 — Investigate the diff (Sonnet sub-agent)

Spawn a second Sonnet sub-agent. Its job is purely mechanical:

```text
Agent({
  subagent_type: "Explore",
  model: "sonnet",
  description: "PR-split diff investigation",
  prompt: "Compute the manifest described in pr-split SKILL.md Step 4
           for the diff between $BASE and HEAD. Return JSON only."
})
```

### What the sub-agent computes

Use `--find-renames` so renamed files travel as one unit, not duplicated.

```bash
# Git
git diff --find-renames --numstat "$BASE...HEAD"
# Sapling
sl diff -r "$BASE" --stat
```

For every changed file collect:

- `path` (post-rename), `old_path` (if renamed), `kind`, `+lines`, `-lines`,
  `hunks`, `top_folder`, `package`.
- `kind` enum: `impl`, `test`, `story`, `mock`, `style`, `types`, `model`,
  `config`, `docs`, `lockfile`, `generated`, `other`. Detect by extension and
  filename suffix (e.g., `*.test.ts` → test, `*.style.ts` → style,
  `pnpm-lock.yaml` → lockfile, `*.snap` → generated).
- `package`: top-level package directory (e.g., `reaqt`, `argon`,
  `aerosani-ui-shared`) — empty for repo-root files.

### Build a within-diff import graph

For each `.ts/.tsx` file in the diff, parse `import` and `export from`
statements (regex is fine — full AST not required) and record edges where
both endpoints are in the diff. Output an adjacency list:

```json
"imports": { "argon/src/foo.ts": ["argon/src/bar.ts"], ... }
```

This drives topological ordering of splits in Step 7.

### Return manifest

```json
{
  "totals": { "files": 47, "added": 1820, "removed": 410 },
  "files": [
    {"path": "argon/src/cycles/table.tsx", "kind": "impl",
     "added": 180, "removed": 42, "hunks": 8,
     "top_folder": "argon/src/cycles", "package": "argon"},
    ...
  ],
  "imports": { ... },
  "renames": [{"old": "...", "new": "..."}],
  "boundaries": {
    "by_package": {"argon": 28, "reaqt": 12, "aerosani-ui-shared": 7},
    "by_top_folder": {...},
    "by_kind": {"impl": 22, "test": 14, "story": 5, "style": 4, "config": 2}
  }
}
```

---

## Step 5 — Collect user inputs

Use `AskUserQuestion`. **Two batches** — keep total at three questions max
across the whole skill (one batch of 1, then one batch of 3).

### Batch 1 — line budget per PR (single-select, 4 options)

Compute estimated PR counts from the manifest *before* asking. The naive
estimate is `ceil(totals.added + totals.removed / budget)`, but adjust upward
if any single file exceeds the budget (that file is its own PR).

```text
Total changed: <X> files, +<Y> / -<Z> lines.

Approximate PR count per budget:
  • 300 lines  → ~A PRs
  • 500 lines  → ~B PRs   ← default (Recommended)
  • 1000 lines → ~C PRs
  • Other      → you supply the cap (must be ≥ 50)
```

If user picks **Other**, prompt for a free-text integer and validate.

### Batch 2 — strategy + numbering + creation mode (3 questions)

#### Q1: Split strategy (single-select)

Options are dynamically built from the manifest. Always include these where
applicable, with the **single best fit marked `(Recommended)`** as the first
option:

| Option              | When to recommend                                                                       |
| ------------------- | --------------------------------------------------------------------------------------- |
| **By package**      | Diff spans 2+ top-level packages (e.g., `reaqt`, `argon`, `aerosani-ui-shared`)         |
| **By folder**       | Diff is concentrated in one package but spans many sibling folders                      |
| **By functional**   | Files cluster naturally by feature/capability (use Sonnet's filename-pattern heuristic) |
| **By layer**        | Diff has clear types→core→UI→tests stratification                                       |
| **Hybrid**          | When package + functional both apply: package outermost, functional within              |

Pick the recommendation by the dominant signal in `manifest.boundaries`. For
example, if 3 packages all have ≥ 5 files, recommend **By package**; if one
package contains > 80% of files but multiple feature folders, recommend
**By folder** or **By functional**.

#### Q2: Starting number for `(k/n)` suffix

Free-text, default `1`. Validate as a positive integer. The suffix in titles
will be `(k/n)`, `(k+1/n)`, ..., where `n = start + N - 1` and `N` is the
number of splits. Example: start=4, N=3 → titles end in `(4/6)`, `(5/6)`,
`(6/6)`.

#### Q3: PR creation mode (single-select, 3 options)

Present in this exact order:

1. **(Recommended)** Auto-create all PRs after final approval
2. Auto-create each PR after individual confirmation
3. Stop after preparation; print exact commands for me to run

---

## Step 6 — Plan the splits

This step runs on the main session model (not a sub-agent) because it is
judgment-heavy and must be revisable in dialogue with the user.

### Algorithm

1. **Bucket** files by the chosen strategy.
2. Within each bucket, **greedily pack** files into PRs respecting the line
   budget (`+lines + -lines` summed). If a single file's `+lines + -lines`
   exceeds the budget, that file becomes its own PR — warn the user but do
   not split a file across PRs.
3. **Topologically sort** the resulting PRs using the import graph from the
   manifest. If PR `B` contains a file that imports a symbol introduced in
   PR `A`, then `A` must come first. Detect cycles; if any cycle is found,
   merge the cycled PRs into one and warn the user.
4. **Generate metadata** per PR:
   - **Title**: `<original PR title or first commit subject> (k/n)`
     where k starts at the user's chosen offset.
     Preserve any `[ABCD-1234]` ticket prefix from the original.
   - **Body**:

     ```markdown
     Part k of n in a stacked split.

     **Files in this split** (<count>, +<lines> / -<lines>):
     - argon/src/cycles/table.tsx
     - argon/src/cycles/use-cycles.ts

     **Rationale**: split by <strategy>; <one-sentence reason for grouping>.

     **Stacked on**: #<prev-pr> (or `main` for split 1)
     **Original PR**: #<n> (if exists; from `gh pr list --head $ORIG`)
     ```

5. **Render the plan** as a table:

   ```text
   Split   Files  +Lines  -Lines  Title preview                            Risk
   ─────   ─────  ──────  ──────  ───────────────────────────────────────  ────
    1/3     12     +180    -42    [ABCD-1234] Refactor cycle table (1/3)   low
    2/3      8     +240    -10    [ABCD-1234] Wire up filters (2/3)        med (depends on 1/3)
    3/3      5     +120     -5    [ABCD-1234] Tests + stories (3/3)        low

   Reply 'go' to execute, or describe revisions
   (e.g., "merge 2 and 3", "move foo.ts from 1 to 2", "rename split 2 to ...").
   ```

6. **Iterate** until the user replies `go`. Honor revisions like:
   - "Merge X and Y" → combine two PRs (re-check budget; warn if over).
   - "Move file F from X to Y" → reassign and re-run the topo sort.
   - "Split X further" → re-bucket the files in PR X.
   - "Rename split N to ..." → update only the title.

---

## Step 7 — Execute the split

### Common setup

```bash
ORIG="<current_branch>"          # from Step 1 (Git only)
TS=$(date +%Y%m%d-%H%M%S)
BACKUP="${ORIG}-presplit-${TS}"  # Git only
N=<number of splits>
```

### Git path

```bash
git branch "$BACKUP"            # backup; never deleted by the skill
git checkout "$BASE"
git pull --ff-only

PREV="$BASE"
for k in $(seq 1 $N); do
  BR="${ORIG}-split-${k}"
  git checkout -b "$BR" "$PREV"

  # Apply only the files in split k from the backup branch.
  # For renamed files, also remove the old path.
  git checkout "$BACKUP" -- <files for split k>
  git rm <old_paths of files renamed within split k, if needed>
  git add -A <files for split k>
  git commit -m "<title for split k>" -m "<body for split k>"

  # Per-split gate (no tests yet)
  pnpm check:style && pnpm check:lint && pnpm check:type \
    || HANDLE_GATE_FAILURE k

  PREV="$BR"
done

# Final stack tip — full gate including tests
git checkout "$PREV"
pnpm check:all || HANDLE_GATE_FAILURE "tip"
```

### Sapling path

Sapling is stack-native, so we rebuild the current commit (or the user's
existing stack of commits) into N draft commits.

```bash
# If the current branch is a single commit, uncommit it to move all changes
# into the working dir, then rebuild the stack.
sl goto "$BASE"
sl uncommit -r <original tip>   # changes now in working dir of $BASE checkout
# (For a multi-commit branch: collapse via `sl fold` first, then uncommit.)

for k in $(seq 1 $N); do
  # Stage only files for split k, commit
  sl add <files for split k>
  sl forget <files NOT in split k that may have been globbed in>
  sl commit -m "<title for split k>" -l <body file>

  pnpm check:style && pnpm check:lint && pnpm check:type \
    || HANDLE_GATE_FAILURE k
done

sl goto tip
pnpm check:all || HANDLE_GATE_FAILURE "tip"
```

### `HANDLE_GATE_FAILURE k`

When a per-split gate fails for split `k` (or `tip`):

1. **Stop** the loop immediately.
2. Print the failing tool's last 50 lines of output.
3. **Reassure the user**: backup is at `$BACKUP` (Git) or `sl unhide
   <original-hash>` (Sapling) — recovery is one command away.
4. Offer three actions via `AskUserQuestion`:
   - **A**) Fix in place — apply minimal edits to make the gate pass, commit
     `--amend` (Git) or `sl amend` (Sapling), re-gate, then resume the loop.
   - **B**) Move the offending file(s) to the next split — undo the current
     commit, remove the file, re-commit, re-gate. The next split picks up
     the file.
   - **C**) Replan from scratch — return to Step 6 with the failure as input
     so the new plan avoids the failure mode (e.g., move tests adjacent to
     impl).

Never silently rewrite or skip a failing gate.

---

## Step 8 — Lossless verification

Before any push, prove the union of splits == the original diff:

```bash
# Git
git diff "$BACKUP" "$PREV" --stat   # MUST print nothing

# Sapling — diff the new tip against the original (stashed) commit hash
sl diff -r "<original tip>" -r "<new tip>"   # MUST be empty
```

If non-empty:

> ❌ Lossless verification FAILED. The split is not equivalent to the original.
> Aborting publish. Your original is safe at:
>   • Git: `git checkout $BACKUP`
>   • Sapling: `sl goto <original tip>` (or `sl unhide` if hidden)
> Inspect the divergence above and re-run the skill.

Do **not** push or open any PR.

---

## Step 9 — Publish (per chosen mode)

### Mode 1 — Auto-create all (recommended default)

#### Git

```bash
for k in $(seq 1 $N); do
  git push -u origin "${ORIG}-split-${k}"
done

# First PR is based on $BASE, each subsequent on the previous split
gh pr create --base "$BASE"            --head "${ORIG}-split-1" \
  --title "<title 1>" --body "<body 1>"
gh pr create --base "${ORIG}-split-1"  --head "${ORIG}-split-2" \
  --title "<title 2>" --body "<body 2>"
# ...
gh pr create --base "${ORIG}-split-$((N-1))" --head "${ORIG}-split-$N" \
  --title "<title N>" --body "<body N>"
```

After all PRs are created, edit each body to interlink them with the actual
PR numbers (`Stacked on #aaa`, `Next: #bbb`).

#### Sapling

```bash
sl pr submit --stack
```

`sl pr submit --stack` creates one PR per draft commit and stacks them
automatically.

### Mode 2 — Auto-create each

After preparing each split locally and gating it, but **before** pushing:

```text
Split k/N is ready (passes lint+type+format).
Title: <title>
Files: <list>

Push and create PR? [y/n/quit]
```

- `y` → push and `gh pr create` / `sl pr submit -r <commit>`, then continue.
- `n` → skip publish for this one (leaves branch local), continue.
- `quit` → stop publishing; remaining splits stay local.

### Mode 3 — Stop after preparation

Print, in a single fenced code block, the exact commands the user can copy
and run themselves. Do nothing remote. Example:

````text
The split is prepared and gated. To publish, run:

```bash
# Git
git push -u origin feature/foo-split-1
git push -u origin feature/foo-split-2
git push -u origin feature/foo-split-3

gh pr create --base main             --head feature/foo-split-1 \
  --title "[ABCD-1234] Refactor cycle table (1/3)" --body-file /tmp/pr-1.md
gh pr create --base feature/foo-split-1 --head feature/foo-split-2 \
  --title "[ABCD-1234] Wire up filters (2/3)" --body-file /tmp/pr-2.md
gh pr create --base feature/foo-split-2 --head feature/foo-split-3 \
  --title "[ABCD-1234] Tests + stories (3/3)" --body-file /tmp/pr-3.md
```
````

(Write the body of each PR to `/tmp/pr-<k>.md` so the printed commands are
runnable as-is.)

---

## Step 10 — Final summary

```text
── PR Split Complete ────────────────────────────
Original branch  : <branch>  (backed up as <branch>-presplit-<ts>)
Base branch      : <base>
Strategy         : <chosen strategy>
Line budget      : <budget> per PR
Splits created   : N
PR numbers       : #aaa, #bbb, #ccc       (omitted in Mode 3)
Quality gates    : ✓ check:style, ✓ check:lint, ✓ check:type on each split
                   ✓ pnpm check:all (incl. tests) on the stack tip
Lossless check   : ✓ diff(backup, tip) is empty

Next steps:
  - Review each PR top-to-bottom in numeric order
  - Merge in order: 1/N → 2/N → … → N/N
  - GitHub auto-rebases the next PR's base when you merge each
  - Once all merged and you're satisfied, delete the backup:
      git branch -D <branch>-presplit-<ts>     # Git
      sl hide <original tip>                   # Sapling
─────────────────────────────────────────────────
```

---

## Edge cases

| Situation                                  | Handling                                                                                               |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| `pnpm check:all` fails on baseline         | Abort with the failure summary; user fixes first                                                       |
| Working tree dirty                         | Abort; user commits or stashes first                                                                   |
| No commits ahead of base                   | Abort; nothing to split                                                                                |
| Single file exceeds line budget            | That file becomes its own PR; warn the user                                                            |
| Renamed file                               | Travels with its new path (use `--find-renames`); never duplicated                                     |
| Lockfile / generated file changes          | Group into the split that touches the related package (or its own "infra" split if cross-cutting)      |
| Import cycle between proposed splits       | Merge the cycled splits into one; warn the user                                                        |
| Sapling: branch is multiple commits        | `sl fold` to collapse first, then `sl uncommit` and rebuild stack                                      |
| `gh` not authenticated                     | Tell user: `gh auth login --git-protocol https` then re-run                                            |
| `gh` works but no upstream remote          | Print remote-set command (`git remote add origin ...`) and abort                                       |
| Lossless verification fails                | Abort publish; backup is safe; surface the divergence                                                  |
| Per-split gate fails                       | Stop; offer fix-in-place / move-file / replan                                                          |
| User chose "Other" line budget             | Validate `>= 50` to avoid degenerate splits                                                            |
| Existing PR already exists for `$ORIG`     | Note its number in each split's body ("Replaces #NNN"). User decides whether to close it after merging |
| `pnpm` not installed / wrong package mgr   | Run from repo root; if the project doesn't use pnpm, abort with a clear "this skill is pnpm-only" msg  |
| Skill invoked outside the repo root        | `cd "$repo_root"` (from Step 1) before any pnpm command                                                |
| User aborts mid-execute (Ctrl-C)           | Tell them: backup is safe; clean up half-built branches with `git branch -D <branch>-split-*`          |

---

## Implementation notes

- **Never use `--no-verify`** when committing. Honor pre-commit hooks; if a
  hook fails, treat it like a gate failure (Step 7's `HANDLE_GATE_FAILURE`).
- **Never amend a public commit.** Only amend the in-progress split commits.
- **Never force-push** the backup branch. Backup is read-only protection.
- **Always use `git checkout --` (path-mode)** to apply file subsets — never
  `cherry-pick` (which preserves the wrong commit boundaries).
- **Tests run only twice**: once at baseline (Step 3) and once at the stack
  tip (Step 7). This keeps the loop fast even for many splits.
- The skill **does not delete or modify** the user's original branch or
  commit. Recovery is always one `git checkout` / `sl goto` away.
