---
name: set-up
description: Wire this machine to burn remaining weekly quota in the window before each reset. Use when the user is inside the weekly-burn repo and says "set it up", "set up weekly burn", or points an agent at the repo for the first time.
---

Turn this repo into a working burner on this machine, then leave it armed and prove it fires. Work in order. Stop and report the exact failure if a step fails; do not patch around it.

Read `docs/scheduling.md`, `docs/config.md`, and `docs/quota-detection.md` first. They hold the decisions this procedure depends on.

## 1. Learn the host before you ask anything

The user may not be on the OS you expect. Establish, by checking rather than assuming:

- OS and whether a scheduler is available: `launchctl` on macOS, `systemctl --user` on Linux with systemd, `crontab` anywhere, Task Scheduler on Windows. `docs/scheduling.md` has a worked example for each.
- Which CLIs are installed and logged in, and their absolute paths. `command -v claude`, `command -v codex`. You need the absolute paths for the job definition.
- Whether a declarative system config owns scheduled jobs. A nix-darwin or home-manager host wants `launchd.user.agents` in its spec rather than a hand-written plist. Ask before editing such a host's files directly.
- Whether `timeout` exists. `burn.sh` falls back to a watchdog without it, which works but is worth knowing.

Say what you found. A user on Windows should hear that nobody has tested that path, not watch you write a plist.

## 2. Ask everything in one batch

Use `AskUserQuestion`. One call. Do not walk them through one question at a time.

**Providers.** Claude, Codex, or both. Only offer what you found installed and authenticated in step 1.

**Model, per provider.** Recommend the strongest on their plan, since the point is spending the fast budget. Name which weekly bucket it drains.

**Effort or reasoning level.** Recommend `high`.

**Burn window length.** How many hours before the reset the burner starts. Default 6. Explain the trade: a longer window converts more quota but starts while you might still want that budget yourself. The burner stops `stop_margin_minutes` before the reset either way.

**Plan location.** Recommend a private path outside this repo, defaulting to `~/.local/state/weekly-burn/plan/PLAN.md`. Say why: `add-job-to-burn-plan` fires during work in other repos, a brief can name a client or an unreleased feature, and this repo is public. Offer the repo's `PLAN.md` as the choice it is, with the consequence stated.

**Spend guard.** Whether to refuse when the provider says spending is not allowed, and whether the first fire runs dry. Recommend both.

**Permission mode, per provider.** Nobody is watching. Recommend `acceptEdits` for Claude and `workspace-write` for Codex. Say plainly that the full-access options let an unattended session run anything, and that Claude's `manual` hangs until the window shuts.

**How to be told it failed.** Offer the OS default notification, or a command of their own for `alert_command`. A silent failure means they find out a week later by noticing the quota went unspent again.

## 3. Read the live reset for each provider

Run `scripts/read-quota.py <provider>` for each one they picked. Record `used_percent` and `resets_at_iso`.

The two providers reset on different days, so each gets its own anchor and its own scheduled job. Never copy one provider's day to the other, and never hardcode a weekday from an example in the docs.

Re-verify the recipe while you are here. If a reader fails, fix `scripts/read-quota.py` and the matching section of `docs/quota-detection.md`, recording the version you checked and the date. A stale reader means a failed fire.

## 4. Write config

Create `~/.config/weekly-burn/` and write `plan-path`, `repo-path`, and one conf per provider, exactly as `docs/config.md` specifies. Every key, including `reset_anchor` from step 3.

Set `dry_run=true` when they asked for a dry first fire.

Create the plan directory and seed `PLAN.md` with the two headings from `docs/plan-format.md` when nothing is there. Create `~/.local/state/weekly-burn/`.

## 5. Install the scheduled jobs

One per provider. Fire time is that provider's live reset minus `window_hours`, in local time, expressed in the host's scheduler.

Set `CLAUDE_BIN` or `CODEX_BIN` in the job's environment to the absolute path from step 1. Skip this and the first fire dies, because schedulers hand out a minimal PATH. Use `docs/scheduling.md` for the exact syntax.

Record `trigger` and `trigger_id` in each conf.

## 6. Verify, and make one fire actually happen

Run `./scripts/test.sh` and quote the result.

Then run each provider's job by hand, through the scheduler rather than by calling the script yourself, so the scheduler's own environment gets tested:

- launchd: `launchctl kickstart -p gui/"$(id -u)"/<label>`
- systemd: `systemctl --user start weekly-burn@<provider>.service`
- cron: run the exact command line from the crontab, with `env -i` to mimic cron's empty environment.

With `dry_run=true` this costs one cheap quota read and proves the whole chain: the scheduler can find the script, the script can find the binary, the binary can read the account, the config parses, and the plan resolves. Quote the log lines from `~/.local/state/weekly-burn/last-run.log`.

Confirm the global skill resolves after running `scripts/install-global-skill.sh`.

Do not let a real burn run now. The dry fire is the proof.

## 7. Tell them what they have

Per provider: next fire time in their timezone, window length, hard stop time, model, effort, permission mode, and trigger id. Then the plan path, whether dry run is still on, and the one line they change to arm it.

## 8. Commit

Commit what you filled in. Short imperative subject, body saying why the choices landed where they did. Do not push unless they ask.
