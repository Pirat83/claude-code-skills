---
name: tune-up
description: >-
  Concrete audit with structured output for the Claude Code workflow. Twelve
  peer-numbered phases: drift setup, permissions, agents, skills, plugins, MCP
  servers, hooks, rules, CLAUDE.md/coordinators/notification-sinks, summary,
  apply, post-apply quality gate. Each phase follows the same
  Subject/Sources/Checks/Output/Apply shape.
  Tracks per-project state in `.claude/.tune-up-state.json` so a project
  untouched for months produces a months-wide upstream-drift delta on its next
  run. Use this skill whenever the user wants to audit, clean up, optimise, or
  catch up on their Claude Code setup — even if they don't explicitly say
  `/tune-up`. Trigger phrases include "optimize my setup", "clean up Claude
  config", "audit my workflow", "what's new in Claude Code I should adopt",
  "my Claude config feels stale", "what plugins should I be using", and
  "drift check".
---

# /tune-up — Claude Code Workflow Audit

Runs a concrete, step-by-step audit of the Claude Code setup for the current
project. Reports findings with a uniform per-phase output, then presents a
summary with proposed actions. Does NOT apply changes without approval.

## How to execute

Parse `$ARGUMENTS`. Recognised flags:

- `/tune-up` — full audit; always re-fetches upstream sources
- `/tune-up --offline` — skip every upstream probe (Phase 1's network leg,
  and the upstream half of Phases 3, 4, 5, 7). Local-only checks still run.
- `/tune-up --quick` — Phase 1 (local-only) + Phase 2 + Phase 10 only.

Run phases in order. For each phase, follow the numbered steps exactly, then
emit the output template. After Phase 10, present the summary and wait for
user approval before running Phase 11.

**Reading and searching.** Prefer the dedicated tools — `Read` for files, `Grep`
for content search, `Glob` for listing paths — because they go through the
harness's permission and telemetry layers, while bash equivalents bypass both
and obscure what the audit actually consulted.

Prefer, not require: `Grep` and `Glob` are not offered to every session, and a
skill that insists on a tool the session does not have cannot run at all. Check
what you actually have before the first read. Where a dedicated tool is missing,
use the `Bash` equivalent (`grep`, `find`, `sed -n`) and **say so once** in the
Phase 1 output, so the reader knows this run's evidence came through a different
path. Do not silently substitute, and do not stall.

Steps below name operations rather than tools for this reason: "list `*/SKILL.md`
under `~/.claude/skills/`" is satisfiable either way; `Glob(...)` is not.

`Bash` is required regardless for shell-only operations: `gh release list`, the
`state_io.sh` / `upstream_probe.sh` helpers, the binary probe in **Name
resolution**, and atomic file moves.

## Design principles

1. **Flat phase numbering.** No nested sub-phases. Twelve peer phases.
2. **One subject per phase.** Each phase audits exactly one concept.
3. **Uniform phase shape.** Every phase has Subject / Sources / Checks /
   Output / Apply branches.
4. **Single state file.** Per-project at `<project>/.claude/.tune-up-state.json`.
   No XDG state, no shared cache, no TTL.
5. **Canonical flag vocabulary** (table below). Same flag means the same
   thing in every phase.
6. **Always re-fetch upstream.** No `--refresh`. `--offline` skips upstream.

### Canonical flag vocabulary

| Flag | Meaning |
|---|---|
| `[duplicate]` | Same thing defined in multiple places |
| `[redundant]` | Subsumed by a broader rule |
| `[unused]` | Defined locally/globally but never referenced by this project |
| `[stale-ref]` | Reference points at something that no longer exists |
| `[outdated]` | Local copy older than authoritative source |
| `[upgrade-available]` | New version available in marketplace/CLI release |
| `[adopt]` | Codebase pattern suggests adopting an automation (hook, subagent, skill, plugin, MCP) — sole source: Phase 10 via `/claude-code-setup:claude-automation-recommender` |
| `[new-feature]` | Upstream added something since last tune-up |
| `[withdrawn]` | Was available to this session last run, is not now |
| `[phantom-tool]` | A name in config resolves to no tool anywhere — delete the reference |
| `[gated-tool]` | Names a tool that exists in the CLI but is withheld from this session — keep the reference, scope it |
| `[mismatch]` | Local config inconsistent with stated policy |
| `[missing]` | Something expected from project type/tech stack is absent |
| `[oversized]` | Exceeds size threshold |
| `[quality:A]` … `[quality:F]` | CLAUDE.md quality grade from `claude-md-improver` (Phase 9) |
| `[budget-warning]` / `[budget-critical]` | Context budget thresholds |

### Name resolution (shared by Phases 2, 3, 4, 7, 8, 9)

Several phases check whether a name written in config actually refers to
something the harness will resolve. They all use this one ladder, so a name
gets the same verdict wherever it appears:

```
name → Phase 1's live block (tools_available / agents_available / skills_available)
  ├─ found              → OK
  └─ not found          → Bash: grep -ac '"<Name>"' "$(readlink -f ~/.local/bin/claude)"
                            ├─ hits > 0  → [gated-tool]
                            └─ hits = 0  → [phantom-tool]
```

The second step matters because "unavailable" has two causes with opposite
fixes. A name can be fictional — it never existed, and the reference should be
deleted. Or it can be a real tool the CLI ships but withholds from this
session, via a remote feature flag or a model-version threshold. Deleting a
rule for a tool that returns next month is the wrong repair, and the two cases
are indistinguishable from the live list alone; only the binary tells them
apart. The grep runs solely on names that already failed to resolve, so its
cost stays proportional to the problem rather than to the size of the config.

**Match the quoted token, not the bare name.** Tool names appear in the binary's
registry as `"Name"`, and an unquoted search matches every substring: `LS`
returns 3078 raw hits against 1 quoted. Short names are the risk — a genuinely
fictional two- or three-letter name will collide with ordinary text and be
reported as gated, which is the precise error the two flags exist to prevent,
and it fails in the direction that tells the user to keep a dead reference.

