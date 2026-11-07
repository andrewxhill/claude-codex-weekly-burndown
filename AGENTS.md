# claude-codex-weekly-burndown

Context for Codex CLI sessions in this repo. Read `CLAUDE.md` too; the project description there applies to both agents, and this file covers what differs for Codex.

**Setting it up?** Follow `.codex/prompts/set-up.md`.

## What differs on the Codex side

The Codex quota read works. `codex` has no `usage` subcommand, so `scripts/read-quota.py codex` speaks the app-server JSON-RPC method `account/rateLimits/read` and prints the same shape the Claude side prints. `docs/quota-detection.md` has the protocol detail and the command that regenerates the schema when it moves.

**Different reset day.** This account's Codex week and Claude week land on different days, so the two providers get separate confs, separate anchors, and separate scheduled jobs. Never copy one provider's day to the other.

**Scheduling.** Codex has no in-session scheduler and no cloud routines, so a host scheduler is the only option: launchd, a systemd timer, or cron. `scripts/burn.sh codex` is the entry point, same as the Claude side.

**Config.** `~/.config/weekly-burn/codex.conf`, same shape as `claude.conf` in `docs/config.md`. `effort` is passed through as `model_reasoning_effort`; `permission_mode` is a sandbox policy (`read-only`, `workspace-write`, `danger-full-access`).

**Skill discovery.** Codex does not read `~/.agents/skills` the way Claude Code does, so `scripts/install-global-skill.sh` alone leaves `add-job-to-burn-plan` invisible to Codex sessions. Find the surface Codex honors, check `codex --help`, `~/.codex/config.toml`, and `~/.codex/AGENTS.md`, confirm it triggers, then record what worked in `docs/quota-detection.md` under a Codex note. The burner itself does not depend on this; it reads the prompt file directly.

## Rules that bite

Everything under that heading in `CLAUDE.md` applies here. Read it.
