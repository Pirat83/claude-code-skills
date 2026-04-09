---
name: tune-up
description: >-
  Concrete audit with structured output for the Claude Code workflow. Checks
  permissions for bloat, agents for staleness, skills for hardcoded patterns,
  and CLAUDE.md for quality. Each phase has executable steps and a structured
  output template. Run periodically or when starting work in a new project.
  Also trigger when the user says "optimize my setup", "clean up Claude config",
  or "audit my workflow".
---

# /tune-up — Claude Code Workflow Audit

Runs a concrete, step-by-step audit of the Claude Code setup for the current
project. Reports findings with structured output per phase, then presents a
summary with proposed actions. Does NOT apply changes without approval.

## How to execute

Run all 6 phases in order. For each phase, follow the numbered steps exactly,
then emit the output template. After all phases, present the Phase 5 summary
and wait for user approval before Phase 6.

Use `Read` tool for files and `Grep` tool for searching — never use bash
`cat`, `grep`, or `rg`.

---

### Phase 1: Permissions Audit

**Steps:**

1. Read all 4 settings files using the `Read` tool (skip any that don't exist):
   - `~/.claude/settings.json` (global shared — Ansible-managed, DO NOT modify)
   - `~/.claude/settings.local.json` (global local)
   - `.claude/settings.json` (project shared)
   - `.claude/settings.local.json` (project local)
2. From each file, extract every entry in the `"allow"` array (under
   `"permissions"` or at the top level depending on format). Build a flat list
   per file: `[(file, entry), ...]`.
3. Flag issues by applying these rules to each entry:
   - **[one-off]** — entry is >100 characters AND contains no `*` wildcard.
   - **[redundant]** — a broader wildcard in the same file or a higher-priority
     file already covers this entry. Priority order (highest first):
     `global shared > global local > project shared > project local`.
     Match logic: entry `Bash(git branch:*)` is covered by `Bash(git:*)`.
     Strip the specific suffix and check if any higher-priority entry starts
     with the same prefix up to the last `:` or `(`.
   - **[duplicate]** — the exact same string appears in more than one file.
   - **[consolidate]** — 3 or more entries in the same file share a common
     prefix (everything before the last `:` or space). Suggest replacing them
     with one `prefix:*` wildcard.
4. Emit the output:

```
Phase 1 — Permissions
  ~/.claude/settings.json:       {N} entries (Ansible-managed, read-only)
  ~/.claude/settings.local.json: {N} entries, {R} removable
  .claude/settings.json:         {N} entries, {R} removable
  .claude/settings.local.json:   {N} entries, {R} removable

  Issues:
  - [redundant] .claude/settings.local.json: "Bash(git branch:*)" covered by global "Bash(git:*)"
  - [one-off] .claude/settings.json: "Bash(psql -h localhost ...)" (128 chars, no wildcard)
  - [duplicate] "Bash(npm:*)" appears in both global local and project shared
  - [consolidate] 4 entries matching "Bash(poetry run *)" → single "Bash(poetry run:*)"

  (or "No issues found." if clean)
```

---

### Phase 2: Agent Audit

**Steps:**

1. List files in `.claude/agents/` using `Glob("*.md", path=".claude/agents/")`.
   If the directory doesn't exist, report "No agents directory" and skip.
2. For each agent `.md` file, read the first 30 lines to get the description
   and key instructions.
3. Check each agent against the known built-in subagent types:
   `general-purpose`, `Explore`, `Plan`, `python-expert`, `pandas-expert`,
   `backtesting-expert`, `graph-execution-expert`, `notebook-expert`,
   `numpy-expert`, `postgres-expert`, `docker-expert`, `valkyrie-coordinator`,
   `claude-code-guide`, `code-simplifier`, `pr-review-toolkit`.
   If an agent's filename (minus `.md`) matches a built-in name AND the file
   content contains no project-specific terms (project name, framework classes,
   domain-specific tools), flag as **[generic]** — it shadows the built-in
   without adding value.
4. Cross-reference: use `Grep` to search for each agent name (filename without
   `.md`) across these locations:
   - `CLAUDE.md` (project root)
   - `.claude/skills/*/SKILL.md`
   - `.claude/agents/*.md` (other agents)
   Report any reference to an agent name that doesn't have a matching file in
   `.claude/agents/` as **[stale-ref]**.
5. Check project tech stack for missing specialists:
   - If `.ipynb` files exist (`Glob("**/*.ipynb")`) but no notebook-related
     agent exists → flag **[missing]**
   - If `Dockerfile` or `docker-compose.yml` exists but no docker agent → flag
   - If `pyproject.toml` has pandas/numpy deps but no data agent → flag
6. Emit the output:

```
Phase 2 — Agents
  {N} agents in .claude/agents/

  Issues:
  - [generic] docker-expert.md — no project-specific content, shadows built-in
  - [stale-ref] CLAUDE.md line 42 references "old-agent" which doesn't exist
  - [missing] Project uses .ipynb files but has no notebook-expert agent

  (or "No issues found." if clean)
```

---

### Phase 3: Skill Audit

**Steps:**

1. List all skills in both locations using `Glob`:
   - Project: `.claude/skills/*/SKILL.md`
   - Global: `~/.claude/skills/*/SKILL.md`
2. For each skill, read the full SKILL.md content.
3. Check for these patterns using `Grep` within each skill file:
   - **[hardcoded-perms]** — file contains `Allowed Commands` or
     `Bash(` permission patterns. These belong in settings files, not skills.
   - **[hardcoded-shell]** — file contains `Shell Command Rules` or similar
     sections dictating shell behavior. These belong in CLAUDE.md.
   - **[stale-ref]** — file references an agent name (pattern: lowercase words
     joined by hyphens, e.g., `python-expert`). Verify each referenced agent
     exists in `.claude/agents/`. Report missing ones.
   - **[stale-doc]** — file references a `docs/` path. Use `Bash` with `ls` to
     verify that path exists. Report missing paths.
   - **[missing-script]** — file references `${CLAUDE_SKILL_DIR}/scripts/` or
     similar script paths. Verify each referenced script file exists relative
     to the skill directory.
4. Emit the output:

```
Phase 3 — Skills
  {N} project skills, {M} global skills

  Issues:
  - [hardcoded-perms] my-skill: has "Allowed Commands" section (use settings.json instead)
  - [stale-ref] my-skill: references "old-agent" which doesn't exist in .claude/agents/
  - [stale-doc] my-skill: references docs/old-guide.md which doesn't exist
  - [missing-script] my-skill: references scripts/validate.sh which doesn't exist

  (or "No issues found." if clean)
```

---

### Phase 4: CLAUDE.md Quality

**Steps:**

1. Read the project `CLAUDE.md` (if it doesn't exist, report and skip).
2. Read `~/.claude/CLAUDE.md` (global).
3. Extract all backtick-quoted names that look like agents or skills — pattern:
   one or more lowercase words joined by hyphens, e.g., `` `python-expert` ``,
   `` `/run-tests` ``, `` `valkyrie-coordinator` ``. Exclude obvious non-names
   (file paths with `/` or `.`, code keywords).
4. For each extracted name:
   - If it looks like an agent reference (no `/` prefix), verify a file exists
     at `.claude/agents/{name}.md`. Flag missing as **[stale-ref]**.
   - If it looks like a skill reference (`/` prefix), verify a directory exists
     at `.claude/skills/{name}/SKILL.md` or `~/.claude/skills/{name}/SKILL.md`.
     Flag missing as **[stale-ref]**.
5. Check for contradictions between project and global CLAUDE.md:
   - Look for tool preference keywords: `mypy`, `pyright`, `basedpyright`,
     `ruff`, `flake8`, `black`, `pytest`, `unittest`. If both files mention
     the same category but different tools, flag as **[contradiction]**.
6. Check for undocumented hooks:
   - Read all 4 settings files and search for `"hooks"` keys. If any hooks
     exist but `CLAUDE.md` doesn't mention them, flag as **[undocumented]**.
7. Check for outdated doc-reading instructions:
   - If `.claude/rules/` exists AND has files synced from `docs/`, AND
     `CLAUDE.md` still says "read docs/ first" or "read docs/code-style/",
     flag as **[outdated]** — rules are auto-loaded, explicit reading
     instructions waste context.
8. Emit the output:

```
Phase 4 — CLAUDE.md
  Issues:
  - [stale-ref] Line 15: mentions "old-agent" — doesn't exist in .claude/agents/
  - [contradiction] Project says "use mypy", global says "use basedpyright"
  - [outdated] Line 8: says "read docs/code-style/" but .claude/rules/ has auto-loaded rules
  - [undocumented] Hook "pre-push" exists in settings but not mentioned in CLAUDE.md

  (or "No issues found." if clean)
```

---

### Phase 5: Summary & Recommendations

Consolidate all issues from Phases 1-4. Assign severity to each:

- **critical** — broken references (stale-ref, missing-script), contradictions
- **warning** — redundant entries, generic agents, hardcoded permissions
- **info** — consolidation opportunities, missing specialists, outdated docs

Emit the summary:

```
=== /tune-up Report ===

Permissions:  {N} entries across {M} files, {R} removable ({P}% reduction)
Agents:       {N} agents, {I} issues found
Skills:       {N} skills, {I} issues found
CLAUDE.md:    {I} issues found

Critical: {C}    Warning: {W}    Info: {I}

Recommended actions:
1. [warning][permissions] Remove {N} redundant entries from {file}
2. [warning][agent] Rewrite {name} — generic content, no project standards
3. [critical][skill] Fix stale reference to "old-agent" in {skill-name}
4. [info][permissions] Consolidate 4 "Bash(poetry run *)" entries → single wildcard
...

Apply all? (all / 1,2,3 / none)
```

---

### Phase 6: Apply (only if user approves)

Wait for the user to respond with which actions to apply.

For each approved action:

1. Show the exact diff (before/after) BEFORE making any change.
2. Apply the change using the `Edit` tool.
3. After all changes, run `Read` on each modified file to confirm correctness.

**Important constraints:**
- NEVER modify `~/.claude/settings.json` — it is Ansible-managed.
- For permission removals, edit the `"allow"` array in the appropriate file.
- For agent/skill fixes, edit or delete the specific file.
- For CLAUDE.md fixes, edit in place.
