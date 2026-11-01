# Ecosystems: commands, traps and worked examples per row

The phases in SKILL.md are ecosystem-agnostic. Three of them need one concrete answer each:
where the version is declared, what "usage" means, and how to become the coverage when nothing
else does; the sections below also carry ecosystem notes for Phases 2 and 9. Read the section you
need before Phase 0. If a bump spans two rows — a chart whose
`appVersion` moves the image, say, or an image that carries a database extension — read both.
What Renovate and Dependabot can and cannot put in a PR (and what their silence means) is in
`bots.md`.

---

## Reading diffs (every ecosystem)

**Commit list and file list between two tags, and one file's hunks:**

```shell
gh api repos/<o>/<r>/compare/<old-tag>...<new-tag> \
  --jq '.commits[] | "- " + (.commit.message | split("\n")[0])'
gh api repos/<o>/<r>/compare/<old-tag>...<new-tag> \
  --jq '.files[] | "\(.status) \(.filename) +\(.additions)/-\(.deletions)"'
gh api repos/<o>/<r>/compare/<old-tag>...<new-tag> \
  --jq '.files[] | select(.filename == "<path>") | .patch'
```

**Tag naming is per ecosystem.** GitHub Actions and most libraries tag `v<version>`; a Helm chart
repo tags `<chart>-<version>` and a chart monorepo tags per chart; some repos tag only the
app. List before guessing: `gh api repos/<o>/<r>/tags --jq '.[].name' | head -30`. A wrong tag
makes `compare` 404, which reads as "no changes". In a monorepo filter to the subtree you consume
before judging by size.

**A rewrite released from another repo has no tag diff.** TypeScript 7 is a Go rewrite built in
`microsoft/typescript-go`; the `microsoft/TypeScript` v7.0.2 release body is a link. Diff the
release artifacts or API surface instead (published `.d.ts`/package contents between versions,
`npm pack` both and `diff -r`), and become the coverage on the repo.

**Blog-only changelogs:** WebFetch returns a summary; for the raw text, `curl -sL <url>` through
an HTML-to-text step (`python3 -I -c` with `html.parser`, or `lynx -dump`).

**A prerelease target needs an issue search**, and a newer tag is not evidence the fix shipped:
compare each candidate fix's closing PR merge date with the tag date of the version you deploy.

**Where the payload is data, diff the data.** A CA bundle: count roots, then handshake each host
the app calls (`openssl s_client -connect host:443 -CAfile <old|new bundle>`) under both bundles.

**Security fix: run the published attack input on old and new**, then judge severity against
actual exposure (whose input reaches it?). One run measured a stack-overflow crash and 4,770 ms
vs 61 ms; the same bug unreachable from untrusted input is a different severity.

**A flaky check:** repeat on both versions and cite the failing assertion; a 2x2 matrix
(old/new test x old/new dependency) separates a regression from a pre-existing flake. A refused
variant of a command is not retried in other forms: prepare one self-contained command with a
pass criterion for the user.

**`compare` truncation, measured.** On joblib, `1.2.0...1.5.3` returns 134 files, 37 with
`patch == null`, and omits `joblib/parallel.py` **entirely** despite it changing by 542 lines;
narrowing to `1.4.2...1.5.3` returns it with its patch intact. Read naively, "the file isn't in
the list" becomes "the file didn't change" — on the file that mattered most. To read a file at
both tags directly:

```shell
gh api "repos/<o>/<r>/contents/<path>?ref=<tag>" --jq .content | base64 -d
```

**Recursive tree diff** — exact, complete, and impossible to truncate; two identical blob SHAs
are proof of byte-identity:

```shell
for t in <old-tag> <new-tag>; do
  gh api "repos/<o>/<r>/git/trees/$t?recursive=1" \
    --jq '.tree[] | select(.type=="blob") | "\(.path) \(.sha)"' | sort > "tree-$t.txt"
done
diff tree-<old-tag>.txt tree-<new-tag>.txt
```

**Worked outcomes of the diff, from real runs:**
- *Sole source.* mypy 2.3.0 → 2.3.1 had no release notes. The diff was six commits; the only
  substantive one replaced an `assert isinstance(...)` with a conditional to fix a crash — a
  *proof* the bump cannot newly reject previously-accepted input, which no changelog existed to
  state.