Report a `[gated-tool]` with the advice to scope the reference ("when
available") rather than remove it, and say which gate is plausible if the
surrounding evidence shows one.

### State file: `<project>/.claude/.tune-up-state.json`

Single JSON document, gitignored by default. Schema:

```json
{
  "schema_version": 2,
  "last_run_iso": "2026-05-02T19:14:00Z",
  "local": {
    "claude_code_cli_version": "v2.3.1",
    "agents_present": ["..."],
    "skills_present": ["..."],
    "plugins_present": ["..."],
    "mcp_servers": ["..."],
    "settings_hooks_fingerprint": "sha256-of-merged-hooks",
    "installed_plugins_fingerprint": "sha256-of-installed_plugins.json"
  },
  "live": {
    "observed_with_model": "claude-opus-5",
    "tools_available": ["..."],
    "agents_available": ["..."],
    "skills_available": ["..."],
    "hook_events_available": ["..."]
  },
  "upstream_at_last_run": {
    "claude_code_latest_release": "v2.3.1",
    "release_notes_max_date": "2026-04-30",
    "marketplace_plugins": ["..."],
    "announced_features": ["..."]
  },
  "acknowledged_upstream_features": ["agent:data-engineer", "..."],
  "pending_ansible_mirror": [
    { "applied_at": "...", "target": "...", "diff_sha256": "..." }
  ]
}
```

Read once at start of Phase 1; rewritten atomically at end of Phase 11. Use
the `state_io.sh` helper (in `${CLAUDE_SKILL_DIR}/scripts/state_io.sh`) to
avoid corrupt-on-crash.

---

## Phase 1 — Drift Setup

**Subject.** Load the snapshot, recompute current local fingerprints, fetch
upstream state (unless `--offline`), print the "since last tune-up" banner.

**Sources.**
- `<project>/.claude/.tune-up-state.json` (or initialise if absent).
- Project tree (for local fingerprints).
- **The running session itself** — the in-context tool, agent and skill
  listings, plus `ToolSearch` to resolve deferred tools by name. This is the
  authority on what *exists*; the release notes below are only the authority on
  what is *new*. (Why: a tool can ship in the binary and still be withheld from
  a session by a remote feature flag or a model-version threshold, and no
  changelog bullet is ever written for that. Existence derived from release
  notes cannot see it, so the audit would keep endorsing config that names
  something the session does not have.)
- `gh release list --repo anthropics/claude-code -L 5 --json tagName,publishedAt`
- `claude-code-guide` subagent (primary release-notes fetcher — handles
  docs URL changes via WebSearch, then WebFetch). Raw `WebFetch` on
  `https://docs.claude.com/en/docs/claude-code/release-notes` is the fallback.
- `~/.claude/plugins/marketplaces/*/` (disk only)
- `~/.claude/plugins/installed_plugins.json`
- `~/.claude/plugins/known_marketplaces.json`

**Steps.**

1. Run `Bash` on `${CLAUDE_SKILL_DIR}/scripts/state_io.sh read` from
   `$CLAUDE_PROJECT_DIR`. The helper prints the current snapshot JSON to
   stdout, or an empty default schema if the file is missing. Parse the
   output. If `schema_version` is greater than `2`, emit `[stale-ref]`
   "snapshot from a future schema; aborting" and stop the run. A
   `schema_version` of `1` predates the `live` block: accept it, treat the
   missing block as a first-run baseline for availability, and emit no
   `[withdrawn]` this run — there is nothing to compare against yet.
2. Recompute the `local` block:
   - `claude_code_cli_version`: `Bash("claude --version 2>/dev/null | head -1")`
   - `agents_present`: list `*.md` in `.claude/agents/`, strip `.md`
   - `skills_present`: list `*/SKILL.md` in `.claude/skills/` plus
     `~/.claude/skills/`, strip `/SKILL.md`
   - `plugins_present`: parse `~/.claude/plugins/installed_plugins.json`,
     extract every `plugins.*` key
   - `mcp_servers`: parse `<project>/.mcp.json` `mcpServers` keys plus
     anything in `~/.claude/settings.json:mcpServers`
   - `settings_hooks_fingerprint`: concatenate the merged `hooks` config
     from all four settings files (in priority order) and `sha256sum`
   - `installed_plugins_fingerprint`: `sha256sum ~/.claude/plugins/installed_plugins.json`

   Then recompute the `live` block — what this session actually has, which is
   not the same question as what is installed on disk:
   - `tools_available`: every tool name offered to this session — the base
     toolset plus every deferred tool named in context. Resolve anything you
     are unsure of with `ToolSearch("select:<Name>")` rather than assuming.
   - `observed_with_model`: the model id powering this session. Record it every
     time. Availability is model-dependent, so a tools list stored without the
     model that observed it will read as a withdrawal the next time the user
     runs on a different tier.
   - `agents_available` / `skills_available`: from the in-context listings,
     unioned with the on-disk `agents_present` / `skills_present` above.
   - `hook_events_available`: the hook event names the harness accepts.
3. Compute the `local_drift` diff against the snapshot's `local` block:
   added/removed agents, added/removed skills, added/removed plugins, hook
   fingerprint changed yes/no. Hold this in memory for the banner.
4. **If `--offline`:** skip steps 5-9. Use snapshot's `upstream_at_last_run`
   as both baseline AND current (so upstream-drift checks emit nothing).
5. **Issue steps 5a-5b in parallel** — two independent probes; the model
   should call both tools in a single message rather than serialising:
   - **5a.** `Bash`-run `${CLAUDE_SKILL_DIR}/scripts/upstream_probe.sh`.
     Returns JSON with `gh_releases` (top 5 tags + dates),
     `marketplace_plugins` (sorted `plugin@marketplace` IDs),
     `installed_plugins` (rich metadata: scope, enabled, installPath,
     installedAt, lastUpdated, mcpServers), `known_marketplaces`. The
     helper itself runs `gh` and the plugin enumeration in parallel
     internally.
   - **5b.** Spawn a `claude-code-guide` subagent (it has WebSearch + WebFetch
     and is purpose-built for navigating Anthropic docs URL changes). Prompt:
     "Find the current Claude Code release notes page (the docs URL has
     redirected before — use WebSearch with `site:docs.anthropic.com OR
     site:docs.claude.com claude-code release-notes` to discover the live URL,
     then WebFetch it). List every bullet added since
     `{snapshot.release_notes_max_date}`. For each, classify as: built-in
     agent, built-in tool, hook event, settings field, plugin marketplace
     addition, other. Output as JSON: `{added_bullets: [{date, category,
     name, summary}]}`. Also extract the canonical lists of built-in agents
     and hook events from the docs in case the release-notes page is sparse."

     **Safety net.** If the agent returns empty/error, fall back to the raw
     `WebFetch https://docs.claude.com/en/docs/claude-code/release-notes`
     with the same prompt — older URL may still resolve. Merge any results.
     The `claude-code-guide` arm is the primary path because it's strictly
     more capable; the raw `WebFetch` is the fallback, not the other way
     around.
6. Build the `upstream_current` block from step 5's results:
   - `claude_code_latest_release` = newest `tagName` from `gh_releases`
   - `release_notes_max_date` = max `date` across `added_bullets` (or
     unchanged if zero new bullets)
   - `marketplace_plugins` = from upstream probe
   - `announced_features` = `added_bullets` grouped by category. These feed
     `[new-feature]` only: they record what upstream *announced*, not what this
     session *has*. Do NOT merge with snapshot values (the diff in step 7 vs
     `upstream_at_last_run` already handles baseline + acknowledgement
     filtering).
   - Nothing here describes what the session *has*. `tools_available`,
     `agents_available` and `hook_events_available` were already recorded from
     the live probe in step 2 and are never derived from `added_bullets`.
     Something can be announced and unavailable, or available and never
     announced; only the live probe tells you which you are looking at.
7. Compute `upstream_drift` diff: `upstream_current` minus
   `upstream_at_last_run`, minus already-`acknowledged_upstream_features`.
   Then compute `availability_drift` from this run's `live` block against the
   snapshot's:
   - available last run, absent now → **`[withdrawn]`**
   - available now, absent last run → `[new-feature]`

   **Model guard.** If the snapshot's `observed_with_model` differs from the
   current model, report every availability delta as informational and suppress
   `[withdrawn]` entirely. The set is model-dependent, so a tier change already
   explains the difference; flagging it as a withdrawal would be wrong on the
   facts and would train the user to ignore the flag.
8. Emit the output:

```
Phase 1 — Drift Setup
  Snapshot:      .claude/.tune-up-state.json (last run: {iso}, {N days} ago)
                 OR "first run, establishing baseline"
  Local CLI:     {version}
  Upstream CLI:  {version}                              {[upgrade-available] | OK}
  Live probe:    {N} tools, {M} agents, {P} skills available to {model}
  Release notes: {N} new bullets since {date}
  Marketplace:   {N} marketplaces fresh on disk

  Local drift since last run:
  {one line per [+]/[-]/[Δ] item, or "no changes"}

  Availability drift:
  {one line per [withdrawn]/[new-feature] item, or "none",
   or "model changed {old} → {new} — deltas informational this run"}

  Pending Ansible mirrors: {count, only if > 0 — list each target}
```

**Apply branches.** None. Phase 11 writes the snapshot.

---

## Phase 2 — Permissions

**Subject.** Audit `permissions.allow` arrays across the four settings files.

