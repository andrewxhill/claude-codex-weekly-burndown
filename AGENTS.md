# claude-codex-weekly-burndown

Context for Codex CLI sessions in this repo. Read `CLAUDE.md` too; the project description there applies to both agents, and this file covers what differs for Codex.

**Setting it up?** Follow `.codex/prompts/set-up.md`.

## Status of the Codex side

Blocked, and honestly so. `docs/quota-detection.md` records the search: `codex-cli 0.166.0` exposes no non-interactive way to read the weekly window. No `usage`, `status`, `limit`, or `quota` subcommand exists, and no flag reports it.

That matters because the repo's first rule is to fail closed on an unreadable quota. A Codex burner today would fire against a budget it cannot see. Setup should tell the user that and leave the Codex trigger unarmed.

Unblock it by finding a quota surface and writing it into the `## Codex` section of `docs/quota-detection.md`. The candidates listed there: `codex doctor`, driving the TUI's status display non-interactively, and cached limit state under `~/.codex/`.

## What differs from the Claude side

**Triggering.** Codex has no in-session scheduler and no cloud routines, so the local launchd path is the only one. `scripts/burn-wrapper.sh` is Claude-specific; Codex needs its own entry point calling `codex exec` with the `burn-remaining` prompt, the configured model, and the reasoning level from `codex.conf`.

**Skill discovery.** Codex does not read `~/.agents/skills` the way Claude Code does, so `scripts/install-global-skill.sh` alone leaves `add-job-to-burn-plan` invisible to Codex sessions. Find the surface Codex honors, check `codex --help`, `~/.codex/config.toml`, and `~/.codex/AGENTS.md`, confirm it triggers, then record what worked under `## Codex global skill` in `docs/quota-detection.md`.

**Config.** `~/.config/weekly-burn/codex.conf`, same shape as `claude.conf` in `docs/config.md`, with reasoning level in place of effort. `plan-path` and `repo-path` are shared.

## Rules that bite

Everything under that heading in `CLAUDE.md` applies here. Read it.
