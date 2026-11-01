# Tree health: the delta of every bump, and the checks that only a new package or a major earns

Serves the skill's goal: triage this bump safely and keep the dependency tree as small and healthy
as possible. There is no audit mode. Every triage computes the **tree delta** of its bump (section
1, cheap, always). Section 2 is one optional note, never blocking. Section 3 runs only when a NEW
package enters the tree or the bump is a MAJOR. Section 4 covers infrastructure trees.

Legend: **run** = executed on a real repo (checked 2026-11-01, or earlier research);
*unverified* = from documentation or knowledge, not executed. Tools that are not installed run via
`uvx`, `npx --yes`, `podman run --rm` (add `:z`/`:Z` to bind mounts on SELinux, and a `docker.io/`
prefix because short names fail without a TTY), or a release tarball checked with `sha256sum -c` in
a scratch bin dir. Never install into the project.

---

## 1. Always: the tree delta of the bump

**Lockfile diff, base vs PR head.** The bot's PR title names one package; the lock names all that
moved. Scripts in `<skill-dir>/references/scripts/` (both **run**, verbatim as shipped; the
arguments are a repo and two git revisions, not two lock files):

```shell
python3 -I <skill-dir>/references/scripts/uvlockdiff.py  <repo> <revA> <revB>   # uv.lock; Python >= 3.11
sh <skill-dir>/references/scripts/npmlockdiff.sh         <repo> <revA> <revB>   # package-lock.json v2/3; needs jq
```

Output is `name: old -> new`, `-` = absent. Appeared and vanished rows are the point: a package
`- -> v` is a new tree member (section 3 applies), one `v -> -` may unblock a removal. uv.lock
multi-version packages print as sets (that branch has no real-diff test). npm rows are per
`node_modules` path, so a nested duplicate is its own row; os/cpu-gated optional packages (a
native payload shipped as 20 `@scope/pkg-<platform>` rows) install one per host: judge them as
one payload. The scripts cover uv and npm only; Poetry/conda: diff `poetry.lock` /
`conda list --explicit` by hand (*unverified*).

**Diff what production installs, not only the lock.** A dev-only change can fill the lock diff
while the image does not move, and the reverse:

```shell
# in a scratch worktree per revision (git worktree add $SCRATCH/a <revA>), then:
uv export --frozen --no-dev --no-emit-project --no-hashes > prod-<rev>.txt
diff prod-<revA>.txt prod-<revB>.txt
```

Example
(walkuere, quantstats bump): the lock lost 15 packages, the `--no-dev` export shrank 98 -> 82
lines, because pygments survived only as a dev dependency.

**For every package that moved, appeared or vanished: list ALL parents and the binding
constraint.** A transitive bump is judged by what constrains it, not by the child alone.

```shell
uv tree --invert --package X                                    # all parents; offline from uv.lock (run)
uvx pipdeptree --python .venv/bin/python -r -p X                # parents WITH ranges (run)
curl -s https://pypi.org/pypi/<parent>/<ver>/json \
  | jq -c '.info.requires_dist|map(select(test("X")))'          # same, no env needed (run)
npm explain X                                                   # each parent and its range (run)
```

- **Does a parent actually hold the package back? Ask the resolver:**
  `uv lock --dry-run --upgrade-package X` prints what would move. A parent range is a real
  constraint only if X does not reach the newest version here; otherwise the pin is lock
  staleness and a one-line lock bump fixes it (*run*, `curl-cffi` below).
- `uv.lock` does **not** store registry packages' specifiers (the entry is just
  `dependencies = [{ name = "yfinance" }]`), so `uv tree` gives parents but never the range. The
  range comes from `pipdeptree` (the package must be installed in that venv, "dependency problems
  found" warnings print first and do not change the exit code, and the unlocked venv can differ
  from the lock) or from PyPI `requires_dist` for the parent's locked version.
- Probe once per parent path. A bump that clears the child for parent A says nothing about B.
- **Removal needs every parent gone; but check whether anything binds the version at all.**
  unternehmen-walkuere: `yfinance` is never declared nor imported; `uv tree --invert --package
  yfinance` shows it arrives only via `lib-pybroker` and `quantstats`, and it drags in
  `curl-cffi` 0.11.1 (PYSEC-2026-2431, fix 0.15.0). Nothing binds `curl-cffi`:
  `uv lock --dry-run --upgrade-package curl-cffi` resolves 0.16.3 (cffi 1.17.1 -> 2.1.1). The
  vulnerable leaf is stale-lock only, fixed by a small lock bump; removal would need both
  parents gone.
