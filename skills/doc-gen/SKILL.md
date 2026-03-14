# doc-gen

Generate LLM-optimized documentation for a codebase module so future agents can understand it without crawling source code.

## Trigger

Use when the user asks to: generate docs, document a module, create module documentation, build cliff notes for a codebase, make a module LLM-readable, or says "doc-gen" followed by a path.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `entry_point` | **Yes** | — | File or folder to start crawling. If a file, its parent directory is the module root. If a folder, that folder is the module root. |
| `docs_output` | No | `{module_root}/docs/` | Where generated docs are written. |
| `brief` | No | — | Path to a filled-in `BRIEF_TEMPLATE.md`. Speeds discovery; code is still source of truth. |

**If `entry_point` is not provided**, ask the user for it before doing anything else. Do not guess.

## Truth Hierarchy

1. **Code** — source of truth. Every claim must cite a file path and symbol.
2. **User answers** — from the clarification loop. Authoritative for intent and domain knowledge.
3. **BRIEF.md** (if provided) — speeds discovery but may be stale. If it conflicts with code, follow code and log the discrepancy.
4. **Inference** — label explicitly as `[inferred]` with supporting evidence. Never state inferred behavior as fact.

## Execution Phases

This skill runs in **four sequential phases**. Do not skip phases or combine them.

---

### Phase 1: Crawl & Inventory

**Goal:** Build a mental model of the module's structure, boundaries, and major flows.

**Step 0 — Confirm paths:** Before doing anything, resolve and echo back the working paths. Let the user correct before proceeding.

```
Crawl root:  {resolved entry_point}
Module root: {parent dir if entry_point is a file, else entry_point}
Docs output: {docs_output, default: {module_root}/docs/}
Brief:       {brief path, or "none provided"}
```

If the user says nothing or confirms, proceed with these paths. If they correct any path, use the corrected value for all subsequent steps.

**Step 1 — Generate fresh tree:** Run the `repo-tree.sh` script from this skill directory against the module root to get an accurate, current directory structure. This replaces any static repo map — always run it fresh rather than relying on cached or documented trees.

```bash
bash /mnt/skills/user/doc-gen/repo-tree.sh <module-root>
```

**Step 2 — Token-efficient code crawl:**
- Start at the entry point. Follow imports to construct a dependency-informed map.
- When a directory appears to be a stable boundary (`api/`, `routes/`, `store/`, `components/`, `hooks/`, `features/`, `models/`, `utils/`, `lib/`, `services/`), summarize it and open only representative files.
- Prioritize reading (in order):
  1. Entry files and barrel exports (`index.ts`, `index.tsx`)
  2. Type definitions and DTOs (understand the domain model first)
  3. Top-level composition (providers, layout, routing)
  4. Data ingestion / transformation layer
  5. Core business logic hooks and utilities
  6. Presentational components (skim — focus on props interfaces)
- Do NOT read every file. Prefer: entry files → public surfaces → types → glue modules → representative implementations.
- For each file read, record: path, key exports, single-line purpose.

**Output of Phase 1:** Present the user with:
1. A **module inventory** — list of discovered sub-modules, their apparent purpose, and file counts
2. A **domain entity list** — key types/DTOs found and their relationships
3. A **feature list** — user-visible behaviors discovered
4. An **open questions list** — things that are unclear, ambiguous, or where multiple interpretations exist

Then proceed immediately to Phase 2.

---

### Phase 2: Clarification Loop

**Goal:** Eliminate ambiguity before writing any documentation. Do not assume.

**Protocol:**
- Review open questions from Phase 1.
- Present **exactly 3 questions** per round to the user.
- Questions should be ordered by impact — ask about things that would most change the documentation first.
- After each round, update your understanding and determine if more questions are needed.
- Continue rounds until: (a) no material ambiguities remain, or (b) the user says to proceed.

**What to ask about:**
- Module boundaries that are unclear (where does this module end and another begin?)
- Intended vs. actual behavior (is this a bug or a feature?)
- Domain terminology (what does the team call this concept?)
- User personas and primary use cases (who uses this and why?)
- Features that appear incomplete (intentionally scoped down, or WIP?)
- Conventions not obvious from code (naming, file placement, patterns)

**What NOT to ask about:**
- Things clearly answered by code (read more carefully instead)
- Implementation details that don't affect documentation
- Stylistic preferences (follow the conventions in this skill)

**Output of Phase 2:** A summary of resolved questions and final understanding, presented to the user for confirmation before proceeding.

---

### Phase 3: Write Documentation

**Goal:** Produce the full documentation set.

**Write in this order** (each deliverable may inform the next):

