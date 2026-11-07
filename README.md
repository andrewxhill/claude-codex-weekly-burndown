# claude-codex-weekly-burndown

Spend the tokens you already paid for.

Claude and Codex both meter weekly. Whatever sits in the bucket when your reset lands is gone, and for most weeks that is a lot. This repo opens a burn window before each reset, reads what is actually left, and works a backlog you keep until the budget runs out or the rollover arrives.

Point your agent at the repo and say `set it up`.

## The burn window

You pick how long it is. Six hours means the burner starts six hours before your reset and works until the rollover is nearly on top of it, then stops.

The stopping is the part worth being careful about. Quota spent after the reset comes out of next week, which defeats the whole exercise, so the burner does not get to decide when to quit. `scripts/burn.sh` computes the deadline from the live reset time, tells the agent how long it has, and kills it at the edge. An agent that loses track of time gets stopped regardless.

Inside the window it works the plan from the top, job after job, committing as it goes and recording each outcome before starting the next. A kill at the deadline then costs you nothing but the job in flight.

Reset days are particular to each account and each provider. Mine land Wednesday for Claude and Friday for Codex, so nothing here hardcodes a date. Reading the window live is also what survives a bought reset, a plan change, or credited usage.

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

- Which providers, from the ones it finds installed and logged in.
- Model and effort per provider. Spend the fast budget; that is the whole point.
- How long the burn window runs.
- Where the plan lives.
- Spend guard, and whether the first fire runs dry so you can watch it land before trusting it.
- How you want to hear about a failure.

Setup checks your OS and picks the scheduler: launchd, a systemd timer, or cron. It then fires the job once through that scheduler, in dry-run mode, which costs one cheap quota read and proves the chain end to end.

Everything runs in your own paid session, on your own account. No API keys, no scraping account pages.

Windows is untested. Setup will say so rather than pretending.

## Guard rails

The burner works while nobody is watching, so:

- It refuses to spend into overage unless you turn that off. Subscription tokens are already paid for; overage is a bill.
- It fails closed. An unreadable quota means no burn.
- The first fire can run dry, reading the meter and naming the job it would have taken without touching it.
- `permission_mode` is yours to set, and setup says out loud what the full-access options mean for an unattended session.
- A failure reaches you. Aborts raise a desktop notification, or run a command of your choosing.

## Reading the code

| Path | What it holds |
|---|---|
| `docs/scheduling.md` | The two triggers, what each reaches, why `CronCreate` cannot do this |
| `docs/quota-detection.md` | The verified quota recipe, re-read at every fire |
| `docs/config.md` | Schema for `~/.config/weekly-burn/` |
| `docs/plan-format.md` | Row shape and the rules |
| `scripts/burn.sh` | Trigger entry point: guard, deadline, hard stop |
| `scripts/read-quota.py` | Reads the weekly window for either provider |
| `scripts/test.sh` | The gate. Stubs `claude`, spends nothing |
| `.claude/skills/burn-remaining/` | What runs at fire time |
| `.claude/skills/set-up/` | The setup procedure |
