#!/usr/bin/env python3
"""Read a provider's weekly quota window. Print uniform JSON, or fail.

    read-quota.py claude
    read-quota.py codex

Output:
    {"provider": "...", "used_percent": 24, "resets_at_iso": "...",
     "window_duration_mins": 10080, "spend_allowed": true, "detail": "..."}

Both numbers have to be machine readable, because the runner computes a hard
deadline from the reset time and refuses to start on a bucket that is spent.
Prose cannot be turned into a timeout. When a provider reworks its output this
script fails loudly instead of guessing, and docs/quota-detection.md says how to
re-derive it.

Binaries: CLAUDE_BIN / CODEX_BIN override PATH lookup. Scheduled jobs need that.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone

WEEKLY_MINS = 7 * 24 * 60


def die(msg):
    print(f"read-quota: {msg}", file=sys.stderr)
    sys.exit(1)


def binary(env_var, name):
    found = os.environ.get(env_var) or shutil.which(name)
    if not found:
        die(f"cannot find the {name} binary. Scheduled jobs get a minimal PATH, so set "
            f"{env_var} in the job definition. PATH was: {os.environ.get('PATH','')}")
    return found


# --- claude ---------------------------------------------------------------
# `claude -p "/usage"` prints lines like:
#   Current week (all models): 24% used · resets Nov 11 at 2am (America/Los_Angeles)
# There is no token count and no machine-readable surface; this is the only one.
USAGE_RE = re.compile(
    r"Current week \((?P<bucket>[^)]+)\):\s*(?P<pct>\d+)%\s*used.*?resets\s+"
    r"(?P<mon>[A-Z][a-z]{2})\s+(?P<day>\d{1,2})\s+at\s+(?P<time>\d{1,2}(?::\d{2})?)\s*(?P<ampm>[ap]m)"
    r"\s*\((?P<tz>[^)]+)\)",
    re.IGNORECASE,
)
MONTHS = {m: i + 1 for i, m in enumerate(
    ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"])}


def parse_claude_reset(mon, day, time_s, ampm, tzname):
    try:
        from zoneinfo import ZoneInfo
        tz = ZoneInfo(tzname)
    except Exception:
        die(f"unknown timezone {tzname!r} in the /usage output")
    hour, _, minute = time_s.partition(":")
    hour, minute = int(hour), int(minute or 0)
    if ampm.lower() == "pm" and hour != 12:
        hour += 12
    if ampm.lower() == "am" and hour == 12:
        hour = 0
    month = MONTHS[mon.lower()[:3]]
    now = datetime.now(tz)
    # The string carries no year. Take this year, and roll forward when that
    # lands in the past, which happens every late December.
    for year in (now.year, now.year + 1):
        when = datetime(year, month, int(day), hour, minute, tzinfo=tz)
        if when >= now - timedelta(hours=12):
            return when
    die("could not place the reset date in a sane year")


def logged_in(claude):
    """Ask claude whether it is authenticated. Unparseable means assume it is,
    so a broken probe never masks a genuine format change."""
    try:
        out = subprocess.run([claude, "auth", "status"],
                             capture_output=True, text=True, timeout=60).stdout
        return json.loads(out).get("loggedIn") is not False
    except Exception:
        return True


def read_claude(model_hint):
    claude = binary("CLAUDE_BIN", "claude")
    try:
        out = subprocess.run([claude, "-p", "/usage", "--model", "haiku"],
                             capture_output=True, text=True, timeout=180).stdout
    except subprocess.TimeoutExpired:
        die("the /usage read timed out after 180s")

    buckets = {m.group("bucket").strip().lower(): m for m in USAGE_RE.finditer(out)}
    if not buckets:
        # The most common cause is not a reworded /usage, it is a scheduled job
        # that cannot authenticate. On macOS the credentials sit in the login
        # keychain, and a launchd or cron job cannot read it, so claude runs an
        # anonymous session that does no work and prints a zero-cost summary.
        # Checking auth here turns a confusing parse error into the real reason.
        if not logged_in(claude):
            die("claude is not authenticated in this environment, so there is no "
                "quota to read. A scheduled job cannot reach the macOS login "
                "keychain where `claude` keeps its credentials, even though your "
                "interactive shell can. Mint a long-lived token with "
                "`claude setup-token` and put it in the job's environment as "
                "CLAUDE_CODE_OAUTH_TOKEN. docs/scheduling.md covers this.")
        die("no weekly line matched in the /usage output, and auth looks fine, so "
            "the output shape probably changed. Refusing to spend on an unknown "
            f"quota. Re-check docs/quota-detection.md. Output began: {out[:200]!r}")

    # `all models` meters everything. A Fable model also draws on its own bucket,
    # so take whichever of the two relevant buckets is further along.
    relevant = [m for name, m in buckets.items()
                if name == "all models" or (model_hint and name in model_hint.lower())]
    if not relevant:
        relevant = list(buckets.values())
    worst = max(relevant, key=lambda m: int(m.group("pct")))
    reset = parse_claude_reset(worst.group("mon"), worst.group("day"),
                               worst.group("time"), worst.group("ampm"), worst.group("tz"))
    return {
        "provider": "claude",
        "used_percent": int(worst.group("pct")),
        "resets_at_iso": reset.isoformat(),
        "window_duration_mins": WEEKLY_MINS,
        "spend_allowed": int(worst.group("pct")) < 100,
        "detail": f"bucket={worst.group('bucket').strip()} buckets_seen={sorted(buckets)}",
    }


# --- codex ----------------------------------------------------------------
# No `usage` subcommand exists. The numbers come from the app-server's JSON-RPC
# method `account/rateLimits/read`.
def read_codex(_model_hint):
    codex = binary("CODEX_BIN", "codex")
    proc = subprocess.Popen([codex, "app-server"], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, bufsize=1)

    def send(req):
        proc.stdin.write(json.dumps(req) + "\n")
        proc.stdin.flush()

    def result_for(want_id):
        while True:
            line = proc.stdout.readline()
            if not line:
                return None
            try:
                msg = json.loads(line.strip())
            except json.JSONDecodeError:
                continue
            if msg.get("id") != want_id:
                continue
            if "error" in msg:
                die(f"app-server error on id {want_id}: {msg['error']}")
            return msg.get("result")

    try:
        send({"id": 1, "method": "initialize",
              "params": {"clientInfo": {"name": "weekly-burn", "version": "1.0.0"},
                         "capabilities": {"experimentalApi": True}}})
        if result_for(1) is None:
            die(f"app-server closed during initialize. stderr: {proc.stderr.read()[:300]}")
        send({"id": 2, "method": "account/rateLimits/read", "params": None})
        payload = result_for(2)
        if payload is None:
            die(f"app-server closed before answering. stderr: {proc.stderr.read()[:300]}")
    finally:
        try:
            proc.stdin.close()
            proc.wait(timeout=5)
        except Exception:
            proc.kill()

    snap = payload.get("rateLimits")
    if not isinstance(snap, dict):
        die("the response carried no rateLimits snapshot")

    windows = [(slot, w) for slot in ("primary", "secondary")
               if isinstance(w := snap.get(slot), dict) and "usedPercent" in w]
    if not windows:
        die("no rate limit window carried a usedPercent; the protocol shape changed")

    # Match on the declared duration. The slots have swapped before, and guessing
    # which one is weekly spends real budget.
    weekly = [(s, w) for s, w in windows
              if isinstance(w.get("windowDurationMins"), int)
              and w["windowDurationMins"] >= WEEKLY_MINS * 0.9]
    if not weekly:
        die("no window looks weekly; durations were "
            f"{ {s: w.get('windowDurationMins') for s, w in windows} }. "
            "Check docs/quota-detection.md against this Codex version.")
    slot, win = max(weekly, key=lambda sw: sw[1]["windowDurationMins"])

    resets_at = win.get("resetsAt")
    if not isinstance(resets_at, int):
        die("the weekly window carried no resetsAt, so the next reset is unknown")

    # The backend owns this flag and its schema warns against inferring recovery
    # from percentages, so trust it over the number when it says no.
    allowed = payload.get("ordinaryUsageAllowed")
    return {
        "provider": "codex",
        "used_percent": win["usedPercent"],
        "resets_at_iso": datetime.fromtimestamp(resets_at, tz=timezone.utc).isoformat(),
        "window_duration_mins": win["windowDurationMins"],
        "spend_allowed": bool(allowed) and win["usedPercent"] < 100 if allowed is not None
                         else win["usedPercent"] < 100,
        "detail": (f"slot={slot} plan={snap.get('planType')} "
                   f"ordinary_usage_allowed={allowed} "
                   f"reached={snap.get('rateLimitReachedType')}"),
    }


READERS = {"claude": read_claude, "codex": read_codex}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in READERS:
        die(f"usage: read-quota.py <{'|'.join(READERS)}> [model]")
    model_hint = sys.argv[2] if len(sys.argv) > 2 else ""
    print(json.dumps(READERS[sys.argv[1]](model_hint), indent=2))


if __name__ == "__main__":
    main()