**Sources.**
- `~/.claude/settings.json` (Ansible-managed, editable with mirror policy)
- `~/.claude/settings.local.json` (global local)
- `<project>/.claude/settings.json` (project shared)
- `<project>/.claude/settings.local.json` (project local)

Priority order (highest first): **global shared > global local > project
shared > project local**.

**Steps.**

1. Read all four settings files via `Read` (skip any that don't exist).
2. From each, extract every entry in the `permissions.allow` array.
3. Apply checks:
   - **`[oversized]`** — entry > 100 chars AND no `*` wildcard.
   - **`[redundant]`** — entry covered by a broader wildcard at same or
     higher priority. Match: strip the suffix after the last `:` or `(`
     and check if a higher-priority entry has the same prefix.
   - **`[duplicate]`** — exact match across files.
   - **`[mismatch]`** (consolidation cluster) — three or more entries in
     the same file share a common prefix; emit one flag per cluster.
   - **`[mismatch]`** (promotion candidate) — entry sits in
     `~/.claude/settings.local.json` or
     `<project>/.claude/settings.local.json` but its scope looks
     machine-wide (no project-specific path, no `~/Projects/<specific>`,
     no host-specific binary). Suggest promoting up to the shared file
     in the same scope tier.
   - **`[mismatch]`** (demotion candidate) — entry in
     `~/.claude/settings.json` or `<project>/.claude/settings.json` looks
     project-specific or host-specific (contains a `~/Projects/<name>`
     path or a binary unique to one host). Suggest demoting down.
   - **`[mismatch]`** (dead path rule) — entry names `Write`, `NotebookEdit`,
     `MultiEdit` or `Glob` **and** carries a path/glob argument rather than the
     `:*` prefix syntax. File permission checks consult only `Edit(path)` and
     `Read(path)` rules, so these never match anything and the permission the
     user thinks they granted is not granted. Emit the rewrite:
     `Write` / `NotebookEdit` / `MultiEdit` → `Edit`, `Glob` → `Read`.
     Check whether the rewritten rule **already exists** in the same file — if
     it does, the entry is dead weight rather than a missing grant, so the fix
     is to delete it and the flag should say so. Getting this backwards
     silently duplicates a rule that was already working.
   - **`[phantom-tool]` / `[gated-tool]`** — entry names a tool that does not
     resolve (see **Name resolution**). The rule can never match, because
     nothing will ever request that tool.
4. Emit:

```
Phase 2 — Permissions
  ~/.claude/settings.json:       {N} entries
  ~/.claude/settings.local.json: {N} entries
  .claude/settings.json:         {N} entries
  .claude/settings.local.json:   {N} entries

  Issues:
  - [redundant]  .claude/settings.local.json: "Bash(git branch:*)" covered by global "Bash(git:*)"
  - [oversized]  .claude/settings.json: "Bash(psql -h ...)" (128 chars, no wildcard)
  - [duplicate]  "Bash(npm:*)" appears in both global local and project shared
  - [mismatch]   3 entries in .claude/settings.json share prefix "Bash(poetry run pytest" — consolidate?
  - [mismatch]   "Bash(gh*)" in settings.local.json looks machine-wide → promote to ~/.claude/settings.json
  - [mismatch]   ~/.claude/settings.json: "Write(//tmp/**)" is never consulted → "Edit(//tmp/**)" (already present — delete this entry)
  - [phantom-tool] .claude/settings.json: "Snip(*)" — no such tool resolves

  (or "No issues found." if clean)
```

**Apply branches.** Edit `permissions.allow` in the appropriate file.
Edits to `~/.claude/settings.json` follow the **Ansible-mirror policy**
in Phase 11.

---

## Phase 3 — Agents

**Subject.** Audit project agents, global agents, plugin-provided agents,
and the upstream live built-in list.

**Sources.**
- `<project>/.claude/agents/`
- `~/.claude/agents/`
- `~/.claude/plugins/cache/*/*/agents/` (plugin-provided)
- Snapshot's `live.agents_available` (previous run)
- Phase 1's `live.agents_available` (this run) — the authority on what exists

**Steps.**

1. List project agents: `*.md` in `.claude/agents/`. If the directory is
   missing, report and continue.
2. List global agents: `*.md` in `~/.claude/agents/`.
3. List plugin agents: `*/agents/*.md` under `~/.claude/plugins/cache/`.
4. For each project agent, read the first 30 lines.
5. Apply checks:
   - **`[mismatch]`** — project agent filename matches a name in
     this run's `live.agents_available` AND the file has no
     project-specific terms (project name from `pyproject.toml` /
     `package.json`, framework class names, domain-specific tools).
     This shadows a built-in without adding value.
   - **`[stale-ref]`** — agent name (lowercase-hyphenated) referenced in
     `CLAUDE.md`, `~/.claude/CLAUDE.md`, or any `.claude/skills/*/SKILL.md`,
     but no matching file exists in any of the three locations (project,
     global, plugin).
   - **`[missing]`** — project tech stack expects a specialist that's
     absent:
     - `.ipynb` files exist → expect a notebook agent
     - `Dockerfile` / `docker-compose.yml` → expect a docker agent
     - `pyproject.toml` mentions `pandas`/`numpy` → expect a data agent
   - **`[unused]`** — globally-installed or plugin-provided agent never
     referenced in this project's tree (search for the bare name across
     `.claude/`, `CLAUDE.md`, top-level docs).
   - **`[phantom-tool]` / `[gated-tool]`** — an agent definition's `tools:`
     frontmatter names a tool that does not resolve (see **Name resolution**).
     The agent still loads, so nothing errors; it just quietly has less reach
     than its definition claims.
   - **`[new-feature]`** — name in this run's `live.agents_available`
     but not in the snapshot's AND not in `acknowledged_upstream_features`.

   Adoption gaps (codebase patterns suggest installing a new agent) are
   no longer audited here — Phase 10 owns that dimension via
   `/claude-code-setup:claude-automation-recommender` and emits `[adopt]`
   flags in the consolidated summary.
6. Emit:

```
Phase 3 — Agents
  Project agents:  {N} ({comma-separated names})
  Global unused:   {names not referenced in this project}
  Plugin agents:   {N} provided by installed plugins

  Issues:
  - [mismatch]      docker-expert.md — no project-specific content, shadows built-in
  - [stale-ref]     CLAUDE.md mentions "numpy-expert" — file does not exist
  - [missing]       project has 12 .ipynb files but no notebook-specialist agent
  - [new-feature]   new built-in agent: data-engineer (release notes 2026-04-22)

  (or "No issues found." if clean)
```

**Apply branches.** Delete agent file; edit CLAUDE.md to fix stale ref;
add new-feature to `acknowledged_upstream_features`. Adoption candidates
appear only in Phase 10 (`[adopt]` flags from automation-recommender).

---

## Phase 4 — Skills

**Subject.** Audit project + global skills, with the in-context skill listing
and on-disk copies as the source of truth.

**Sources.**
- `<project>/.claude/skills/*/SKILL.md`
- `~/.claude/skills/*/SKILL.md`
- `~/.claude/plugins/cache/*/*/skills/*/SKILL.md` (plugin-provided)
- Phase 1's `live.skills_available`
- Git-tracked copies of the same skills elsewhere on disk (see `[outdated]`)

**Steps.**

