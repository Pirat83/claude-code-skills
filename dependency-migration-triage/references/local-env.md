# The local environment follows the bump

A merged bump changes the repo, not the machines and local artifacts built from it. In any
lockfile repo whose CI and production install fresh, CI and the image follow every bump by
construction; the **developer environment is the one place a bump does not land by itself**.
Green CI proves the pins solve, not that this host matches (a pip overlay once shadowed conda).

Run this once in Phase 9, **after the last merge of a batch**, scoped to what the bump touched.
Case 8 in case-studies.md is why the step exists. Batch scope: every PR merged in the window
into the checkout's branch, not only the ones the user named (mark the extras).

**Default is read-only: list the drift and print the commands.** Sync, install, pull and
Ansible apply mutate the host (and a shared venv); run them only on the user's yes. A no-post
or "do not modify any environment" brief means read-only, full stop (section 4).

## 1. What to bring in line

| Touched | Bring local in line | Prove it |
|---|---|---|
| Python deps (uv / Poetry / npm) | `uv sync --frozen` in every worktree that runs gates or commits; `poetry install --sync`; `npm ci` | in-process `pkg.__version__` / `importlib.metadata.version()` / `npm ls <pkg>` equals the lock |
| Derived artifacts | `dbt parse` per project after a dbt-core bump; regenerate codegen/stubs; `pre-commit install` after hook bumps | **version-aware**: a gate passing on a stale artifact proves nothing (a 1.11.11 manifest passes as current under 1.12.6). For dbt, every `target/manifest.json` has `metadata.dbt_version` == the installed dbt |
| Local dev stack (compose/podman) | `podman compose pull && up -d`; a dev-DB **major** is a migration (dump/restore), not a pull | image digest / `select version()` equals the declared tag |
| Workstation CLIs pinned in Ansible (flux, flux-schema, kubectl, helm, kubeseal) | `ansible-playbook ... --tags <tool> --check --diff`, then the real run (**user-run**) | **every** binary on PATH (`which -a flux`; two exist, `/usr/local/{bin,sbin}`) reports the pin, and it equals the cluster |
| Hand-managed host envs | single-package install (existing conda rule) | installed == declared |
| IDE | re-sync the project interpreter **and** the module SDKs after `pyproject` changes; never hand-edit `.iml`. Look for stale interpreters pointing at retired envs (PyCharm: module SDK in `.iml`, project SDK in `misc.xml`, cached versions in `~/.config/JetBrains/*/options/jdk.table.xml`) | the IDE resolves the bumped import; no SDK references a retired env (example: a PyCharm project still on the old conda env, Python 3.12.10, quantstats 0.0.62). A leftover side env is retire-or-sync: say which |

Evidence behind the rows (author's projects, as examples): after a dbt-core bump an old
`target/manifest.json` reddened a test; the gate's pyright resolves via `<worktree>/.venv`, so a
committing worktree needs its own `uv sync --frozen`; PyCharm module deps are regenerated from
`pyproject`.

## 2. Worked procedure: a shared uv venv (unternehmen-walkuere, 2026-11-01)

Host-specific details below (paths, tools that need a manual download) are examples from the
author's machine; read yours.

0. **Re-read the target first, read-only.** `git fetch`, then compare against the current
   `origin/main`, not the merged SHA from the brief: main moves (a later commit may re-add a
   package the merge dropped; walkuere #105 re-added ipykernel/ipython). Also name the
   checkout's branch: if it is not the default branch (an unrelated PR's branch can be checked
   out), compare the venv to *that branch's* lock and say the venv reflects it, not main.
1. **Nobody is using the env.** The `.venv` is shared by every session on the checkout:
   `ps -eo args | grep -F "<repo>/.venv" | grep -vc grep` must print 0. If not, stop and say who.
2. **`git pull --ff-only`** on the main checkout so the lock and `.python-version` are current.
3. **Interpreter first, when `.python-version` moved:** check what exists
   (`uv python find <ver> --managed-python`, or the venv's `pyvenv.cfg`), then
   `uv python install <ver>`. uv-managed CPython matches the official image; a distro python of
   the same version differs. On the author's host uv python downloads are manual (user-run).
4. **Exact sync:** `uv sync --frozen --python <ver> --managed-python`. An exact sync removes
   packages the lock dropped (`ipython` and 14 dependencies in the case).
5. **Prove it** against the **current** lock, dev group included:
   - `uv sync --frozen --check` prints "Would make no changes"
   - `.venv/bin/python -V` equals `.python-version`
   - `importlib.metadata.version("<pkg>")` equals the lock for each bumped package
   - for each package the lock dropped from the **runtime** set (`--no-dev`, i.e. the image),
     `find_spec` is None only if the *current* lock still lacks it; a later commit that
     re-adds it makes a present package correct
6. **Full test suite from the synced venv**, not from a `PYTHONPATH`/`--target` overlay — the
   overlay used during triage proved the wheels, not the environment.

Committing worktrees (the ones whose gate runs pyright or tests) get their own
`uv sync --frozen`; do not point them at the shared venv.

## 3. Second example: Flux, four pins and no bot

Four pins of one version that no bot follows together: Ansible `workstation_flux_version`
(`roles/workstation/defaults/main.yml`), homelab `manifests.yaml` `version:`, flux-system
`gotk-components.yaml`, and the cluster controllers themselves. A Flux bump is **one coupled
change**, and its last step is the local CLI: Ansible `--check --diff`, the real run
(user-run), then `which -a flux` and `flux version` against the cluster.

## 4. Shared-machine hygiene

- Check that nothing runs from an env before recreating or exact-syncing it (step 1).
- Triage itself must not touch the shared env: test wheels on a scratch `PYTHONPATH`
  (`uv pip install --target <scratch> --no-deps`). That is exactly what makes the
  post-merge catch-up a separate, explicit step.
- Anything needing sudo, a download of an interpreter or an Ansible apply is **user-run**:
  give the command, do not run it.
- If a step is skipped (a session still in the env, no network), the report lists the drift
  by package (local vs lock) instead of silently ending at "merged".

## 5. Read-only mode (the default)

`uv sync --check` and running `.venv/bin/python` touch or execute the shared venv, so a
read-only run substitutes:
- compare the `.venv/lib/python*/site-packages/*.dist-info` names and versions with the lock
  (`uv export --frozen --no-hashes`), excluding packages whose platform markers do not apply
  here (appnope, colorama);
- read the interpreter from `pyvenv.cfg`, not by running it;
- read the deployed version from the image digest (`podman run` of the same `sha256`): it proves
  the image, not the running process, so say so. Do not `kubectl exec` where that is
  approval-gated;
- for dbt, read `metadata.dbt_version` from each `target/manifest.json` and compare with the
  installed dbt.
Report the drift by package (local vs lock) and print the fix commands (sections 1-2).

## 6. Deferred post-merge check (an issue)

When the earliest run time falls after the session ends, open an issue labelled
`post-merge-check` (labels first: `gh label list`, bots.md "Labels must exist"; creating the
issue needs the user's yes). Body template:

```
Merged: <PR>, head <sha>. Level: <triage level>.
Baseline: <numbers/versions to record> — take it BEFORE <scheduled job, with its time>;
          the baseline has a latest time, the compare has an earliest time.
Compare:  <command> at <earliest time>. Pass if: <criterion>.
If it fails: <revert/hold action>.
```
