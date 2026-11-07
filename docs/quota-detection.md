# Quota detection

Every fire reads the live window. Nothing in this repo trusts a reset time written down a week earlier.

`scripts/read-quota.py <provider>` is the one place that reads it, and it prints the same shape for both providers:

```json
{
  "provider": "claude",
  "used_percent": 27,
  "resets_at_iso": "2026-11-11T02:00:00-08:00",
  "window_duration_mins": 10080,
  "spend_allowed": true,
  "detail": "bucket=all models buckets_seen=['all models', 'fable']"
}
```

Both numbers have to be machine readable. The runner turns `resets_at_iso` into a hard deadline and kills the burner at it, and you cannot compute a timeout from prose. When a provider reworks its output the reader exits non-zero with the reason, the runner refuses to spend, and you get a notification. It never guesses.

## Claude

Verified against Claude Code 2.1.319 on 2026-11-06.

```bash
claude -p "/usage" --model haiku
```

Slash commands work in print mode. Pinning to `haiku` makes reading the meter almost free.

```
You are currently using your subscription to power your Claude Code usage

Current week (all models): 27% used · resets Nov 11 at 2am (America/Los_Angeles)
Current week (Fable): 6% used · resets Nov 11 at 1:59am (America/Los_Angeles)
```

Claude Code reports **percent of the weekly bucket used**. No token count appears anywhere, and no flag or subcommand exposes one: `claude --help` lists no `usage`, `quota`, or `limit` command, and `~/.claude.json` caches per-project cost totals rather than the weekly window. Write percentages in anything you add here.

Two buckets meter separately. `all models` covers everything; `Fable` has its own allowance. The reader takes whichever of the two relevant buckets is further along, so a Fable model does not get waved through on the strength of the all-models number.

The reset string carries no year, so the reader takes the current year and rolls forward when that lands in the past. The timezone sits in the parentheses and gets used as given.

## Codex

Verified against codex-cli 0.166.0 on 2026-11-06.

There is no `usage` subcommand, and `codex exec --json` reports per-turn tokens with no weekly window. The numbers live in the app-server's JSON-RPC API, so the reader speaks that protocol over stdio:

```
→ {"id":1,"method":"initialize","params":{"clientInfo":{"name":"weekly-burn","version":"1.0.0"},
                                          "capabilities":{"experimentalApi":true}}}
→ {"id":2,"method":"account/rateLimits/read","params":null}
```

The response carries a `rateLimits` snapshot holding two windows, `primary` and `secondary`. Each has `usedPercent`, `resetsAt` as a unix epoch, and `windowDurationMins`.

**Match the weekly window on its declared duration, not on its slot.** On this account the weekly window arrived as `primary` with `windowDurationMins: 10080`, which is not where you would guess. The slots have moved before, and picking the wrong one spends real budget against the wrong clock.

A real reading from this account:

```json
{"used_percent": 5, "resets_at_iso": "2026-11-13T21:16:04+00:00",
 "window_duration_mins": 10080, "detail": "slot=primary plan=prolite ordinary_usage_allowed=True"}
```

`ordinaryUsageAllowed` sits on the response, and the protocol schema says outright that clients must not infer recovery from percentages or reset times. So the reader trusts that flag over the number when it says no.

Regenerate the protocol schema when something stops matching:

```bash
codex app-server generate-json-schema --out /tmp/codex-schema
grep -rl 'GetAccountRateLimits' /tmp/codex-schema
```

`codex app-server` is marked experimental. Expect it to move, and re-verify before blaming the burner.

## When a read fails

Fail closed. An unknown budget means no burn:

1. `read-quota.py` exits non-zero with the reason on stderr.
2. `burn.sh` logs the abort to `~/.local/state/weekly-burn/last-run.log` and raises a notification.
3. Nothing runs. A partial burn against an unknown budget is worse than a skipped week.

No retry loop. A failed read almost always means the provider changed shape, and waiting fifteen minutes will not fix that. Read the log, fix this file and the reader, run `scripts/burn.sh <provider>` by hand.