1. List all skills across the three locations above.
2. For each project + global skill, read the full SKILL.md.
3. Apply checks:
   - **`[mismatch]`** — SKILL.md contains `Allowed Commands` or `Bash(...)`
     permission patterns (skills shouldn't carry permissions; that's
     `settings.json`'s job).
   - **`[mismatch]`** — SKILL.md contains "Shell Command Rules" or similar
     directive sections (those belong in CLAUDE.md).
   - **`[stale-ref]`** — references an agent name (lowercase-hyphenated,
     no `/` prefix) that doesn't exist in any agent location.
   - **`[stale-ref]`** — references a `docs/` path that doesn't exist
     (verify with `Bash("test -e <path>")`).
   - **`[stale-ref]`** — references `${CLAUDE_SKILL_DIR}/scripts/<file>`
     where the file doesn't exist relative to the skill's own directory.
   - **`[phantom-tool]` / `[gated-tool]`** — SKILL.md names a tool that does
     not resolve (see **Name resolution**), whether in prose, in a Sources
     list, or in `allowed-tools` frontmatter. A skill whose instructions call a
     tool the session does not have fails partway through, at the point of use,
     with no warning beforehand.
   - **`[outdated]`** — a skill installed under `~/.claude/skills/` has a
     git-tracked counterpart on disk that differs. Discover counterparts with
     `Bash("find ~/Projects -maxdepth 4 -path '*/skills/*/SKILL.md' 2>/dev/null")`,
     mirroring the Ansible-repo discovery in Phase 11, and compare by content.
     Report the direction and size of the divergence — an installed copy ahead
     of its repo is unbacked work that dies with the disk, while one behind its
     repo is running stale. Both are worth knowing; neither is automatically
     the error.
   - **`[unused]`** — globally-installed skill never referenced from this
     project tree.

   Adoption gaps (skills the project should install) are no
   longer audited here — Phase 10 owns that dimension via
   `/claude-code-setup:claude-automation-recommender` and emits `[adopt]`
   flags in the consolidated summary.
4. Emit:

```
Phase 4 — Skills
  Project skills:  {N}
  Global skills:   {M}
  Plugin skills:   {P}

  Issues:
  - [mismatch]        /pre-commit-check carries hardcoded "Bash(pytest...)"
  - [stale-ref]       /post-push-check references docs/ci.md (does not exist)
  - [outdated]        /tune-up — installed 1171 lines, git copy 245 lines (installed is ahead, unbacked)
  - [unused]          /frontend-design — no UI work in this project

  (or "No issues found." if clean)
```

**Apply branches.** Edit SKILL.md inline; print update command for
`[outdated]`; offer to disable `[unused]` skills via project settings.
Adoption candidates appear only in Phase 10 (`[adopt]` flags from
automation-recommender).

For `[mismatch]` flags that involve rewriting a skill SKILL.md (e.g. a
skill carries hardcoded permissions and needs to be split), prefer
delegating the rewrite to **`/skill-creator:skill-creator`** in Phase 11
rather than editing inline — it enforces the canonical SKILL.md
conventions and can run trigger-eval on the description.

---

## Phase 5 — Plugins

**Subject.** Audit installed plugins for updates, channel mismatches, and
project-level usage. Disk-only — no network.

**Sources.**
- Phase 1's `upstream_probe.sh` output, specifically:
  - `installed_plugins[]` — rich metadata per installed plugin (`id`,
    `version`, `scope`, `enabled`, `installPath`, `installedAt`,
    `lastUpdated`, `mcpServers`, `projectPath` for local-scope)
  - `marketplace_plugins[]` — sorted `<name>@<marketplace>` IDs of every
    plugin available across configured marketplaces
  - `known_marketplaces[]` — marketplace metadata (`name`, `source`,
    `lastUpdated`)
- Snapshot's `upstream_at_last_run.marketplace_plugins` (diff baseline)
- `claude plugin list --available --json` is the canonical source. The
  shell helper already invokes it (with on-disk fallback if `claude` isn't
  on `$PATH`); Phase 5 reads from that result, never directly from
  `installed_plugins.json` or `marketplaces/*/.claude-plugin/marketplace.json`.

**Steps.**

1. From `installed_plugins[]`, group by `scope` (`user` vs `local`). Note
   any disabled (`enabled: false`) entries — informational, not flagged
   unless they're also stale.
2. For each entry in `known_marketplaces[]`, flag `[stale-ref]`
   "marketplace clone is more than 7 days stale" if
   `now - lastUpdated > 7d` (the harness should sync more often).
3. Cross-reference: the set of marketplaces that any installed plugin
   came from must be a subset of `known_marketplaces[].name`. Any
   mismatch is `[stale-ref]` "installed plugin from unknown marketplace".
4. Apply checks:
   - **`[upgrade-available]`** — installed plugin's `version` is older
     than the marketplace manifest's latest.
   - **`[mismatch]`** (channel) — plugin's `channel` field, when present
     (v3+ schema), differs from marketplace's recommended channel.
   - **`[unused]`** — installed plugin's namespace (e.g. `playwright@`)
     never appears in this project's tree (search across `.claude/`,
     `CLAUDE.md`, top-level docs).
   - **`[new-feature]`** — plugin in `upstream_current.marketplace_plugins`
     but not in `upstream_at_last_run.marketplace_plugins` and not in
     `acknowledged_upstream_features` as `plugin:<id>`.
5. Emit:

```
Phase 5 — Plugins
  Installed:           {N}
  Referenced in proj:  {M}
  Marketplaces:        {marketplace_id (last sync: ...)}

  Issues:
  - [upgrade-available]  code-simplifier@claude-plugins-official 1.0.0 → 1.2.0
  - [unused]             playwright@claude-plugins-official (installed 2026-02-23, no project ref)
  - [new-feature]        marketplace added: notebook-tools@claude-plugins-official
  - [stale-ref]          marketplace claude-hud last synced 14 days ago

  (or "No issues found." if clean)
```

**Apply branches.** Print `claude plugin update <id>`; print
`claude plugin remove <id>` (only on `[unused]`, only after explicit
confirm); offer project-level disable list edit; add new marketplace
entries to `acknowledged_upstream_features` as `plugin:<id>`.

---

## Phase 6 — MCP Servers

**Subject.** Audit MCP servers for redundancy, heavy startup, and policy
mismatches. (Pure intra-project; no upstream dimension.)

**Sources.**
- `<project>/.mcp.json`
- `~/.claude/settings.json:mcpServers`
- `<project>/.claude/settings.json:enabledMcpjsonServers / disabledMcpjsonServers`

**Steps.**

1. Read `<project>/.mcp.json` and the `mcpServers` block of any settings
   file that defines one.
2. Apply checks:
   - **`[redundant]`** — `filesystem` server (Read/Write/Glob/Grep are
     built-in) or `github` server (use `gh` CLI; the MCP fork has fewer
     tools and slower startup).
   - **`[mismatch]`** (heavy startup) — `command` uses `podman run`,
     `docker run`, or `npx`.
   - **`[oversized]`** — `toolTimeout` > 120 seconds.
   - **`[mismatch]`** (over-enabled) — `enableAllProjectMcpServers: true`
     in any settings file. Prefer selective enablement.
3. Count total registered tools. If > 20, mention as informational
   "namespace pressure" note (not a flag).
4. Emit:

```
Phase 6 — MCP Servers
  Configured:    {N}
  Tool namespace: ~{N} tools (target: <20)

  Issues:
  - [redundant]    filesystem — Read/Write/Glob/Grep are built-in
  - [redundant]    github — `gh` CLI covers this
  - [mismatch]     ssh-dispatch uses `podman run` (heavy startup)
  - [oversized]    alpaca: toolTimeout=300s

  (or "No issues found." if clean)
```

**Apply branches.** Edit `.mcp.json` to remove the server; reduce timeout;
flip `enableAllProjectMcpServers` to selective enablement.

---

## Phase 7 — Hooks & Environment Activation

**Subject.** Audit `hooks` config for env-activation completeness, hook-event
schema drift, and policy mismatches.

**Sources.**
- All four settings files (`hooks` block)
- Snapshot's `live.hook_events_available` (previous run)
- Phase 1's `live.hook_events_available` (this run) — the authority
- Project-type detection: `pyproject.toml`, `environment.yml`,
  `pom.xml`, `build.gradle`, `build.gradle.kts`

