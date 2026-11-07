# claude-codex-weekly-burndown

Context for Claude Code sessions in this repo. Every session loads this file, so it describes the project rather than issuing a procedure.

**Setting it up?** Invoke the `set-up` skill. The procedure lives there, in `.claude/skills/set-up/SKILL.md`, and not in this file. An auto-loaded file that tells every future session to run setup gets setup run again by a session that was asked to fix a typo.

## What this is

A weekly-quota burner. A scheduled trigger wakes a couple of hours before the account's weekly reset, reads how much of the bucket is left, takes the top job off a prioritized backlog, and spends the remainder on it. Claude Pro and Max meter weekly, and whatever you have not spent by reset time is gone.

## How the pieces fit

One scheduled job per provider runs `scripts/burn.sh <claude|codex>` when that provider's burn window opens. The runner reads the live quota through `scripts/read-quota.py`, refuses to start on a spent bucket, computes a hard deadline from the live reset time, and runs the `burn-remaining` skill under a kill at that deadline. The skill works the plan from the top, job after job, until the budget or the clock runs out.

Claude and Codex meter on separate clocks and reset on different days, so each gets its own conf, its own anchor, and its own job.

Config lives in `~/.config/weekly-burn/`: `plan-path`, `repo-path`, and `claude.conf`. State goes to `~/.local/state/weekly-burn/last-run.log`. `docs/config.md` has the schema.

The real plan lives outside this repo by default. `add-job-to-burn-plan` is installed globally and fires during work in other repos, so briefs can name clients and unreleased work, and this repo is public. The `PLAN.md` here is an empty format example.

## Rules that bite

**Never hardcode a reset time.** Read it live at every fire, from `docs/quota-detection.md`. Reset days differ per account. Code that assumes Sunday is wrong for most people.

**Quota comes back as a percentage.** Both providers report percent used; no token count exists in either CLI surface. `scripts/test.sh` fails the build if a doc claims otherwise.

**Fail closed on an unreadable quota.** No burn on a budget nobody can see. A half-finished job costs more than a skipped week.

**The hard stop is enforced, not requested.** Quota spent after the rollover comes out of next week. `scripts/burn.sh` wraps the agent in a deadline and kills it at the window edge, so an agent that loses track of time still stops. Exit 124, 143, or 137 is the designed ending.

**Quota reading lives in one place.** `scripts/read-quota.py` handles both providers and prints one shape. It has to be code rather than prose because the runner computes a timeout from the reset time. When a provider changes shape it exits non-zero and nothing spends.

**`CronCreate` cannot schedule this.** Session-only, in-memory, dead when the session exits, expires after seven days. `docs/scheduling.md` covers launchd, systemd, and cron.

**Do not assume macOS.** Setup checks the host and picks its scheduler. `timeout` is absent from stock macOS, so the runner carries a watchdog fallback.

**The burner runs unattended.** Scope boundaries in a brief are the only thing standing between a backlog row and an agent with a large budget and nobody watching.

## Before you claim it works

`./scripts/test.sh` is the gate. It stubs `claude`, so it spends nothing. Run it and quote the output.
