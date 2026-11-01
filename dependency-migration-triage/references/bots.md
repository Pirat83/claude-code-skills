# Bots: mechanics, visibility, holds and what a bot could not do

Read before Phase 0 when the PR (or its absence) comes from Renovate or Dependabot. What a bot
can and cannot put in a PR decides what its PRs — and the absence of one — actually mean.
Facts below are from docs.renovatebot.com, docs.github.com and Renovate's source (checked
2026-11-01) unless marked *observed* (real PRs/logs) or *unverified*. Repo-specific facts are
dated: they describe that day's `main`, not a standing truth. Several examples are real PRs from
this lab's eval runs (freelance-automation TypeScript 7, valkyrie-ai); they are worked evidence,
so a regression eval built on them is contaminated and should say so.

---

## Bot mechanics (Renovate and Dependabot)

These were each learned the hard way.

**Renovate**
- **Rebase triggers** are the "rebase/retry" checkbox in the PR body and the `rebase` label. A
  comment does nothing. Either trigger is processed on Renovate's *next run*; dispatch the
  Renovate workflow if you need it sooner.
- **Open PRs get retargeted** to newer versions without a new PR. Record the head SHA you triaged
  and compare at merge time.
- **The `stability-days` status can be stale.** One showed pending from a check run days earlier
  while the digest was 17 days old. Read the release or digest age directly.
- **Regex managers move one capture group.** A version and its checksum on adjacent lines are two
  fields; unless the config says otherwise, only the version moves (ecosystems.md, Actions).
- **No `conda` manager exists** (no directory in `lib/modules/manager`); a conda
  `environment.yml` gets no Renovate PRs.
- **Security PRs skip the line.** Vulnerability PRs ignore `prConcurrentLimit`,
  `branchConcurrentLimit` and the schedule (`prHourlyLimit` still applies). `vulnerabilityAlerts`
  reads GitHub's Dependabot alerts, so it needs the dependency graph and alerts enabled and only
  covers ecosystems GitHub parses. `osvVulnerabilityAlerts` queries OSV instead, **direct
  dependencies only**. A transitive fix is Dependabot's job.
- **Commit prefix** (this file owns the prefix mechanics; releases.md uses them).
  `config:recommended` includes `:semanticPrefixFixDepsChoreOthers`: only pep621/poetry
  *runtime* bumps become `fix(deps)`; dev groups, flux, helm, docker, actions are `chore(deps)`.
  Prefixes appear only if the last 20 base-branch commits are conventional, otherwise titles
  are plain. release-please releases on `feat`/`fix`/`deps`/`!`, so `chore(deps)` and
  `build(deps)` release nothing.
- **The Dependency Dashboard is not the authority for what Renovate extracts.** *Observed*
  (valkyrie-ai, 44.199.0): the `flux` manager extracted `ghcr.io/pirat83/valkyrie-ai` from
  HelmRelease values (live job `depCount` 5 = local extract 5) while the dashboard omitted it.
  For a visibility question use the job log's extracted deps or a local `--dry-run=extract`
  (below); writing a hidden image into values made the local extract list it. The `flux`
  manager read `registry`+`repository`+`tag` shapes and nested list entries
  (`deployments[].image`) there.
- **A disable rule must name every manager that extracts the dependency.** The homelab
  preset's `ghcr.io/pirat83/**` app-image rule matched only the `kubernetes` manager, while the
  `flux` manager extracted the same image.

**Dependabot**
- **It resolves one dependency at a time.** A bump that only resolves together with other bumps
  produces no PR — just a skipped update in the job log. "No PR" does not mean "up to date".
- **The open-PR limit hides updates.** The default `open-pull-requests-limit` is 5 for version
  updates (docs.github.com, dependabot options); the job log shows `Updating <pkg> from <old> to
  <new>` and then nothing, because the cap was reached. Security PRs have a separate limit
  (documented as 10; not re-checked).
- **A young release producing no PR may be an implicit 3-day cooldown** on version updates (not
  security updates). *Unverified*: the figure is not in the Dependabot docs read for this
  skill. Check the release age before calling it a coverage gap.
- **Version updates are off on forks by default.** A fork with a `dependabot.yml` can show zero
  Dependabot PRs (*observed*: Pirat83/fritz_exporter); enabling them is a repo setting.
