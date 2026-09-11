---
name: homelab-new-repo
description: >-
  Create a new Flux cluster-content repository in the Blue-Sharp home lab from the
  Blue-Sharp/homelab-template GitHub template — scaffolds the files, substitutes the NAME
  token, creates the namespace, mints the read-only Flux deploy key, re-seals the Discord
  webhook, and registers the repo with Flux. Use this whenever the user wants to add a new
  piece of software to the cluster, mentions "new repo", "new namespace", "add <software> to
  the cluster", "self-register with Flux", or asks how to onboard anything into the home lab —
  even if they don't name the template. Also use it when they ask what a new cluster repo
  needs, since the answer is "run this and it does the parts that can be automated".
  Do NOT use it for disaster recovery of EXISTING repos — that is flux-system/dr-reseed.sh.
---

# Adding a cluster-content repo to the home lab

This automates the checklist in `flux-system/README.md`. Most of it is mechanical, and the
mechanical part is exactly where it has gone wrong before: the three most recently created repos
all silently missed `.claude/settings.json`, and a repo built by copying a sibling by eye shipped
two naming defects. The template fixes what can be inherited; this skill fixes what has to be
generated or created in the cluster.

## What you cannot decide for the user

Ask before doing anything. These are the only real inputs, and guessing either one produces a repo
that looks right and fails later:

1. **The name.** Repository name == namespace name, always. It is also the `secretRef.name` and the
   `sourceRef.name` — one token, `NAME`, drives every mechanical field and two filenames.
2. **What it `dependsOn`.** `kube-system` is always there (it carries sealed-secrets, without which
   no SealedSecret in the repo ever unseals). Anything else depends on what the repo contains — a
   Postgres `Cluster` needs `cnpg-system`, a `Redis` needs `redis-operator`, a plain HelmRelease
   usually needs nothing more. **Ask; do not infer from the name.** Get this wrong and the objects
   are applied before their CRDs exist, and the Kustomization fails in a way that reads like a
   manifest error.

## The sequence

```shell
gh repo create Blue-Sharp/NAME --private --template Blue-Sharp/homelab-template
gh repo edit   Blue-Sharp/NAME --add-topic homelab --add-topic kubernetes
git clone https://github.com/Blue-Sharp/NAME ~/Projects/NAME

# Git identity is set PER REPO in this lab -- there is no global user.name, deliberately,
# because this machine carries several identities and a global one would silently sign
# unrelated clones with the wrong name. A fresh clone therefore inherits nothing, and the
# first commit below fails with "Identität des Autors unbekannt" rather than anything that
# points at the cause. Copy it from a sibling instead of typing it: all repos in the set
# agree, so there is no value to choose.
git -C ~/Projects/NAME config --local user.name  "$(git -C ~/Projects/homelab config --local user.name)"
git -C ~/Projects/NAME config --local user.email "$(git -C ~/Projects/homelab config --local user.email)"
```

