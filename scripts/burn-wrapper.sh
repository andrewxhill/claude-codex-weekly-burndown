#!/usr/bin/env bash
# Entry point for the local trigger. A launchd agent runs this a couple of hours
# before the weekly reset; it checks the spend guard, then hands the actual work
# to the burn-remaining skill inside a `claude -p` session.
#
# This script stays thin on purpose. It does not parse the backlog and it does not
# decide what to work on. The one thing it reads out of `/usage` is the percentage
# the guard needs, because a wrapper that cannot see the quota cannot refuse to
# spend past it. Everything else about reading quota lives in docs/quota-detection.md
# so a reworded `/usage` is a docs fix, not a code fix.
#
# Config:  ~/.config/weekly-burn/      (override with WEEKLY_BURN_CONFIG_DIR)
# State:   ~/.local/state/weekly-burn/ (override with WEEKLY_BURN_STATE_DIR)
# Binary:  whatever `claude` resolves to (override with CLAUDE_BIN)
set -uo pipefail

config_dir="${WEEKLY_BURN_CONFIG_DIR:-$HOME/.config/weekly-burn}"
state_dir="${WEEKLY_BURN_STATE_DIR:-$HOME/.local/state/weekly-burn}"
conf="$config_dir/claude.conf"
log=""

die() {
  printf 'weekly-burn: %s\n' "$1" >&2
  [ -n "$log" ] && printf '%s\tabort\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$log"
  exit 1
}

note() {
  printf 'weekly-burn: %s\n' "$1"
  [ -n "$log" ] && printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$log"
}

mkdir -p "$state_dir" || die "cannot create state dir $state_dir"
log="$state_dir/last-run.log"

# --- config ---------------------------------------------------------------
[ -f "$conf" ] || die "missing $conf; run the set-up skill in the weekly-burn repo first"
[ -f "$config_dir/plan-path" ] || die "missing $config_dir/plan-path; run the set-up skill first"
[ -f "$config_dir/repo-path" ] || die "missing $config_dir/repo-path; run the set-up skill first"

conf_get() {
  local key="$1" val
  val="$(grep -E "^[[:space:]]*$key[[:space:]]*=" "$conf" | tail -1 | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  printf '%s' "$val"
}

model="$(conf_get model)"
effort="$(conf_get effort)"
permission_mode="$(conf_get permission_mode)"
dry_run="$(conf_get dry_run)"
allow_overage="$(conf_get allow_overage)"

for pair in "model:$model" "effort:$effort" "permission_mode:$permission_mode" "dry_run:$dry_run" "allow_overage:$allow_overage"; do
  [ -n "${pair#*:}" ] || die "$conf is missing a value for ${pair%%:*}"
done

plan_path="$(tr -d '\n' < "$config_dir/plan-path")"
repo_path="$(tr -d '\n' < "$config_dir/repo-path")"
plan_dir="$(dirname "$plan_path")"

[ -f "$plan_path" ] || die "plan not found at $plan_path"
[ -d "$repo_path" ] || die "repo not found at $repo_path"
[ -f "$repo_path/docs/quota-detection.md" ] || die "repo at $repo_path has no docs/quota-detection.md"

# --- locate claude -------------------------------------------------------
# launchd gives a job /usr/bin:/bin:/usr/sbin:/sbin and nothing else, so the
# install that works in your shell is invisible here. Set CLAUDE_BIN in the
# plist, or put the real directory on PATH there.
claude_bin="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || true)}"
[ -n "$claude_bin" ] && [ -x "$claude_bin" ] || die "cannot find the claude binary. launchd jobs get a minimal PATH that excludes ~/.local/bin, so set CLAUDE_BIN in the plist (or add the directory to PATH there). Current PATH: $PATH"

# --- live quota read ------------------------------------------------------
# Recipe and output shape are documented in docs/quota-detection.md.
usage_out="$("$claude_bin" -p "/usage" --model haiku 2>&1)" || die "the /usage read failed: $(printf '%s' "$usage_out" | head -2)"

pct_for() {
  printf '%s' "$usage_out" \
    | grep -iE "Current week \($1\)" \
    | grep -oE '[0-9]+% used' \
    | grep -oE '[0-9]+' \
    | head -1
}

all_pct="$(pct_for 'all models')"
[ -n "$all_pct" ] || die "could not read a weekly percentage out of /usage; refusing to spend on an unknown quota. Re-check docs/quota-detection.md against the installed version."

worst="$all_pct"
case "$model" in
  *fable*|*Fable*)
    fable_pct="$(pct_for 'Fable')"
    [ -n "$fable_pct" ] && [ "$fable_pct" -gt "$worst" ] && worst="$fable_pct"
    ;;
esac

reset_line="$(printf '%s' "$usage_out" | grep -iE 'Current week \(all models\)' | head -1)"
note "quota read: ${worst}% used of the bucket for $model | $reset_line"

# --- dry run --------------------------------------------------------------
if [ "$dry_run" = "true" ]; then
  top_row="$(grep -m1 -E '^- \[ \] ' "$plan_path" || true)"
  if [ -n "$top_row" ]; then
    note "dry run: top of queue is ${top_row}"
  else
    note "dry run: no open rows in $plan_path"
  fi
  if [ "$allow_overage" != "true" ] && [ "$worst" -ge 100 ]; then
    note "dry run: the spend guard would block a real run; bucket is at ${worst}% with allow_overage=false"
  else
    note "dry run: the spend guard would allow a real run at ${worst}% used"
  fi
  note "dry run: trigger fired correctly and spent nothing. Set dry_run=false in $conf to arm it."
  exit 0
fi

# --- spend guard ----------------------------------------------------------
# Subscription tokens are already paid for. Overage is not. Fail closed.
if [ "$allow_overage" != "true" ] && [ "$worst" -ge 100 ]; then
  die "weekly bucket for $model is at ${worst}% and allow_overage=false; refusing to spend into overage"
fi

# --- burn -----------------------------------------------------------------
note "starting burn: model=$model effort=$effort permission_mode=$permission_mode plan=$plan_path"
cd "$repo_path" || die "cannot cd to $repo_path"

"$claude_bin" -p "/burn-remaining" \
  --model "$model" \
  --effort "$effort" \
  --permission-mode "$permission_mode" \
  --add-dir "$plan_dir" 2>&1 | tee -a "$log"
rc="${PIPESTATUS[0]}"

if [ "$rc" -eq 0 ]; then
  note "burn finished clean"
else
  note "burn exited $rc"
fi
exit "$rc"
