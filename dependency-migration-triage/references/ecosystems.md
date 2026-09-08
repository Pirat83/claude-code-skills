# Ecosystems: resolving phases 0, 3 and 5/7

The phases in SKILL.md are ecosystem-agnostic. Three of them need one concrete answer each:
where the version is declared, what "usage" means, and how to become the coverage when nothing
else does. Read the section you need before Phase 0. If a bump spans two columns — a chart whose
`appVersion` moves the image, say — read both.

---

## Helm chart, under Flux

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

Then the repo's own gates: `flux schema validate . --config .fluxschema.yml`, and the shared
policy job if the lab has one. Reconcile order when you do go live is source → Kustomization →
HelmRelease; forcing a HelmRelease against a stale source just makes you fight the old spec.

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
- **Base distro changed**, taking a shell, a CA bundle, or a libc with it.

**Phase 5/7 — run it.** `podman run --rm --entrypoint sh <image>:<new> -c 'id; ls -la <datadir>'`
against both tags is usually the whole experiment.

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

**Phase 5/7 — run the workflow on a branch.** For an action used by many repos, run one caller
and read the log rather than reasoning about all of them.

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
imports, call sites, and config keys naming the tool.

**Phase 5/7 — the real toolchain**: `pytest`, `mypy`, `ruff`, an actual docs build. For a tool
whose job is deciding whether code is correct (type checker, linter), running the new version
against the real codebase is the only way to find behaviour changes — see case study 1.

For numeric or compiled dependencies, "tests pass" may be too weak a claim if determinism is a
shipped feature: compare full-precision outputs or hashes across both arms, not just exit codes.

---

## npm / Node

**Phase 0 — where declared.** `package.json` plus the lockfile. The lockfile is what actually
installs; a `package.json` range bump with no lockfile change installs nothing new.

**Phase 3** — grep `import`/`require` plus config files that name the package (bundler, lint,
test runner configs).

**Phase 5/7** — `npm test`, `npm run build`. For a transitive bump with no direct usage, `npm ls
<pkg>` shows who actually pulls it in, which is usually the real answer to "does this reach us".
