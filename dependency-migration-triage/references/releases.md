# Releases: what a dependency change means for the repo's own consumers

SKILL.md Phase 4 asks for a **release level** only when the repo has a release process. This
file says when that is, how to pick the level, and how the level reaches the release. Facts
below were verified against the tools' docs/source and real PRs on 2026-11-01 unless marked.

## 1. When this applies

- The repo has a release process **and it is live**: `release-please-config.json` (or a
  `RELEASING.md`, a release workflow) AND releases actually happen here
  (`gh release list -L 3`, a recent release workflow run: `gh run list -w release-please`).
  Config alone is not a process. Then the report carries a level (section 2).
- Otherwise the report says **"no release process here"** in one line and moves on. Do not
  invent one.
- Which repos release: those with **consumers** — published artifacts, images, charts,
  libraries, skills. GitOps leaf repos (Flux cluster content) do not: the merge is the rollout.
- **A fork whose releases happen upstream has no release process here, even with the config
  file present** (`gh repo view --json isFork`). The fork rule wins over SKILL.md Phase 8's
  "carry the level in the merge subject": keep upstream's convention (`build(deps)` etc.) and
  never add a release process to a fork.

## 2. Decision table: the consumer's level

**Override rule first.** Consumer must act -> **major**. New observable capability -> **minor**.
Otherwise **patch**. Dev/test/CI-only change -> **no release** (`chore`). Where a table row is
stricter than the rule (a library's raised floor is "major if unsure"), the row wins; where the
rule is stricter (the operator must act on a base-image bump), the rule wins.

**"Dev-only" is decided by the lock, not by the declaration.** In a single-lock project (a uv
workspace, one `package-lock.json`) a pin in a dev group also moves a package that a runtime
dependency pulls in. If `uv tree --frozen --invert --package <pkg> --no-dev` (npm: `npm explain
<pkg>` showing a non-dev path) still shows a runtime path, the bump changes what production
installs: triage it as runtime (at least `fix(deps)`), whatever the bot's `chore(deps-dev)` title
says. Seen on valkyrie-ai#58: `dbt-common` pinned in valkyrie-orchestrator's dev group, yet
reached at runtime via dbt-adapters → dbt-core → dbt-postgres.

| Change | Library | Application / service / deploy repo |
|---|---|---|
| In-range or lockfile-only bump of a runtime dep | patch | patch |
| Widen a dependency range | minor | n/a |
| Raise a dependency floor / drop a dependency | major if unsure | patch (minor if new capability) |
| Raise runtime floor (`requires-python`, `engines`) | **major** unless a documented drop policy exists (contested, see below) | minor; major if the operator must act |
| Dependency type leaks into the public API and changed | major | n/a |
| Persisted or output numbers changed (SKILL.md Phase 4 "persisted derived numbers") | per docs; default minor, **major if consumers persist them** | major; minor if an automatic, reversible migration |
| Add an extra / optional feature | minor | minor |
| Remove an extra | major | n/a |
| Transitive security patch | patch | patch |
| Base image bump | n/a | patch; minor for OS/libc; major if user/path/port/entrypoint change or the operator must act |
| Published Helm chart | follows the upstream chart's level; **major on a `values.yaml` break** | same |
| GitOps-only repo | n/a | none (no release process; the merge is the rollout) |

**Contested:** whether raising `requires-python` is a major for a library. Semver says it
breaks consumers on the old interpreter; much of the Python ecosystem ships it in a minor under
a support-window policy. Unverified as a convention. Cite the repo's own stated policy if there
is one; otherwise say "major, contested" and let the user decide.

## 3. How the level reaches the release

release-please releases on **`feat`, `fix`, `deps`**, and any type with **`!`**. `chore` and
`build` release nothing, and the default changelog hides everything except feat/fix/perf/revert.

What each bot emits by default (Renovate's `fix(deps)` only for runtime bumps, Dependabot
mirroring history, the `commit-message` settings) is in bots.md, "Commit prefix". The upshot:
a bot PR alone rarely releases what Phase 4 decided, so the skill sets the type **at merge
time**.

**Squash convention (all non-fork repos on both accounts, applied and verified 2026-11-01):**
squash-only (`allow_merge_commit=false`, `allow_rebase_merge=false`) with
`squash_merge_commit_title=PR_TITLE` and `squash_merge_commit_message=BLANK`. The PR title is the
one place the subject is visible, editable and reviewed before the merge, also for web-UI merges.
The message is `BLANK` because release-please's `src/commit.ts` extracts a BREAKING CHANGE note
"regardless of whether [it falls] in summary, body, or footer" and `splitMessages()` cuts a body
at a blank line followed by `feat:`/`fix:`/… into extra commits — a PR body (bot release notes
or a human description) would cut phantom commits or a spurious major. So: **breaking → `!` in
the subject; an exact version → `--body "Release-As: x.y.z"`; bot PRs → `--body ""`** (harmless
under BLANK, protective anywhere the setting differs). Squash-only also makes a stray
`gh pr merge --merge` fail loudly (one rollout script used it; three merge commits landed before
it was fixed).

Before the rollout the settings differed (measured 2026-11-01): valkyrie-ai, claude-code-skills,
Blue-Sharp/homelab `COMMIT_OR_PR_TITLE`/`COMMIT_MESSAGES` (a single-commit PR squashes with its
**commit** title, so a PR-title edit did nothing); unternehmen-walkuere `PR_TITLE`/`BLANK`
(footers in the PR body dropped); valkyrie-ui `PR_TITLE`/`PR_BODY`. For a repo not yet on the
convention, read the setting (`gh api repos/<o>/<r> --jq '.squash_merge_commit_title,
.squash_merge_commit_message'`); explicit `--subject` and `--body` are correct under every
setting. Apply the convention (user-run, per repo; homelab-health layer 5 §5.9 checks it):
`gh api -X PATCH repos/<o>/<r> -f allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=BLANK`.

**When the user said to merge, run the command yourself; otherwise print it for them.** Re-check
the head SHA first.

```bash
gh pr merge <n> --squash --subject "fix(deps): bump <pkg> to <ver>" --body ""   # or feat
gh pr merge <n> --squash --subject "feat(deps)!: <what consumers must do>" --body ""
gh pr merge <n> --squash --subject "fix(deps): ..." --body "Release-As: 2.0.0"     # specific version
```

`Release-As: x.y.z` is read from the commit **body** (case-insensitive, per release-please's README).
Use it only when the user wants a specific version, or to release a commit whose type cuts nothing:
it also works on a `chore(deps-dev): …` title, which keeps the type honest. Verified in
Pirat83/valkyrie-ui 2026-11-02: three dev-tooling bumps merged with their titles unchanged plus
`--body "Release-As: 0.2.x"` cut v0.2.1-v0.2.3. release-please then lists the chore under
"Miscellaneous Chores" in the notes.

**Pre-1.0 (`0.y.z`) projects.** By default release-please turns a breaking commit (`!` /
`BREAKING CHANGE:`) into **1.0.0**. To keep a 0.x project in 0.x, set in
`release-please-config.json` (verified in release-please's config schema, 2026-11-01):
`"bump-minor-pre-major": true` — breaking changes bump the minor while < 1.0.0 — and, if
features should bump only the patch, `"bump-patch-for-minor-pre-major": true`. Check these
before mapping a level to a subject in a 0.x repo: with both set, `feat!` → 0.(y+1).0 and
`feat` → 0.y.(z+1).

**Retroactive versions for already-merged history.** Squash subjects of merged commits can't
be rewritten. The triage's level becomes a tag (or a `Release-As:` footer on the next commit)
instead of a merge subject; run the triage per releasable commit or batch as a late,
no-post run.

## 4. Recipe (worked example: claude-code-skills, the release setup for this repo)

Files in the repo:
- `.github/workflows/release.yaml`: on push to `main`, one job running
  `googleapis/release-please-action@45996ed1f6d02564a971a2fa1b5860e934307cf7 # v5.0.0`,
  `permissions: contents: write, pull-requests: write, issues: write` (issues for labels).
  `token` defaults to `GITHUB_TOKEN`. In Blue-Sharp repos use
  `runs-on: ${{ vars.CI_RUNNER || 'arc-runners' }}` (homelab-health flags hosted runners).
- `release-please-config.json`: `release-type: simple`, `include-component-in-tag: false`.
- `.release-please-manifest.json`: `{".": "<current version>"}`. release-please finds the
  existing `vX.Y.Z` tag from the manifest. `bootstrap-sha` is only a safety net and is ignored
  after the first release.
- An existing hand-written `CHANGELOG.md` is preserved; new entries go above the first version
  header.

Repo setting (**user-run**; send both fields, the default is `read`/`false`):

```bash
gh api -X PUT repos/<owner>/<repo>/actions/permissions/workflow \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true
```

Caveat: PRs created with `GITHUB_TOKEN` do not trigger CI, and `release.created` follow-on
workflows will not fire. Fine where no required checks exist; otherwise mint a GitHub App token
with `actions/create-github-app-token` (already used in Blue-Sharp/homelab `architecture.yaml`
and `renovate.yaml`).

For a manifest-with-packages example, `~/Projects/fritz_exporter/release-please-config.json` is
an upstream-derived config (Pirat83/fritz_exporter is a fork; its releases happen upstream and
it has never released, so it is a config example, not a running process).
The release PR is the human gate: it stays open until merged; the first release after the
recipe lands is proposed from the `feat`/`fix` commits since the tag.

**Confirm the release happened (Phase 9).** After merging a `fix`/`feat`/`deps` commit:
`gh pr list --label "autorelease: pending"` shows the release PR picking it up; after that PR
merges, `gh release view v<x.y.z>` (or `gh release list -L 1`) confirms the release exists and
its notes list the commit. A `chore`/`build` merge produces neither: say so.
## 5. Moving major tags (`v1` for Action repos)

No tool does it (a small `git tag -f v1` step would). It only matters if consumers pin tags.
The lab pins SHAs, so skip unless asked. Whether immutable releases forbid it: unverified.
