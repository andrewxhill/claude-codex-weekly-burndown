# claude-codex-weekly-burndown

Context for Claude Code sessions in this repo. Every session loads this file, so it describes the project rather than issuing a procedure.

**Setting it up?** Invoke the `set-up` skill. The procedure lives there, in `.claude/skills/set-up/SKILL.md`, and not in this file. An auto-loaded file that tells every future session to run setup gets setup run again by a session that was asked to fix a typo.

## What this is

A weekly-quota burner. A scheduled trigger wakes a couple of hours before the account's weekly reset, reads how much of the bucket is left, takes the top job off a prioritized backlog, and spends the remainder on it. Claude Pro and Max meter weekly, and whatever you have not spent by reset time is gone.

## How the pieces fit

A trigger runs `scripts/burn-wrapper.sh`, which reads the quota, clears the spend guard, and hands the work to the `burn-remaining` skill inside a `claude -p` session. The skill reads the plan, takes the top live row, opens its brief, and does the job.

Config lives in `~/.config/weekly-burn/`: `plan-path`, `repo-path`, and `claude.conf`. State goes to `~/.local/state/weekly-burn/last-run.log`. `docs/config.md` has the schema.

The real plan lives outside this repo by default. `add-job-to-burn-plan` is installed globally and fires during work in other repos, so briefs can name clients and unreleased work, and this repo is public. The `PLAN.md` here is an empty format example.

## Rules that bite

**Never hardcode a reset time.** Read it live at every fire, from `docs/quota-detection.md`. Reset days differ per account. Code that assumes Sunday is wrong for most people.

**Quota comes back as a percentage.** `/usage` reports percent of the weekly bucket used. No token count exists in any CLI surface. `scripts/test.sh` fails the build if a doc claims otherwise.

**Fail closed on an unreadable quota.** No burn on a budget nobody can see. A half-finished job costs more than a skipped week.

**Keep the quota recipe in docs, not code.** The burner reads `docs/quota-detection.md` at runtime so a reworded `/usage` is a docs fix. One exception, documented in the file: the wrapper parses the percentage itself, because a wrapper that cannot see the quota cannot refuse to spend past it.

**`CronCreate` cannot schedule this.** Session-only, in-memory, dead when the session exits, expires after seven days. `docs/scheduling.md` covers the two mechanisms that do work.

**The burner runs unattended.** Scope boundaries in a brief are the only thing standing between a backlog row and an agent with a large budget and nobody watching.

## Before you claim it works

`./scripts/test.sh` is the gate. It stubs `claude`, so it spends nothing. Run it and quote the output.