**The topics are load-bearing, not decoration.** `flux-system/dr-reseed.sh` derives its repo list
from `homelab`, and `homelab`'s `architecture.yaml` checks every repo carrying it. A repo without
them is silently never restored after a cluster rebuild. (Renovate does NOT use the topic — it
scans any org repo that ships a Renovate config, which the template's `.github/renovate.json` is.)

**Check once, on the first run after 2026-09-10:** `gh run list -R Blue-Sharp/NAME --limit 3`
must show the "Initial commit" CI run as *skipped*, not failed. The template's `ci.yaml` guards
each job with `!(github.event.created && github.ref == 'refs/heads/main')` so GitHub's own
template commit no longer mails a red run; that `created` is `true` on a template-generation push
is inferred, not yet observed. If it ran and failed, the guard does not work — fix it, then delete
this paragraph. If it was skipped, just delete this paragraph.

Then substitute, in file contents **and in filenames**:

```shell
cd ~/Projects/NAME
git mv NAME-source.yaml        <name>-source.yaml
git mv NAME-kustomization.yaml <name>-kustomization.yaml
# WORD-BOUNDED, both of them. A bare s/NAME/.../g also rewrites prose merely CONTAINING the
# token -- the template's own "TWO NAMES FOR ONE TOOL" became "TWO <name>S FOR ONE TOOL" in
# every repo created before 2026-09-10, and the check below could not see it, because a
# mangled word no longer contains NAME. Fixed here and in the template's self-test together.
grep -rl NAME . --exclude-dir=.git | xargs sed -i "s/\bNAME\b/<name>/g"
grep -rnw NAME . --exclude-dir=.git   # must print nothing
```

That last line matters more than it looks. `NAME` is chosen to be greppable precisely so an
unsubstituted one fails loudly instead of looking plausible.

Now the parts a template cannot carry:

```shell
kubectl create namespace <name>

# NOTE THE 2>&1 -- flux prints the key on STDERR. A plain pipe yields an EMPTY file, and gh then
# answers 422 "key is invalid", which reads like a key problem and is not one.
flux create secret git <name> --namespace <name> \
  --url=ssh://git@github.com/Blue-Sharp/<name> 2>&1 \
  | sed -n 's/^✚ deploy key: //p' > /tmp/<name>.pub
gh repo deploy-key add /tmp/<name>.pub --repo Blue-Sharp/<name> --title flux-<name>   # read-only
rm /tmp/<name>.pub
```

The Discord webhook must be **re-sealed**, never copied: kubeseal's default scope binds the
ciphertext to namespace *and* name, so another repo's file cannot decrypt here. Read the plaintext
from a live Secret and re-seal in one pipeline so it never touches disk:

```shell
kubectl -n postgres get secret discord-webhook -o jsonpath='{.data.address}' | base64 -d \
  | kubectl create secret generic discord-webhook --namespace <name> \
      --from-file=address=/dev/stdin --dry-run=client -o yaml \
  | kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system \
      --format yaml > discord-webhook-sealedsecret.yaml
```

Then the local gates — they are cheap and they are what CI will run anyway:

```shell
kubectl kustomize .                                 # builds; count the objects
flux schema validate . --config .fluxschema.yml     # all valid
```

Commit **first**, then run the deprecated-API gate. That order is not a preference — the gate
compares the working tree against the last commit, so on a fresh clone with everything still
uncommitted it reports your own scaffolding (ten files, dozens of lines) and tests nothing.
Run before committing, it cannot fail, which is worse than failing.

```shell
git add -A && git commit
flux migrate -f . --yes && git status --porcelain   # must be empty
git push
```

**Read CI by commit SHA, never `--limit 1`.** A repo created from the template already has one
completed run — the template's own scaffolding, which FAILS, because `NAME` is unsubstituted and
`discord-webhook-sealedsecret.yaml` does not exist there. `gh run list --limit 1` hands you that
run, already `completed`, so a naive wait loop exits immediately on someone else's failure:

```shell
sha=$(git rev-parse HEAD)
gh run list --repo Blue-Sharp/<name> --limit 10 \
  --json headSha,status,conclusion,databaseId \
  --jq ".[] | select(.headSha==\"$sha\")"
```

Then register with Flux:

```shell
kubectl apply -f <name>-source.yaml -f <name>-kustomization.yaml
flux reconcile kustomization <name> -n <name> --with-source
```

## Two traps worth stating plainly

**Let Flux create the workload objects.** It is tempting to `kubectl apply` a manifest to test it
and let Flux adopt it afterwards. Adoption costs one rolling restart, because Flux stamps inventory
labels onto the object and some operators propagate labels into a pod template. It is free for a
stateless cache and not free for anything holding data. Push first, let Flux apply, then verify by
reading the running pod.

**`Ready` means applied, not working.** A Kustomization goes green the moment the API server accepts
the manifest — while the workload behind it authenticates with the wrong password or scrapes
nothing. Verification means asserting a positive count (`count(up{job="..."}) == 1`), never reading
an empty result as health.

## Before adding manifests to the new repo

The repo is now a valid shell with no content. Before writing its manifests, run the convention
survey the shared invariants require: a read-only agent that enumerates conventions across all
repos **and the live cluster** and reports deviations. Copying the nearest sibling by eye is what
produced the defects this template exists to prevent.

**One naming decision the survey will surface, worth knowing before you hit it.** A repo whose
software brings its own Helm chart ends up with two source objects, and they collide by default:

| software name vs repo name | chart's `HelmRepository` | self-registration `GitRepository` |
|---|---|---|
| **same** (`redis-operator`, `cert-manager`, `traefik`, `descheduler`) | `<name>-chart-source.yaml` | `<name>-source.yaml` |
| **differ** (`cnpg-system`/`cloudnative-pg`, `kube-flannel`/`flannel`) | `<software>-source.yaml` | `<repo>-source.yaml` |

The `-chart-source` spelling is the collision case only, NOT the general rule. No CI check holds
you to either spelling, and getting it wrong in the other direction fails silently: Renovate's flux manager only scans `*-source.yaml`, so a chart source
named anything else silently stops being version-scanned, with no error anywhere.

## Finish by saying what you did not do

The template deliberately ships these as `TODO`, because none can be generated:

- the repo's own manifests, and the `resources:` list in `kustomization.yaml`
- `.node-placement.yaml` — ships as an empty `objects: []`, and the build fails the moment a
  workload renders with no entry in it, which is the point
- the value-contract step in `.github/workflows/ci.yaml` — the repo's own invariants, kept short:
  only things that fail silently, late, or in another repo
- `README.md` and `CLAUDE.md` bodies
- the monitor for anything exposing metrics, which ships in the same commit as the workload

Tell the user which of these remain rather than leaving them to discover it from a red CI run.
