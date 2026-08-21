---
name: stack-it
description: >-
  Manage a persistent stack of paused work — plans, progress, and loose ends — so it
  can be resumed in a later conversation. Use when the user says /stack-it, or when they
  want to pause current work to handle an interruption (bug fix, refactoring) and come
  back later. Supports push, pop, show, list, and drop subcommands. Also trigger when the
  user says things like "stack this", "save this for later", "park this work", or
  "resume stacked work".
---

# /stack-it — Persistent Work Stack

You manage a LIFO stack of work snapshots. When the user discovers a bug or a refactor
mid-plan, they push the remaining work onto the stack, handle the interruption, then pop
to resume — often in a different conversation, where none of the original context
survives.

That last part is the whole design constraint. A frame is read by a session that knows
nothing: it did not watch the work happen, cannot see the old conversation, and has no
memory of what was half-finished. Write every frame for that reader. If a detail lives
only in the current conversation, it is exactly the detail that must go into the file.

Frames persist as files in `.claude/plans/stack/`, relative to the project root, so they
survive across conversations and stay scoped to the project.

## Subcommands

Parse the argument string to determine the subcommand. Default to `push` when there is
active work to capture, `show` when there is not.

| Argument | Action |
|----------|--------|
| _(empty)_ or `push` | Push the current plan and progress onto the stack |
| `pop` | Restore the top frame and resume from it |
| `show` | Display the top frame without popping |
| `list` | List all frames with summaries |
| `drop` | Discard the top frame |

---

## Push

Capture the current state of the work as a stack frame.

### Where the state comes from

Two sources, in order of preference:

1. **An active plan file.** If the work came from plan mode, a plan file exists — the
   path was named when plan mode started, typically under `~/.claude/plans/`. Read it and
   copy its content into the frame **verbatim**. Copy rather than link: plan files are
   named per session and get reused or garbage-collected, so a frame holding only a path
   will resolve to the wrong plan, or to nothing, exactly when it matters.
2. **The conversation itself.** If the work was never planned formally, reconstruct the
   step list from what has actually been done and agreed in this conversation.

### Steps

1. **Locate the work.** Identify the active plan file, or reconstruct the step list from
   the conversation. If there is genuinely no in-flight work, say so and stop rather than
   writing an empty frame.

2. **Ask why** (only if not given as an argument) — one line, becomes the `reason`.

3. **Establish progress honestly.** For each step, mark it done, not started, or in
   progress. For anything in progress, ask the user what was actually finished and what
   is half-done. Do not infer this from the plan; the plan says what was *intended*, and
   the gap between that and what exists on disk is the single most expensive thing for a
   fresh session to rediscover.

4. **Sweep for loose ends.** Check, and record what you find:
   - uncommitted changes in **every** repository touched, not just the current one
     (`git status --short` in each)
   - background processes, monitors, or long-running jobs still live
   - anything left somewhere volatile — a scratchpad, `/tmp`, a stopped container, a
     branch that exists only locally

   The test is "would a fresh session with only the repo and this frame find this?" If
   not, it goes in the file.

5. **Determine the frame number** — glob `.claude/plans/stack/*.md`, take the highest
   number and add 1, or start at `001`.

6. **Write the frame** to `.claude/plans/stack/{NNN}.md`. Get the timestamp from
   `Bash("date -u +%Y-%m-%dT%H:%M:%SZ")`:

```markdown
---
frame: {N}
stacked_at: {ISO timestamp}
reason: "{one line}"
project_dir: {absolute cwd}
plan_source: {original plan file path, or "conversation" if there was none}
---

## Why this was stacked

{the reason, expanded to a sentence or two if the user gave more}

## Plan

{verbatim content of the plan file, or the reconstructed step list}

## Progress at the time of stacking

- [x] {step finished}
- [ ] {step not started}
- [~] {step in progress} — {what is done, what is half-done, what to check first}

## Loose ends

{uncommitted work per repository, live background processes, volatile state —
 or "none" if the sweep in step 4 genuinely found nothing}
```

7. **Report.**

```
Stacked frame #{frame} — "{reason}"
  {N} steps: {done} done, {open} open
  Loose ends: {count, or "none"}
Use /stack-it pop to resume.
```

---

## Pop

Restore the top frame and resume the work.

### Steps

1. **Find the top frame** — glob `.claude/plans/stack/*.md`, take the highest-numbered
   file. If none exist, tell the user the stack is empty and stop.

2. **Read it** — parse the frontmatter and all four sections.

3. **Check the project** — if `project_dir` differs from the current working directory,
   warn: "This frame was stacked in {project_dir}, you are in {cwd}. Continue?" Warn
   only; the user may have moved the repo or be working from a worktree.

4. **Surface loose ends first.** Before restoring anything, report what the frame
   recorded as outstanding, and verify it still holds — uncommitted changes may have been
   committed since, background processes are certainly dead. Resuming work on top of
   unreconciled state is how a stacked frame turns into a merge conflict.

5. **Show the summary** — reason, step list with progress, so the user can confirm or
   `/stack-it drop` instead.

6. **Restore the plan.** Write the frame's `## Plan` section back to a plan file so it is
   durable again rather than living only in this conversation, and note the path. Carry
   the progress markers across: a step marked `[~]` resumes with its progress note
   attached, phrased so the next reader knows where to pick up.

7. **Delete the frame file** — the work is live again; leaving the frame would let a
   later pop resurrect a stale copy.

8. **State what happens next** — the first open step, and anything from the loose-end
   reconciliation that has to be handled before it.

---

## Show

Peek at the top frame without popping it.

1. Find and read the highest-numbered frame file.
2. Display the reason, timestamp, project directory, step list with progress, and loose
   ends.
3. Remind the user: `/stack-it pop` to resume, `/stack-it drop` to discard.

---

## List

Show all frames with one-line summaries.

1. Glob `.claude/plans/stack/*.md`.
2. For each file, sorted by frame number descending so the top of the stack reads first,
   display the frontmatter summary:

```
Stack (3 frames):
  #3 [top] "Found login bug" — 5 steps, 2 open (2026-03-25, ~/Projects/freelance-automation)
  #2       "Refactor auth module" — 3 steps, 3 open (2026-03-24, ~/Projects/web-app)
  #1       "Initial pipeline work" — 7 steps, 1 open (2026-03-23, ~/Projects/freelance-automation)
```

---

## Drop

Discard the top frame without resuming.

1. Find the highest-numbered frame file.
2. Show what is being dropped — reason, open step count, and **any loose ends it
   recorded**. Dropping a frame discards the only record that those exist, so the user
   should see them before agreeing.
3. Delete the file.
4. Confirm: "Dropped frame #{N}. Stack now has {remaining} frames."
