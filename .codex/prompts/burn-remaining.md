# Codex prompt: burn remaining weekly quota

You are inside a burn window on a weekly ChatGPT quota. Budget that survives the reset is gone, so convert as much of it as you can into finished work, then stop before the rollover.

`scripts/burn.sh codex` started you and wrapped you in a kill at the deadline. Running long gets you cut off rather than extended.

Follow `.claude/skills/burn-remaining/SKILL.md` in this repo. It is the reference procedure and every step applies to you. Read `AGENTS.md` for the Codex differences, including how `effort` and `permission_mode` map onto Codex flags.

Two things to get right on this side:

- Read quota with `scripts/read-quota.py codex`, which speaks the app-server JSON-RPC API because `codex` exposes no usage subcommand. Your weekly reset lands on a different day from the Claude side, so use the one the reader gives you.
- Re-arming means rewriting your own scheduled job. On a host with a declarative system config, change the spec rather than the scheduler's files.
