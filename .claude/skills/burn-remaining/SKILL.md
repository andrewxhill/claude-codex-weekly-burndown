---
name: burn-remaining
description: Spend remaining weekly tokens on the top job in the burn plan. Fires about two hours before each weekly quota reset. Use when a scheduled trigger wakes you, when the user says "burn my remaining tokens", or when quota is close to resetting and the user wants the top backlog item cleared.
---

A trigger woke you to spend weekly budget that is about to expire. Work through these steps in order.

`scripts/burn-wrapper.sh` has already read the quota and cleared the spend guard when a launchd trigger started you. Re-read it anyway. You need the reset time, and a human who ran you by hand skipped the wrapper entirely.

## 1. Resolve config

Read these, and stop if any is missing rather than guessing a default:

- `~/.config/weekly-burn/plan-path` for the plan. Job briefs sit at `<dirname>/jobs/<slug>/readme.md`.
- `~/.config/weekly-burn/repo-path` for this repo.
- `~/.config/weekly-burn/claude.conf` for `model`, `effort`, `dry_run`, `allow_overage`, `reset_anchor`, `lead_minutes`, `trigger`, `trigger_id`.

`docs/config.md` documents every key.

## 2. Read live quota

Follow the `## Claude` section of `docs/quota-detection.md` in the repo at `repo-path`. Record the percent used and the reset time with its timezone.

Stop and log when any of these holds:

- The read fails or the output no longer matches what the doc describes. Fail closed; `docs/quota-detection.md` explains why.
- The bucket for your configured model sits at 100% and `allow_overage=false`.
- Too little budget remains to finish anything whole. A half-done job costs more to pick up than it saved.

## 3. Honor `dry_run`

With `dry_run=true`: log the quota reading, name the top job you would have taken, and exit without touching it. The user is watching one fire land before arming the thing. Do not decide on their behalf that the real run is fine.

## 4. Take the top job

Read the plan at `plan-path`. Take the first row under `## Open jobs, highest priority first` whose `[expires YYYY-MM-DD]` is still in the future.

Rows that expired get dropped: prepend each to `## Completed, newest first` as abandoned, dated today, and say in the sentence that nobody reached it. Then exit if nothing live is left.

Open the row's `jobs/<slug>/readme.md` for the brief. The row is a handle; the brief is the spec. A row whose brief is missing is broken, not an invitation to invent the work. Log it and move to the next row.

## 5. Do the work

Run at the `model` and `effort` from `claude.conf`. The window is closing, so use the budget.

Hold the brief's scope. The brief names its boundaries because nobody is awake to catch you widening them. Load the `engineering-discipline` skill and work to it: a failing test before a bug fix, the project's own quality gate before any claim that this is done.

Commit as you go. Push only when the brief says to.

## 6. Record what happened

Whether the job finished or the window shut first:

- Move the row from Open to the top of `## Completed, newest first`, dated today, with one sentence on what shipped. An abandoned job says so plainly.
- Append a line to `~/.local/state/weekly-burn/last-run.log`: what you read, what you took, where it ended.

Report the outcome you actually got. A job you got halfway through is a job you got halfway through.

## 7. Re-arm if the window moved

Compare the live reset time from step 2 against `reset_anchor` in `claude.conf`. Within fifteen minutes, leave it alone; the schedule re-fires on its own.

Past fifteen minutes, rebuild the trigger for `new_reset - lead_minutes`, then write the new `reset_anchor` and `trigger_id` back to `claude.conf`. How you rebuild depends on `trigger`:

- `launchd`: rewrite the plist through whatever owns it. On a machine with a declarative system spec, change the spec and rebuild rather than editing `~/Library/LaunchAgents/` by hand. `docs/scheduling.md` covers this.
- `cloud-routine`: you cannot re-arm yourself from here. Log the drift and tell the user what the new anchor should be.
