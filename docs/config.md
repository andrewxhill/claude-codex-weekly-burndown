# Config

Setup writes everything under `~/.config/weekly-burn/`. The runner and the global skill read it at fire time. Nothing here is secret, and nothing here belongs in a commit.

## `plan-path`

One line: the absolute path to your real `PLAN.md`.

`add-job-to-burn-plan` reads this from any repo on the machine, which is why it is a bare file rather than a key inside a provider conf. Job briefs live beside it, at `<dirname>/jobs/<slug>/readme.md`.

Setup defaults it to `~/.local/state/weekly-burn/plan/PLAN.md`. Point it at this repo's `PLAN.md` only if you are fine publishing every brief you ever defer.

## `repo-path`

One line: the absolute path to this repo's checkout. The runner needs it to find the skills and the Codex prompt.

## `claude.conf` and `codex.conf`

One per provider, `key=value`, `#` for comments. Every key is required; `burn.sh` refuses to run when one is empty.

```ini
# --- what to run ---------------------------------------------------------
# Decides which weekly bucket drains.
model=claude-opus-5

# claude: low | medium | high | xhigh | max
# codex:  passed through as model_reasoning_effort
effort=high

# claude: acceptEdits | auto | dontAsk | bypassPermissions | manual | plan
# codex:  read-only | workspace-write | danger-full-access
# Nobody is awake to answer a prompt. `manual` hangs until the window shuts.
permission_mode=acceptEdits

# --- the window ----------------------------------------------------------
# How long before the reset the job fires, and how much of the week's
# remaining budget the burner gets to spend.
window_hours=6

# How far before the reset everything stops. The runner computes the hard
# deadline from the live reset time and kills the burner at it, so quota
# never leaks into next week.
stop_margin_minutes=5

# --- guards --------------------------------------------------------------
# true: read quota, name the top job, write the log, spend nothing.
# Leave it true until you have watched one fire land.
dry_run=true

# false: refuse to start when the provider says spending is not allowed.
allow_overage=false

# --- schedule bookkeeping ------------------------------------------------
# ISO 8601 reset the schedule was built around. The burner compares the live
# reset against this and re-arms past fifteen minutes of drift.
reset_anchor=2026-11-11T02:00:00-08:00

# launchd | systemd | cron | schtasks
trigger=launchd

# launchd label, systemd unit, or whatever identifies the job to its scheduler.
trigger_id=sh.weekly-burn.claude

# --- alerting ------------------------------------------------------------
# Optional. Runs on an abort or a non-deadline failure, with
# WEEKLY_BURN_MESSAGE and WEEKLY_BURN_PROVIDER in its environment.
# Empty falls back to osascript on macOS or notify-send on Linux.
alert_command=
```

The two confs are independent. Claude and Codex reset on different days, so they get different `reset_anchor` values, different `trigger_id` values, and separate scheduled jobs.

## Environment the scheduled job needs

`scripts/burn.sh` and `scripts/read-quota.py` read these:

- `CLAUDE_BIN` and `CODEX_BIN`, absolute paths to the binaries. Required in any scheduled job, because schedulers hand you a minimal PATH that excludes wherever these are installed. Both scripts fail with that specific complaint instead of something vague.
- `WEEKLY_BURN_CONFIG_DIR`, defaulting to `~/.config/weekly-burn`.
- `WEEKLY_BURN_STATE_DIR`, defaulting to `~/.local/state/weekly-burn`.

The last two exist so `scripts/test.sh` can run against a sandbox. Leave them unset in the job.

## State

`~/.local/state/weekly-burn/last-run.log`, one tab-separated line per event with UTC timestamps and the provider name. `burn.sh` creates the directory. Nothing rotates it, and `.gitignore` covers `*.log`.
