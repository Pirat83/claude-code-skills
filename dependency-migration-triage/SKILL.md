---
name: dependency-migration-triage
description: >-
  Rigorously triage a single Renovate or Dependabot dependency version-bump PR, in any
  ecosystem — Python/PyPI, Helm charts under Flux, container images, GitHub Actions, or npm.
  Pull the real changelog/release notes across the full old->new version range (not the
  registry's summary blurb), always read the actual source diff between the two tags as well
  — a changelog records what changed and can never record what stayed the same, which is what
  most "we are unaffected" arguments actually rest on — map both against actual usage sites in
  this repo, write a migration plan that distinguishes interface changes from
  conceptual/behavioral ones (a version bump can quietly change defaults or strictness with no
  signature change at all), verify whether existing checks would actually catch a regression in
  that exact spot or merely execute the line with stale data, write a regression test that
  fails on the old behavior when a real issue is found, fix what's fixable, report back linking
  the originating bot PR, and after the merge return to settle whatever could not be verified
  before it. Use this whenever the user wants to review, assess, migrate,
  or avoid "merging blindly" a Renovate/Dependabot PR; asks "what changed" or "what needs to
  adapt" for a dependency bump; wants confidence a version bump is safe beyond "CI is green";
  or just pastes a bot PR number/link and asks to check it out. Trigger even for dependencies
  that look boring (docs tooling, linters, CI actions, a patch bump of your own reusable
  workflow) — some of the highest-value findings here come from bumps everyone assumes are safe.
---

# Dependency Migration Triage

Request: **$ARGUMENTS** (a bot PR number/URL, or a dependency name + old version -> new version)

You're triaging one dependency version bump. The goal is not "does it still resolve" — it's
"what actually changed underneath this version number, and does anything in *this* repo need to
adapt because of it." A green CI run on the bump PR itself is necessary but not sufficient: CI
only proves the currently-selected checks still pass, and says nothing about whether those
checks were ever capable of catching the specific thing that changed.

Read `references/case-studies.md` before Phase 4 if this is your first time running this skill,
or whenever a phase result feels uncertain. Its four worked examples come from a Python repo,
but every lesson in it is about evidence, not about Python.

Work through Phases 0-8 in order, then Phase 9 after the bump is actually merged — it is the
only one that runs in a later sitting, and the one most easily lost. Scale depth to actual
signal (see "Right-size the investigation" before Phase 1) — a trivial patch bump of a barely-used tool doesn't warrant the
same effort as a major-version jump of something running in production, and pretending otherwise
produces padded reports, not better decisions.

## Ecosystem dispatch

Three phases — 0, 3 and 5/7 — are the only ones that depend on the ecosystem. Resolve them from
this table, then run the phases as written. `references/ecosystems.md` has the detail, the
traps, and the exact commands for each column; read the column you need before Phase 0.

| | **0** where the version is declared | **3** how to map to usage | **5/7** how to become the coverage |
|---|---|---|---|
| **Python / PyPI** | `pyproject.toml`, `setup.cfg`, `requirements*.txt`, `uv.lock` | grep `src/`, `tests/`, `docs/` for imports and call sites | `pytest`, `mypy`, `ruff`, the real build |
| **Helm chart (Flux)** | `*-helmrelease.yaml` → `spec.chart.spec.version`; `*-source.yaml` for the repo | the HelmRelease's own `values:` block, key by key, against the new chart's `values.yaml`; plus CRD versions | `helm template` **against source-controller's served artifact**; `flux schema validate`; the lab's `policy.yaml` gator rules |
| **Container image** | image tag in a manifest, `Dockerfile` `FROM`, or a compose file | entrypoint, env vars, UID/GID, mounted paths, exposed ports | run it: `podman run --entrypoint ...`, or a one-pod smoke |
| **GitHub Actions** | `uses:` SHA pins in `.github/workflows/` and `.github/actions/` | every `with:` input and every output consumed downstream | run the workflow on a branch |
| **npm / Node** | `package.json` + lockfile | grep `import`/`require` and config files | `npm test`, `npm run build` |

If the bump doesn't fit a column, say so and reason from first principles — the phases below
don't depend on the table, only on being able to answer its three questions.

## Phase 0 — Identify the bump

Resolve the PR (or dependency name) to: dependency name, old version, new version, and where in
the repo it's declared. `gh pr view <n> --repo <owner>/<repo>` gets you the title and diff.

**Right-size the investigation.** Before going deep, get a fast read on stakes:
- Does this run in production, or is it tooling only (linters, type checkers, doc builders, CI
  actions)? A chart that serves live traffic deserves more scrutiny than a linter nobody's users
  ever touch.
- How big is the jump — a patch release, or several majors/many minors? Bigger jumps need more
  changelog reading, not more assumption.
- Does anything in this repo exercise the dependency at all (see Phase 5)? If a dependency has
  zero coverage today, that's itself a finding worth surfacing regardless of whether this
  particular bump breaks anything.

A one-line patch bump of an unused-by-default dev tool can reasonably get a light pass. A major
version bump of something serving live traffic cannot.

**A bump of your own code is still a bump.** A repo pinning a reusable workflow or chart you
also own is the easiest case, not an exempt one: the diff is commits you can read directly, so
the triage is cheap — but "I wrote it" is not evidence about what it does to the caller.

## Phase 1 — Get the real changelog, not the registry blurb

A registry's description field and a bot PR's auto-generated "Changelog" section are starting
points, not the source of truth — they're often truncated, and they only show the *target*
version's notes, not the full range you're crossing. Go to the dependency's actual source repo
and read the CHANGELOG.md / release notes / "what's new" docs covering **every** minor/major
version between old and new (patch releases are usually folded into their minor version's notes
— confirm this is true for the specific project rather than assuming). Use WebFetch/WebSearch.
For a wide range, you don't need to quote every entry — you need to have actually read enough to
know whether something in it touches what this repo uses.

For a Helm chart, note that a chart has **two** version numbers and they move independently: the
chart version Renovate bumped, and the `appVersion` of the software inside it. A chart-only bump
can still change the application, and an appVersion bump can land with no chart changes at all.

**Treat the `appVersion` move as a second dependency and run Phases 1 and 2 against it
separately**, rather than as a footnote to the chart's own notes. In practice this is where the
findings are — the chart diff is routinely a handful of trivial lines while the application diff
is thousands. From one run: authentik's chart delta was version labels and a quoting change,
while the app moved ~3,300 lines and rewrote its proxy outpost in another language;
`plugin-barman-cloud` 0.7.1 -> 0.8.0 never mentioned in any note that its appVersion went
v0.14.0 -> v0.15.0, and the entire substance of that bump was app-side. Read the appVersion out
of `Chart.yaml` at **both** tags; the PR title names only one of the two numbers.

**If the target is a prerelease (`-rc`, `-alpha`, `-beta`), add an issue search.** A prerelease
exists because it is expected to have defects, and the ones that matter are filed *against the
tag after it ships* — no diff can show you those. Search the project's issues for the version
string, and for every candidate fix compare the **closing PR's merge date against the tag date**:
a fix merged after the tag is not in the release you are about to deploy, and a newer tag
existing is not by itself evidence that it is. This is what produced a DO-NOT-MERGE verdict on
rustfs `1.0.0-rc.5` — two write-availability regressions whose fixes merged five days after the
tag was cut, one of which stopped all writes on a single-volume node after a day of uptime while
the pod stayed `Ready` throughout.

## Phase 2 — Read the diff between the two tags

Do this on every bump, including ones with a good changelog. A changelog records what changed;
it can never record what *stayed the same* — and most reachability arguments are claims about
the absence of change ("we're fine because the value we set is untouched"). No prose will ever
state that for you. The diff is also the only thing that pins a change to an exact version and
an exact symbol.

So the diff does two different jobs depending on what else exists:

- **No usable changelog** — an absent or empty release, notes that live only in an in-repo
  `CHANGES.rst`, a bare dump of PR titles. Then the diff is the only primary source there is,
  and "I read the changelog" is a claim you are not in a position to make.
- **A usable changelog** — then it gives you leads and the diff turns them into proof, far more
  cheaply, because the prose already told you which files to open.

Compare the tags directly — no clone needed:

```
gh api repos/<owner>/<repo>/compare/<old-tag>...<new-tag> \
  --jq '.commits[] | "- " + (.commit.message | split("\n")[0])'
gh api repos/<owner>/<repo>/compare/<old-tag>...<new-tag> \
  --jq '.files[] | "\(.status) \(.filename) +\(.additions)/-\(.deletions)"'
```

Add `| select(.filename == "<path>") | .patch` to read one file's hunks. Finding the right
`<owner>/<repo>` and tag naming is ecosystem-specific — see `references/ecosystems.md`; a Helm
chart's tags in particular are usually `<chart-name>-<version>`, not `v<version>`, and a
monorepo of charts will not tag at all in the shape you expect.

**`compare` truncates silently on wide ranges, and the failure mode is a false negative.**
Over many versions GitHub drops the `patch` field and then drops files from `.files` altogether
— with no error and no marker. Measured on joblib: `1.2.0...1.5.3` returns 134 files, 37 with
`patch == null`, and omits `joblib/parallel.py` **entirely** despite it changing by 542 lines;
narrowing to `1.4.2...1.5.3` returns it with its patch intact. Read naively, "the file isn't in
the list" becomes "the file didn't change" — the exact opposite of the truth, on the file that
mattered most.

Two habits make that safe:
- **Step through the range** one minor at a time rather than spanning it in one call, and treat
  a single wide compare as a survey, never as evidence of absence.
- **Never conclude "unchanged" from a file's absence.** If a file you expected to change isn't
  listed, narrow the range until it appears, or fetch it at both tags and diff locally
  (`gh api repos/<o>/<r>/contents/<path>?ref=<tag> --jq .content | base64 -d`). Absence of
  evidence here really is not evidence of absence.

**On a large repo, skip `compare` and diff the recursive git trees instead.** Two calls — one per
tag — list every blob SHA in the repository at that commit, so the added / removed / changed set
is exact, complete, and structurally impossible to truncate:

```shell
for t in <old-tag> <new-tag>; do
  gh api "repos/<o>/<r>/git/trees/$t?recursive=1" \
    --jq '.tree[] | select(.type=="blob") | "\(.path) \(.sha)"' | sort > "/tmp/tree-$t.txt"
done
diff /tmp/tree-<old-tag>.txt /tmp/tree-<new-tag>.txt
```

Two identical blob SHAs are *proof* of byte-identity, which is the strongest available form of
the "proving non-change" argument this phase rests on — and it costs one API call per tag rather
than a hunt through hunks. Fetch the patch only for the paths this shows actually moved.

**In a monorepo, filter to the subtree you consume before judging anything by size.** A compare
between two chart tags in a chart monorepo spans every other chart's commits; "412 files changed"
means nothing until you restrict to `charts/<name>/`.

Extract, in the order that decides things:

1. **Which files changed.** Cross-reference against Phase 3's usage sites. A change confined to
   a component this repo never uses is unreachable, full stop.
2. **The patch for the parts that *are* reachable** — and, for anything you intend to call safe,
   confirmation that its source is genuinely untouched rather than merely unmentioned.
3. **Metadata that decides what can resolve or run at all** — a language floor, a dependency
   pin, a required platform version, a chart's `kubeVersion`. These are routinely absent from
   the prose.

Worked outcomes, all from real runs of this skill:

- **Sole source.** mypy 2.3.0 → 2.3.1 had no release notes. The diff was six commits; the only
  substantive one replaced an `assert isinstance(...)` with a conditional to fix a crash — a
  *proof* the bump cannot newly reject previously-accepted input, which no changelog existed to
  state.
- **Scoping a vague warning.** alpaca-py 0.44.0's notes flagged one item "Breaking Change" with
  no scope. The file list showed it touching one module the codebase never imports. Unreachable,
  settled in one command.
- **Proving non-change.** For a pytest-randomly 3.12 → 4.1 major bump, the questions that
  mattered were whether one flag still worked and whether seed propagation survived. The diff
  answered both by showing the relevant entry-point name and class body byte-identical across
  the tags. A changelog cannot tell you that something is unchanged; only the diff can.

**Two mirror-image traps, each of which reads as a finding and is not:**

- **A file's presence in the changed list is not evidence your output changed.** Three rule
  templates changed between two chart versions while the rendered rules came out byte-identical,
  because every hunk sat behind a conditional this repo never enters. "Changed file" to "changed
  behaviour" is an inference, and Phase 5's render is what settles it.
- **A new key in the new version's schema is not evidence of new behaviour.** The old version may
  have done the same thing by a different mechanism, in which case reporting it as "new in vN" is
  simply wrong. kube-prometheus-stack v90 added an `authorization:` block to the etcd
  ServiceMonitor values, which read as v90 newly putting a bearer token on a plaintext scrape;
  rendering v88 showed it already sent one, via `bearerTokenFile`. What changed was the
  *mechanism*, not the behaviour — and the schema diff could not tell them apart.

Track which source each later claim rests on. "Read in the diff" and "stated in the changelog"
are different strengths of evidence, and Phase 8 asks you to report them apart.

## Phase 3 — Map to actual usage

Find every real usage site, using the ecosystem's column in the dispatch table. Don't reason
from the dependency's own docs in the abstract; ground every claim in this repo's actual usage,
with `file:line` references. If a dependency isn't used anywhere, say so plainly — that changes
everything downstream (see Phase 5).

The shape of "usage" differs by ecosystem and getting it wrong is how a triage misses things.
For code, usage is imports and call sites. For a Helm chart it is **every key you set in the
HelmRelease's `values:` block** — that is your interface to the chart, and a key the new chart
renamed or removed does not error, it is silently ignored. For a container image it is the
assumptions around it, not inside it: UID, entrypoint, paths, env. For an Action it is the
`with:` inputs you pass and the outputs you consume.

**Then widen it: usage is also everything else in the repo that hardcodes a value this
dependency controls.** This is the highest-value widening available in this phase, and it gets
missed precisely because the obvious interface looks complete. Once you know the version numbers
involved, grep the repo for the *old* ones:

```shell
grep -rn "<old chart version>\|<old appVersion>\|<old image tag>" . --exclude-dir=.git
```

In one run that is what found a CI workflow pinning `promtool` to "whatever Prometheus the
cluster runs" — a version the chart bump silently invalidated, sitting in a file nobody would
open while reviewing a HelmRelease. CI workflows, Ansible vars, Dockerfiles, README commands,
dashboards and alert rules all hardcode versions, images and metric names that a bump can move
underneath them.

**Ask once per triage whether a second repo has to move in lockstep.** Some dependencies are
coupled to something declared elsewhere — a CLI to the controller it talks to (`kubeseal` and
the sealed-secrets controller), a validator to the server whose rules it checks (`promtool` and
Prometheus). A bot bumps one side and structurally cannot see the other. If your bot config
*ignores* a dependency, that ignore rule is documentation that a coupling exists — read the
ignore list as part of this phase.

**A key of yours that is absent from the parent chart's `values.yaml` is not necessarily a
dropped key.** `helm show values <parent>` does not expand subchart defaults, so a legitimately
set subchart key (`grafana.*`, `kube-state-metrics.*`) reads as absent and manufactures a
"removed upstream" finding. Resolve subchart keys against the subchart's own values, or settle
it with the render.

## Phase 4 — Migration plan: interface changes AND conceptual/behavioral ones

For each usage site found in Phase 3, cross-reference against Phase 1's changelog and Phase 2's
diff, and classify: **safe as-is** / **trivial fix** (renamed key or parameter, deprecated arg)
/ **real change needed** / **new concept to adopt**.

The trap to avoid: only checking whether an interface changed shape. Some of the most
consequential changes in a version bump are changes to *default behavior* with no interface
change at all — stricter validation defaults, a changed resource default, a narrower timeout, a
different probe, a schema a third-party API now returns that your code doesn't expect. Read
`references/case-studies.md` for two concrete examples of exactly this class. Ask explicitly,
for each usage site: "if I changed nothing on my side, could this new version make this do
something different than before?" — that question catches what an interface diff alone won't.

## Phase 5 — Coverage check: does a check actually cover *this*, or just execute the line?

For every usage site flagged as anything other than "safe as-is" in Phase 4, find the test or CI
check that exercises it and read it — don't just check whether coverage tooling marks the line
as executed, or whether the repo's CI is green. Ask: does the check construct the *specific
input/shape* that the changed behavior would affect, with *live* logic (or a fixture reflecting
the *new* reality), or does it pass with data that predates the change and therefore can't
reveal a regression even though it technically runs? A line at 100% coverage can still be
worthless for catching this exact class of bug — `references/case-studies.md` has a worked
example. This phase's output is not a percentage; it's a specific yes/no per flagged usage site,
with reasoning.

**When coverage turns out to be zero or inadequate — which is common for tooling, CI actions,
and anything a test suite can't reach — you have to become the coverage yourself, and that means
verifying *both directions*, not just one.** The natural instinct is to check "does the new
version work" and stop once it does. That only catches regressions; it silently misses the
mirror case, where the *old* version was already broken and the bump is actually a load-bearing
fix rather than a no-op. The only way to tell those apart is to run the exact same check against
both versions and compare — if you're about to spend the effort building or executing something
to confirm the new version is fine, spend the same few minutes running the identical check
against the old version first. `references/case-studies.md` (case study 4) documents this skill
catching itself getting this wrong.

Use the ecosystem's "become the coverage" column. For a Helm chart that means rendering both
chart versions with **this repo's actual `values:`** and diffing the output — which is the only
thing that surfaces a silently-ignored key, since a wrong key renders nothing while every object
reports Ready and CI stays green.

**Diff per rendered object, never as one text blob.** Every object carries `helm.sh/chart` and
`app.kubernetes.io/version` labels, so a raw diff of a large chart is almost entirely label
churn — measured at roughly 1,800 changed lines concealing 7 real changes. Parse both renders
into a map keyed by `(kind, namespace, name)`, normalise the version labels to a placeholder,
and report three sets: objects **added**, objects **removed**, objects whose normalised body
**changed**. That turns an unreadable diff into a short list, and added/removed are findings in
their own right — one major bump added exactly one object, a service-account-token Secret, and
that was the entire story of the upgrade.

`references/ecosystems.md` carries the render mechanics that change the *answer* rather than
merely being convenient — the namespace flag, capability gating, subchart resolution, and how to
render at all when `helm` isn't installed. Getting any of them wrong produces a confident,
wrong, well-formatted diff.

**A policy or contract that asserts your *declared* values cannot catch this class of bug at
all.** It reads the same file you wrote, so a key the chart quietly stopped consuming still sits
there with the right value and the assertion still passes — which is exactly how an
`insecureSkipVerify` setting survived a major bump as a dead key with CI green and a contract
explicitly guarding it. Repointing such an assertion after a move restores the guard for *that*
move and does nothing for the next one. Only the render knows whether the chart consumes a key,
so a check meant to guard a value's *effect* has to assert against rendered output, not source.

**For a JavaScript Action with a committed `dist/`, compare the `dist/index.js` blob SHA across
the two tags.** That is cheaper *and* stronger than running the workflow on a branch: identical
SHAs prove zero runtime change, whereas a green run proves only that one path worked once. It
cleared `renovatebot/github-action` v46.2.2 -> v46.2.5 in a single API call.

## Phase 6 — Write a regression test, only when there's a real finding

If Phase 4/5 turned up an actual breaking change with inadequate coverage: write a check that
constructs the exact input/shape that exposes it, and **prove it's a real regression test, not a
plausible-sounding one** — reproduce the old broken behavior directly (revert your Phase 7 fix
locally, or hand-run the old logic in a scratch snippet) and confirm the new check fails against
it, then reinstate the fix and confirm it passes. This is the difference between "I think this
would have failed" and "I watched it fail."

If Phase 4/5 found nothing wrong: say so and stop here. Don't manufacture a test to look
thorough — a fabricated regression test for a non-issue is noise that looks like rigor, and
future readers can't tell the difference between "this guards something real" and "this pads the
diff" unless you're honest about which is which right now.

## Phase 7 — Fix what's fixable

Mechanical migrations (deprecation warnings, renamed keys or parameters, newly-required explicit
arguments) get fixed inline as part of this same pass — don't leave free wins for a human to
redo. Real breaking changes get a proper fix paired with the Phase 6 regression test. If
something needs a genuinely new concept adopted (not just a find-replace), implement it, but
flag that this is a judgment call the maintainer may want to review more closely.

**If this phase produced a real change** (skip this entirely for a nothing-to-fix outcome —
running either of these against a no-op finding is pure overhead), close the loop on your own
work before Phase 8:

- Run the `silent-failure-hunter` agent (from the `pr-review-toolkit` plugin, if available —
  otherwise apply the same lens yourself: does the fix swallow an error anywhere, degrade to a
  fallback without surfacing it, or introduce a new way for something to fail quietly?) against
  the diff. This is the same failure class the whole skill exists to catch in third-party
  dependencies — pointing it at your own fix is the same discipline turned inward.
- If the fix touches secrets, authentication, or a publish/release pipeline (long-lived tokens,
  credential handling, OIDC config, CI steps that push artifacts somewhere), run
  `/security-review` before proceeding. Skip it for everything else — most triages never go near
  credentials, and running it by default would be blanket overhead for no signal.

## Phase 8 — Report, mirroring the migration

**Settle this before composing anything: is this a dry run?** If no real PR exists, or you were
asked to exercise this skill itself, stop after producing the would-be title, body and diff and
say so explicitly — do not call `gh pr comment` or `gh pr create`. Deciding it *after* the
report is written is how a comment gets fired at a PR that should never have received one.

Report on the bump PR — a comment on it when there's nothing to change, a PR against it or a
companion PR when there is (follow the repo's own branch conventions; check recent merged PRs
for the base branch). The write-up must:

- Reference the originating bot PR explicitly, so a maintainer can find it from either direction.
- **State plainly which of three tiers each claim rests on, and don't blur them:** *verified by
  executing something* (a render actually diffed, a test that really failed then passed, a tool
  actually invoked against the new version), *read in the diff* (Phase 2 — a file list proving
  unreachability, a hunk read directly), or *inferred from changelogs*. The middle tier is the
  one that gets silently promoted to the first or demoted to the third; name it as its own thing.
- **Name the adjacent instances of anything you fix, and say whether they are in scope.** A
  finding rarely has exactly one site. Dropping a pointless credential from the etcd scrape left
  the identical exposure on the `kube-proxy` and `coredns` scrapes, same one-line fix each; a
  report that fixes one and is silent about the rest reads as complete and is not. Enumerate the
  siblings even when you deliberately leave them alone, and say why you did.
- **Say what a merge will visibly do**, when it does anything: which workloads restart, whether
  it is an in-place restart or a switchover, how long it took to reconcile, and what has to be
  true beforehand (a fresh backup, a quiet window). "Safe to merge" and "safe to merge right
  now" are different claims.
- If nothing needed fixing, say so plainly — "verified: the following was checked and nothing
  needs to change" — rather than staying silent. Silence is indistinguishable from not looking.
- Let the maintainer choose their own depth: deep-review the finding, or trust it and merge.

## Phase 9 — Close the loop after the merge

Almost every triage ends with claims it *could not* execute: runtime properties no pre-merge
check can reach ("does this Kubernetes version still populate a manually created token
Secret?"), schema effects that only exist once migrations have run, a backup path that has to
actually run once. Phase 8 makes you label those honestly. This phase exists because labelling
them is where it otherwise stops — the verdict gets written, the PR gets merged, and nobody
returns to the sentence that said *inferred, not executed*.

**While still in Phase 8, for each claim you are about to file as inferred, write down the exact
command that would settle it and what result counts as a pass.** Expressed as prose, a
post-merge check is a task somebody has to re-derive; expressed as a command with a pass
condition it is a two-minute mechanical pass. "Confirm the outpost still works" is the first
kind. "`select ... from django_migrations`, and the through model must reuse the existing table
rather than create a new one" is the second.

**After the merge reconciles, run them and post the outcome as a follow-up comment on the merged
PR.** That comment is the only place the two halves of the evidence ever meet; merging closes
the PR, it does not close the triage. Three claims filed as unverifiable in one session, each
settled in minutes once the code was live: a manually created service-account-token Secret *was*
still populated (1336 bytes); a Django through-model migration *did* reuse the existing table,
leaving a blueprint's wholesale assignment intact; a backup *did* complete on the new sidecar
image, in 28 seconds.

**Read a rollout's logs as a curve, not a snapshot.** A single grep for errors right after a
rollout is near-useless in both directions: startup noise reads as a regression, and a slow
failure has not happened yet. Sample the same window at least twice, minutes apart, and report
the trend. A service that emitted 34 warnings in its first minute, then 14, then 4, then 0, with
zero restarts, is starting up; an identical first sample with a flat count is a service failing
over and over, and only the second sample distinguishes them.

**Prefer evidence that something *worked* over evidence that nothing complained** — a populated
series count, a completed backup, a `200` at the end of a redirect chain, a metric with a value.
An empty error log is also exactly what a component that never started produces.

## A note on trusting static tools

Lint/type-checker/policy findings (linter rules, security scanners, admission-policy failures)
are hypotheses, not verdicts, until you've traced the actual dataflow. A rule can flag a pattern
that's provably safe in context — `references/case-studies.md` has a worked example of exactly
this. Before calling anything a "bug" in your report, verify it against the real code path, not
just the rule's generic description of what it usually catches. Getting this wrong in the other
direction — dismissing a real finding as "probably fine" without tracing it — is just as much a
failure; the discipline is doing the trace either way, not defaulting to belief or disbelief.
