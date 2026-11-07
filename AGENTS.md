# claude-codex-weekly-burndown

Project context for Codex CLI sessions in this repo. Read `CLAUDE.md` as well: the project description and the "Rules that bite" there apply to both agents, and this file covers only what differs for Codex.

**Setting it up?** Follow `.codex/prompts/set-up.md`.

## What differs on the Codex side

**Quota reading.** `codex` exposes no `usage` subcommand, so `scripts/read-quota.py codex` speaks the app-server JSON-RPC method `account/rateLimits/read` and prints the same shape the Claude side prints. `docs/quota-detection.md` has the protocol detail and the command that regenerates the schema when it moves.

**A different reset day.** The Codex week and the Claude week land on different days, so the two providers get separate confs, anchors, and scheduled jobs. Take each day from that provider's own live reading.

**Scheduling.** Codex has no in-session scheduler and no cloud routines, so a host scheduler is the only route: launchd, a systemd timer, or cron. `scripts/burn.sh codex` is the entry point, the same as the Claude side.

**Config.** `~/.config/weekly-burn/codex.conf`, same shape as `claude.conf` in `docs/config.md`. `effort` is passed through as `model_reasoning_effort`, and `permission_mode` is a sandbox policy: `read-only`, `workspace-write`, or `danger-full-access`.

**Authentication survives a scheduled job.** Codex resolves one credential store, `~/.codex/auth.json`, which a launchd or cron job reads like any other file. The shadowed-credential problem in `docs/scheduling.md` is Claude-side only.

## Skill discovery

Codex has no skill mechanism at 0.166.0: no `skills` subcommand, nothing for it in `config.toml`, and `codex plugin` only reaches marketplace plugins. So `scripts/install-global-skill.sh` leaves Codex a pointer instead, in `~/.codex/AGENTS.md`, which Codex loads in every session. A pointer in an always-loaded file does the same work a skill description does: it says what the material is and when to reach for it.

Verified on 0.166.0. A `codex exec` run handed "add that to the burn list" followed the pointer, read the skill, wrote a brief with scope boundaries, and inserted a correctly formatted row, for about 15k tokens.

The plan sits outside your workspace, so a sandboxed run needs its directory made writable before the row can be written:

```bash
codex exec --sandbox workspace-write \
  --add-dir "$(dirname "$(cat ~/.config/weekly-burn/plan-path)")" ...
```

An interactive session asks for approval instead of needing the flag. The burner itself is unaffected either way, because `scripts/burn.sh` passes `.codex/prompts/burn-remaining.md` directly as the prompt.
