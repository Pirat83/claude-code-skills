# Batches and fan-out: triaging many PRs at once

SKILL.md's phases describe one dependency. Most real runs are not one PR: a weekly backlog of
a dozen bot PRs, a Dependabot group, or one shared change — a reusable-workflow digest, a
template commit — that a bot fans out as twenty identical PRs across twenty repos. This file
says what changes when there are many. The phases themselves don't change; what changes is
*how many times* you run them and what you verify per PR instead.

The one rule underneath all of it: **every PR that gets merged, closed or superseded has a
verdict first.** In one run twelve bot PRs, two of them majors, were folded into a branch by a
base change and marked merged with no triage. The user's question afterwards — "so you merged
also the complicated PRs to this branch without /dependency-migration-triage?" — had only one
honest answer. If a PR does get folded in untriaged, say so at that moment, not in the summary.
In another run the user asked "did you run /dependency-migration-triage on them" about twenty
digest PRs judged from green CI and "it is our own change" — both of which SKILL.md rules out
as evidence.

## 1. Inventory

List every PR in scope with its dependency, old → new version, **head SHA**, and the files it
touches. Re-list before you finish: bots keep opening PRs during a long run, and a summary that
says "all open PRs" while three new ones arrived mid-run is wrong.

Then group:
- **By distinct dependency** — two PRs bumping the same thing in different repos are one triage.
- **By shared source** — N PRs that all repoint the same pin ("Update shared-workflow digest to
  3db42e4") are one triage of the range between the old and new pin.
- **By coupling** — a chart PR and its image PR, a library and the plugin that pins it, an
  operator and the CRDs it serves. Coupled PRs get one joint verdict and a fixed order.
- **By staleness** — PRs that edit a file the base branch no longer uses (SKILL.md Phase 0) get
  the verdict *stale* and a note recording what they were holding. Recommend closing them; close
  only when the user has asked or approved.

## 2. Triage each distinct dependency once

Run Phases 0-7 once per group, not once per PR.

**A shared change fanned out across repos.** Triage the upstream range once, completely — and
remember that a digest range is a bump that can *contain* bumps: one range carried a new `gh`
version plus its SHA256, and "I did not confirm the new SHA256 matches" was left in the report.
Then, per repo, verify only what can differ:
1. The PR's diff is exactly the pin lines, nothing else (bot titles go stale; diffs don't).
2. The repo's base branch hasn't moved in a way that interacts (a conflicting edit, a removed
   file).
3. The repo's CI actually consumed the new pin — the new SHA or version appears in the job log.
   A green check from a run on the old pin proves nothing; re-trigger it.
4. Whether the change can reach the running system at all — whether the deploy tooling consumes
   that path (a GitOps Kustomization that never includes `.github/` cannot be affected by a CI
   pin).

**Fanning out to subagents.** For a large batch, one agent per group is the fast path. Pick the
tier per group: the cheapest model for mechanically verifying N identical digest PRs against a
known range, a mid tier for a real triage, and the coordinating loop for the joint verdict.
Each brief carries:
- the path to this skill and the group's ecosystem row in `ecosystems.md`;
- the fallbacks that keep a phase from being skipped — "no `helm` here" is answered by rendering
  from a container, not by skipping the render;
- an instruction to **contradict the brief** when it is wrong (briefs have carried wrong
  premises, "expect ARC runners", "PlayBook uses bigtree", that agents then corrected);
- the report format: every claim tagged *executed* / *read in the diff* / *inferred*, and a
  mandatory line listing **which phases were not done and why**.

**Treat agent output as claims, not findings.** Before anything is posted, the coordinator
re-runs the one claim each verdict rests on (a fix predicted to pass CI, a "this label still
holds after the join"), and checks every "the repo does not X" against the file. And don't
generalise one PR's observation to the batch: "Dependabot downgrades the lock `revision` from 5
to 3" was reported from one PR and contradicted by four others, where the header was unchanged.
Check each PR.

## 3. Order the merges

- **Security fixes first**; they should not wait behind a queue of cosmetic bumps.
- **Least critical first** for everything else, so a surprise lands on something that can take
  it, and the most-shared lockfile or the vacuous-gate-risk PR last.
- **Coupled pairs in their fixed order** (the chart before the image that needs it; the
  producer before the alerts that consume its new labels).
- **One at a time when PRs share a lockfile.** Each merge makes the next conflict. After each
  merge, wait for the next PR to be rebased and its CI to finish on the new base. GitHub reports
  mergeability as `UNKNOWN` while it recomputes; that is not a conflict.
- **In a GitOps repo, check the system is Ready between merges** (`flux get kustomizations`,
  `flux get helmreleases -A`), so a failure is attributable to exactly one merge.

Re-check each PR's head SHA before merging it (SKILL.md Phase 8). In batches this bites more
often, because runs are longer: one chart PR moved from 92.14.1 to 92.16.0 after triage, and the
delta carried an Alertmanager change dropping default CORS headers.

**Merge exactly the list the user approved.** If your list and theirs differ — "merge the 19
digest PRs" when your own list has 20 — say so before merging, not after.

## 4. Bot mechanics that bite in batches

See `bots.md` → "Bot mechanics" for how to rebase or retrigger each bot (Renovate: checkbox or
`rebase` label, not a comment; Dependabot: comments) and why retargeted heads matter. In batches
one more thing bites:
- **A PR that applied cleanly may be empty by the time it merges** — an earlier merge already
  contained its change. Check the net diff against current base before merging, and close an
  empty PR rather than recording an empty merge as a bump.

## 5. Report

- **One verdict table for the batch**: PR, dependency, verdict, tier of the deciding evidence,
  merge state. That is what the user reads.
- **A short comment on each PR** with its own verdict and the evidence specific to it — for a
  fanned-out shared change, the per-repo checks plus a link to the single full triage.
- **Post without asking per PR, when posting is approved.** Ask once for the whole batch only if
  merge authority, the base branch, or whether this is a no-post run is genuinely unclear. A
  no-post run posts, labels, pushes and merges nothing: it prints the comments and commands.
- Phase 9's commands are collected per batch, with the earliest time each can run.