- **npm duplicates.** freelance-automation: root `undici@8.12.3` beside `undici@7.30.0` under
  `cheerio@1.2.0` (`^7.19.0`), found by `npm explain undici`. A bump that fixes the root copy
  leaves the nested one; `npm dedupe --dry-run` shows what could merge (here it failed on an
  engine mismatch, retry with `--engine-strict=false`; *unverified* beyond that failure).

**Vulnerabilities on the new lock** (run all three on the PR head, compare with base):

```shell
podman run --rm -v $PWD/uv.lock:/s/uv.lock:ro,Z ghcr.io/google/osv-scanner:latest scan source -L /s/uv.lock   # run
uv export --frozen --no-emit-project --no-hashes -q > req.txt \
  && uvx pip-audit --disable-pip --no-deps -r req.txt                                                         # run
npm audit                                                                                                     # run (CI had it)
```

**Dependabot may never alert on an advisory that GitHub reviewed under a GHSA id**, and Renovate's
`osvVulnerabilityAlerts` sees direct dependencies only, so osv-scanner on the lock is the
backstop for a transitive vulnerable version, run on every triage that touches a lock.
osv-scanner reads `uv.lock` and `package-lock.json` directly (91 and 333 packages), exit 1 =
findings, 0 clean, 128 = nothing scannable; it needs the network and marks npm dev deps
`(dev)`. Its "fixed version" is the lowest fixed release, which may be a major jump, not a safe
bump. It agreed with pip-audit on walkuere: `curl-cffi 0.11.1` and `diskcache 5.6.3` (PYSEC-2026-2447,
no fix); pip-audit lists each twice. `npm audit` has known false positives. Mount the single file
read-only; the table shows `s/uv.lock`. No conda-lock support: pip-audit on `pip freeze` (*unverified*).

---

## 2. Optional tree note (reported, never blocking)

Declared versus imported, and scope. Report what the bump makes newly visible; do not turn
pre-existing noise into a blocker.

**Python: deptry** (**run**). It maps imports to distributions through the interpreter's installed
metadata, so it MUST run in the project env:

```shell
uv run --no-sync --with deptry deptry .      # walkuere: 3 issues; bare `uvx deptry .`: ~120 bogus DEP001
```

- Outside the env it reported 120 to 124 `DEP001` ("`alpaca` imported but missing", the dist is
  `alpaca-py`). Poetry has no `[project]`, so use the Poetry env: `poetry run deptry .`
  (valkyrie-research: 81 issues, mostly notebooks).
- uv workspace: run per member directory; a virtual root has no `[project]`. The namespace package
  `valkyrie` gives DEP003 false positives (`--per-rule-ignores DEP003=valkyrie`).
- Dev classification: `[dependency-groups]` and Poetry groups are read as dev. `[project.optional-
  dependencies]` count as regular unless `--optional-dependencies-dev-groups tests,docs`. The
  `--help` text says `--dev-optional-dependencies` (stale); `--pep621-dev-dependency-groups` is
  deprecated.
- Expected noise: deliberately declared runtime-only deps (walkuere, as of 2026-11-01:
  `psycopg-binary`, `py-spy`, `numba`). Do not fix them silently; document the ignore with its
  reason: `[tool.deptry.per_rule_ignores]` `DEP002 = ["numba", "py-spy"]` (CLI
  `--per-rule-ignores "DEP002=numba|py-spy"`, **run**: 3 issues became 1).
- deptry does not flag `yfinance` in walkuere: nothing imports it and nothing declares it. Only the
  tree walk in section 1 finds that.
- conda `environment.yml` is not supported by deptry; FawltyDeps conda support is *unverified*.
  Fall back to `pipdeptree` plus a grep of imports.

**npm: knip** (**run**; depcheck is archived):

```shell
npx --yes knip --strict       # a runtime import of a devDependency shows only here, as "unlisted"
```

Plain `knip` reports only the unused devDependency, `--production` alone reports nothing. Strict
excludes tests and config importing dev deps, which is the wanted behaviour. freelance-automation
already has `knip` as a devDependency with a `dead` script; its run was clean.

**Scope.** Is the package in the right place: runtime vs dev vs peer vs optional vs extra? A
package that only tests import belongs in a dev group (deptry DEP004, knip strict). **Does an extra
pull more than the code uses?** Diff the trees:

