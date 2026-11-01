---
name: dependency-migration-triage
description: >-
  Triage Renovate and Dependabot version bumps so every merge is safe and the dependency tree
  stays as small and healthy as possible: one PR, a backlog, or one shared change fanned out
  across repos, in Python (uv, Poetry, pip, conda), npm, Helm under Flux, Kustomize, container
  images, GitHub Actions, Ansible, databases and operators. Use whenever the user gives a bot PR
  number or link (a bare number counts when the author is a bot or the branch is renovate/* or
  dependabot/*), wants to merge bot PRs ("merge 19 and 20", "which bot PR is next", "merge the
  green updates") because merging still needs triage, asks what changed or what must adapt,
  wants more than "CI is green", raises a Dependabot or security alert or an upcoming release,
  or asks whether merged bumps are running. Covers the tree delta of each bump, which bot can
  see what, the semver level for the user's own release, and bringing the local environment in
  line after the merge. Not for a lab-wide "what's next" sweep (homelab-health).
---

# Dependency Migration Triage

Request: **$ARGUMENTS** (bot PR numbers/URLs, an alert, or a dependency name + old version -> new version)

**Goal: triage each bump safely and keep the dependency tree as small and healthy as possible.**
The question is never only "does it still resolve" but "what changed underneath this version
number, what does this repo have to adapt, and does the tree come out smaller or at least no
worse". A green CI run is necessary, not sufficient: it proves the selected checks passed, not
that they could have caught this change — or that they ran the new version at all.

**More than one PR, or one change fanned out as N PRs?** Read `references/batches.md` first; the
phases then run once per *distinct* dependency. **Merging is part of this skill**: a request to
merge bot PRs is a request to triage them first — every merged PR carries a recorded triage level
(Phase 8).

References, loaded when a phase points at them: `ecosystems.md` (commands and traps per
ecosystem), `bots.md` (what Renovate and Dependabot can and cannot see; holds and labels),
`tree-health.md` (tree delta and health tools), `releases.md` (semver level for the user's own
release), `local-env.md` (after the merge), `case-studies.md` (read before Phase 4 on a first
run, or whenever a result feels uncertain).

Work through Phases 0-8 in order, then Phase 9 after the merge. Scale depth to signal (Phase 0).

## Ecosystem dispatch

Phases 0, 3 and 5/7 depend on the ecosystem; resolve them here, details in `ecosystems.md`.

| | **0** declared in | **3** usage is | **5/7** become the coverage with |
|---|---|---|---|
| **uv / pip** | `pyproject.toml`, `uv.lock`, `requirements*.txt` | imports, call sites, vendored copies | `pytest` (which marker tier does CI run?), type checker, linter, real build |
| **Poetry** | `[tool.poetry]` + groups, `poetry.lock` | as uv | `poetry run …`; check which lockfile governs (Phase 0) |
| **Conda** | `environment.yml` + what the host has installed | as uv | `conda install --dry-run` churn; single-package apply |
| **Helm (Flux)** | `*-helmrelease.yaml`, `*-source.yaml` | every key in `values:`; CRDs | `helm template` both versions from the served artifact, `--kube-version`/`--api-versions`, per-object diff |
| **Kustomize / manifests** | `kustomization.yaml`, `image:` lines, remote bases | resources, patches, CRD fields | `kustomize build` diff, schema/policy gates |
| **Container image** | manifest tag, `FROM`, compose | entrypoint, env, UID, paths; version files copied in | run both tags |
| **Stateful** (DB, extension, operator) | image tag **and** the version inside the data | everything reading the stored data | rehearse on a copy of production-shaped data |
| **GitHub Actions** | `uses:` SHA pins; `*_VERSION`/`*_SHA256` pairs | `with:` inputs, consumed outputs | run a caller; read the tool's version in its log |
| **Ansible** | `requirements.yml`, `defaults/main.yml` pins | modules used; hosts the pin lands on | `--check --diff` on one host |
| **npm** | `package.json` + lockfile | imports, config files, peer ranges of consumers | `npm test`/`build`, gate input counts |

If nothing fits, reason from first principles — the phases need only these three answers.

## Phase 0 — Identify the bump

Resolve: dependency, old → new version, where declared, and **the PR head SHA**
(`gh pr view <n> -R <o>/<r> --json title,headRefOid,files`). Bots retarget open PRs; the SHA is
how you notice at merge time and diff only the delta.

- **Does the declaring file still govern?** After a migration (conda → uv, a chart moved) open bot
  PRs edit dead files: verdict *stale*, recommend closing, triage the replacement, and record any
  coupled bump the PR was holding somewhere durable first.
- **Which lockfile governs?** With two (mid-migration), the tracked one that CI installs from is
  the truth (`git ls-files`; the CI install step) — e.g. a Poetry repo with a stray untracked
  `uv.lock` left by a trial migration: `poetry.lock` governs.
- **Which bot can see this dependency?** Classify it *Renovate-visible / Dependabot-visible /
  invisible to both* from the real config chain (`bots.md`) — for Renovate, a local extract dry run or its job log, not
the Dependency Dashboard (it hides extracted deps). Invisible dependencies — chart-default
  images, curl'd binaries without an annotation, versionless `requirements.yml`, `enabled: false`
  pins — are the ones nothing will ever propose; the triage is their only reviewer.
- **Already merged, held or reverted?** A PR merged without a triage record — including a human
  PR that fixed an alert — gets a *late triage*, posted on the merged PR. A held or reverted bump:
  re-verify its unblock condition first; upstream may have moved. A PR body carrying verdict and
  evidence tiers counts as the triage record.
- **No single PR?** An unreleased version → a findings note keyed to the future bump (no fix that
  breaks today's version). Called from another skill → report into its file. "Check the open PRs"
  → open bot PRs **and** queued updates (Dependency Dashboard; Dependabot job log) **and** open
  alerts, plus settled decisions in memory. An alert is a bump request: triage the fix version.

**Right-size the investigation.** Production or tooling? Patch or several majors? Reached only
from tests/dev? → reachability verdict plus one probe, a few lines. Byte-identical where it
matters (chart tarball `templates/`/`values.yaml`/`crds/` under `diff -ru`; an Action's
`dist/index.js` blob SHA)? → that is the Phase 2 result; skip to Phase 8. Zero usage → verdict
*remove*. A bump of your own workflow or chart is still a bump, and its pin range can carry a
nested one (a tool version, a checksum). Post-merge checking scales the same way.

## Phase 1 — Read the real changelog across the whole range

The registry blurb and the bot's "Changelog" section show the target version only. Read the
project's own release notes for **every** minor/major crossed (confirm patches fold into their
minor). WebFetch returns a summary: quote only text you actually read.

**Two version numbers → two triages.** A chart's `appVersion` (and any wrapper's payload: an
image's runtime, an operator's software) moves independently of the chart version and usually
carries the findings. Read it at both tags and run Phases 1-2 on it too (`ecosystems.md`, Helm).

**Prerelease target?** Search the project's issues for the version and compare each fix's merge
date with the tag date — a fix merged after the tag is not in the release you deploy, and a newer tag existing is not by
itself evidence that it is. A rewrite released from another repo (TypeScript 7 from
`microsoft/typescript-go`) has no tag diff to read: diff the released artifacts and API surface.

## Phase 2 — Read the diff between the two tags

Always, unless Phase 0 proved byte-identity. A changelog records what changed; only the diff
shows what stayed the same, which is what "we are unaffected" rests on.

```
gh api repos/<o>/<r>/compare/<old>...<new> --jq '.files[] | "\(.status) \(.filename) +\(.additions)/-\(.deletions)"'
```

`compare` truncates silently on wide ranges — files vanish from `.files` with no marker. Step one
minor at a time, never conclude "unchanged" from absence, or diff the recursive git trees (blob
SHAs: exact and untruncatable; recipe in `ecosystems.md`). Exactly 1,000 results is a page cap.
In a monorepo, filter to your subtree. Where the payload is data (CA bundle, tz data, schema
catalog), diff the data. Run a new tool once offline to find what it fetches at runtime from an
unpinned upstream.

Extract, in order: which files changed (vs. Phase 3 usage); the patch for reachable parts and
proof that what you call safe is untouched; metadata that decides whether it resolves or runs at
all (language floor, `kubeVersion`, pins). Two traps: a changed file is not a changed output, and
a new schema key is not new behaviour — render or run the old version before claiming either.
Track whether each claim was *read in the diff* or *stated in the changelog* (Phase 8).

## Phase 3 — Usage, then the tree delta

**Usage**, with `file:line`: imports and call sites plus copied library code; every HelmRelease
`values:` key (a renamed key is silently ignored); the assumptions around an image; `with:`
inputs; every alert rule, dashboard and fixture naming a metric or label the dependency emits.
Then grep the repo for the **old** version strings — CI pins, Ansible vars, Dockerfiles,
`.python-version`, READMEs. Stale version text in comments and docs is fixed in the same change,
made version-neutral, never left as a follow-up.

**Co-declared pairs.** A bot often moves one half: a version beside its `*_SHA256` (five times
across the `gh`, `yq` and `kubeseal` download pins in one lab), `FROM python:` beside
`.python-version`, a chart beside image tags written explicitly in its `values:` (they don't
follow `appVersion`; Renovate split one such pair twice), a pin that must equal something running
elsewhere. Verify the coupled value by
executing it; if a half-bump recurs, propose fixing the bot config once.

**Couplings no bot sees.** A CLI and its controller, a validator and its server, a pin set kept in
four places (the Flux CLI: Ansible, a workflow, `gotk-components.yaml`, the cluster). A bot bumps
one side, or — resolving one dependency at a time — never opens a PR for a major that needs other
majors. Treat the set as one bump; record coupling sets where they will be found again. A bot's
ignore list documents a coupling; a missing upper bound proves nothing about runtime
compatibility; "match the version in the cluster" may conflate a server with its client library.

**Tree delta** — at standard and deep level in lockfile ecosystems (uv and npm verified; others
in `tree-health.md`); at light level, one line. Diff the lockfile between base and head
(`python3 -I <skill-dir>/references/scripts/uvlockdiff.py <repo> <base> <head>`, `npmlockdiff.sh`),
and what production installs if that differs (`uv export --no-dev`). For every package that moved, appeared or
vanished: **all its parents and the binding constraint** (`uv tree --invert --package X`; ranges
via `pipdeptree -r` or PyPI `requires_dist`; `npm explain X`), one probe per parent path, and
vulnerabilities on the new lock (osv-scanner — a bot may never alert on a reviewed advisory).
Whether a parent really holds a transitive back is one command: `uv lock --dry-run
--upgrade-package X`. A transitive package leaves the tree only when **every** parent drops it —
name them. For a security fix, run the published attack input on old and new and judge severity
by who can reach it. A package the repo never imports is judged by
reachability (chain → changed path → one probe on old and new), not usage. Zero usage of a
direct dependency → *remove*, after finding what it provided transitively that the repo imports
undeclared (run the suite with those modules blocked).

**Tree note — optional, never blocking.** One line from deptry/knip (unused, undeclared,
misplaced scope, an extra pulling more than used). Licence, provenance, install scripts,
upstream health and EOL only when a **new package enters the tree, on a major** (in `0.y.z` a
`0.y` bump counts as major), **or a component is within ~30 days of its EOL**. Commands and
caveats: `tree-health.md`.

## Phase 4 — Migration plan, verdict, release level

For each usage site, classify against Phases 1-2: **safe as-is** / **trivial fix** / **real
change** / **new concept to adopt**. The trap is checking only interface shape: ask per site "if I
change nothing, could the new version do something different?" — stricter validation, a changed
default, a narrower timeout, a new API response shape. Three recurring classes:

- **Stored data** — a changed on-disk default can start a service empty with every probe green.
  Reproduce on a *copy*, record counts as the Phase 9 baseline, name the only copy of the data.
- **Persisted derived numbers** — diff outputs on identical inputs field by field (one analytics
  bump moved 55 of 576 stored fields, no test failed); backfill or accept the break, as a decision.
- **A version inside the data** — an image bump does not upgrade a DB extension's catalog; name
  the post-artifact step and its cost (`ecosystems.md`, Stateful).

**Verdicts:** merge / merge with fix / block / *remove the dependency* / *hold with a guard* (a
constraint in the repo's own manifest at the **first breaking version**, linked to the upstream
issue — a code change on the bot's branch) / *stale*. A freeze is the last option: state what a
stale pin costs and put *remove* next to it (case study 7).

**Blocked bumps** (`bots.md`): a **short block** — a known unblock event within ~2 weeks — keeps
the PR open with label `blocked` and the condition in the triage comment (Renovate's
`stop-updating` label stops rebases). An **indefinite block** — no date — becomes a bot-config
hold whose `description` states a **testable unblock condition on both sides** ("TS >= 7.1 *and*
dependency-cruiser >= 18.8", not "once 7 is supported"); an open PR is the wrong record there (it
takes a `prConcurrentLimit` slot, gets rebased and retargeted). Coupled bumps no bot opens → one
issue labelled `dependencies`,`hold`. Labels, issues and holds are **proposed** and created only
on the user's yes (labels: `gh label list` first; never `--force`, it rewrites existing ones).

**Adoption line** in every report: what the new version enables here (`file:line`) — or "none".

**Release level** — only if the repo has `release-please-config.json` (or another documented
release process); otherwise one line: "no release process". Decide major / minor / patch / none
for the *user's own* project with the table in `releases.md`. A release process means a config
**and** releases that actually happen (`gh release list`); a fork whose releases happen upstream
has none here (consumer must act → major; new
observable capability → minor; otherwise patch; dev/test/CI-only → none).

## Phase 5 — Does a check actually cover *this*?

For every site not "safe as-is", read the check that exercises it: does it build the input shape
the change affects, with live logic or a fixture of the *new* reality — or does it pass on data
that predates the change (case study 2)? Output a yes/no per site.

**Prove the check ran the new version.** Each of these gave green results that tested nothing:
the PR's CI never runs the change (callers pin the action by SHA; the job lives in another repo) —
grep the log for the new version; a scratch worktree without the PR's lockfile; `python -I`
ignoring `PYTHONPATH`; a CI marker tier that never imports the dependency. Every arm prints the
version it loaded from inside the process under test.

**Check the gate's denominator.** A gate that analyses zero inputs exits 0 (case study 5: TS7,
"0 modules cruised"). Compare input counts on base and bump branch; check the consumer tool's
**own** declared support for the new version wherever it lives (a peer range, a custom field like
dependency-cruiser's `supportedTranspilers`, its docs). Offer a guard that fails the gate on zero
inputs (`depcruise --output-type json | jq -e '.summary.totalCruised > 0'`).

**No adequate check → become the coverage, both directions** (case study 4): run the identical
check on old and new — the old one may already be broken. A harness earns trust first: a
known-valid control passes; a baseline arm with setup errors is void; shell-sensitive steps run
under the step's shell; flakes get a 2×2 run (old/new test × old/new dependency); environment failures are labelled
as such, with proof. For Helm: render both versions with this repo's real `values:`, per object;
a policy asserting *declared* values cannot catch a key the chart stopped reading.

Use what the repo already has (compose file, units, recipes) before building infrastructure;
clean up only resources you started, by recorded ID. When the decisive check needs access you
don't have, hand the user one self-contained command with a pass criterion — never retry variants
of a refused command.

## Phase 6 — Regression test, only for a real finding

Write a check that builds the exact input that exposes the break, watch it fail on the old
behaviour and pass on the fix. Found nothing? Say so and write no test.

## Phase 7 — Fix what's fixable

Fix mechanical migrations inline (renamed keys, deprecations, the stale half of a pair, stale
version text). Real breaks get a fix plus the Phase 6 test; a new concept gets implemented and
flagged as a judgment call.

**On the bot's branch**: stack commits on the bot's commit (a commit also freezes a Renovate
branch — intended), never force-push over it; pushing is part of posting (no-post runs keep the
fix as a diff). If a push is refused or prompts, ask once. Report channel: a comment when nothing
changes, a commit on the bot branch or a companion PR when something does, per the repo's branch
conventions.

**Out of scope unless asked**: adding bot hold/ignore/disable rules, closing, superseding or
reordering PRs. Offer them with their consequence. Hand-managed environments get single-package
changes, never a re-solve.

**If this phase changed something**: run `silent-failure-hunter` (pr-review-toolkit) or apply its
lens; `/security-review` only when credentials, auth or release pipelines are touched.

## Phase 8 — Report and record

**No-post run?** Only when no real PR exists, another skill called this one, or the user said
read-only or "test of the skill" — then nothing leaves the machine: no comment, push, label,
issue, hold or merge; produce title, body and diff and say nothing was posted.
Otherwise invoking this skill on a real PR authorises the comment; don't ask "should I post?".

**Every PR gets a recorded triage level before it merges** — no silent batch merges (measured
across two accounts, Sep–Nov 2026: 348 of 392 merged bot PRs had no record, and the one real miss
was merged exactly that way):

| Level | When | Minimum record |
|---|---|---|
| **light** | digest/patch of tooling, byte-identical artifact, test-only dependency | one line: what was checked and why that suffices |
| **standard** | everything else | verdict, tier-labelled bullets, what a merge does, adoption line |
| **deep** | majors, runtime/stateful changes, security fixes, a real finding | standard + migration plan, coverage verdicts, Phase 9 commands |

"Automerged by rule X" counts as light when the rule is documented in the bot config.

**Merging is a separate authority**: merge when told ("merge them if harmless" counts), else ask
— and end every report with one merge-state line (*merged (squash)* or *merge now?*). Check
allowed methods (`gh repo view --json squashMergeAllowed,…`) and that the head SHA is still the
one triaged. In a releasing repo the merge carries the level: `gh pr merge <n> --squash --subject
"fix(deps): …"` (or `feat`/`feat!`), plus `--body "Release-As: x.y.z"` for a specific version —
run it when told to merge, print it otherwise. **Convention: every repo is squash-only with
`PR_TITLE` + `BLANK`** — breaking is `!` in the subject, an exact version is
`--body "Release-As: x.y.z"`, and a bot PR is merged with an explicit `--body ""` (release-please
reads BREAKING CHANGE anywhere in a body and splits bodies at `fix:`/`feat:` lines into extra
commits, so PR bodies never go into history). A repo not yet on the convention: read its setting
(`gh api repos/<o>/<r> --jq '.squash_merge_commit_title, .squash_merge_commit_message'`); explicit
`--subject`/`--body` is correct under every setting (`releases.md`).

The report — written to a file, posted with `gh pr comment --body-file`:
- **One-line verdict first**: migration needed yes/no; safe to merge yes / now / after X; level.
- The originating bot PR, linked.
- **Each claim's tier**: *verified by executing*, *read in the diff*, or *inferred from
  changelogs* — never blur the middle one.
- **Close cheap gaps** instead of listing them; list only what cannot run before the merge.
- **Adjacent instances** of anything fixed, and whether they are in scope.
- **What a merge visibly does** — restarts (e.g. `checksum/*` pod annotations that change on every
  chart bump), switchover, preconditions — read from the live or rendered object (`maxSurge`,
  `maxUnavailable`, `podManagementPolicy`); baselines from a window at least one restart cycle
  after the last rollout, named.
- Phase 9 numbers to compare against; the tree delta in one line; the adoption line.
- "Verified, nothing to change" when that is the result — silence reads as not looking.

Keep it short: the verdict line, tier-labelled bullets, the merge-state line.

Re-read every number against collected evidence before posting. Delegated parts: apply
`batches.md` "Treat agent output as claims".

## Phase 9 — Close the loop after the merge

For every claim filed as inferred, Phase 8 already wrote **the command, the pass condition and
the earliest time it can run**. After the merge reconciles, run them and post the outcome on the
merged PR. **If the earliest time is after this session ends** (a +48 h watch, the next deploy, a
weekly job), open an issue labelled `post-merge-check` with command, pass condition and date, and
close it with the result (a baseline that must be taken before a scheduled job goes in the
issue too) — deferred checks are exactly the ones that got dropped before (10 of 30 in the same
measurement). Re-read `origin/main` first: compare against current main, not the merge SHA.

**Check the new version is what runs**: through layered pins (caller → reusable workflow →
pinned action → tool) read the tool's own version where it is consumed (case study 6); on
hand-managed hosts assert installed == declared. A different environment than the pinned one is
reported as such, not as a pass. A bump merged without triage gets one late, posted on the PR.

**The local environment follows the merge** — once, after the last merge of a batch, against
the checkout's *current* lock, read-only by default (list the drift, print the commands; change
the machine only on the user's yes), scoped to what the bump touched: dev venvs and worktrees, derived artifacts (`dbt parse`), the local dev
stack, workstation CLIs pinned in Ansible, the IDE interpreter. Production installs the lock
fresh; the developer's machine is the one place a bump does not land by itself (case study 8).
Procedure and proofs: `local-env.md`.

Read a rollout's logs as a curve (two samples, minutes apart), and prefer evidence that
something *worked* — a populated series, a completed backup, a `200` — over an empty error log.
Probe through the real path (Service, ingress), not an ad-hoc pod.

## A note on trusting static tools

Lint, type-checker and policy findings are hypotheses until you trace the dataflow (case study 3).
Verify against the real code path before calling something a bug — and don't dismiss a finding
as "probably fine" without the same trace.
