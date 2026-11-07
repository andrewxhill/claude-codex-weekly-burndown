#!/usr/bin/env bash
# Run the burn window for one provider.
#
#   burn.sh claude
#   burn.sh codex
#
# A scheduled job calls this when the burn window opens. It reads the live quota,
# refuses to start on a spent bucket, works out how long is left before the reset,
# then runs the burn-remaining skill under a hard timeout so the agent cannot
# overrun the rollover no matter what it decides.
#
# Config:  ~/.config/weekly-burn/        (override: WEEKLY_BURN_CONFIG_DIR)
# State:   ~/.local/state/weekly-burn/   (override: WEEKLY_BURN_STATE_DIR)
# Binaries: CLAUDE_BIN / CODEX_BIN. Scheduled jobs need these; their PATH is minimal.
set -uo pipefail

provider="${1:-}"
case "$provider" in
  claude|codex) ;;
  *) printf 'usage: %s <claude|codex>\n' "$0" >&2; exit 2 ;;
esac

here="$(cd "$(dirname "$0")" && pwd)"
config_dir="${WEEKLY_BURN_CONFIG_DIR:-$HOME/.config/weekly-burn}"
state_dir="${WEEKLY_BURN_STATE_DIR:-$HOME/.local/state/weekly-burn}"
conf="$config_dir/$provider.conf"
log="$state_dir/last-run.log"

mkdir -p "$state_dir" 2>/dev/null || { printf 'weekly-burn: cannot create %s\n' "$state_dir" >&2; exit 1; }

conf_get() {
  grep -E "^[[:space:]]*$1[[:space:]]*=" "$conf" 2>/dev/null | tail -1 | cut -d= -f2- \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

say() { printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$provider" "$1" | tee -a "$log"; }

alert() {
  local msg="$1"
  local cmd; cmd="$(conf_get alert_command 2>/dev/null || true)"
  if [ -n "$cmd" ]; then
    WEEKLY_BURN_MESSAGE="$msg" WEEKLY_BURN_PROVIDER="$provider" sh -c "$cmd" >/dev/null 2>&1 || true
  elif command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$msg\" with title \"weekly-burn ($provider)\"" >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "weekly-burn ($provider)" "$msg" >/dev/null 2>&1 || true
  fi
}

die() { say "ABORT $1"; alert "$1"; exit 1; }


# Stock macOS ships no `timeout`, so fall back to a watchdog. The hard stop is the
# whole point of a burn window; it cannot depend on coreutils being present.
run_with_deadline() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    "$@" &
    local job=$!
    ( sleep "$secs"; kill -TERM "$job" 2>/dev/null; sleep 10; kill -KILL "$job" 2>/dev/null ) &
    local watchdog=$!
    wait "$job"; local jrc=$?
    kill "$watchdog" 2>/dev/null
    return "$jrc"
  fi
}

[ -f "$conf" ] || { say "ABORT missing $conf; run the set-up skill"; alert "missing $conf"; exit 1; }

model="$(conf_get model)"
effort="$(conf_get effort)"
permission_mode="$(conf_get permission_mode)"
window_hours="$(conf_get window_hours)"
stop_margin_minutes="$(conf_get stop_margin_minutes)"
dry_run="$(conf_get dry_run)"
allow_overage="$(conf_get allow_overage)"

for k in model effort permission_mode window_hours stop_margin_minutes dry_run allow_overage; do
  [ -n "$(conf_get "$k")" ] || die "$conf has no value for $k"
done
for f in plan-path repo-path; do
  [ -f "$config_dir/$f" ] || die "missing $config_dir/$f; run the set-up skill"
done

plan_path="$(tr -d '\n' < "$config_dir/plan-path")"
repo_path="$(tr -d '\n' < "$config_dir/repo-path")"
plan_dir="$(dirname "$plan_path")"
[ -f "$plan_path" ] || die "no plan at $plan_path"
[ -d "$repo_path" ] || die "no repo at $repo_path"

# --- live quota ----------------------------------------------------------
quota="$("$here/read-quota.py" "$provider" "$model" 2>&1)" \
  || die "quota read failed, so the budget is unknown and nothing will run: $(printf '%s' "$quota" | tail -2 | tr '\n' ' ')"

jqf() { printf '%s' "$quota" | python3 -I -c "import json,sys;print(json.load(sys.stdin).get('$1',''))"; }
used_percent="$(jqf used_percent)"
resets_at="$(jqf resets_at_iso)"
spend_allowed="$(jqf spend_allowed)"
say "quota ${used_percent}% used, resets $resets_at ($(jqf detail))"

# --- deadline ------------------------------------------------------------
# Everything downstream is driven by seconds-until-stop, so a bad reset time
# stops the run here rather than producing a nonsense timeout.
seconds_left="$(python3 -I - "$resets_at" "$stop_margin_minutes" <<'PY'
import sys
from datetime import datetime, timedelta, timezone
try:
    reset = datetime.fromisoformat(sys.argv[1])
except ValueError:
    print("ERR"); raise SystemExit(0)
if reset.tzinfo is None:
    print("ERR"); raise SystemExit(0)
stop = reset - timedelta(minutes=int(sys.argv[2]))
print(int((stop - datetime.now(timezone.utc)).total_seconds()))
PY
)"
[ "$seconds_left" != "ERR" ] || die "could not parse the reset time $resets_at"

