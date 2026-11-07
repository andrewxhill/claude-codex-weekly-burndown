# Scheduling

Two mechanisms can wake the burner. They reach different things, and the difference decides how the rest of the repo is wired. Setup asks you to pick one and records it as `trigger` in `claude.conf`.

## What will not work

`CronCreate`, the in-session cron tool, cannot do this job. Its jobs live in memory, die when the Claude session exits, fire only while the REPL sits idle, and expire after seven days. Its `durable` parameter has no effect. Nobody keeps a REPL idle for five days, so a weekly trigger built on it never fires. If you find a doc in this repo that says otherwise, it is stale; fix it.

## `trigger=launchd` (local)

A launchd agent on your Mac runs `scripts/burn-wrapper.sh`, which reads the quota, checks the spend guard, then runs `claude -p "/burn-remaining"`.

What this buys you: the burner sees your real worktree, reads `~/.config/weekly-burn/`, writes `~/.local/state/weekly-burn/last-run.log`, and commits where you can see the commits. Every path the rest of this repo assumes resolves correctly.

What it costs you: the Mac has to be awake and logged in at the fire time. A sleeping laptop misses the window, and launchd runs the job once the machine wakes, which may be after the reset.

On a machine whose system config is declarative, the agent belongs in that spec rather than hand-written into `~/Library/LaunchAgents/`. On this machine that means `~/Projects/_infra/macos-spec` through nix-darwin, which owns `launchd.user.agents`. Setup checks for a spec and routes the change through it. Elsewhere, write the plist and load it:

```bash
launchctl bootstrap gui/"$(id -u)" ~/Library/LaunchAgents/sh.weekly-burn.claude.plist
```

The path argument is required. `launchctl bootstrap gui/$(id -u)` on its own does nothing.

### The PATH trap

launchd hands a job `/usr/bin:/bin:/usr/sbin:/sbin` and nothing more. Your `claude` almost certainly lives somewhere else, `~/.local/bin/claude` on a native install, so the wrapper cannot find it and the fire dies on the first call.

Set `CLAUDE_BIN` in the plist. The wrapper prefers it over PATH discovery and says exactly this when it finds neither.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>sh.weekly-burn.claude</string>
  <key>ProgramArguments</key>
  <array>
    <string>/absolute/path/to/repo/scripts/burn-wrapper.sh</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CLAUDE_BIN</key><string>/Users/you/.local/bin/claude</string>
    <key>HOME</key><string>/Users/you</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key><integer>3</integer>
    <key>Hour</key><integer>0</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
  <key>StandardOutPath</key><string>/Users/you/.local/state/weekly-burn/launchd.out.log</string>
  <key>StandardErrorPath</key><string>/Users/you/.local/state/weekly-burn/launchd.err.log</string>
</dict>
</plist>
```

`Weekday` runs 0 to 7 with Sunday at both ends, so 3 is Wednesday. Derive it from the live reset, never from this example.

`StartCalendarInterval` fires once when the Mac wakes if it was asleep at the appointed time. That late fire can land after the reset, in which case the burner reads a full bucket and a reset a week out. It will do the work anyway. Decide whether you want that; `lead_minutes` and your sleep schedule are the only things that prevent it.

## `trigger=cloud-routine` (durable)

`/schedule` creates a scheduled cloud agent that fires whether or not your machine is on. It is in research preview, so expect the limits to move.

Four things break if you pick this without planning for them:

- A cloud session loads no skills from your machine. `burn-remaining` has to reach it through the pushed repo or inside the prompt itself.
- `~/.config/weekly-burn/` and `~/.local/state/weekly-burn/` do not exist there. Config has to travel in the repo or the prompt, and the log has to go somewhere the cloud session can write.
- Commits land in a cloud checkout. They reach you only if the routine pushes, which means the burner needs a branch to push to and you need to accept unattended pushes.
- The burner cannot re-arm itself. `CronDelete` and `CronCreate` do not touch a cloud routine, so a drifting reset window needs you.

Pick this when you want the window caught reliably and you are willing to move config into the repo and let the routine push a branch.

## Why two hours

Enough runway to finish a real job, close enough that you are spending budget you were about to lose. Both numbers are yours to change: `lead_minutes` in `claude.conf`.

The lead is approximate either way. Recurring schedules carry a per-job offset of up to half the period, capped at thirty minutes, so a two-hour lead can land ninety minutes out. Do not set a lead so tight that the offset eats it.

## Drift and re-arming

The schedule encodes one week's reset time. Buying a reset, changing plans, or having usage credited moves the real window, and the recorded `reset_anchor` goes stale.

So the burner re-reads the live reset at every fire and compares it against `reset_anchor`. Past fifteen minutes of drift it rebuilds the trigger for the new anchor and writes the new anchor and id back to `claude.conf`. Under fifteen minutes it leaves the schedule alone.
