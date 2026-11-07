# Scheduling

One job per provider, because Claude and Codex meter on their own clocks and reset on different days. Each job opens that provider's burn window.

## The burn window

You pick how long the window is. `window_hours=6` means the job starts six hours before the reset and the burner works until the rollover is nearly on top of it.

Three numbers matter:

- `window_hours`, when the job fires. Yours to choose.
- `stop_margin_minutes`, how far before the reset everything stops. Default 5.
- The hard stop, which `scripts/burn.sh` computes from the live reset time and enforces with a kill.

The hard stop is the part that matters. Quota spent after the rollover comes out of next week, which defeats the point, so the burner does not get to decide when to quit. `burn.sh` wraps the agent in a deadline, tells it how long it has, and kills it at the edge. An agent that loses track of time gets stopped anyway.

Exit code 124, 143, or 137 from the burner means the deadline fired. That is the designed ending, not a failure, and the log says so.

## Picking the fire time

Read the live reset, subtract `window_hours`, convert to local time, and express that in whatever the host's scheduler speaks. Never hardcode a weekday from an example; reset days differ per account and per provider.

A scheduled job gets a minimal environment, so set `CLAUDE_BIN` or `CODEX_BIN` to the absolute path of the binary. `which claude` in your shell is not what the scheduler sees. Everything in this repo fails with that exact complaint rather than something vague, but it still fails.

## Authentication: which credential the job resolves

Claude Code keeps credentials in two stores on macOS, and a scheduled job can resolve a different one from your shell:

- the login keychain, as the generic password `Claude Code-credentials`
- the file `~/.claude/.credentials.json`, mode 600

It prefers the keychain whenever an item exists there. Signing out leaves that item in place holding `accessToken` and `refreshToken` as `""` with `expiresAt` 0, and an emptied item still counts as existing. A context that reads the keychain therefore picks up the empty tokens and authenticates as nobody, while a context that cannot read the keychain falls back to the file and works normally.

Verified on 2.1.319. One machine, one minute apart: `claude auth status` returned `loggedIn: false` under launchd and `loggedIn: true` from a shell whose keychain access was blocked. The file held a credential minted that day; the keychain item had been empty since six weeks earlier.

An anonymous session says nothing about it. `claude -p` runs, does no work, and prints a zero-cost summary, which is why `scripts/read-quota.py` checks auth before blaming the `/usage` format.

Check it the way the scheduler will, then read what the job logged:

```bash
launchctl kickstart -p gui/"$(id -u)"/sh.weekly-burn.claude
```

When the job reports `loggedIn: false` and your shell reports `true`, compare the stores:

```bash
security find-generic-password -s 'Claude Code-credentials' -w |
  python3 -c 'import json,sys; o=json.load(sys.stdin)["claudeAiOauth"]; print("keychain token chars:", len(o.get("accessToken") or ""))'
python3 -c 'import json,os; o=json.load(open(os.path.expanduser("~/.claude/.credentials.json")))["claudeAiOauth"]; print("file token chars:", len(o.get("accessToken") or ""))'
```

Zero in the keychain against a real length in the file means the item is shadowing a working credential. Delete the item and the file takes over:

```bash
security delete-generic-password -s 'Claude Code-credentials'
```

`claude` picks up the file on its next run, in your shell and in the scheduled job alike, and the plist needs nothing added.

On a host with no interactive login there is no file to fall back to. Mint a credential there with `claude setup-token` and put it in the job's environment as `CLAUDE_CODE_OAUTH_TOKEN`.

**Codex resolves one store.** `~/.codex/auth.json`, which a scheduled job reads like any other file. Verified against 0.166.0.

## macOS: launchd

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>sh.weekly-burn.claude</string>
  <key>ProgramArguments</key>
  <array>
    <string>/absolute/path/to/repo/scripts/burn.sh</string>
    <string>claude</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CLAUDE_BIN</key><string>/Users/you/.local/bin/claude</string>
    <key>HOME</key><string>/Users/you</string>
    <key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key><integer>2</integer>
    <key>Hour</key><integer>20</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
  <key>StandardOutPath</key><string>/Users/you/.local/state/weekly-burn/launchd.claude.out.log</string>
  <key>StandardErrorPath</key><string>/Users/you/.local/state/weekly-burn/launchd.claude.err.log</string>
</dict>
</plist>
```

```bash
launchctl bootstrap gui/"$(id -u)" ~/Library/LaunchAgents/sh.weekly-burn.claude.plist
launchctl kickstart -p gui/"$(id -u)"/sh.weekly-burn.claude   # fire it once, now
```

The path argument on `bootstrap` is required. `Weekday` runs 0 to 7 with Sunday at both ends. Derive it from the live reset, never from this example.

On a machine whose system config is declarative, the agent belongs in that spec instead of hand-written here. On a nix-darwin host that means `launchd.user.agents`.

Asleep at the fire time, launchd runs the job when the machine wakes. That late run can land after the reset, which is exactly why `burn.sh` re-reads the live window and exits clean when it finds the window already closed.

## Linux: systemd timer

```ini
# ~/.config/systemd/user/weekly-burn@.service
[Service]
Type=oneshot
Environment=CLAUDE_BIN=%h/.local/bin/claude
Environment=CODEX_BIN=%h/.local/bin/codex
ExecStart=/absolute/path/to/repo/scripts/burn.sh %i
```

```ini
# ~/.config/systemd/user/weekly-burn@.timer
[Timer]
OnCalendar=Tue 20:00
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl --user enable --now weekly-burn@claude.timer
systemctl --user start weekly-burn@claude.service   # fire it once, now
```

`Persistent=true` catches up a missed run after a reboot, and `burn.sh` handles a late catch-up by checking whether the window is still open.

## Anywhere with cron

```cron
0 20 * * 2 CLAUDE_BIN=/home/you/.local/bin/claude /absolute/path/to/repo/scripts/burn.sh claude
16 7 * * 5 CODEX_BIN=/home/you/.local/bin/codex /absolute/path/to/repo/scripts/burn.sh codex
```

cron's environment is smaller than you expect, so set the binary paths inline. cron skips a run entirely when the machine is off; nothing catches it up.

## Windows

Task Scheduler, running `scripts/burn.sh` through WSL or Git Bash. Nobody has tested this. Say so to the user rather than implying it works.

## When it fails

`burn.sh` writes every event to `~/.local/state/weekly-burn/last-run.log` and raises a desktop notification on an abort or a non-deadline failure. It uses `alert_command` from the provider's conf when set, otherwise `osascript` on macOS or `notify-send` on Linux.

Set `alert_command` to reach yourself some other way. The command runs with `WEEKLY_BURN_MESSAGE` and `WEEKLY_BURN_PROVIDER` in its environment:

```ini
alert_command=curl -s -X POST -d "$WEEKLY_BURN_MESSAGE" https://example.com/hook
```

A silent failure is the worst outcome here, because you find out a week later by noticing the quota went unspent again.

## Drift and re-arming

The schedule encodes one week's reset time. Buying a reset, changing plans, or having usage credited moves the window, and `reset_anchor` in the conf goes stale.

So the burner compares the live reset against `reset_anchor` at every fire. Past fifteen minutes of drift it rebuilds the schedule for the new anchor and writes the new anchor back. Under fifteen minutes it leaves the schedule alone.
