---
name: stack-it
description: >-
  Manage a persistent task stack for pausing and resuming work across conversations.
  Use when the user says /stack-it, or when they want to pause current tasks to handle
  an interruption (bug fix, refactoring) and come back later. Supports push, pop, show,
  list, and drop subcommands. Also trigger when the user says things like "stack this",
  "save these tasks for later", "park this work", or "resume stacked work".
---

# /stack-it — Persistent Task Stack

**IMPORTANT:** Always use the Task* tools (`TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`) to manage tasks.

You manage a LIFO stack of task snapshots. When the user discovers a bug or refactoring mid-plan, they push their remaining tasks onto the stack, handle the interruption, then pop to resume.

Stack frames persist as files in `.claude/plans/stack/` (relative to the project root), so they survive across conversations and stay scoped to the project.

## Subcommands

Parse the argument string to determine the subcommand. Default is `push` when there are active tasks, `show` when there are none.

| Argument | Action |
|----------|--------|
| _(empty)_ or `push` | Push current tasks onto the stack |
| `pop` | Restore the top frame as new tasks |
| `show` | Display the top frame without popping |
| `list` | List all frames with summaries |
| `drop` | Discard the top frame |

---

## Push

Serialize all non-completed tasks into a stack frame file.

### Steps

1. **Read current tasks** — call `TaskList`. If there are no pending/in-progress tasks, tell the user there's nothing to stack and stop.

2. **Gather details** — for each non-completed task, call `TaskGet` to retrieve the full description and dependency graph (`blocks`, `blockedBy`).

3. **Ask for context** (only if not provided as argument) — ask the user briefly why they're stacking. Keep it to one line. This becomes the `reason` field.

4. **Capture progress on in-progress tasks** — if any task has status `in_progress`, ask the user what progress was made so far. This is important context for when the work resumes, potentially in a different conversation where all prior context is lost.

5. **Determine frame number** — glob `.claude/plans/stack/*.md`, find the highest existing number, add 1. If no files exist, start at `001`.

6. **Write the frame file** to `.claude/plans/stack/{NNN}.md` using this format:

```markdown
---
frame: {N}
stacked_at: {ISO timestamp}
reason: "{user's reason}"
project_dir: {current working directory}
plan_file: {path to active plan file, if any — check conversation context}
---

## Stacked Tasks

### {original task subject}
- **Original status:** {pending|in_progress}
- **Description:** {full task description}
- **Progress notes:** {what was done so far, only for in_progress tasks}
- **Blocks:** {comma-separated list of task subjects this blocks}
- **Blocked by:** {comma-separated list of task subjects this is blocked by}
```

Use task **subjects** (not IDs) in the blocks/blockedBy fields — IDs are conversation-scoped and meaningless after a pop.

7. **Report** — show the user what was stacked:
```
Stacked {N} tasks as frame #{frame} — "{reason}"
  {task subjects listed}
Use /stack-it pop to restore when ready.
```

---

## Pop

Restore the top stack frame as new tasks in the current conversation.

### Steps

1. **Find top frame** — glob `.claude/plans/stack/*.md`, pick the highest-numbered file. If none exist, tell the user the stack is empty.

2. **Read the frame** — parse the frontmatter and task list.

3. **Check project context** — if `project_dir` differs from the current working directory, warn the user: "This stack was created in {project_dir}. You're currently in {cwd}. Continue anyway?" Only warn, don't block.

4. **Show summary** — display the stacked tasks and reason before restoring, so the user can confirm or `/stack-it drop` instead.

5. **Recreate tasks** — for each stacked task, call `TaskCreate` with the original subject and description. If a task was `in_progress`, prepend the progress notes to the description:
   > **Resumed from stack:** {progress notes from when this was stacked}

6. **Re-establish dependencies** — after all tasks are created, use `TaskUpdate` with `addBlockedBy`/`addBlocks` to rewire dependencies. Match tasks by subject since IDs are new.

7. **Delete the frame file** — remove the `.md` file from `.claude/plans/stack/`.

8. **Show restored task list** — call `TaskList` and display it.

---

## Show

Peek at the top frame without popping it.

1. Find and read the highest-numbered frame file.
2. Display the tasks, reason, timestamp, and project directory.
3. Remind the user: `/stack-it pop` to restore, `/stack-it drop` to discard.

---

## List

Show all stacked frames with one-line summaries.

1. Glob `.claude/plans/stack/*.md`.
2. For each file (sorted by frame number, highest first = top of stack), read the frontmatter and display:
   ```
   Stack (3 frames):
     #3 [top] "Found login bug" — 5 tasks (2026-03-25, ~/Projects/freelance-automation)
     #2       "Refactor auth module" — 3 tasks (2026-03-24, ~/Projects/web-app)
     #1       "Initial pipeline work" — 7 tasks (2026-03-23, ~/Projects/freelance-automation)
   ```

---

## Drop

Discard the top frame without restoring.

1. Find the highest-numbered frame file.
2. Show what's being dropped (reason + task count).
3. Delete the file.
4. Confirm: "Dropped frame #{N}. Stack now has {remaining} frames."