```shell
uv tree --package bigtree                       # run (offline)
# compare with the same command on a resolution without the extra; extras' own lines:
curl -s https://pypi.org/pypi/<pkg>/<ver>/json | jq -r '.info.requires_dist[]|select(test("extra == \"all\""))'   # run
```

---

## 3. Only for a NEW package or a MAJOR

A transitive that merely moved patch or minor skips this section. Run it on the package that
entered the tree, or on the major, and put the answers in the report. **Major includes 0.x**: in
0.y.z a minor (0.y) bump is treated as major (semver section 4), and a 0.0.z bump as potentially
breaking every time. Also run the EOL row whenever a running component is within about 30 days
of its EOL, whatever kind of bump this is (PostgreSQL 14: EOL 2026-11-12).

| Check | Command | Notes |
|---|---|---|
| Licence change | `curl -s https://api.deps.dev/v3/systems/pypi/packages/<p>/versions/<v> \| jq .licenses` for both versions, `npm` under `/systems/npm/` | **run.** PyPI classifiers are noisy ("non-standard" for yfinance) |
| Provenance, PyPI | `curl -s https://pypi.org/integrity/<pkg>/<ver>/<file>/provenance` | **run.** 404 = none; pip-audit 2.10.1 had a bundle, `uv 0.9.0` none |
| Provenance, npm | `npm audit signatures`; deps.dev `slsaProvenances` / `attestations` | **run** (108 verified on freelance-automation). `slsaProvenances` is npm-only |
| Install scripts | `npm query ':attr(scripts,[postinstall])'` (also `[install]`, `[preinstall]`) | **run** (found `@googleworkspace/cli`) |
| Upstream health | deps.dev version `projectStatus` (PyPI only, null on npm); project: `/v3/projects/github.com%2Fpsf%2Frequests` | **run.** Slash MUST be `%2F`. `scorecard` is absent for small repos (curl_cffi, sigstore-js): optional, and dated, not live. A `-1` check = failed to run |
| Yanked / abandoned | `jq '.urls[].yanked'` on PyPI JSON; release dates from PyPI/npm `time` | yanked **run** (false) |
| Publisher change | `npm view <pkg> maintainers`, `_npmUser` | *unverified*; no cheap PyPI equivalent known |
| EOL | `curl -s https://endoflife.date/api/v1/products/<p>/releases/<r>` | **run.** Use **v1** (`isEol`, `eolFrom`, `isMaintained`, `latest`); legacy `/api/<p>.json` still answers with `eol`, flat. Many dev tools are absent (`typescript` is a 404): fall back to the upstream support policy and release cadence |
| Fetches at build/install time | `pip download <pkg>==<v> --no-deps --no-binary :all:`, then read `pyproject.toml` `build-backend` | An sdist-only package whose custom PEP 517 backend downloads at build time is a network-at-install dependency. *Observed*: `dbt-core-experimental-parser`, a 4.7 KB sdist whose backend pulls a 174 MB hash-checked binary from GitHub; found via the installed `RECORD` size. Note it (install needs network; reproducibility) |

deps.dev version keys: `advisoryKeys, attestations, deprecatedReason, isDefault, isDeprecated,
licenses, links, projectStatus, publishedAt, registries, relatedProjects, slsaProvenances`.
Advisory detail: `/v3/advisories/<GHSA>` gives aliases and `cvss3Score`.

---

## 4. Infrastructure trees

The same questions, different graph: what is really deployed, who names it, who can see it.

**Chart-default images are invisible to both bots** (bots.md, "Invisible to both", owns the
explanation, the dagster `postgres:14.6`/`busybox:1.28` example and the `helm template | grep
image:` audit). The point here: they still run, so inventory and EOL-check them below.

**Running-image inventory** (**run**, read-only):

```shell
kubectl get pods -A -o json | jq -r '.items[].spec | (.containers + (.initContainers // []))[].image' | sort -u
```

On the home lab: 64 distinct images, 9 digest-pinned, 55 tag-only, 0 `:latest`. Duplicates worth a
look: `k8s-sidecar` from two registries at one tag, `busybox` at `1.28` and `stable`, Postgres at
three lines. This lists spec images; resolved digests are in `status.containerStatuses[].imageID`
(not queried). Compare with the rendered set to find the undeclared ones above. EOL check per
image with section 3's endoflife call (Postgres 14 EOL 2026-11-12 was found this way).
`trivy image <img>` as a one-off over the set is *unverified* (not installed).