- **Coverage must be measured from its own job log.** In the conda ecosystem (observed October
  2026), a pip spec with an extra (`psycopg[binary]==3.3.6`, `bigtree[all]`) was silently dropped
  by the parser — 25 of 29 declared pins were checked, with nothing logged for the other four —
  and a single fully-qualified build-string spec made it skip every conda dependency in the file.
  When triage touches the bot's config, or a dependency the bot "should" be proposing, compare
  declared pins against checked pins in the job log; reproducing the parser locally does not
  count.
- **`ignore: versions: [">=N"]` sets a ceiling, not a floor.** The bot proposes the newest version
  *below* it. Put the hold at the first breaking version. The conda ecosystem accepted
  `update-types` in the config and then ignored it.
- **It responds to comments** (`@dependabot rebase`, `@dependabot recreate`), unlike Renovate.
- **Scope of an entry.** `github-actions` with `directory: "/"` scans `.github/workflows` and a
  root `action.yml`, **not** `.github/actions/*` composite actions: use
  `directories: ["/", "/.github/actions/*"]`. `docker` at `/` bumps only the Dockerfile — never
  compose images (walkuere #95 touched `Dockerfile` alone; its timescaledb/redis/rqmonitor
  compose images were never proposed): add a separate `docker-compose` entry. The `helm`
  ecosystem is unused in any repo here; its file scope is *unverified*.
- **Commit prefix.** `commit-message.prefix` works everywhere; `prefix-development` only for
  bundler/composer/mix/maven/npm/pip/uv. Without `commit-message` Dependabot mirrors the repo's
  history (*observed*: `chore(deps)` in walkuere, `build(deps)` in Pirat83/valkyrie-ai) — both
  release nothing under release-please. A releasing repo sets `commit-message: prefix: fix`,
  plus `prefix-development: chore` where supported, and `include: scope`.