**Precondition.** `CLAUDE_ENV_FILE` must be set in the Claude Code process
environment. Recommended location: `~/.claude/settings.local.json`
(machine-local, Ansible-safe):

```json
{ "env": { "CLAUDE_ENV_FILE": "/tmp/claude-env-<user>.sh" } }
```

If absent, env-activation hooks silently no-op because `$CLAUDE_ENV_FILE`
expands to empty.

**Steps.**

1. Check `~/.claude/settings.local.json` and `~/.claude/settings.json`
   for `env.CLAUDE_ENV_FILE`. If neither defines it, flag
   **`[mismatch]`** ("CLAUDE_ENV_FILE unset; hooks will silently no-op").
2. Detect project type:
   - `pyproject.toml` containing `[tool.poetry]` → **Poetry**
   - `environment.yml` or `meta.yaml` → **Conda**
   - `pom.xml`, `build.gradle`, `build.gradle.kts` → **Java** (Maven/Gradle)
   - None → report "None detected" and skip steps 3-5.
3. Read `<project>/.claude/settings.json` and
   `<project>/.claude/settings.local.json`. In
   `hooks.SessionStart[*].hooks[*].command`, search for any string
   containing `$CLAUDE_ENV_FILE` (literal or `"$CLAUDE_ENV_FILE"`).
4. Apply checks:
   - **`[missing]`** — typed project but no SessionStart hook writing to
     `$CLAUDE_ENV_FILE`. Apply branch installs the project-type template
     (see Apply branches below).
   - **`[mismatch]`** — env-activation hook lacks `if [ -n "$VENV" ]`
     (or equivalent guard for the project type).
   - **`[mismatch]`** — multiple hooks write to `$CLAUDE_ENV_FILE` and
     mix `>` (truncate) with `>>` (append). Only the first should
     truncate; subsequent ones should append. Mixed redirects in
     arbitrary order produce nondeterministic env content.
5. Apply upstream checks:
   - **`[new-feature]`** — this run's `live.hook_events_available` contains a
     name not in the snapshot's and not in `acknowledged_upstream_features`
     as `hook:<name>`.
   - **`[stale-ref]`** — settings register a hook under an event name that is
     not in `live.hook_events_available`. This is silent in the worst way: the
     hook is well-formed, the settings file parses, and it simply never fires.
   - **`[phantom-tool]` / `[gated-tool]`** — a `matcher` in `PreToolUse`,
     `PostToolUse` or `PostToolUseFailure` names a tool that does not resolve
     (see **Name resolution**). Same silence: a matcher on a tool the harness
     never emits is indistinguishable from a hook that simply has not
     triggered yet.
6. Emit:

```
Phase 7 — Hooks & Environment Activation
  CLAUDE_ENV_FILE:   {set in <file> | UNSET}
  Project type:      {Poetry | Conda | Java | None detected}
  Env hook present:  {yes (guarded, > redirect) | MISSING | unguarded}

  Issues:
  - [mismatch]     CLAUDE_ENV_FILE unset; hooks will silently no-op
  - [missing]      Poetry project lacks venv-activation SessionStart hook
  - [mismatch]     hook command does not check if env exists before writing PATH
  - [new-feature]  upstream added hook event: SubagentStop
  - [stale-ref]    settings register a hook on "PreCommit" — not an accepted event name

  (or "No issues found." if clean)
```

**Apply branches.**

For **`[missing]`**, install the project-type SessionStart template.
Append a new entry to `hooks.SessionStart` in
`<project>/.claude/settings.json` (create the file with a standard
skeleton if absent). Do NOT add a `matcher` to the new entry — it must
fire on every session start, not just `compact`/`resume`. Preserve any
existing entries. Templates use `>` (truncate):

- **Poetry:**
  ```
  VENV="$(cd "$CLAUDE_PROJECT_DIR" && poetry env info --path 2>/dev/null)"; \
  if [ -n "$VENV" ] && [ -d "$VENV/bin" ]; then \
    printf 'PATH=%s:%s\nVIRTUAL_ENV=%s\n' "$VENV/bin" "$PATH" "$VENV" > "$CLAUDE_ENV_FILE"; \
  fi
  ```
- **Conda** (read `name:` from `environment.yml`):
  ```
  CP="$(conda env list | awk -v n=<name> '$1==n {print $NF}')"; \
  if [ -n "$CP" ] && [ -d "$CP/bin" ]; then \
    printf 'PATH=%s/bin:%s\nCONDA_PREFIX=%s\n' "$CP" "$PATH" "$CP" > "$CLAUDE_ENV_FILE"; \
  fi
  ```
- **Java** (resolve via `update-alternatives --query javac` on Linux or
  `/usr/libexec/java_home -v <ver>` on macOS):
  ```
  JH="$(...resolver...)"; \
  if [ -n "$JH" ] && [ -d "$JH/bin" ]; then \
    printf 'JAVA_HOME=%s\nPATH=%s/bin:%s\n' "$JH" "$JH" "$PATH" > "$CLAUDE_ENV_FILE"; \
  fi
  ```

After installing, remind the user to restart Claude Code so the hook
fires; the LSP MCP server picks up the new `$PATH` only at session start.

For **`[mismatch]`** (CLAUDE_ENV_FILE unset), append
`{ "env": { "CLAUDE_ENV_FILE": "/tmp/claude-env-${USER}.sh" } }` to
`~/.claude/settings.local.json`.

For **`[mismatch]`** (unguarded hook or mixed redirect), edit the hook
command in place.

For **`[new-feature]`**, add `hook:<name>` to
`acknowledged_upstream_features`.

---

## Phase 8 — Rules & Context Budget

**Subject.** Audit `.claude/rules/` for size, scope, duplication, and total
auto-loaded context budget.

**Sources.**
- `<project>/.claude/rules/**/*.md`
- `<project>/CLAUDE.md`
- `~/.claude/CLAUDE.md`
- Memory files (`MEMORY.md` and any files it links to)
- Phase 1's `live` block, via **Name resolution**

**Steps.**

1. List rule files: `**/*.md` under `.claude/rules/`. If none,
   report "No rules directory" and skip rule-specific checks (still run
   the budget computation).
2. For each rule file, measure size in bytes.
3. Apply checks:
   - **`[oversized]`** — file > 3 KB. Rules should be concise directives,
     not documentation. Tables, full code blocks, multi-paragraph prose
     belong in `docs/`, not rules.
   - **`[mismatch]`** (broad scope) — rule scoped `**/*.py` (or similar
     wide glob) but content is specific to a subpath (e.g. only relevant
     to `framework/graph.py`).
   - **`[duplicate]`** — rule's first heading or description matches a
     CLAUDE.md section heading. Auto-loaded rules and CLAUDE.md
     duplication wastes context.
   - **`[phantom-tool]` / `[gated-tool]`** — the rule names a tool that does
     not resolve (see **Name resolution**). Use the same extraction Phase 9
     step 2 performs, over each rule file. Rules load automatically on every
     turn exactly like CLAUDE.md, so a phantom name here has identical blast
     radius and is worth the same flag.
4. Compute the context budget. Count only what the harness loads on **every
   turn**, because that is the cost the thresholds are calibrated against:
   - project CLAUDE.md + global CLAUDE.md, plus anything they `@`-import
     (an imported file is auto-loaded exactly like its importer, so it counts)
   - every file under `.claude/rules/`
   - `MEMORY.md` — the index only

   Individual memory files are **not** in this total. They load when a memory is
   recalled, not every turn, so counting the pool inflates the figure by however
   much history the user has accumulated and reports `[budget-critical]` on a
   setup that is nowhere near it. A flag that fires on healthy config is worse
   than no flag: it trains the reader to skip the line.

   - **`[budget-warning]`** if the per-turn total > 50 KB.
   - **`[budget-critical]`** if the per-turn total > 100 KB.

   Report the recall-time memory pool on its own line as context, unflagged. It
   is a real cost, just not a per-turn one, and its size is the user's call.
