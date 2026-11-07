# Codex prompt: burn remaining weekly quota

A trigger woke you to spend weekly budget that is about to expire.

## Before anything: check whether this is armed

Read the `## Codex` section of `docs/quota-detection.md`.

That section records an unresolved search: `codex-cli` exposes no non-interactive read of the weekly window. If it still says so, stop here. Log the stop to `~/.local/state/weekly-burn/last-run.log` and exit clean. The first rule in this repo is no burn on a quota nobody can read, and that rule does not bend because a trigger fired.

Someone unblocking this should write the working recipe into that section first, then come back.

## Once a quota read exists

Run it, record percent used and the actual reset time, then work the same sequence the Claude side does. `.claude/skills/burn-remaining/SKILL.md` is the reference implementation; read it rather than reinventing the order here.

The differences on this side:

- Config is `~/.config/weekly-burn/codex.conf`, with reasoning level in place of effort. `plan-path` and `repo-path` are shared.
- Re-arming means rewriting the launchd agent. On a machine with a declarative system spec, change the spec and rebuild instead of editing `~/Library/LaunchAgents/` by hand.
- `codex exec` runs the work.

Stop and log when the bucket is spent, when `allow_overage=false` and you are at the edge, or when too little remains to finish something whole.
