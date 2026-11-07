# Plan format

`PLAN.md` is a human-maintained, agent-maintained priority queue. Every agent on this machine reads and writes it the same way.

## Open jobs section

Each job is one Markdown list item under `## Open jobs, highest priority first`. Order on the page is priority: the top line is the next thing the burner will pick up.

Row shape:

```
- [ ] [expires YYYY-MM-DD] One-sentence description of the job ([jobs/<slug>](jobs/<slug>/readme.md)).
```

Rules:

- The `[ ]` checkbox stays unchecked until the burner completes the job.
- `[expires YYYY-MM-DD]` is required. If the burner wakes on a day past the expiration, it skips the row and drops it.
- The description is one imperative sentence. Skip "we should" and "it would be nice to"; state the work.
- Every job links to `jobs/<slug>/readme.md`. That folder holds the full spec: context, acceptance criteria, scope boundaries, any reference files. The line in `PLAN.md` is the handle, not the brief.
- The burner picks the first non-expired row and moves it to Completed when done.

## Completed section

Under `## Completed, newest first`. The burner prepends; newest sits on top.

Row shape:

```
- [x] ~~YYYY-MM-DD: One-sentence outcome of the job~~ ([jobs/<slug>](jobs/<slug>/readme.md)).
```

The outcome sentence describes what shipped, not what was tried. If the job was abandoned, the sentence says so, named and dated.

## Where the plan lives

`~/.config/weekly-burn/plan-path` holds one absolute path to the real `PLAN.md`. Job briefs sit beside it, at `<dirname>/jobs/<slug>/readme.md`.

Setup defaults that to a private directory outside the weekly-burn repo. The repo is public, and `add-job-to-burn-plan` fires during work in other repos, so a brief can carry a client name or an unreleased feature into a public commit. The `PLAN.md` in the repo is an empty format example; the burner never reads it unless you pointed `plan-path` at it on purpose.

## Adding a job from any project

Every agent session on this machine can reach the `add-job-to-burn-plan` skill, which writes the brief, inserts the row where the user wants it, and commits when the plan directory is a git repo. Its `SKILL.md` carries the procedure.

It writes the description itself from the conversation it is already in, and asks only about priority and expiration. Being asked to restate work you just described is the fastest way to stop using a tool like this.