5. Emit:

```
Phase 8 — Rules & Context Budget
  Rules:               {N} files, {total_kb} KB total

  Budget breakdown:
    CLAUDE.md (project + global + imports):  {kb} KB
    Rules (.claude/rules/):                  {kb} KB
    Memory index (MEMORY.md):                {kb} KB
    Total auto-loaded per turn:              {kb} KB  [{OK | budget-warning | budget-critical}]

    Memory pool (loads on recall, not counted above): {kb} KB across {N} files

  Issues:
  - [oversized]   rules/code-style/patterns.md — 22 KB (target: <3 KB)
  - [mismatch]    rules/architecture/graph-pipeline.md scoped **/*.py but only relevant to framework/graph.py
  - [duplicate]   rules/code-style/testing.md duplicates CLAUDE.md "Testing Standards" section
  - [gated-tool]  rules/workflow/planning.md instructs "track steps via `TaskCreate`" — exists in the CLI, withheld from this session

  Recommended trimming:
  For each [oversized] file: move examples/tables to docs/{path}, keep only
  the directive (what to do) in the rule file.

  (or "No issues found." if clean)
```

**Apply branches.** Split / shrink / scope-narrow rule files; remove
duplicated sections from CLAUDE.md.

---

## Phase 9 — CLAUDE.md, Coordinators & Notification Sinks

**Subject.** Four related cross-cutting checks merged into one phase:
(1) CLAUDE.md cross-references and contradictions; (2) coordinator-agent
adoption gaps; (3) notification-sink coverage for long-running work;
(4) CLAUDE.md quality grade via `/claude-md-management:claude-md-improver`.

**Sources.**
- `<project>/CLAUDE.md`
- `~/.claude/CLAUDE.md`
- Phase 1's `live` block, via **Name resolution**
- `<project>/.claude/agents/*-coordinator.md` and `~/.claude/agents/*-coordinator.md`
- All settings hooks (`Stop`, `SubagentStop`, `Notification`)
- `<project>/.mcp.json` for sink-style servers (`PushNotification`,
  `RemoteTrigger`, slack/discord/teams MCPs)
- Project skills/scripts grep for `run_in_background` patterns
- `/claude-md-management:claude-md-improver` (report-only, for the
  quality grade)

**Steps.**

1. Read project + global CLAUDE.md.
2. Extract every backtick-quoted name that looks like an agent, a skill, or a
   tool — three patterns:
   - lowercase-hyphenated (`` `python-expert` ``) → agent
   - slash-prefixed (`` `/run-tests` ``) → skill
   - `PascalCase` or `mcp__*` (`` `TaskCreate` ``, `` `mcp__github__get_issue` ``)
     → tool

   **Split multi-name spans.** One pair of backticks often holds a list —
   `` `TaskCreate,TaskUpdate,TaskList,TaskGet` `` is four names, not one
   unmatchable string. Split on commas, slashes and the word "and", then resolve
   each part. A pattern anchored to a whole backtick span silently skips exactly
   the densest references, which are the ones most worth catching.

   Exclude obvious non-names (paths with an interior `/`, code keywords, and
   PascalCase words that are plainly prose rather than identifiers — `README`,
   `JSON`, `HTTP`). When a name is ambiguous, resolving it is cheap and a false
   `[phantom-tool]` is expensive, so resolve rather than guess.

3. **Separate use from mention.** Only flag a name the document tells the reader
   to *invoke*. A name can also be discussed — listed in a table of rule forms,
   quoted while explaining what some other check does, named in a sentence about
   naming. Those are mentions, and flagging them produces findings whose only
   possible repair is to stop writing about the subject.

   The test is whether removing the tool would make the surrounding sentence
   false or merely unnecessary. "Call `Grep` to search" breaks; "rules naming
   `MultiEdit` are never consulted" stays true and is precisely the sentence you
   want to keep. When genuinely unsure, prefer the mention reading and stay
   silent — a missed phantom costs one stale line, while a false one sends the
   user to delete working documentation.
4. Apply CLAUDE.md checks:
   - **`[stale-ref]`** — agent name (no `/` prefix) backtick-quoted but
     no matching file in any agent location.
   - **`[stale-ref]`** — skill name (`/`-prefixed) backtick-quoted but
     no matching `*/SKILL.md`.
   - **`[stale-ref]`** — hook defined in any settings file but not
     mentioned in CLAUDE.md.
   - **`[phantom-tool]`** — a tool name resolves nowhere (see **Name
     resolution**). The instruction around it can never execute as written, so
     the fix is to delete the reference and rewrite the instruction in terms of
     what the session does have.
   - **`[gated-tool]`** — a tool name resolves to something the CLI ships but
     withholds from this session. The instruction is not fictional, only
     unreachable here; scope it ("when available") or record the gate, and do
     **not** delete it — this is the one case where the obvious repair is the
     wrong one.
   - **`[mismatch]`** — project vs global CLAUDE.md disagree on a tool
     (mypy vs basedpyright; pytest vs unittest; flake8 vs ruff).
   - **`[mismatch]`** — CLAUDE.md says "read docs/" for code style or
     architecture but `.claude/rules/` already has auto-loaded rules
     (rules are loaded automatically — explicit reading instructions
     waste context).
