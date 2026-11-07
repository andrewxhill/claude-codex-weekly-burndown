---
name: burn-remaining
description: Spend the remaining weekly quota on jobs from the burn plan during the window before a reset. Use when a scheduled trigger wakes you, when the user says "burn my remaining tokens", or when a weekly quota is about to reset and the user wants backlog cleared.
---

You are inside a burn window. Quota that survives the reset is gone, so the job is to convert as much of it as possible into finished work, then stop before the rollover.

`scripts/burn.sh` started you and told you the deadline. It also wrapped you in a kill at that deadline, so running long does not get you extra time, it gets you cut off mid-sentence. Work accordingly.

A human may have invoked you directly instead, in which case nothing has been read yet and no deadline is enforced. Check which situation you are in.

## 1. Resolve config

Read these and stop if any is missing, rather than assuming a default:

- `~/.config/weekly-burn/plan-path` for the plan. Briefs are at `<dirname>/jobs/<slug>/readme.md`.
- `~/.config/weekly-burn/repo-path` for this repo.
- `~/.config/weekly-burn/<provider>.conf` for `model`, `effort`, `dry_run`, `allow_overage`, `window_hours`, `stop_margin_minutes`, `reset_anchor`, `trigger`, `trigger_id`.

`docs/config.md` documents every key.

## 2. Confirm the window

Run `scripts/read-quota.py <provider>` from `repo-path`. You need the reset time and the percentage even when the runner already read them, because your deadline arithmetic depends on them and a human-invoked run has neither.

Stop and log when:

- The read fails. Fail closed; `docs/quota-detection.md` says why.
- `spend_allowed` is false and `allow_overage` is not true.
- The reset is already inside `stop_margin_minutes`. The window is gone.

## 3. Honor `dry_run`

With `dry_run=true`: log the reading, name the job you would have taken, and exit without touching it. Someone is watching one fire land before arming this. Do not decide for them that the real thing is fine.

## 4. Work the plan from the top, repeatedly

This is a window, not a single errand. Keep taking jobs until the budget runs out or the deadline gets close.

For each pass:

1. Read the plan. Take the first row under `## Open jobs, highest priority first` whose `[expires YYYY-MM-DD]` is still ahead of today.
2. Drop expired rows as you meet them: prepend each to `## Completed, newest first`, dated today, saying nobody reached it.
3. Open the row's `jobs/<slug>/readme.md`. The row is a handle; the brief is the spec. A row with no brief is broken, so log it and move to the next row rather than inventing the work.
4. Do the job. Commit as you go. Move the row to Completed with a one-sentence outcome.
5. Check the clock and the quota, then decide whether another job fits.

Start nothing you cannot land. Before picking up a job, ask whether there is time to leave it finished or at least committed and coherent. When the honest answer is no, stop and write up what you did. Half a job is worse than an unspent hour, because someone has to work out where you got to.

## 5. Do the work properly

Run at the `model` and `effort` from the conf. The budget exists to be spent, so use it on depth rather than haste.

Hold each brief's scope. The brief names its boundaries because nobody is awake to catch you widening them. Load the `engineering-discipline` skill and work to it: a failing test before a bug fix, the project's own gate before any claim that something is done.

Push only when a brief says to.

## 6. Record as you go, not at the end

A kill at the deadline takes anything you were saving up. So after each job, before starting the next:

- Update the plan.
- Append to `~/.local/state/weekly-burn/last-run.log`: what you read, what you took, how it ended.

Report what you actually got. A job you got halfway through is a job you got halfway through.

## 7. Re-arm if the window moved

Compare the live reset against `reset_anchor` in the conf. Within fifteen minutes, leave it alone.

Past fifteen minutes, rebuild the schedule for `new_reset - window_hours` and write the new `reset_anchor` back. `docs/scheduling.md` has the mechanics for each scheduler. On a host with a declarative system config, change the spec rather than editing the scheduler's files by hand.

Do this early in the run, not at the end, where the deadline will eat it.