**Deprecated APIs: pluto** (**run**, `detect-files`). No container image exists
(`quay.io/fairwinds/pluto:v5.24.4` is unknown); download the release tarball and check it:

```shell
gh release download v5.24.4 -R FairwindsOps/pluto -p 'pluto_5.24.4_linux_amd64.tar.gz' -p checksums.txt
sha256sum -c --ignore-missing checksums.txt
pluto detect-files -d . --target-versions k8s=<cluster-version> -o wide
```

Exit 2 = deprecated, 3 = removed, 4 = deprecated with no replacement. Without `--target-versions`
pluto uses a built-in default, not the cluster. It reads literal manifests only: HelmRelease values
and chart contents are not rendered, so run it on the `helm template` output
(`helm template ... | pluto detect -`, *unverified*). `detect-helm` reads release secrets from the
live cluster (*unverified*, no cluster contact). Control: a `policy/v1beta1` PodDisruptionBudget
gives exit 3. `flux migrate -f . --dry-run` covers Flux CRs (**run**: "no custom resources found
that require migration"; the homelab CI already runs it).

**Actions workflows** (**run**, on homelab):
- `uvx zizmor .github/workflows/`: exit code is a severity bitmask, not 0/1; gate with
  `--min-severity medium`. Offline: 28 findings. `GH_TOKEN=$(gh auth token)` enables online audits
  (40, adds `ref-version-mismatch`; private repos warn on `impostor-commit`). `github-app` and
  `artipacked` are noisy (intentional broad app tokens; later steps needing git credentials).
- `podman run --rm -v $PWD:/r:ro,Z -w /r docker.io/rhysd/actionlint:latest`: `docker.io/` is
  required; `-w /r` is how it finds the workflows. SC2012/SC2086 info items are noise
  (`-ignore 'SC2012'`).
- `pinact run --fix=false --no-api <files>` (both flags; pass files one per argument): exit 2 on an
  unpinned action; `Blue-Sharp/homelab/...@<sha> # main` is flagged "requires a version comment".
  Renovate `pinGitHubActionDigests` already pins, so use pinact only to audit.

**Ansible.** A versionless `requirements.yml` collection is invisible to both bots (bots.md,
"Invisible to both"); add ranges (`version: ">=x,<y"`) so Renovate sees them. Also **run**:
`ansible-lint` warned that system collections (`ansible.posix` 1.6.2 under
`/usr/lib/python3.14`) shadow the installed 2.2.2, an implicit dependency. For an extraction
check of any Renovate config see bots.md, "Renovate local dry run".

---

## 5. Per-ecosystem tool table

| Ecosystem | Tree delta | Declared vs imported | Vulnerabilities | Health (new/major only) |
|---|---|---|---|---|
| uv | `uvlockdiff.py`, `uv tree --invert`, `pipdeptree -r` | deptry in-env (**run**) | osv-scanner on `uv.lock`, pip-audit via `uv export` (**run**) | deps.dev, PyPI provenance (**run**) |
| Poetry | `poetry.lock` diff (*unverified*), `poetry show --tree` (*unverified*) | `poetry run deptry .` (**run**) | pip-audit on `poetry export` (*unverified*) | as uv |
| npm | `npmlockdiff.sh`, `npm explain` (**run**) | `knip --strict` (**run**) | `npm audit`, osv-scanner (**run**) | `npm audit signatures`, install-script query, deps.dev (**run**) |
| conda | `conda list --explicit` diff, `pipdeptree -r` (*unverified*) | none verified | pip-audit on `pip freeze` (*unverified*) | deps.dev |
| Helm / Flux | `flux tree`, `helm dependency list` (*unverified*) | rendered images vs repo pins | pluto on the render; `trivy config` (*unverified*) | `flux check --pre`, endoflife.date (**run**) |
| Images | running inventory (**run**) | declared vs running image set | `trivy image` (*unverified*) | endoflife.date, digest pins |
| Actions | `pinact` (**run**) | n/a | zizmor, actionlint (**run**) | Scorecard via deps.dev (**run**) |
| Ansible | `ansible-galaxy collection list` (*unverified*) | grep FQCN modules vs `requirements.yml` (*unverified*) | `pip-audit` for pip deps; no collection CVE DB | version ranges so Renovate sees them |