- **It respects human retitles and commits.** After a retitle plus a pushed commit it never
  renamed back or force-pushed (*observed*: walkuere #41 #56 #98 #100 #101).

**Both**
- **Lockfile claims are per PR.** Check a lockfile header or format version on each PR rather
  than generalising from one.
- **Titles go stale.** A PR titled "7.29 → 7.30" moved a root `undici` to 8.11.2 in its diff.
  The diff is the PR.

---

## Visibility classification

Phase 0 question, per dependency: **Renovate-visible, Dependabot-visible, or invisible to
both?** "No PR" means something only if the file is in a bot's scope. Decide from the repo's
real config chain, never from the bot's name:

1. **Renovate:** local `renovate.json` / `.github/renovate.json` → each `extends` preset. The
   Blue-Sharp repos use `local>Blue-Sharp/homelab` = `~/Projects/homelab/default.json` (read it
   for `managerFilePatterns`, `packageRules` with `enabled: false`, customManagers,
   `minimumReleaseAge`). Also `enabledManagers`. Not every repo uses the preset: as of
   2026-11-01 Blue-Sharp/freelance-automation `main` extends only `config:recommended` with
   `enabledManagers: [npm, nvm]` (at eval base e070995 it was `[npm]`; re-read with
   `gh api repos/<o>/<r>/contents/renovate.json` before quoting).
2. **Dependabot:** `.github/dependabot.yml` — `package-ecosystem`, `directory`/`directories`,
   `ignore`, `open-pull-requests-limit` (`0` = version updates off, security only).
3. **Repo security settings:** `gh api -i repos/o/r/vulnerability-alerts | head -1` (204 = alerts
   on) and `gh api repos/o/r/automated-security-fixes --jq .enabled`.

**Coverage state per repo:** *version updates* (a bot config covers it), *security-only* (no
config, alerts 204, `automated-security-fixes` true — Pirat83/valkyrie-ai: Dependabot PRs
appear, but no version bumps ever), or *none* (ssh-dispatch, vanna-lab, dagster-quickstart: no
bot proposes anything). A repo with both bots must have a deliberate split (freelance-automation
as of 2026-11-01: Renovate owns npm/nvm, Dependabot owns github-actions).

| Thing | Renovate manager | Dependabot ecosystem | Note |
|---|---|---|---|
| uv.lock | `pep621` | `uv` (indirect deps via `dependency-type: indirect`; security covers lockfile deps) | deps outside pyproject/lock invisible |
| Poetry | `poetry` | `pip` | |
| requirements.txt | `pip_requirements` | `pip` | `>=` ranges give no bump |
| conda environment.yml | **none** | `conda` (parser drops extras; see above) | |
| npm | `npm` | `npm` | |
| Flux HelmRelease chart | `flux` | **none** | default pattern only `gotk-components.ya?ml`: each repo must widen `managerFilePatterns` (the homelab preset does) |
| images in HelmRelease `spec.values` | `flux` — only once patterns are widened; reads `repository`+`tag`, `registry`+`repository`+`tag` and nested list entries (44.199.0, verified) | none | chart-default images not written in the repo are invisible |
| plain Helm values.yaml | `helm-values`, default `values.ya?ml`, `repository`+`tag` shapes only | none | |
| Kustomize `images:` / `?ref=` | `kustomize` | none | |
| raw K8s `image:` | `kubernetes`: **no default pattern, reads nothing** until set | none | CNPG `imageName:` needs a customManager |
| Dockerfile / compose | `dockerfile` / `docker-compose` | `docker` (Dockerfile only) / `docker-compose` | |
| GitHub Actions | `github-actions` (pins via `helpers:pinGitHubActionDigests`) | `github-actions` (`directories:` for composites) | |
| binaries in workflows (`*_VERSION`/`SHA256`) | customManager with `# renovate:` annotation; moves the version, **not** the checksum | none | |
| Ansible requirements.yml | `ansible-galaxy`, default `(galaxy\|requirements)(.ansible)?.ya?ml` | none | |
| Ansible vars | customManager with annotation | none | |
| Flux bootstrap `gotk-components.yaml` | `flux` system manifest | none | homelab ignores `flux-system/**` |
| pre-commit | `pre-commit`, off unless `:enablePreCommit` | `pre-commit` | |

**Invisible to both** — "nothing will ever propose this", so surface it (explicit values,
annotation, or a `helm template | grep image` audit):
- chart-default images not named in the repo (dagster's `postgres:14.6`, `busybox:1.28`,
  verified as init containers). Pin them explicitly in the HelmRelease values so a bot sees
  them; find them with `helm template ... | grep image:` (**run**: podman `alpine/helm:3.19.0`,
  4 images found). tree-health.md section 4 points here;
- images that exist only in rendered output;
- curl'd binaries without a `# renovate:` annotation;
- a versionless `requirements.yml` (no pin, nothing to bump);
- `enabled: false` deps — hand-pinned sets (fluxcd actions, prometheus, kubectl in the homelab
  preset). They are **also absent from the Dependency Dashboard** (*observed*:
  `prometheus/prometheus` annotated in homelab `alert-rules.yaml:57`, yet the dashboard lists
  only checkout and yq for that file). Their only record is the preset's `description`: read
  the preset, and triage the set together.

---

## Holds and labels

Everything here is **proposed** unless the user approved it (and a no-post run creates nothing:
no comment, push, label, issue, hold or merge). A no-post run lists the commands it would run.

**Which hold.** The selector is the unblock event:
- **Short block** = a known unblock event or date within about two weeks (a rebase, an
  upstream fix, an rc): the PR stays open, gets the `blocked` label, and the triage comment
  states the unblock condition. On a Renovate PR the `stop-updating` label
  (`stopUpdatingLabel`) also stops rebases.
- **Indefinite block** = no date: a bot-config hold whose `description` states the unblock
  condition. **Why an open PR is the wrong record for it:** Renovate counts it against
  `prConcurrentLimit` (the dashboard's *Rate-Limited* section; the limit was 5 in the eval repo,
  read yours) so it can crowd out new PRs, rebases
  burn CI on a PR nobody will merge, and the bot retargets it to newer versions, so the
  triaged head is not what sits there later.

**Guard versus config hold.** A *guard* lives in the repo's own manifest (a constraint,
an override, a test) and fits transitive or downstream breakage the repo does not exercise: the
bump itself may still merge. A *config hold* blocks the bump itself. On an exact-pinned direct
dependency (an npm devDependency) the bot's commit *is* the manifest change, so a guard would
mean reverting it: use the config hold.

**The unblock condition must be precise and testable, on both sides, and re-verified whenever
the hold is revisited** (upstream moves: a 9-day-old beta had already changed the answer).
The model is freelance-automation `renovate.json`; as of 2026-11-01 its description reads
"drop once the supported range includes 7", which would wrongly clear 7.0.x (7.0.x never works
with dependency-cruiser; the 7.0.2 run cruised 0 modules). Write it as:

