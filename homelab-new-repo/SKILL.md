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
```

**The topics are load-bearing, not decoration.** Renovate autodiscovers by the `homelab` topic and
`flux-system/dr-reseed.sh` derives its repo list from it. A repo without them is silently never
scanned and silently never restored after a cluster rebuild.

Then substitute, in file contents **and in filenames**:

```shell
cd ~/Projects/NAME
git mv NAME-source.yaml        <name>-source.yaml
git mv NAME-kustomization.yaml <name>-kustomization.yaml
grep -rl NAME . --exclude-dir=.git | xargs sed -i "s/NAME/<name>/g"
grep -rn NAME . --exclude-dir=.git   # must print nothing
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

Then the local gates before pushing — they are cheap and they are what CI will run anyway:

```shell
kubectl kustomize .                                 # builds; count the objects
flux schema validate . --config .fluxschema.yml     # all valid
flux migrate -f . --yes && git diff --stat          # must be empty
```

Commit and push, then register with Flux:

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

## Finish by saying what you did not do

The template deliberately ships these as `TODO`, because none can be generated:

- the repo's own manifests, and the `resources:` list in `kustomization.yaml`
- the value-contract step in `.github/workflows/ci.yaml` — the repo's own invariants, kept short:
  only things that fail silently, late, or in another repo
- `README.md` and `CLAUDE.md` bodies
- the monitor for anything exposing metrics, which ships in the same commit as the workload

Tell the user which of these remain rather than leaving them to discover it from a red CI run.