1. `DOMAIN.md` — vocabulary and invariants (grounds all other docs)
2. `ARCHITECTURE.md` — structure and data flow
3. `modules/*.md` — one per stable sub-module
4. `features/*.md` — one per user-visible feature
5. `functional-spec/PRODUCT.md` — implementation-agnostic spec
6. `adr/*.md` — only for consequential decisions (0–6 ADRs)
7. `AGENTS.md` — playbook for future agents (references all above, includes routing table and conventions)
8. `INDEX.md` — table of contents linking everything

**Documentation root:** Use the `docs_output` path confirmed in Phase 1 Step 0. All deliverables are written relative to this directory.

**No static repo map.** Do not create a REPO_MAP.md file. Instead:
- The `repo-tree.sh` script provides an always-fresh directory tree on demand.
- Agent routing pointers ("if you need X, start here") live in `AGENTS.md` under Quick Lookup.
- Directory conventions live in `AGENTS.md` under Conventions.
- File-level exports are discoverable from barrel files — do not duplicate them in docs.

**Writing rules:**
- Every factual claim must cite evidence as `path#SymbolName` or `path#L10-L25`.
- If inferred, label `[inferred]` with supporting evidence.
- Prefer Mermaid diagrams over ASCII art. Use Mermaid for: component trees, data flow, state machines, entity relationships. Use fenced code blocks with `mermaid` language tag.
- Prefer concise structured bullets over prose. Optimize for scanability.
- Use consistent terminology — align with `DOMAIN.md` glossary.
- Omit sections entirely when not applicable. Do not write "N/A" or "Not applicable" filler.
- Cross-reference between docs using relative links. Do not duplicate content — link to the canonical location.

---

### Phase 4: Validation & Handoff

**Goal:** Ensure quality and completeness.

- Re-read each deliverable and verify claims against code.
- Produce a **BRIEF VS CODE DIFFERENCES** section listing any discrepancies between the user's BRIEF.md (if provided) and what code shows.
- Produce a final **OPEN QUESTIONS** section for anything that remains genuinely uncertain.
- Present the complete file list to the user.

---

## Deliverable Templates

### DOMAIN.md

```markdown
# {Module Name} — Domain

## Glossary

| Term | Definition | Code Reference |
|------|-----------|----------------|
| ... | ... | `path#Type` |

## Entities & Relationships

<!-- Mermaid ER diagram if 3+ entities -->

## Invariants

- {thing} MUST always {constraint}. — `path#symbol`

## Business Rules

- When {condition}, {behavior}. — `path#symbol`

## Edge Cases & Failure Modes

- {scenario}: {what happens}
```

### ARCHITECTURE.md

```markdown
# {Module Name} — Architecture

## Entry Points

| Entry | Purpose | File |
|-------|---------|------|
| ... | ... | `path` |

## Composition Overview

<!-- Mermaid component diagram -->

## Data Flow

<!-- Mermaid flowchart: ingestion → transformation → state → rendering -->

## State Model

- {what state exists, where it lives, how it updates}

## Cross-Cutting Concerns

### Performance
### Error Handling
### Loading States
<!-- Omit any section heading that doesn't apply -->

## Key Design Decisions

- {decision}: {rationale} — see `adr/NNN-{slug}.md` if ADR exists
```

### modules/*.md

```markdown
# Module: {Name}

## Purpose

{1–2 sentences}

## Public Surface

| Export | Type | File |
|--------|------|------|
| ... | ... | `path` |

## Responsibilities

- {does this}
- {does that}

## Non-Goals

- {explicitly does NOT do this}

## How It Works

{High-level description, ≤1 paragraph. Mermaid diagram if helpful.}

## Key Types

| Type | Purpose | File |
|------|---------|------|
| ... | ... | `path` |

## Invariants & Failure Modes

- {invariant or failure scenario}

## Extension Points

- To add {X}, create {file} following {pattern}. See {example}.

## Related Files

- `path` — {1-line description}
```

### features/*.md

```markdown
# Feature: {Name}

## User Story

As a {persona}, I want to {action} so that {outcome}.

## Scope

{What this feature includes and excludes}

## UX Flow

### Empty State
### Loading State
### Success State
### Error State
<!-- Omit states that don't apply -->

## Acceptance Criteria

- [ ] {testable criterion}

## Data Model (Conceptual)

<!-- What data does this feature consume and produce? Implementation-agnostic. -->

## State Transitions

<!-- Mermaid state diagram if non-trivial -->

## Code Touchpoints

| Concern | File |
|---------|------|
| Entry point | `path` |
| Logic | `path` |
| UI | `path` |
| Types | `path` |

## Known Pitfalls

- {gotcha}
```

### functional-spec/PRODUCT.md

```markdown
# {Module Name} — Product Specification