- *Scoping a vague warning.* alpaca-py 0.44.0's notes flagged one item "Breaking Change" with no
  scope. The file list showed it touching one module the codebase never imports. Unreachable,
  settled in one command.
- *Proving non-change.* For a pytest-randomly 3.12 → 4.1 major bump, the questions were whether
  one flag still worked and whether seed propagation survived. The diff showed the entry-point
  name and class body byte-identical across the tags.

**The mirror-image traps, worked:**
- Three rule templates changed between two chart versions while the rendered rules came out
  byte-identical, because every hunk sat behind a conditional this repo never enters.
- kube-prometheus-stack v90 added an `authorization:` block to the etcd ServiceMonitor values,
  which read as v90 newly putting a bearer token on a plaintext scrape; rendering v88 showed it
  already sent one, via `bearerTokenFile`. The *mechanism* changed, not the behaviour.

**Runtime-fetched data, worked.** A manifest validator's built-in schema catalog turned out to
be fetched from the upstream `main` branch at run time, so CI validated against Kubernetes 1.37
schemas while the cluster ran 1.36 — after the triage had first claimed the binary version
pinned it. Running the old binary offline is what showed it.

---

## Helm chart, under Flux

**The `appVersion` move is a second dependency, worked.** authentik's chart delta was version
labels and a quoting change, while the app moved ~3,300 lines and rewrote its proxy outpost in
another language. `plugin-barman-cloud` 0.7.1 -> 0.8.0 never mentioned in any note that its
appVersion went v0.14.0 -> v0.15.0, and the entire substance of that bump was app-side. Read the
appVersion out of `Chart.yaml` at **both** tags; the PR title names only one of the two numbers.

**Prerelease issue search, worked** (rule in Reading diffs above). rustfs `1.0.0-rc.5` got DO-NOT-MERGE for two
write-availability regressions whose fixes merged five days after the tag was cut; one stopped
all writes on a single-volume node after a day of uptime while the pod stayed `Ready`.

**Phase 0 — where declared.** `*-helmrelease.yaml` → `spec.chart.spec.version` is what Renovate
bumps. `spec.chart.spec.sourceRef` names a `HelmRepository` (or `GitRepository`) declared in
`*-source.yaml`; that is where the chart actually comes from.

**A chart has two version numbers and they move independently.** The chart version is packaging;
`appVersion` is the software inside. Get both for old and new before anything else:

```shell
helm repo add <name> <url from the HelmRepository .spec.url>
helm repo update <name>
helm search repo <name>/<chart> --versions | head
helm show chart <name>/<chart> --version <ver> | grep -E '^(version|appVersion|kubeVersion)'
```

