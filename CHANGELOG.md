# Changelog

## Unreleased

### Added
- `dependency-migration-triage`: goal "triage each bump safely and keep the dependency tree as small and healthy as possible":
  - tree delta of every bump (lockfile diff, multi-parent transitives with the binding constraint, vulnerabilities on the new lock) and an optional tree note; `references/tree-health.md`, `references/scripts/{uvlockdiff.py,npmlockdiff.sh}`
  - bot visibility (Renovate / Dependabot / invisible to both), holds and labels; `references/bots.md`
  - semver release level for the user's own project and the release-please recipe; `references/releases.md`
  - local environment follows the merge; `references/local-env.md`, case study 8
  - recorded triage level for every merged PR; merge intent and alerts trigger the skill
  - Poetry, Kustomize, CRD and Ansible coverage in `references/ecosystems.md`
  - `evals/evals.json`: 8 no-post cases pinned to real PRs, plus trigger cases
- `dependency-migration-triage` (ea24e75): batches, bot mechanics, case studies 5-7

## v1.0.0 (2026-04-09)

### Added
- `matplotlib-render-review` — Render-Review-Refine workflow for matplotlib charts with visual feedback loop
- `gws-sheets-verify` — Playwright screenshot verification for Google Sheets operations
- `tune-up` — 6-phase Claude Code workflow audit with concrete commands and structured output
