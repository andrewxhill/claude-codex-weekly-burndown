---
name: set-up
description: Wire this machine to burn leftover weekly quota before each reset, covering the host check, config, scheduled jobs, and one proving fire. Use on a first run in the weekly-burn repo, including a bare "set it up".
---

Turn this repo into a working burner on this machine, leave it armed, and prove it fires. Work in order. When a step fails, stop and report the exact failure rather than patching around it.

Read `docs/scheduling.md`, `docs/config.md`, and `docs/quota-detection.md` first. They hold the decisions this procedure depends on.

## 1. Learn the host before you ask anything

The user may not be on the OS you expect. Answer each of these by running something, and show the output:

- OS, and which scheduler is available: `launchctl` on macOS, `systemctl --user` on Linux with systemd, `crontab` anywhere, Task Scheduler on Windows.
- Which CLIs are installed and logged in, plus the absolute path of each. `command -v claude`, `command -v codex`. The job definition needs the absolute path.
- **Whether each CLI can authenticate from a scheduled job**, which is a different question from whether it authenticates in your shell. `docs/scheduling.md` has the check and the fix.
- Whether a declarative system config owns scheduled jobs. A nix-darwin or home-manager host wants `launchd.user.agents` in its spec rather than a hand-written plist. Ask before editing such a host's files.
- Whether `timeout` exists. `burn.sh` falls back to a watchdog without it, which works and is worth knowing.

Done when every bullet above has an answer you obtained from the host. A user on Windows should hear that nobody has tested that path before they watch you write a plist.

## 2. Ask everything in one batch

Use `AskUserQuestion`, in a single call:

**Providers.** Claude, Codex, or both, offering only what you found installed and authenticated in step 1.

**Model, per provider.** Recommend the strongest on their plan, since the point is spending the fast budget. Name which weekly bucket it drains.

**Effort or reasoning level.** Recommend `high`.

**Burn window length.** How many hours before the reset the burner starts. Default 6. Explain the trade: a longer window converts more quota, and it starts while you might still want that budget yourself. The burner stops `stop_margin_minutes` before the reset either way.

**Plan location.** Recommend a private path outside this repo, defaulting to `~/.local/state/weekly-burn/plan/PLAN.md`. Say why: `add-job-to-burn-plan` fires during work in other repos, a brief can name a client or an unreleased feature, and this repo is public. Offer the repo's `PLAN.md` as the choice it is, with that consequence stated.

**Spend guard.** Whether to refuse when the provider says spending is not allowed, and whether the first fire runs dry. Recommend both.

**Permission mode, per provider.** Nobody is watching. Recommend `acceptEdits` for Claude and `workspace-write` for Codex. Say plainly that the full-access options let an unattended session run anything, and that Claude's `manual` hangs until the window shuts.

**How to be told it failed.** Offer the OS default notification, or a command of their own for `alert_command`. A silent failure means they find out a week later by noticing the quota went unspent again.

## 3. Read the live reset for each provider

Run `scripts/read-quota.py <provider>` for each one they picked. Record `used_percent` and `resets_at_iso`.

The two providers reset on different days, so each gets its own anchor and its own scheduled job. Take each day from that provider's own reading, never from the other provider and never from an example in the docs.

Re-verify the recipe while you are here. When a reader fails, fix `scripts/read-quota.py` and the matching section of `docs/quota-detection.md`, recording the version you checked and the date. A stale reader means a failed fire.

## 4. Write config

Create `~/.config/weekly-burn/` and write `plan-path`, `repo-path`, and one conf per provider, exactly as `docs/config.md` specifies. Every key, including `reset_anchor` from step 3.

Set `dry_run=true` when they asked for a dry first fire.

Create the plan directory and seed `PLAN.md` with the two headings from `docs/plan-format.md` when nothing is there. Create `~/.local/state/weekly-burn/`.

## 5. Install the scheduled jobs

One per provider. Fire time is that provider's live reset minus `window_hours`, in local time, expressed in whatever the host's scheduler speaks.

Set `CLAUDE_BIN` or `CODEX_BIN` in the job's environment to the absolute path from step 1. Schedulers hand out a minimal PATH, so the first fire dies without it. `docs/scheduling.md` has the exact syntax.

Record `trigger` and `trigger_id` in each conf.

## 6. Fire it through the scheduler

Run `./scripts/test.sh` and quote the result.

Then fire each provider's job the way the scheduler will, so the scheduler's own environment gets tested:

- launchd: `launchctl kickstart -p gui/"$(id -u)"/<label>`
- systemd: `systemctl --user start weekly-burn@<provider>.service`
- cron: the exact command line from the crontab, wrapped in `env -i` to mimic cron's empty environment.

With `dry_run=true` this costs one cheap quota read and proves **the chain**: the scheduler finds the script, the script finds the binary, **the binary authenticates in the scheduler's context**, the config parses, and the plan resolves. Quote the log lines from `~/.local/state/weekly-burn/last-run.log`.

Running the script yourself from a terminal is not a substitute and does not count. Your shell can resolve a different credential from the scheduler's, so a run that works for you says nothing about the scheduled one. This step is the only thing between the user and a burner that reports success today and silently does nothing every week.

An abort naming authentication is common on the first macOS attempt, and `docs/scheduling.md` has the credential comparison that settles it. Read what the log says, fix that, and fire again until it shows a clean dry run.

Run `scripts/install-global-skill.sh`. It installs for both agents, which discover differently, so confirm both.

Claude, from a directory with nothing to do with this repo:

```bash
cd /tmp && claude -p "Answer yes or no, invoking nothing: is a skill named add-job-to-burn-plan available to you?" --model haiku
```

Codex, by checking the pointer landed in the file it loads globally:

```bash
grep -c 'add that to the burn list' ~/.codex/AGENTS.md
```

When that file is read-only, the installer prints the block and exits non-zero. On a host with a declarative dotfile setup, put the block in whatever renders the file.

Done when the log shows a clean dry run for every provider, the Claude probe answers yes, and the Codex pointer is in place. Leave the real burn for the scheduled fire.

## 7. Tell them what they have

Per provider: next fire time in their timezone, window length, hard stop time, model, effort, permission mode, and trigger id. Then the plan path, whether dry run is still on, and the one line they change to arm it.

## 8. Commit

Commit what you filled in. Short imperative subject, body saying why the choices landed where they did. Pushing waits for them to ask.
