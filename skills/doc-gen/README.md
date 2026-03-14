# doc-gen Skill — Installation Guide

## What's in the box

```
doc-gen/
├── SKILL.md            # The skill definition (Claude Code reads this)
├── BRIEF_TEMPLATE.md   # Optional template you fill per module to speed things up
├── repo-tree.sh        # Shell script for on-demand directory trees
└── README.md           # This file
```

## Installation on Mac

Claude Code looks for user skills in a specific folder inside your project. Here's how to set it up.

### Step 1: Find your project root

This is the folder where your `CLAUDE.md` file lives (or where you run `claude` from). Open Terminal and `cd` into it.

```bash
cd /path/to/your/project
```

### Step 2: Create the skills directory (if it doesn't exist)

Claude Code expects user skills at `.claude/skills/`. Each skill gets its own subfolder.

```bash
mkdir -p .claude/skills/doc-gen
```

### Step 3: Copy the files

Copy all four files from wherever you downloaded them into the skill folder:

```bash
cp /path/to/downloaded/doc-gen/SKILL.md       .claude/skills/doc-gen/
cp /path/to/downloaded/doc-gen/BRIEF_TEMPLATE.md .claude/skills/doc-gen/
cp /path/to/downloaded/doc-gen/repo-tree.sh    .claude/skills/doc-gen/
cp /path/to/downloaded/doc-gen/README.md       .claude/skills/doc-gen/
```

### Step 4: Make the shell script executable

```bash
chmod +x .claude/skills/doc-gen/repo-tree.sh
```

### Step 5: Tell CLAUDE.md about it (optional but recommended)

Open your project's `CLAUDE.md` and add a routing entry so Claude Code knows the skill exists:

```markdown
## Skills

- **doc-gen** — Generate LLM-optimized documentation for a module.
  Trigger: "doc-gen <path>", "document this module", "generate docs for <path>"
  Location: `.claude/skills/doc-gen/SKILL.md`
```

### Step 6: Verify

Start Claude Code and say:

```
doc-gen src/features/my-module
```

Claude should read the skill, run `repo-tree.sh` against your module, crawl the code, then start asking you clarification questions before writing docs.

## Usage

### Quick start (no brief)

Just give it an entry point:

```
doc-gen src/features/knowledge-graph
```

or

```
doc-gen src/features/knowledge-graph/knowledge-graph-app.tsx
```

### With a brief (faster, fewer questions)

1. Copy `BRIEF_TEMPLATE.md` somewhere near your module:

```bash
cp .claude/skills/doc-gen/BRIEF_TEMPLATE.md src/features/my-module/docs/BRIEF.md
```

2. Fill in what you know. Leave blanks for what you don't.

3. Tell Claude Code:

```
doc-gen src/features/my-module — brief is at src/features/my-module/docs/BRIEF.md
```

### Controlling the clarification loop

Claude will ask 3 questions per round. You can:

- **Answer normally** — Claude incorporates your answers and may ask more
- **Say "proceed"** — Claude stops asking and starts writing with what it has
- **Say "skip"** on any question — Claude marks it as unresolved and moves on

## Gitignore note

You probably want to commit the skill so your whole team can use it:

```bash
# These should NOT be in .gitignore
.claude/skills/doc-gen/
```

The generated docs (in `src/features/*/docs/`) should be committed too — that's the whole point.

## Updating the skill

Just overwrite the files in `.claude/skills/doc-gen/`. There's no cache to clear. Claude Code reads the skill fresh each time it's triggered.
