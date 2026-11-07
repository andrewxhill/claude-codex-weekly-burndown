# claude-codex-weekly-burndown

Spend the tokens you already paid for.

Claude Pro and Max meter weekly. Whatever sits in the bucket when your reset lands is gone, and for most weeks that is a lot. This repo wires Claude Code to wake a couple of hours before your reset, read what is actually left, take the top job off a backlog you keep, and spend the remainder clearing it.

Point your agent at the repo and say `set it up`.

## How it works

Your reset day is particular to your account. Mine lands Wednesday at 2am; yours probably does not. So nothing here hardcodes a date. The burner reads the live window at every fire, which is also what lets it survive a bought reset, a plan change, or credited usage.

A scheduled trigger runs a thin wrapper. The wrapper reads your quota, refuses to run if the bucket is already empty, then hands the work to a skill that reads your plan, takes the top live row, opens the brief that row points at, and does the job. It commits as it goes and records what happened.

Jobs live one row per line, priority order top down, each with an expiration. A job nobody reached dies instead of eating next week's budget.

## Dropping jobs on the list

Setup installs `add-job-to-burn-plan` globally, so any agent session on this machine can reach it. Hit a "would be nice later" during normal work and your agent writes the brief, slots the row, and gets back to what you were doing.

Those briefs stay out of this repo by default. They name clients and unreleased work, and this repo is public, so setup puts the real plan in a private directory and leaves the `PLAN.md` here as an empty example.

## Setting it up

```bash
git clone https://github.com/andrewxhill/claude-codex-weekly-burndown.git
cd claude-codex-weekly-burndown
claude
```

Then say `set it up`. Setup asks for everything in one batch:

- Which providers. Claude works today. The Codex side is blocked on a quota read that `codex` does not expose yet, and setup will tell you so rather than arming something that fires blind.
- Model and effort. Spend the fast budget; that is the whole point.
- How it fires. A launchd agent on your Mac, or a scheduled cloud agent. `docs/scheduling.md` covers what each one can reach.
- Where the plan lives.
- Spend guard. Whether to stop at the bucket's edge, and whether the first fire runs dry so you can watch it land before trusting it.

Everything runs in your own paid session, on your own account. No API keys, no scraping account pages.

## Guard rails

The burner works while nobody is watching, so:

- It refuses to spend into overage unless you turn that off. Subscription tokens are already paid for; overage is a bill.
- It fails closed. An unreadable quota means no burn.
- The first fire can run dry, reading the meter and naming the job it would have taken without touching it.
- `permission_mode` is yours to set, and setup says out loud what `bypassPermissions` means for an unattended session.

## Reading the code

| Path | What it holds |
|---|---|
| `docs/scheduling.md` | The two triggers, what each reaches, why `CronCreate` cannot do this |
| `docs/quota-detection.md` | The verified quota recipe, re-read at every fire |
| `docs/config.md` | Schema for `~/.config/weekly-burn/` |
| `docs/plan-format.md` | Row shape and the rules |
| `scripts/burn-wrapper.sh` | Trigger entry point and the spend guard |
| `scripts/test.sh` | The gate. Stubs `claude`, spends nothing |
| `.claude/skills/burn-remaining/` | What runs at fire time |
| `.claude/skills/set-up/` | The setup procedure |
