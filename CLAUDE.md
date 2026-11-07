# claude-codex-weekly-burndown

Project context for Claude Code sessions in this repo. Every session loads this file, so it describes the project and leaves procedures to the skills.

**Setting it up?** Invoke the `set-up` skill. Keeping the procedure there is what stops a session asked to fix a typo from re-running setup.

## What this is

A weekly-quota burner. Claude and Codex subscriptions both meter weekly, and whatever sits unspent when the reset lands is gone. One scheduled job per provider opens a **burn window** of the user's chosen length before that provider's reset, then works a backlog until the budget or the clock runs out.

## How the pieces fit

`scripts/burn.sh <claude|codex>` is what a scheduler fires. It reads the live quota through `scripts/read-quota.py`, refuses a spent bucket, computes a hard deadline from the live reset, and runs the `burn-remaining` skill under a kill at that deadline.

Claude and Codex meter on separate clocks and reset on different days, so each gets its own conf and its own scheduled job. `docs/config.md` has the schema, and `~/.config/weekly-burn/` holds the live values.

The real plan lives outside this repo. `add-job-to-burn-plan` installs globally and fires during work in other repos, so a brief can name a client or unreleased work, and this repo is public. The `PLAN.md` here is an inert format example.

## Rules that bite

**Read the reset live at every fire.** Reset days differ per account and per provider, so a hardcoded weekday is wrong for most people. `docs/quota-detection.md` holds the verified recipe for both providers.

**Quota comes back as a percentage.** Neither CLI exposes a token count on any surface. The gate fails the build on a doc that claims otherwise.

**Fail closed on an unreadable quota.** A partial burn against an unknown budget costs more than a skipped week, so the reader exits non-zero and nothing spends.

**`burn.sh` enforces the hard stop.** Quota spent past the rollover comes out of next week, so the runner kills the agent at the window edge rather than trusting it to stop. Exit 124, 143, or 137 is the designed ending. `docs/scheduling.md` has the window math.

**Keep quota reading in one place.** `scripts/read-quota.py` handles both providers and prints one shape, because the runner computes a timeout from the reset time and prose yields no timeout.

**Only a host scheduler can fire this.** `CronCreate` is session-only, lives in memory, and expires after seven days. `docs/scheduling.md` covers launchd, systemd, and cron.

**Prove the chain through the scheduler.** A scheduled job can resolve a different credential from your shell. Claude Code prefers the keychain item `Claude Code-credentials` over `~/.claude/.credentials.json`, and an item emptied by a sign-out still counts as existing, so a job reading the keychain authenticates as nobody and runs an anonymous session that does nothing and reports success. `docs/scheduling.md` has the comparison and the command that clears it. Codex resolves one file and is unaffected. A terminal run proves nothing about the scheduled one.

**Check the host before assuming macOS.** Setup picks the scheduler from what it finds there. Stock macOS ships no `timeout`, so the runner carries a watchdog fallback.

**Scope every brief as though nobody is watching, because nobody is.** The boundaries written into a brief are all that stands between a backlog row and an agent with a large budget and no supervision.

## Before you claim it works

`./scripts/test.sh` is the gate. It stubs both provider binaries, so it spends nothing. Run it and quote the output.
