# Quota detection

The burner reads live quota at every fire and never trusts a date written down a week earlier. This file holds the recipe it follows. Update this file when a provider rewords its output; the burner reads it at runtime, so a reword is a docs fix rather than a code change.

One exception, on purpose: `scripts/burn-wrapper.sh` pulls the percentage out of `/usage` itself, because a wrapper that cannot see the quota cannot refuse to spend past it. That is the only number baked into code, and it fails closed when the pattern stops matching.

## Claude

Verified against Claude Code 2.1.319 on 2026-11-06.

### Command

```bash
claude -p "/usage" --model haiku
```

Slash commands work in print mode. Pin the model to `haiku` so reading the meter costs almost nothing.

### Output

```
You are currently using your subscription to power your Claude Code usage

Current week (all models): 24% used · resets Nov 11 at 2am (America/Los_Angeles)
Current week (Fable): 6% used · resets Nov 11 at 1:59am (America/Los_Angeles)

What's contributing to your usage?
Approximate · sessions on this machine only · shares overlap
...
```

### What you get, and what you do not

Claude Code reports **percent of the weekly bucket already used**. There is no token count anywhere in this output, and no CLI flag or subcommand exposes one. `claude --help` lists no `usage`, `quota`, or `limit` command, and `~/.claude.json` caches per-project cost totals rather than the weekly window. Write "percent used" in anything you add here. A plan written around a token count needs rewriting.

Two buckets reset on their own clocks:

- `all models` covers everything.
- `Fable` has a separate allowance.

The bucket you drain depends on the model in `claude.conf`. Check `all models` always, and check `Fable` too when the configured model is a Fable.

### Parsing the reset time

`resets Nov 11 at 2am (America/Los_Angeles)` carries no year. Take the year from today's date, and if the parsed date lands in the past, roll it forward one year. The timezone sits in the parentheses; use it rather than assuming the machine's zone.

Treat the whole string as prose that Anthropic may reword. Match loosely, and when a match fails, stop instead of guessing.

### Reset cadence

Weekly, on a day and hour particular to the account. The example above resets Wednesday at 2am Los Angeles time. Do not assume Sunday, and do not copy another account's day. Read it.

### When the read fails

Fail closed. An unknown quota means no burn:

1. Append the failure to `~/.local/state/weekly-burn/last-run.log`.
2. Skip the job. A partial burn against an unknown budget is worse than a skipped week.
3. Exit non-zero so the trigger's own logs show it.

The wrapper does not retry. The launchd trigger fires weekly, a failed read almost always means `/usage` changed shape, and fifteen minutes will not fix that. Read the log, fix this file, run the wrapper by hand.

## Codex

Unresolved as of 2026-11-06, against `codex-cli 0.166.0`.

No non-interactive quota surface turned up. `codex --help` lists no `usage`, `status`, `limit`, or `quota` subcommand, and nothing in the flag list reports the weekly window. The subcommands that exist cover sessions, auth, MCP, plugins, sandboxing, and cloud tasks.

Candidates for whoever picks this up:

- `codex doctor`, which diagnoses install, config, auth, and runtime health, and may print limit state.
- The interactive TUI's own status display, if it can be driven non-interactively.
- Files under `~/.codex/`, checked for a cached limit window.

Until one of those pans out, the Codex burner cannot satisfy the fail-closed rule above, so setup should not arm it. Say that to the user rather than wiring a trigger that spends against a quota nobody can read.

## Codex global skill

Codex does not read `~/.agents/skills` the way Claude Code does. Record here what surface you used to expose `add-job-to-burn-plan` to Codex sessions, once you have confirmed one works.