```json
{ "matchPackageNames": ["typescript"], "allowedVersions": "<7",
  "description": "Hold TypeScript below 7. Unblock only when TypeScript >=7.1 AND dependency-cruiser >=18.8 (18.8.0-beta-1 supports >=7.1 <8); verify with `npm run arch` cruising >0 modules." }
```

A partial unblock (skip one broken minor) would be `"<7 || >=7.1.0"`; that range syntax is
*unverified*. Re-check the consumer's own declared support, wherever it lives (see
ecosystems.md, npm), not only the version you remember.

Dependabot holds go in `.github/dependabot.yml` (`ignore:` with a `versions` ceiling, plus a
comment naming the unblock condition) — **never `@dependabot ignore` comments**: they are stored
server-side and invisible in the repo.

**Coupled bumps no bot opens** (a chart + its `uv.lock`, a lockstep set): one issue labelled
`dependencies`, `hold`. **Deferred post-merge check** whose earliest run time is after the
session ends: an issue labelled `post-merge-check` (template in local-env.md).

**Labels must exist.** `gh pr edit --add-label` fails on a missing label. Run `gh label list`
first and create only the missing ones, **without `--force`**: `--force` overwrites an existing
label's colour and description (it would repaint Dependabot's `dependencies`). Applies to
`blocked`, `hold`, `post-merge-check`, `dependencies`; label creation needs the user's yes like
any other repo change.

---

## Reading what a bot could not do

**Renovate Dependency Dashboard** (issue titled "Dependency Dashboard"; sections as in
Renovate's source): *Pending Approval* (`dependencyDashboardApproval`), *Group Size Not Met*,
*Awaiting Schedule*, *Rate-Limited* (`prConcurrentLimit`/hourly cap hit), *Errored*, *PR
Creation Approval Required*, *PR Edited (Blocked)*, *Pending Status Checks*, *Other Branches*,
*Open*, *PR Closed (Blocked)*, *Config Migration Needed*, *Repository Problems*.
- A commit pushed onto a Renovate branch freezes it: Renovate stops updating the branch and the
  dashboard lists it under *PR Edited (Blocked)*. Do not amend; the `rebase` label or checkbox
  discards your edits.
- A missing PR is explained by one of these sections, or by the dependency not being detected
  at all (see Visibility). Artifact failures also appear as an "artifact update problem" comment
  on the PR.

**Dependabot** has no dashboard. Version updates it could not make appear only in the job log
(Insights → Dependency graph → Dependabot): "checked N of M" dependencies, skipped coupled
updates, the cap reached. Compare N/M with the declared pins.

---

## Renovate local dry run (extraction check)

*Run 2026-11-01 (Renovate 44.199.0).* Validates what a config extracts; it is not a
substitute for the bot's own run. For a **visibility question use `--dry-run=extract`**: no token
needed, under 5 minutes, and `LOG_FORMAT=json` gives a parseable `packageFiles` record. Use
`lookup` only when you need available versions.

```shell
cp -r <repo> $SCRATCH/r && cd $SCRATCH/r && git init -q   # a :ro mount breaks it: renovate writes cache/git state
podman run --rm -v "$PWD:/repo:Z" -w /repo -e LOG_LEVEL=info -e LOG_FORMAT=json \
  docker.io/renovate/renovate:44.199.0 renovate --platform=local --dry-run=extract
# lookup: add -e GITHUB_COM_TOKEN=<token> and --dry-run=lookup
podman run --rm -v "$PWD:/repo:Z" -w /repo --entrypoint renovate-config-validator \
  docker.io/renovate/renovate:44.199.0 --strict            # *unverified* invocation
```

- `local>` presets do not resolve on the local platform (`config-presets-invalid`, exit 1):
  **inline the preset** into the scratch copy's `renovate.json`. A `github>` preset on a
  private repo needs a token (not tested).
- Lookups for GitHub-hosted deps need `GITHUB_COM_TOKEN` (not `RENOVATE_TOKEN`); without it
  "Rate limit exceeded for api.github.com". Lookup results are *unverified*; extraction was
  verified (`github-actions: 2 files, 9 deps`; valkyrie-ai flux `depCount` 5).
- Local mode reads the repo's own `renovate.json`; `RENOVATE_CONFIG_FILE` does not replace it.
- `!` in `managerFilePatterns` is not an exclusion; use a `matchFileNames` rule.
- `npx renovate` needs Node ^24.11; use the container.