**Explicit image tags in `values:` do not follow `appVersion`, so a chart-only bot PR is a
half-bump.** If the values pin `image.tag` (dagster-k8s is the case), the chart bump moves
nothing that runs; the image is a second change that must move with it. Renovate split this pair
twice (valkyrie-ai #6/#7 and #17). Group the pair in the bot config or bump them together, and
name the image bump as part of the verdict. Conversely, chart-default images that values do not
name are invisible to the bots (bots.md).

`helm show chart` also prints `sources:`, which is how you find the GitHub repo for Phase 2.
Chart repos usually tag `<chart-name>-<version>`, **not** `v<version>`, and a monorepo of charts
tags per chart — check `gh api repos/<o>/<r>/tags --jq '.[].name' | head -30` before assuming a
tag name, or a `compare` will 404 and look like "no changes".

**Phase 3 — usage is your `values:` block, key by key.** That block is your entire interface to
the chart. This is the highest-value check in the whole triage, because of the failure mode:

> **A key the new chart renamed, moved or removed does not error. It is silently ignored.** The
> release installs, every object reports `Ready`, Flux is happy, CI is green — and the setting
> you thought you were applying simply isn't. Nothing anywhere reports this.

So diff your keys against the chart's own `values.yaml` at both versions:

```shell
helm show values <name>/<chart> --version <old> > /tmp/values-old.yaml
helm show values <name>/<chart> --version <new> > /tmp/values-new.yaml
diff -u /tmp/values-old.yaml /tmp/values-new.yaml
```

**A key of yours absent from the parent chart's `values.yaml` is not necessarily dropped.**
`helm show values <parent>` does not expand subchart defaults, so a legitimately set subchart key
(`grafana.*`, `kube-state-metrics.*`) reads as absent and manufactures a "removed upstream"
finding. Resolve subchart keys against the subchart's own values, or settle it with the render.

**Read the chart's values from the published artifact — the version Flux actually serves — not
from the upstream repo's default branch.** The default branch is ahead of every release; a key
that exists there may not exist in the version you're pinning, and checking against it produces
a confident wrong answer.

Also check **CRDs**. `helm upgrade` does not upgrade CRDs — that is Helm's documented behaviour,
not a bug. If the chart's `crds/` directory changed between the tags, the new CRD will not be
applied unless the HelmRelease says so (`spec.upgrade.crds: CreateReplace`). A chart bump that
adds a field you then set in `values:` will render it into a CR the cluster's *old* CRD rejects
— or worse, silently prunes.

**Phase 5/7 — become the coverage by rendering both versions with your real values.**

```shell
yq '.spec.values' <repo>-helmrelease.yaml > /tmp/my-values.yaml
for v in <old> <new>; do
  helm template <releaseName> <name>/<chart> --version $v \
    -n <namespace> -f /tmp/my-values.yaml > /tmp/render-$v.yaml
done
diff -u /tmp/render-<old>.yaml /tmp/render-<new>.yaml
```

**Pass `-n <namespace>`.** Without it `helm template` renders every namespaced object into
`default`, and a diff of two such renders looks fine while telling you nothing about where
anything lands.

**Pass `--api-versions` for capability-gated templates.** Anything behind `.Capabilities`
renders as nothing without it, which reads in a diff as "this object was removed":
`--api-versions monitoring.coreos.com/v1 --api-versions gateway.networking.k8s.io/v1`.

**`helm dependency update` first, if you render from a chart source directory** — required even
when every subchart condition is false, or the render fails outright. A release *tarball*
already contains its subcharts, which is one good reason to prefer one.

**Fetching the chart without configuring a repo.** Pins the version by construction and leaves
no local helm repo state behind:

```shell
curl -sSL -o chart.tgz \
  https://github.com/<owner>/<repo>/releases/download/<chart>-<ver>/<chart>-<ver>.tgz
tar xzf chart.tgz
```

**`helm` may not be installed — render it from a container rather than skipping the phase.**
This render is too load-bearing to abandon over a missing binary:

```shell
podman run --rm -v "$PWD:/w:z" --entrypoint helm docker.io/alpine/helm:3.19.0 \
  template <releaseName> /w/<chart-dir> -n <namespace> -f /w/values.yaml
```

The `:z` relabel is required on SELinux hosts (Fedora, RHEL); without it the mount is unreadable
inside the container.

**Extract the `values:` block with a YAML parser**, not by hand — and note `yq` may be absent
too, in which case `python3 -c "import yaml, ..."` does the same job. Hand-reindenting a large
values block is its own source of false findings.

**Diff per object, not as text** (no script ships for it; `scripts/` has lock diffs only, so
write the keyed diff once per run). Key both renders by `(kind, namespace, name)`, normalise
`helm.sh/chart`, `app.kubernetes.io/version` and any `chart:` label to a placeholder, then
report added / removed / changed separately. Without that, version-label churn buries the real
changes — measured at ~1,800 changed lines hiding 7 real ones on a 120-object chart. Added and
removed are findings in their own right: one major bump added exactly one object, a
service-account-token Secret, and that was the entire story of the upgrade.

**A policy or contract that asserts your *declared* values cannot catch a dead key.** It reads
the file you wrote, so a key the chart stopped consuming still has the right value and the
assertion passes — which is how an `insecureSkipVerify` setting survived a major bump as a dead
key with CI green and a contract explicitly guarding it. A check meant to guard a value's
*effect* has to assert against rendered output, not source.

**Keep `checksum/*` pod-template annotations when predicting a rollout.** They hash
label-bearing ConfigMaps/Secrets, so they change on every chart bump and restart those pods even
when nothing else differs. Normalising them hides the restart; say "pods X restart" in what a
merge does. Read `maxSurge`/`maxUnavailable`/`podManagementPolicy` from the rendered object.

**Classify added objects by hook annotation.** `helm template` renders `helm.sh/hook: test`
objects (Grafana's chart ships three), which show up as "added". Flux never runs them unless the
HelmRelease sets `spec.test.enable`, so they are not a cluster change — say so rather than
reporting new objects.

**Diff the two tarballs before rendering anything.** `diff -ru` of the unpacked chart
directories showing `templates/`, `values.yaml` and `crds/` byte-identical makes the key-by-key
check and the render moot; only `Chart.yaml` metadata moved. This cleared authentik, traefik,
dagster and kube-prometheus-stack bumps in one command each.

**Validate rendered config with the new binary's own checker** where one exists
(`blackbox_exporter --config.check`, `promtool check config`, `alertmanager --config.check`
equivalents): the chart may render the same config while the new app version rejects it.

**When a changelog says behaviour changes under a condition, check the condition against live
objects.** Traefik's new HTTP/HTTPS backend rule only mattered for some backends; listing all ten
live backends and checking each settled it, where reading the rule alone could not.

**A CI-tool bump that renders for every consumer can be triaged by rendering every consumer.**
Running the lab's own renderer under both tool versions across all 18 consumer repos, with 0
object differences, was cheaper and stronger than reading the tool's changelog for reachability.

Then the repo's own gates: `flux schema validate . --config .fluxschema.yml`, and the shared
policy job if the lab has one. Reconcile order when you do go live is source → Kustomization →
HelmRelease; forcing a HelmRelease against a stale source just makes you fight the old spec.

**Commands that change an answer (Flux/Helm, from real runs):**
- *Gated templates vanish without capability flags.* Render with
  `--kube-version <cluster> --api-versions <group/version>` for each gate; PodDisruptionBudget,
  ServiceMonitor and HTTPRoute silently disappear otherwise (read in a diff as "removed").
- *Read the artifact Flux actually serves:*
  `kubectl -n <ns> get helmchart <ns>-<chart> -o jsonpath='{.status.artifact.url}'`, then
  `kubectl -n flux-system exec deploy/source-controller -- sh -c 'wget -qO c.tgz <url>'` (or
  `port-forward deploy/source-controller 19091:9090` and curl).
- *Live state beats the PR's premise:*
  `kubectl get hr <n> -n <ns> -o jsonpath='{.status.history[0].chartVersion} {.status.history[0].appVersion}'`
  — the cluster ran 1.0.1 while the PR said 1.0.3.
- *Object-kind drift of a repo:* `kubectl kustomize . | grep '^kind:' | sort | uniq -c` before
  and after.
- *Not-ready gate around merges:* `flux get all -A --status-selector ready=false`, before and
  after.
- *The Helm embedded in helm-controller* (read its `go.mod`) can differ from the CI Helm: when it
  changes, render all consumers under both helm versions.
- *Missing `helm`/`gator`/`promtool`:* run via podman, or download the release tarball, verify
  its `.sha256sum`, and extract into a scratch bin dir (several helm versions side by side; set
  `HELM_CONFIG_HOME`). In subagents wrap scripts in `bash -s <<'EOF'` (zsh heredoc quirks).

## CRDs (Flux and operators)

**Served/stored versions before trusting a migration.**
`kubectl get crd <x> -o json | jq '.spec.versions[]|{name,served,storage}'`. The cluster served
Flux `Alert`/`Provider` only as `v1beta3`, so a `flux migrate` to `v1` would have broken the
apply. For a CRD bump, `kubectl diff --server-side -f <crds.yaml>` shows what changes live.

**Inventory of CRs using a removed or renamed field:**
`kubectl get <kind> -A -o json | python3 -I -c '...'` over every instance (CNPG `plugins`,
redis CRs), compared with the new CRD's property keys.

---

## Container image

**Phase 0 — where declared.** An image tag in a manifest, a `FROM` in a `Dockerfile`, an
`image:` in a compose file, or a chart value like `.Values.image.tag`.

**Phase 2/3 — usage is the assumptions *around* the image, not the code inside it.** Compare the
two tags' metadata directly; this is fast and catches most real breakage:

```shell
skopeo inspect docker://<image>:<old> > /tmp/img-old.json
skopeo inspect docker://<image>:<new> > /tmp/img-new.json
diff <(jq -S '{Env,Labels,Architecture,Os}' /tmp/img-old.json) \
     <(jq -S '{Env,Labels,Architecture,Os}' /tmp/img-new.json)
```

What actually breaks, in rough order of frequency:

- **UID/GID changed.** The classic. Existing volumes are owned by the old UID and the new image
  can't write to them. Nothing about the image "fails" — the app just can't start, or starts and
  can't persist.
- **Entrypoint or CMD changed**, so your `command:`/`args:` override now means something else.
- **A path moved** — config, data directory, socket.
- **Base distro changed**, taking a shell, a CA bundle, or a libc with it. Diff the bundle:
  count roots and handshake each host the app calls under both (see Reading diffs).

**A language-runtime base image (`FROM python:3.12.x`) has a twin in the repo.** Tools inside the
image read `.python-version`, `.nvmrc`, `.tool-versions` or a `requires-python` floor copied in
at build time. A bot PR that changes only `FROM` then fails at build with "No interpreter found
for Python 3.12.10" — and a rebase never fixes it. This happened twice in one repo. Grep for the
old patch version and move every copy in the same PR.

**Phase 5/7 — run it.** `podman run --rm --entrypoint sh <image>:<new> -c 'id; ls -la <datadir>'`
against both tags is usually the whole experiment.

**Digest and config proofs.** `skopeo inspect --raw docker://<img>:<tag> | sha256sum` is the
manifest-list digest a PR's pin should equal; `skopeo inspect --config` for both tags compares
layers, labels and creation time. Guard with `command -v skopeo`.

**Stateful image on a copy of real data.** `podman run -d --network none -v <vol>:/var/lib/postgresql/data:O <image>`
— the `:O` overlay leaves the volume untouched. A long-running process under `timeout` exits 124
by design: judge by log lines (`failed-to-evaluate|level=error`), not the exit code.

For a post-merge probe in a cluster, go through the Service or ingress. An ad-hoc curl pod can
return `000` because a NetworkPolicy blocks it, which reads as an outage that isn't there; a
`kubectl port-forward svc/<name>` takes the real path.

---

## Stateful component: databases, extensions, operators

**Phase 0 — two versions, not one.** The image tag is what the bot bumps. The version that
decides behaviour is often recorded *inside the data*: a PostgreSQL extension's version in
`pg_extension`, a schema migration table, an on-disk format, the resources an operator already
manages. A new image ships the new extension *binaries*; the catalog stays on the old version
until someone runs the upgrade. In one run the timescaledb-ha image rolled cleanly, every probe
passed, and the extension stayed at 2.29.2.

```sql
SELECT extname, extversion FROM pg_extension;                       -- what the catalog says
SELECT name, default_version FROM pg_available_extensions WHERE name = '<ext>';  -- what the image offers
```

**Phase 2 — read the upgrade scripts, not just the changelog.** For an extension, the
`<ext>--<old>--<new>.sql` scripts are the migration: which catalog tables get rebuilt, what takes
an `ACCESS EXCLUSIVE` lock and on what, what scales with data size. That is the cost model for
the maintenance window, and no release note states it.

**Phase 5/7 — rehearse on production-shaped data.** A throwaway database on the *real* images,
loaded with a schema the shape of production (1,923 chunks, the same continuous aggregates), gave
a measured 152 ms for the update. A minimal fixture would have given a number that means nothing.

Mechanics that decided the procedure for timescaledb, as an example of what to look for:
- `ALTER EXTENSION timescaledb UPDATE` must be the first command in a fresh session
  (`psql -X`); the CNPG `Database` resource's extension `version:` field could not do it.
- Every open connection fails one query after the update, so plan a restart of the server or
  its clients.
- Pause writers first (schedulers, sensors), take a backup immediately before, and record that
  they were paused somewhere the next session will see.

**Orchestrator evidence (Dagster, worked).** "Did production actually run it" is answered by
the instance, not by the pod: runs since the deploy that SUCCEEDED (filter on the `dagster/image`
tag), and materialization counts per asset (for dbt assets, `unique_id` metadata). Example
shape, run in the webserver pod: `DagsterInstance.get().get_latest_materialization_event(
AssetKey([...]))` and compare its timestamp to the deploy time (list the keys first if the path
is unverified). Report "N runs SUCCESS since the deploy" as the evidence; it was the strongest
line in a triage.

**Phase 9** — the post-image step is its own item with a command, a pass condition (the catalog
version equals the image's default version) and a time. A merge of the image PR alone does not
close the triage.

**Operators that change a storage default.** redis-operator 0.27.0 changed the casing of the AOF
filename, so Redis would have started empty on the old data. The proof was to `BGSAVE`, copy
`/data`, and start throwaway containers on that copy under both filenames, which reproduced the
empty start. Record key or row counts before merging; Phase 9 compares against them.

---

## GitHub Actions

**Phase 0 — where declared.** `uses:` refs in `.github/workflows/*.yaml` and
`.github/actions/*/action.yaml`. Where actions are SHA-pinned, the line reads
`uses: owner/repo@<40-hex-sha> # v3` — **the SHA is the truth and the comment is a hint.** They
can disagree. Confirm the new SHA really is the tag it claims:

```shell
gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq .object.sha
```

A mismatch is not a formatting nit — a force-pushed tag pointing at different code is precisely
the supply-chain attack SHA pinning exists to stop, and it looks exactly like a routine bump.

**Phase 3 — usage is every `with:` input you pass and every output you consume.** An input that
was renamed or removed is accepted silently by most actions and simply ignored; an output that
changed shape breaks the step that reads it, often much later in the job.

For a **reusable workflow** (`uses: owner/repo/.github/workflows/x.yaml@ref`) the interface is
its `on.workflow_call.inputs` and `.secrets`. Diff those between the two refs before anything
else — a newly-required input fails every caller, and a removed one fails them silently.

**For a JavaScript Action with a committed `dist/`, compare the `dist/index.js` blob SHA across
the two tags.** Identical SHAs prove zero runtime change, which is stronger than a green run on a
branch; it cleared `renovatebot/github-action` v46.2.2 -> v46.2.5 in one API call.

**Version and checksum are one unit.** Composite actions that download a binary declare
`<TOOL>_VERSION` and `<TOOL>_SHA256` side by side and run `sha256sum -c`. Renovate's regex
managers bump the version and leave the hash, so the PR is broken — and its own CI is green,
because callers pin the action by SHA and nothing runs the new pair until a caller is bumped.
This recurred on five bumps across `gh`, `yq` and `kubeseal`. Settle it by executing:

```shell
curl -sSLO <release-url-for-new-version>
sha256sum <artifact>                                   # compute it
curl -sSL <release-url>/<checksums-file> | grep <artifact>   # upstream's statement of it
echo "<old-sha>  <artifact>" | bash -euo pipefail -c 'sha256sum -c'   # must FAIL
```

A checksums file may carry many hash columns (yq's `checksums` has about 20, with the order in a
separate `checksums_hashes_order` file): grep the artifact name, then pick the sha256 column by
that order, or compare against your computed value rather than eyeballing. If running the
downloaded binary is blocked, compare hashes in both directions without executing it
(computed == upstream, old != upstream) and run it in `podman` or read the caller's CI log for
the version.

**List every caller of a reusable workflow or action** with `gh search code` (it can return
nothing for private orgs) or loop `gh api repos/<o>/<r>/contents/.github/workflows` over
`gh repo list <org>`, or grep local clones. A header comment saying callers use `@main` is not
evidence; read the real `uses:` lines.
Push the corrected hash to the bot's branch (when pushes are approved). On the second
recurrence, propose fixing the cause once, but **check the shared preset first**: the homelab
customManager's description documents the half-bump as intended, and no Renovate mechanism
updates a release-asset checksum on its own (regex managers have no sha256 datasource;
`postUpgradeTasks` needs a self-hosted bot plus `allowedCommands`). Name a mechanism or say none
exists.

**Phase 5/7 — run the workflow on a branch.** For an action used by many repos, run one caller
and read the log rather than reasoning about all of them.

**The bump PR's own checks rarely exercise the action.** If callers pin it by SHA, or the step
only runs in a reusable workflow consumed elsewhere, the PR's green check ran the *old* code.
Grep the job log for the new version string or SHA; zero hits means CI did not test the bump.
The first real run is a caller's PR — name that caller and its expected log line as the Phase 9
check.

**`fluxcd/flux2/action` without `with: version:` installs the latest CLI** (Flux 2.10 turned 21
repos red). A CI step failing on `api.github.com/.../attestations` is a network/API flake that
looks like a bump failure; re-run before diagnosing.

**Pins nest.** caller → reusable workflow → composite action (SHA-pinned) → tool binary. Bumping
one layer leaves the others where they were: after a Helm v4 pin merged, nineteen digest PRs went
green while `helm version --short` in their logs still printed `v3.21.4`, because the inner
action pins were stale. Read the tool's own version output in a consumer log after the merge.

**A red Renovate branch: check which pin the failing run used before diagnosing.** Nineteen repos
went red after Renovate rebased their digest branch across a pin commit; the log line "Failed to
download flux binary" was the action's own script source echoed into the log, not an error from
`main`. Reproduce shell behaviour under `bash -euo pipefail` (what `shell: bash` runs), not zsh.

---

## Python / PyPI

**Phase 0 — where declared.** `pyproject.toml`, `setup.cfg` (`install_requires`), `requirements*.txt`,
`uv.lock`. These are not interchangeable, and which one governs decides whether the bump changes
anything at all: a floor in a requirements file used only by a docs build does not feed the test
matrix. Establish which file feeds which job before concluding anything.

**Watch open-ended floors.** If constraints are `>=`, a fresh install already resolves to the
post-bump version — so an "old vs new" comparison installs the same thing twice and measures
nothing. Reproducing a real "before" arm needs `==` pins.

**Phase 3 — grep `src/`, `tests/` and, if that's the only place it appears, `docs/`** for
imports, call sites, and config keys naming the tool. Also grep for copied library code — a
method body reproduced locally, often with a drift test beside it — and diff the copy against the
new upstream.

For a transitive dependency, settle loading before reading anything:

```shell
python -c "import <app entry modules>; import sys; print('<pkg>' in sys.modules)"
uv tree --invert --package <pkg>      # who pulls it in, and in which group
```

`False` from the first line means the app's import path never loads the package; the bump can
only matter through the remaining paths `uv tree` shows.

**Phase 5/7 — the real toolchain**: `pytest`, `mypy`, `ruff`, an actual docs build. For a tool
whose job is deciding whether code is correct (type checker, linter), running the new version
against the real codebase is the only way to find behaviour changes — see case study 1.

**Read which tier CI runs.** `pytest -m "not integration"` in CI means a dependency used only by
integration tests is never imported by the gate; one psycopg2 bump went green without executing a
line of psycopg2. Check `addopts`, markers and the CI command before counting a green run.

**Make sure the arm you're running has the bumped version.** In a scratch worktree, copy in the
PR's `uv.lock` and `uv sync --frozen` before running any gate; a worktree without it installs main's
lock, and a gate that keys off staged changes may run nothing at all on a clean tree ("passed in
about a second"). Print `pkg.__version__` and `pkg.__file__` from inside the process. `python -I`
ignores `PYTHONPATH` — a harness using it tested the old version three times.

**Become the coverage without fighting a workspace pin.** An old-vs-new arm when the workspace
pins the package: `PYTHONPATH=<pkg>/src uv run --no-project --isolated --with <pkg>==<old> … python probe.py`
(and `pytest --noconftest`), repeated with `==<new>` (valkyrie-ai polars triage). To test a
wheel without touching a shared venv: `uv pip install --target <scratch> --no-deps <wheel>` and
put `<scratch>` on `PYTHONPATH` (walkuere).

**Two cheap ways to get a "new" arm without building an environment per PR:**
- *Overlay venv*: `python -m venv --system-site-packages /scratch/ov && /scratch/ov/bin/pip
  install --no-deps <pkg>==<new>` — the base environment stays untouched, the overlay wins on
  import.
- *Unzipped wheels*: download the PR's wheels, check their hashes against the PR's lock, unzip
  them into a scratch directory and put it first on `PYTHONPATH`. One run used this to test each
  of several bumps alone against a 900-test baseline with no venv at all.

`pip install --dry-run <pkg>==<new>` in the real environment shows newly required transitive
packages (one rq bump pulled in `croniter`) before anything is installed.

**Removal and undeclared imports.** When a bump or cleanup drops packages from the lock (an extra
removed, a transitive no longer pulled in), run the suite with those modules blocked — a
`sys.modules['<mod>'] = None` stub in `conftest.py` or an import hook — so anything the repo was
importing without declaring fails now, not in production. Dropping `bigtree[all]` exposed that
quantstats imports IPython without declaring it.

**Validated models against real data.** For a bump that tightens a Pydantic-style model, replay
real historical payloads through the new version (`raw_data=True` or the equivalent), paging
until counts stop being round.

For numeric or compiled dependencies, "tests pass" may be too weak a claim if determinism is a
shipped feature: compare full-precision outputs or hashes across both arms, not just exit codes.
If those outputs are *persisted*, diff them field by field on identical inputs and treat the
change as a data-continuity decision (SKILL.md Phase 4).

---

## Poetry (`pyproject.toml` with `[tool.poetry]`)

**Phase 0 — where declared.** `[tool.poetry.dependencies]` and groups
(`[tool.poetry.group.<g>.dependencies]`), locked in `poetry.lock`. `poetry show --tree` and
`poetry show --outdated` give the tree and the candidates. Dependabot reads Poetry through its
`pip` ecosystem; Renovate through `poetry`.

**Two lockfiles during a migration: which one governs?** Check which is tracked
(`git ls-files | grep -E 'poetry.lock|uv.lock'`) and which CI installs from. valkyrie-research:
`poetry.lock` tracked, CI uses `./.github/actions/setup-poetry`, `uv.lock` is an untracked
leftover — never read the untracked one as truth. Everything else (Phase 3, 5, 7) follows the
Python section with Poetry commands.

---

## Conda (`environment.yml`)

**Phase 0 — the manifest and the environment are different things.** A Dependabot conda PR edits
`environment.yml`. On a host whose environment is maintained by hand, merging that PR installs
nothing; the live env and the file drift apart (one 83-file deploy set differed from the host in
exactly one file, `environment.yml`). Establish which governs: the file, the host's
`conda list`, or both.

**Phase 5 — the solver is the finding.** Before applying anything:

```shell
conda install -n <env> --dry-run <pkg>=<new>
```

Read the whole transaction, not the one line you asked for. A test-only psycopg2 patch bump
would have moved libpq 17 → 18, libgcc/libstdcxx 14 → 16 and openssl 3.5 → 3.6 — ~30 MB of
churn onto a production-adjacent host — and another dry run moved openssl although the
dependency lists were identical. Churn beyond the requested package is the real risk of the bump
and belongs at the top of the report.

**Phase 7 — apply one package, never re-solve.** `pip install --no-deps <pkg>==<new>` for a pip
package inside the env; `conda remove --force <pkg>` where a plain `conda remove` wants to take
dependents with it (it tried to remove pydantic along with dash-extensions). Never run an env-wide
update to land a single bump.

**Phase 9** — before any post-merge test on the host, assert installed version == declared
version. A post-merge pytest run on the old installed version proves nothing about the bump.

---

## npm / Node

**Phase 0 — where declared.** `package.json` plus the lockfile. The lockfile is what actually
installs; a `package.json` range bump with no lockfile change installs nothing new.

**Phase 3** — grep `import`/`require` plus config files that name the package (bundler, lint,
test runner configs).

**Phase 3 — also read the declared support of the tools that consume the package, wherever it
lives.** For a compiler or runtime bump (TypeScript, Node), the tools that analyse your code —
dependency-cruiser, ESLint parsers, type-aware linters — each declare which versions they
support. That declaration may be `peerDependencies` / `peerDependenciesMeta`, or a tool-specific
field: dependency-cruiser uses `supportedTranspilers` in its own `package.json`
(`npm view dependency-cruiser@<v> supportedTranspilers`), with no peer entry at all. Read the
consumer's own field, its docs, or its runtime warning against the new version; "no peer
declared" is not "compatible".

**Phase 5/7** — `npm test`, `npm run build`. For a transitive bump with no direct usage, `npm ls
<pkg>` shows who actually pulls it in, which is usually the real answer to "does this reach us".

**Gate input counts** (SKILL.md Phase 5, case study 5): dependency-cruiser prints its count as
`N modules, M dependencies cruised` — compare it between base and bump branch. A gate that can
go vacuous should be made to fail on zero inputs; offer the fix, e.g.
`depcruise ... --output-type json | jq -e '.summary.totalCruised > 0'`.

**Platform-optional packages** (TypeScript 7 ships a native payload as one
`@typescript/typescript-<platform>` optional package per OS/CPU) appear as ~20 new rows in the
lock diff: one native payload, not 20 new dependencies.