if [ "$seconds_left" -le 0 ]; then
  say "window already closed (reset $resets_at is within the ${stop_margin_minutes}m margin); nothing to do"
  exit 0
fi

# --- guard ---------------------------------------------------------------
guard_blocks=""
if [ "$allow_overage" != "true" ]; then
  [ "$spend_allowed" = "True" ] || [ "$spend_allowed" = "true" ] \
    || guard_blocks="provider reports spending is not allowed (${used_percent}% used)"
fi

# --- dry run -------------------------------------------------------------
if [ "$dry_run" = "true" ]; then
  top="$(grep -m1 -E '^- \[ \] ' "$plan_path" || true)"
  say "dry run: $([ -n "$top" ] && printf 'top of queue %s' "$top" || printf 'no open rows in %s' "$plan_path")"
  say "dry run: ${seconds_left}s of budget window left, hard stop ${stop_margin_minutes}m before $resets_at"
  say "dry run: guard would $([ -n "$guard_blocks" ] && printf 'BLOCK (%s)' "$guard_blocks" || printf 'allow')"
  say "dry run: fired correctly and spent nothing. Set dry_run=false in $conf to arm it."
  exit 0
fi

[ -z "$guard_blocks" ] || die "$guard_blocks; set allow_overage=true to spend past it"

# --- burn ----------------------------------------------------------------
hours_left=$(( seconds_left / 3600 )); mins_left=$(( (seconds_left % 3600) / 60 ))
say "starting burn: ${hours_left}h${mins_left}m until hard stop, model=$model effort=$effort"

brief="You are in a weekly burn window that closes at $resets_at, minus a ${stop_margin_minutes} minute safety margin.
You have ${hours_left}h${mins_left}m. Spend as much of the remaining weekly quota as you usefully can before then, working the plan at $plan_path from the top down, one job at a time.
Stop cleanly before the window closes. Do not start a job you cannot finish or leave in a committed, coherent state. Record what you did in the plan and the log as you go, not at the end, because this process gets killed at the deadline."

cd "$repo_path" || die "cannot cd to $repo_path"
rc=0
case "$provider" in
  claude)
    claude_bin="${CLAUDE_BIN:-$(command -v claude || true)}"
    [ -x "$claude_bin" ] || die "cannot find claude; set CLAUDE_BIN in the job definition"
    run_with_deadline "$seconds_left" "$claude_bin" -p "/burn-remaining $brief" \
      --model "$model" --effort "$effort" \
      --permission-mode "$permission_mode" --add-dir "$plan_dir" 2>&1 | tee -a "$log"
    rc="${PIPESTATUS[0]}"
    ;;
  codex)
    codex_bin="${CODEX_BIN:-$(command -v codex || true)}"
    [ -x "$codex_bin" ] || die "cannot find codex; set CODEX_BIN in the job definition"
    prompt="$(cat "$repo_path/.codex/prompts/burn-remaining.md" 2>/dev/null)" \
      || die "missing $repo_path/.codex/prompts/burn-remaining.md"
    run_with_deadline "$seconds_left" "$codex_bin" exec \
      --model "$model" -c "model_reasoning_effort=\"$effort\"" \
      --sandbox "$permission_mode" --cd "$repo_path" --skip-git-repo-check \
      "$prompt

$brief" < /dev/null 2>&1 | tee -a "$log"
    rc="${PIPESTATUS[0]}"
    ;;
esac

case "$rc" in
  0)   say "burn finished clean" ;;
  124|143|137) say "burn hit the hard stop at the window edge, which is the designed ending" ;;
  *)   say "burn exited $rc"; alert "burn exited $rc; see $log"; exit "$rc" ;;
esac
