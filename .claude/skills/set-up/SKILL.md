---
name: set-up
description: Wire this machine's Claude Code to burn remaining weekly quota a couple of hours before reset. Use when the user is inside the weekly-burn repo and says "set it up", "set up weekly burn", or points Claude at the repo for the first time.
---

Turn this scaffold into a working burner for the user's account, then leave the machine armed. Work in order. Stop and report the exact failure if a step fails; do not patch around it.

Read `docs/scheduling.md`, `docs/config.md`, and `docs/quota-detection.md` before you ask anything. They carry the decisions this skill depends on.

## 1. Ask everything in one batch

Use `AskUserQuestion`. One call, all of it. Do not walk them through one question at a time.

**Providers.** Claude, Codex, or both. Check `docs/quota-detection.md` first: while the Codex quota read is listed unresolved, say so and recommend Claude only. Arming a burner against a quota nobody can read breaks the fail-closed rule.

**Model.** Recommend the strongest model on their plan, since the point is spending the fast budget. Say which weekly bucket that model drains; `all models` and `Fable` meter separately.

**Effort.** `low`, `medium`, `high`, `xhigh`, or `max`. Recommend `high`.

**Trigger.** `launchd` or `cloud-routine`, from `docs/scheduling.md`. Recommend `launchd`: every path in this repo assumes local config, local state, and a local worktree. Name the tradeoff, that a sleeping Mac misses the window.

**Plan location.** Recommend a private path outside this repo, defaulting to `~/.local/state/weekly-burn/plan/PLAN.md`. Tell them why: `add-job-to-burn-plan` fires during work in other repos, and a brief can name a client or an unreleased feature. Offer the repo's own `PLAN.md` as the choice it is, with the consequence stated.

**Spend guard.** Whether to refuse once the bucket hits 100%, and whether the first fire runs dry. Recommend both. Subscription tokens are already paid for and overage is not, and nobody wants to learn their trigger works by reading a surprise diff.

**Permission mode.** The burner runs with nobody watching. Recommend `acceptEdits`. Say plainly that `bypassPermissions` lets an unattended session run anything, and that `manual` hangs on the first prompt until the window shuts.

## 2. Read the live reset time

Run the `## Claude` recipe in `docs/quota-detection.md`. Record the percent used and the reset time with its timezone.

Do not hardcode a weekday or an hour. Read it from the account, every time. Reset days differ between accounts.

Re-verify the recipe against the installed version while you are here. Update `docs/quota-detection.md` when the output has changed shape, including the version you checked and the date. The burner reads that file at fire time, so a stale doc is a failed fire.

## 3. Write config

Create `~/.config/weekly-burn/` and write `plan-path`, `repo-path`, and `claude.conf` exactly as `docs/config.md` specifies. Every key, including `reset_anchor` from step 2 and `lead_minutes`.

Set `dry_run=true` when they asked for a dry first fire.

Create the plan directory, and seed `PLAN.md` with the two headings from `docs/plan-format.md` when no plan exists there yet. Create `~/.local/state/weekly-burn/`.

## 4. Install the trigger

Compute the fire time: live reset minus `lead_minutes`, in the user's local zone.

For `trigger=launchd`, point the agent at `scripts/burn-wrapper.sh` and set `CLAUDE_BIN` in its environment to the absolute path of the user's `claude`. Skip that and the fire dies on its first call, because launchd's PATH excludes wherever `claude` is installed. `docs/scheduling.md` has a worked plist. Check for a declarative system spec first; on this machine that is `~/Projects/_infra/macos-spec`, which owns `launchd.user.agents` through nix-darwin, and the agent belongs there rather than hand-written into `~/Library/LaunchAgents/`. Use the `nix-darwin-update` skill for that change. Without a spec, write the plist and load it with the full path argument as `docs/scheduling.md` shows.

For `trigger=cloud-routine`, use the `schedule` skill. Work through the four constraints in `docs/scheduling.md` before you create anything: the routine sees no local skills, no local config, no local state, and its commits need a push to reach the user. Say which of those you solved and how.

Record `trigger` and `trigger_id` in `claude.conf`.

## 5. Install the global skill

Run `scripts/install-global-skill.sh`. It symlinks `skills/add-job-to-burn-plan` into `~/.agents/skills/`, which Claude Code reads through `~/.claude/skills`.

Confirm the link resolves and the skill's frontmatter parses. A dead symlink here means the skill silently never triggers.

## 6. Verify, without firing

Run `./scripts/test.sh` and quote the result.

Then show the user: next fire time in their zone, model, effort, permission mode, plan path, whether the first fire is dry, and the trigger id. Confirm the global skill resolves.

Do not run the burner. Verification is structural. The dry first fire is what proves the trigger, and it proves it on schedule.

## 7. Commit

Commit what you filled in. Short imperative subject, and a body saying why the choices landed where they did. Do not push unless they ask.
