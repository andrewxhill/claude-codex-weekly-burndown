# claude-codex-weekly-burndown

Project context for Codex CLI sessions in this repo. Read `CLAUDE.md` as well: the project description and the "Rules that bite" there apply to both agents, and this file covers only what differs for Codex.

**Setting it up?** Follow `.codex/prompts/set-up.md`.

## What differs on the Codex side

**Quota reading.** `codex` exposes no `usage` subcommand, so `scripts/read-quota.py codex` speaks the app-server JSON-RPC method `account/rateLimits/read` and prints the same shape the Claude side prints. `docs/quota-detection.md` has the protocol detail and the command that regenerates the schema when it moves.

**A different reset day.** The Codex week and the Claude week land on different days, so the two providers get separate confs, anchors, and scheduled jobs. Take each day from that provider's own live reading.

**Scheduling.** Codex has no in-session scheduler and no cloud routines, so a host scheduler is the only route: launchd, a systemd timer, or cron. `scripts/burn.sh codex` is the entry point, the same as the Claude side.

**Config.** `~/.config/weekly-burn/codex.conf`, same shape as `claude.conf` in `docs/config.md`. `effort` is passed through as `model_reasoning_effort`, and `permission_mode` is a sandbox policy: `read-only`, `workspace-write`, or `danger-full-access`.

**Authentication survives a scheduled job.** Codex resolves one credential store, `~/.codex/auth.json`, which a launchd or cron job reads like any other file. The shadowed-credential problem in `docs/scheduling.md` is Claude-side only.

## Open question: skill discovery

Codex does not read `~/.agents/skills` the way Claude Code does, so `scripts/install-global-skill.sh` alone leaves `add-job-to-burn-plan` invisible to Codex sessions.

To close this: find the surface Codex honors by checking `codex --help`, `~/.codex/config.toml`, and `~/.codex/AGENTS.md`, confirm it triggers, then record what worked in this section. The burner does not depend on it, because `scripts/burn.sh` passes `.codex/prompts/burn-remaining.md` directly as the prompt.
