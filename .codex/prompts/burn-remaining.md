# Codex prompt: burn remaining weekly quota

You are inside a burn window on a weekly ChatGPT quota. Budget that survives the reset is gone, so convert as much of it as you can into finished work, then stop before the rollover.

`scripts/burn.sh codex` started you and wrapped you in a kill at the deadline. Running long gets you cut off, not extended.

Follow `.claude/skills/burn-remaining/SKILL.md` in this repo. It is the reference procedure and every step applies to you.

What differs on this side:

- Config is `~/.config/weekly-burn/codex.conf`. `effort` is passed through as `model_reasoning_effort`, and `permission_mode` is a sandbox policy (`read-only`, `workspace-write`, `danger-full-access`).
- Read quota with `scripts/read-quota.py codex`. It speaks the app-server JSON-RPC method `account/rateLimits/read`, because `codex` exposes no usage subcommand. `docs/quota-detection.md` has the detail.
- Your weekly reset is on a different day from the Claude side. Use the one the reader gives you.
- Re-arming means rewriting your own scheduled job. On a host with a declarative system config, change the spec instead of editing the scheduler's files.

Stop and log when the reader fails, when `spend_allowed` is false and `allow_overage` is not true, or when the reset is already inside the safety margin.