> Implementation-agnostic. Describes WHAT the product does, not HOW.

## Personas & Goals

| Persona | Goal |
|---------|------|
| ... | ... |

## Functional Requirements

### {Feature Name}

- **MUST**: {requirement}
- **SHOULD**: {requirement}
- **MAY**: {requirement}

## Non-Functional Requirements

- Performance: {requirement}
- Accessibility: {requirement}
<!-- Only include categories with actual requirements -->

## Conceptual Data Model

<!-- Mermaid ER diagram — entities and relationships only, no implementation details -->

## User Journeys

### {Journey Name}

1. {step}
2. {step}
3. {step}

**Edge cases:** {list}

## Out of Scope

- {explicitly excluded}
```

### adr/*.md (ADR template)

```markdown
# ADR-{NNN}: {Title}

## Status

Accepted | Superseded | Deprecated

## Context

{What situation or problem prompted this decision?}

## Decision

{What was decided?}

## Consequences

- {positive or negative consequence}

## Alternatives Considered

| Alternative | Why not chosen |
|-------------|----------------|
| ... | ... |
```

### AGENTS.md

```markdown
# {Module Name} — Agent Playbook

> Read this file first. It tells you what to read next for any task.

## Quick Start

1. Read `INDEX.md` for the full doc map.
2. Read `DOMAIN.md` for vocabulary.
3. Read `ARCHITECTURE.md` for structure and data flow.
4. Read the relevant `features/*.md` or `modules/*.md` for your task.

## Quick Lookup

<!-- Routing table — the most important section for token efficiency. -->
<!-- Keep this updated when files move or new modules/features are added. -->

| If you need to... | Start here |
|--------------------|------------|
| Understand the domain vocabulary | `DOMAIN.md` |
| See how data flows end-to-end | `ARCHITECTURE.md` |
| ... | `path` |

## Fresh Repo Tree

Do NOT rely on a static file listing. Run this to get the current structure:

\`\`\`bash
bash /mnt/skills/user/doc-gen/repo-tree.sh {module-root}
\`\`\`

## Build / Test / Run

| Action | Command |
|--------|---------|
| ... | ... |

## Conventions

### Directory Structure

| Directory | Purpose | Conventions |
|-----------|---------|-------------|
| ... | ... | ... |

### Naming & Patterns

- {file placement rules}
- {naming conventions}
- {pattern expectations}

## Change Workflows

### Add a Feature

1. {step}

### Fix a Bug

1. {step}

### Extend the Data Model

1. {step}

### Tune Performance

1. {step}

<!-- Only include workflows relevant to this module's nature -->

## Documentation Update Rules

| When you change... | Update... |
|---------------------|-----------|
| A domain type or DTO | `DOMAIN.md` glossary, relevant `modules/*.md` key types |
| Module public surface | Relevant `modules/*.md` |
| User-visible behavior | Relevant `features/*.md` and `functional-spec/PRODUCT.md` |
| File/folder structure | `Conventions` table above (and re-run `repo-tree.sh` for freshness) |
| A design decision | Relevant `adr/*.md` |

## Context-Minimizing Guidance

{Which docs to load before touching code. Ordered by priority for typical tasks.}
```

### INDEX.md

```markdown
# {Module Name} — Documentation Index

| Document | Description |
|----------|-------------|
| [AGENTS.md](./AGENTS.md) | Agent playbook — read first |
| [DOMAIN.md](./DOMAIN.md) | Vocabulary, invariants, business rules |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Structure, data flow, design decisions |
| [functional-spec/PRODUCT.md](./functional-spec/PRODUCT.md) | Implementation-agnostic product spec |

## Modules

| Module | Description |
|--------|-------------|
| ... | ... |

## Features

| Feature | Description |
|---------|-------------|
| ... | ... |

## ADRs

| ADR | Decision |
|-----|----------|
| ... | ... |
```

---

## Quality Checklist (self-review before handoff)

- [ ] Every factual claim cites a file path and symbol
- [ ] Inferred content is labeled `[inferred]`
- [ ] No sections contain filler ("N/A", "None", "Not applicable")
- [ ] Terminology is consistent with DOMAIN.md glossary
- [ ] No content is duplicated across docs — cross-references used instead
- [ ] Mermaid diagrams are syntactically valid
- [ ] All relative links resolve correctly
- [ ] AGENTS.md Quick Lookup table covers all major navigation needs
- [ ] AGENTS.md Conventions table matches actual directory structure
- [ ] AGENTS.md change workflows are specific to this module (not generic)
- [ ] BRIEF VS CODE DIFFERENCES is populated (even if empty)
- [ ] OPEN QUESTIONS is populated (even if empty)
