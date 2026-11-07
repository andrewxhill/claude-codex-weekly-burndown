---
name: add-job-to-burn-plan
description: Append a job to the user's weekly burn plan. Use when the user says "add that to the burn list", "put that on the burn plan", "save it for next week's burn", "if we have tokens left this week", "burn it later", or otherwise defers work to the weekly leftover-quota queue. Available in every agent session on this machine.
---

The user is deferring work to their weekly burn plan. Write the brief, slot the row, confirm, and get back to whatever you were doing. This fires mid-task, so keep it short.

## 1. Find the plan

Read `~/.config/weekly-burn/plan-path`. It holds one absolute path to `PLAN.md`.

Missing, or the file it names does not exist: tell the user weekly-burn is not set up and point them at the repo to run `set it up`. Then stop.

Job briefs live beside the plan, at `<dirname of plan-path>/jobs/<slug>/readme.md`. Not in this repo, and not in the weekly-burn repo. The plan path is the only thing that decides where they go.

Confirm the plan has a `## Open jobs, highest priority first` heading before you edit it.

## 2. Ask only what you cannot answer

You have been in this conversation. You know what the work is. Write the description yourself from that context and show it to them as part of the confirmation.

Ask, in one batch, only what is genuinely open:

- **Priority.** Where it lands against the current top rows. Default to the end of the open list. Read the existing rows first so you can name them instead of asking abstractly.
- **Expiration.** Default four weeks from today. Convert to an absolute `YYYY-MM-DD`; no relative dates in the file.

Skip either question when they already answered it. Someone who says "put that on the burn list for next week" has given you the expiration.

## 3. Write the brief

Create `<plan-dir>/jobs/<slug>/readme.md`. Kebab-case slug from the description, `-2` suffix on a collision.

It holds:

- A short title.
- Two to five sentences: what the job is, why it matters, what done looks like.
- The files, URLs, commands, and references the burner will need. It starts cold, in a fresh session, with none of this conversation.
- Scope boundaries, stated as boundaries. The burner runs unattended with a large budget and nobody to stop it widening the job. This paragraph is the only thing that does.

Write enough that a stranger could do the work. You are that stranger in a week.

## 4. Insert the row

One row, at the position they chose, under `## Open jobs, highest priority first`:

```
- [ ] [expires YYYY-MM-DD] <one-sentence imperative description> ([jobs/<slug>](jobs/<slug>/readme.md)).
```

Leave every other row's order alone. Leave the Completed section alone.

## 5. Commit only if it belongs to a repo

The plan directory may be a git repo or a plain directory. Check.

A repo: commit the brief and the row together, short imperative subject. No push.

Not a repo: the files are written and there is nothing else to do. Do not initialize one.

## 6. Confirm in one line

Give them the description you wrote, the slot, and the expiration. Then return to the task you interrupted.