5. Apply coordinator checks:
   - **`[unused]`** — globally-installed coordinator (file ends
     `-coordinator.md` OR description mentions "routes to" / "delegates
     to") not referenced in this project's CLAUDE.md.
6. Apply notification-sink checks:
   - Detect long-running work: any `.claude/skills/*/SKILL.md` mentions
     `run_in_background`, `Bash run_in_background=true`, or backtest /
     long-job patterns.
   - Detect existing sinks: settings hooks (`Stop`, `SubagentStop`,
     `Notification`) writing to a sink, or MCP servers matching
     `PushNotification`, `RemoteTrigger`, slack/discord/teams.
   - **`[missing]`** — long-running work detected AND no sink configured.
7. Apply CLAUDE.md quality scoring (sub-check 4). Invoke
   `/claude-md-management:claude-md-improver` in **report-only mode** —
   tell it explicitly to emit only its Phase 3 quality report (per-file
   grade table + top-3 issues) and to NOT proceed to its Phase 4 edit
   step. Scope the scan with `--max-depth 3` (or equivalent) limited to
   the project root and `~/.claude/` so monorepos don't trigger a
   filesystem-wide walk.
   For each CLAUDE.md the improver returns:
   - **`[quality:A]` … `[quality:F]`** — record the grade and top-3
     issues per file. The actual `[quality:X]` flag (with the X letter
     filled in) carries forward to Phase 10's summary, where grade < B
     gets severity `warning` and grade < D gets severity `critical`.
   The improver's edit phase is deferred to Phase 11: if any file's grade
   is < B AND the user approves the corresponding Phase 10 item, Phase 11
   hands the edit pass back to the improver (its built-in confirmation
   gate covers the actual diff).
8. Emit:

```
Phase 9 — CLAUDE.md, Coordinators & Notification Sinks
  CLAUDE.md size:      {kb} KB
  Coordinators avail:  {names}
  Notification sinks:  {names | NONE}

  Quality grades (claude-md-improver):
    ~/.claude/CLAUDE.md       grade: B+   issues: missing commands section, 2 stale refs
    <project>/CLAUDE.md       grade: C    issues: low actionability, no test commands

  Issues:
  - [stale-ref]   CLAUDE.md backticks 'numpy-expert' — agent file absent
  - [phantom-tool] ~/.claude/CLAUDE.md names `search_skills` — resolves nowhere; delete the reference
  - [gated-tool]  ~/.claude/CLAUDE.md startup step loads `TaskCreate` — in the CLI, withheld from this session; scope it
  - [mismatch]    CLAUDE.md says "use mypy" but pyproject pins basedpyright
  - [mismatch]    CLAUDE.md says "read docs/code-style/" — rules auto-load
  - [unused]      coordinator: code-coordinator (not in CLAUDE.md)
  - [missing]     long-running backtests + no PushNotification/RemoteTrigger sink
  - [quality:C]   <project>/CLAUDE.md — improver-flagged improvements available

  (or "No issues found." if clean)
```

**Apply branches.** Edit CLAUDE.md to fix `[stale-ref]` / `[mismatch]`;
insert coordinator reference; offer notification-sink template (Stop hook
→ user-chosen sink: PushNotification config, ssh-dispatch RemoteTrigger,
Slack MCP). For `[quality:X]` flags with grade < B, hand off to
`/claude-md-management:claude-md-improver`'s edit phase in Phase 11
(its own confirmation gate covers the actual diff).

---

## Phase 10 — Summary & Recommendations

**Subject.** Consolidate every flag from Phases 2–9 into a single ordered
list with severity and apply prompt. Run
`/claude-code-setup:claude-automation-recommender` in parallel and fold
its codebase-pattern adoption recommendations in as `[adopt]` flags —
this is the **sole** source of adoption-gap reasoning in tune-up.

**Sources.**
- Every flag accumulated from Phases 2–9.
- `/claude-code-setup:claude-automation-recommender` (run during this
  phase, in parallel with the aggregation pass).

**Severity rubric.**

- **critical** — blocks Claude Code from working correctly. Examples:
  env-activation hook missing on a Poetry project (`[missing]` in Phase 7);
  `[stale-ref]` to a hook event upstream removed; CLAUDE.md backticks an
  agent name with no file (Phase 9); `[quality:F]` on any CLAUDE.md.
- **warning** — degrades quality but doesn't break. Examples: `[oversized]`
  rule, `[redundant]` permission, `[mismatch]` (consolidation), `[outdated]`
  skill, `[quality:C]` / `[quality:D]` on CLAUDE.md.
- **info** — nice-to-have. Examples: `[adopt]` (codebase-pattern adoption
  gap from automation-recommender), `[new-feature]`, `[unused]`
  (project-local cleanup opportunities), `[quality:B]` on CLAUDE.md.

**Steps.**

1. Aggregate every flag from Phases 2–9. Tag each with one of the three
   severities per the rubric above.
2. Invoke `/claude-code-setup:claude-automation-recommender` in
   report-only mode (the skill is read-only by design — it never writes).
   Feed its output into the summary as `[adopt]` flags, one per
   recommendation, severity `info`. Categories from the recommender
   (Hooks / Subagents / Skills / Plugins / MCP Servers) become the
   `[adopt]` sub-label:
   ```
   [adopt:mcp]      context7 — project has Python + doc-heavy deps
   [adopt:hook]     PostToolUse formatter — project uses ruff but no auto-fix wired
   [adopt:subagent] security-reviewer — project has auth + secrets handling
   ```
3. Order: critical first, warning next, info last. Within each tier,
   group by phase (with `[adopt]` flags grouped at the end of `info`).
4. Number each issue (1, 2, 3...) so the user can selectively approve.
5. Emit:

```
=== /tune-up Report ===

Permissions:  {N} entries across 4 files, {R} flagged
Agents:       {N} agents, {I} flagged
Skills:       {N} skills, {I} flagged
Plugins:      {N} installed, {I} flagged
MCP servers:  {N}, {I} flagged
Hooks/env:    {I} flagged
Rules:        {N} files, {kb} KB total, {I} flagged
CLAUDE.md:    {I} flagged

Critical: {C}    Warning: {W}    Info: {I}

Recommended actions:
1. [critical][hooks]       Install Poetry env-activation SessionStart hook
2. [critical][claude-md]   Remove stale ref to "numpy-expert" in CLAUDE.md line 42
3. [warning][permissions]  Remove 4 redundant entries from settings.local.json
4. [warning][skills]       /pre-commit-check carries hardcoded permissions
5. [warning][claude-md]    <project>/CLAUDE.md grade C — improver edit pass available
6. [info][plugins]         playwright unused in this project — disable here?
7. [info][agents]          new built-in agent: data-engineer
8. [info][adopt:hook]      add ruff PostToolUse auto-fix hook (recommender)
9. [info][adopt:mcp]       install context7 MCP server (recommender)
...

Apply all? (all / 1,3,5 / none)
```

**Apply branches.** None. Phase 11 owns the writes.

---

## Phase 11 — Apply (only if user approves)

**Subject.** Apply user-approved fixes; persist the updated snapshot.

Wait for the user response. Recognise: `all`, comma-separated numbers
(e.g. `1,3,5`), `none`, or free-form ("just the env hook"). Map back to
flag IDs from Phase 10.

For each approved item:

1. Show the exact diff (before / after) BEFORE writing.
2. Apply with `Edit` (existing files) or `Write` (new files).
3. After all writes, `Read` each modified file to confirm.

### Constraints

- **`~/.claude/settings.json` is editable** but Ansible-managed: any write
  triggers the **Ansible-mirror policy** below. The skill no longer treats
  this file as read-only.
- **Settings file edits go through `/update-config`, not raw `Edit`.** For
  any change to a `settings.json` or `settings.local.json` file
  (permissions, hooks, env vars, MCP server configuration), invoke the
  `/update-config` skill with a description of the change. It understands
  the merge semantics (global vs local priority order, the four-file
  resolution chain) and the harness's settings schema. Raw `Edit` is
  reserved for non-settings files (CLAUDE.md, rules, SKILL.md, .mcp.json
  when the change isn't expressible as an `mcpServers` settings update).
- Never auto-run `claude plugin install/update/remove` — print the command
  for the user to execute. (Why: these mutate global state outside the
  project worktree, may need network/auth, and outlive this session.)
- Never auto-upgrade the CLI — print `claude upgrade` only. (Same reason.)

### Ansible-mirror policy

Applies to any edit that touches `~/.claude/settings.json`:

1. Before applying, show the diff AND a banner:
   ```
   WARNING: ~/.claude/settings.json is Ansible-managed. The next deployment
   will overwrite it. Mirror this change to roles/claude/files/settings.json
   in the Ansible repo.
   ```
2. Search for an Ansible repo on disk:
   `Bash("find ~/Projects ~/code -maxdepth 4 -path '*/ansible*/roles/claude/files/settings.json' 2>/dev/null | head -3")`.
   If exactly one match, offer to apply the same edit there too.
   If multiple matches, list them and ask which (if any).
   If none, just emit the banner.
3. Record the applied edit in
   `.claude/.tune-up-state.json:pending_ansible_mirror[]`:
   ```json
   {
     "applied_at": "<iso>",
     "target": "~/.claude/settings.json",
     "diff_sha256": "<sha256 of the unified diff>"
   }
   ```
4. On the **next** `/tune-up` run, Phase 1's banner shows
   "Pending Ansible mirrors: N" and lists each. The list is cleared only
   when the user explicitly says so during a future Phase 11 run (no way
   to verify the Ansible repo commit happened, so user must confirm).

### Apply branch catalogue

| Flag | Apply action |
|---|---|
| `[duplicate]` | Settings file → `/update-config`; CLAUDE.md → `Edit` |
| `[redundant]` | `/update-config` to remove the entry from the relevant settings file |
| `[unused]` | Offer project-local disable list edit via `/update-config`; never auto-uninstall |
| `[stale-ref]` | `Edit` referrer (CLAUDE.md, SKILL.md) to remove or fix the reference |
| `[outdated]` | Print update command (`claude plugin update <id>`, etc.) |
| `[upgrade-available]` | Print `claude upgrade` or `claude plugin update <id>` |
| `[adopt]` | Print install command + offer to add CLAUDE.md mention. The `[adopt:hook]` / `[adopt:mcp]` apply path uses `/update-config` for the settings change; `[adopt:subagent]` / `[adopt:skill]` use `Write` for the new file. |
| `[new-feature]` | Add to `acknowledged_upstream_features` |
| `[mismatch]` | Settings file → `/update-config` (with Ansible mirror policy if `~/.claude/settings.json`); other → `Edit` |
| `[missing]` | Settings hook → `/update-config`; CLAUDE.md / file → `Write`/`Edit` |
| `[oversized]` | Offer split/shrink edit (rules → `Edit`/`Write`) |
| `[quality:X]` | Hand off to `/claude-md-management:claude-md-improver`'s edit phase if grade < B and user approves |
| `[budget-warning]` / `[budget-critical]` | Inform; require user-led trim |

### Snapshot wrap-up

After all applies (or "no fixes needed"):

1. Build the final snapshot:
   - `last_run_iso` = current UTC ISO timestamp
   - `local` = recomputed from current state (same as Phase 1 step 2)
   - `upstream_at_last_run` = Phase 1's `upstream_current` (so next run
     diffs against today's upstream, not the now-stale baseline)
   - `acknowledged_upstream_features` = old list +
     every `[new-feature]` from Phase 10 (whether the user explicitly
     approved or not — the user has been shown them, so re-announcing is
     noise).
   - `pending_ansible_mirror` = old list + any new mirror entries from
     this run, minus anything the user asked to clear.
2. Run `Bash` on `${CLAUDE_SKILL_DIR}/scripts/state_io.sh write -` from
   `$CLAUDE_PROJECT_DIR`, piping the JSON via stdin. The trailing `-` is
   load-bearing: the helper requires an explicit source argument and uses
   `-` as the stdin sentinel. The helper writes atomically (tempfile +
   rename).
3. **First-apply gitignore offer.** If `<project>/.gitignore` does not
   contain `.claude/.tune-up-state.json` AND this is the first time the
   snapshot is being written (snapshot file did not exist before this
   run), offer to append `/.claude/.tune-up-state.json` to `.gitignore`.
   Show the diff, never silently apply.

### Post-apply sibling-skill pass

After all writes are done and the snapshot is persisted, offer the
contextual sibling skills below. These are *content* hooks (bootstrap a
file, capture session learnings, surface related skills) — diff-level
quality review (security, code review, simplification) lives in
Phase 12.

Each is opt-in (one prompt per applicable category):

- **If Phase 9 found no `CLAUDE.md` in the project root**: offer `/init`
  to bootstrap one. This fires only when the file is genuinely absent;
  if a CLAUDE.md exists with `[quality:X]` issues, the
  `claude-md-improver` edit hand-off (already in the apply catalogue)
  is the right path instead.
- **If any `[adopt]` Phase 10 item was applied** (new MCP / hook /
  subagent / skill / plugin from automation-recommender): offer
  `/skill-discovery` to surface related skills the user might also want
  — install-count and last-update fields help rank.
- **If any CLAUDE.md was edited or created** (via `/init`, the
  improver edit phase, or any `[stale-ref]` / `[mismatch]` fix): offer
  `/claude-md-management:revise-claude-md` to capture learnings from
  this tune-up session. The slash command is shipped by the
  `claude-md-management` plugin and encodes a discipline that bare
  Read/Edit doesn't — a mandatory reflection checklist (commands used,
  code-style, testing, env quirks, gotchas), routing between
  `CLAUDE.md` (team-shared) and `.claude.local.md` (personal,
  gitignored), a strict one-line-per-concept format, and an explicit
  "avoid verbose / obvious / one-off" filter. The improver lands
  structural quality (Phase 9 + 11 hand-off); this skill appends what
  was found and decided. Complementary, not duplicative.
- **If `~/.claude/settings.json` was edited and the user has a
  pre-commit-check skill installed**: offer `/pre-commit-check` to
  validate the JSON before they commit the Ansible mirror.

Frame each as a question, not an automatic invocation: "X file changed.
Run `/init` to bootstrap CLAUDE.md? (y/n)". Skip the offer entirely
when no applicable category fired this run.

### Restart reminder

If a SessionStart env-activation hook was newly installed, remind the user
to restart Claude Code. The LSP MCP server picks up the new `$PATH` only
at the next session start.

---

## Phase 12 — Post-Apply Quality Gate

**Subject.** After Phase 11 has applied user-approved fixes, validate the
resulting diff with read-only quality skills. Phase 11 *applies*; Phase 12
*validates the apply*. Skipped entirely if Phase 11 made no changes.

**Sources.**
- The set of files Phase 11 touched (capture during apply via the diff
  log, or `Bash("git diff --name-only HEAD")` if the project is a git
  worktree and changes are unstaged).
- `/security-review` (read-only)
- `/review` (read-only)
- `/simplify` (read-only — only its analysis pass; this phase does not
  invoke its fix pass)
- `/skill-creator:skill-creator` (used in eval/trigger-validation mode
  for SKILL.md changes)

**Steps.**

1. Build the change set: collect every file path Phase 11 wrote to. If
   the project is a git worktree with unstaged changes, prefer
   `git diff --name-only HEAD` over the apply log (handles cases where
   Phase 11 also triggered a hook that wrote additional files).
2. Classify each path:
   - `<any>/settings.json` or `<any>/settings.local.json` → settings
   - `*.sh`, helper scripts, `${CLAUDE_SKILL_DIR}/scripts/*` → script
   - `**/SKILL.md` → skill
   - everything else → general
3. Offer the relevant quality skills, one yes/no per applicable trigger:

   | Trigger (one or more files match) | Skill offered | Why |
   |---|---|---|
   | settings | `/security-review` | Catches permission overreach in `permissions.allow`, sensitive env-var exposure, hook commands that escape sandboxing |
   | any change | `/review` | Diff-level review of every Phase 11 change in one pass; catches issues the per-flag apply branches don't see |
   | script | `/simplify` | Reuse / quality / efficiency punch list for shell scripts and skill helpers |
   | skill | `/skill-creator:skill-creator` | Validates the SKILL.md against canonical conventions; runs trigger-eval on the description so the skill keeps firing on the right prompts |

4. Phase 12 produces no flags of its own — the offered skills emit their
   own reports if the user accepts. If the user declines all, Phase 12
   prints a one-line summary of skipped checks and exits.

**Output.**

```
Phase 12 — Post-Apply Quality Gate
  Files changed:    {N}  ({list, capped at 10})

  Recommended quality checks:
  1. settings touched           → /security-review            (y/n)
  2. files changed              → /review                     (y/n)
  3. shell scripts touched      → /simplify                   (y/n)
  4. SKILL.md touched           → /skill-creator:skill-creator (y/n)

  (or "Phase 11 made no changes — quality gate skipped." if N=0)
```

**Apply branches.** None — Phase 12 is itself the apply layer for
quality skills. Each accepted offer hands off to the corresponding
skill, which runs in its own context and emits its own output.

**Why this is a phase, not Phase 11 hooks.** Phase 11 mixes *applies*
(write a settings change, edit CLAUDE.md) with *content hooks*
(`/init`, `/skill-discovery`, native CLAUDE.md learnings capture).
Phase 12 owns *diff-level review* of everything Phase 11 wrote. Keeping
them separate means the quality gate always sees the final state of all
applies, not interspersed mid-Phase-11 partial state, and the audit
flow reads as: setup → check → summarise → apply → review.
