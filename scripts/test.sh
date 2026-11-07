#!/usr/bin/env bash
# Quality gate. Stubs every provider binary, so it spends nothing and needs no network.
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }

printf '\nsyntax\n'
while IFS= read -r f; do
  bash -n "$f" 2>/dev/null && ok "$(basename "$f")" || bad "$(basename "$f")" "$(bash -n "$f" 2>&1 | head -2)"
done < <(find "$repo_root/scripts" -name '*.sh' -type f | sort)
python3 -I -m py_compile "$repo_root/scripts/read-quota.py" 2>/dev/null && ok "read-quota.py" || bad "read-quota.py compiles"

printf '\ndocs match reality\n'
grep -rqniE 'tokens remaining' "$repo_root/docs" "$repo_root/.claude" "$repo_root/.codex" "$repo_root"/*.md 2>/dev/null \
  && bad "no token-count claims" "providers report percent used" || ok "no token-count claims"
grep -rqniE 'every Sunday' "$repo_root"/*.md 2>/dev/null \
  && bad "no hardcoded reset weekday" || ok "no hardcoded reset weekday"
grep -rqn 'burn-wrapper' "$repo_root" --include='*.md' 2>/dev/null \
  && bad "no stale burn-wrapper references" || ok "no stale burn-wrapper references"

printf '\npublic plan is inert\n'
rows="$(grep -cE '^- \[[ x]\]' "$repo_root/PLAN.md" 2>/dev/null || true)"
[ "${rows:-0}" -eq 0 ] && ok "published PLAN.md carries no rows" || bad "published PLAN.md carries no rows" "$rows rows"
dangling=0
while IFS= read -r slug; do
  [ -f "$repo_root/$slug" ] || dangling=$((dangling+1))
done < <(grep -oE 'jobs/[a-z0-9-]+/readme\.md' "$repo_root/PLAN.md" 2>/dev/null | sort -u)
[ "$dangling" -eq 0 ] && ok "no dangling job links" || bad "no dangling job links" "$dangling"

# --- runner --------------------------------------------------------------
runner="$repo_root/scripts/burn.sh"

setup_sandbox() {
  sandbox="$(mktemp -d)"
  export WEEKLY_BURN_CONFIG_DIR="$sandbox/config" WEEKLY_BURN_STATE_DIR="$sandbox/state"
  mkdir -p "$WEEKLY_BURN_CONFIG_DIR" "$sandbox/bin" "$sandbox/plan" "$sandbox/fakerepo/.codex/prompts"
  export STUB_LOG="$sandbox/calls.log"; : > "$STUB_LOG"
  : > "$sandbox/fakerepo/.codex/prompts/burn-remaining.md"
  # stub read-quota.py so the gate never touches a real account
  cat > "$sandbox/bin/read-quota.py" <<'STUB'
#!/usr/bin/env python3
import json, os, sys
from datetime import datetime, timedelta, timezone
print(json.dumps({
  "provider": sys.argv[1],
  "used_percent": int(os.environ.get("STUB_PCT", "20")),
  "resets_at_iso": os.environ.get("STUB_RESET") or (datetime.now(timezone.utc) + timedelta(hours=6)).isoformat(),
  "window_duration_mins": 10080,
  "spend_allowed": os.environ.get("STUB_ALLOWED", "True") == "True",
  "detail": "stub",
}))
STUB
  chmod +x "$sandbox/bin/read-quota.py"
  for b in claude codex; do
    cat > "$sandbox/bin/$b" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$STUB_LOG"
echo "stub ran"
STUB
    chmod +x "$sandbox/bin/$b"
  done
  export PATH="$sandbox/bin:$PATH"
  # the runner finds read-quota.py beside itself, so give it a scripts dir
  mkdir -p "$sandbox/scripts"; cp "$runner" "$sandbox/scripts/"; cp "$sandbox/bin/read-quota.py" "$sandbox/scripts/"
  runner_under_test="$sandbox/scripts/burn.sh"
  printf '%s\n' "$sandbox/plan/PLAN.md" > "$WEEKLY_BURN_CONFIG_DIR/plan-path"
  printf '%s\n' "$sandbox/fakerepo" > "$WEEKLY_BURN_CONFIG_DIR/repo-path"
  printf '# plan\n\n## Open jobs, highest priority first\n\n- [ ] [expires 2099-01-01] Do the thing ([jobs/thing](jobs/thing/readme.md)).\n' > "$sandbox/plan/PLAN.md"
  for p in claude codex; do
    cat > "$WEEKLY_BURN_CONFIG_DIR/$p.conf" <<CONF
model=test-model
effort=high
permission_mode=$([ "$p" = codex ] && echo workspace-write || echo acceptEdits)
window_hours=6
stop_margin_minutes=5
dry_run=false
allow_overage=false
CONF
  done
}
teardown_sandbox() {
  rm -rf "$sandbox"
  unset WEEKLY_BURN_CONFIG_DIR WEEKLY_BURN_STATE_DIR STUB_LOG STUB_PCT STUB_RESET STUB_ALLOWED
}

printf '\nrunner: refusals\n'
setup_sandbox
out="$("$runner_under_test" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "no provider argument is a usage error" || bad "no provider argument is a usage error" "rc=$rc"
out="$("$runner_under_test" gemini 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "unknown provider is a usage error" || bad "unknown provider is a usage error" "rc=$rc"
rm "$WEEKLY_BURN_CONFIG_DIR/claude.conf"
out="$("$runner_under_test" claude 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'claude.conf'; } && ok "missing conf names the file" || bad "missing conf names the file" "rc=$rc $out"
[ ! -s "$STUB_LOG" ] && ok "missing conf spends nothing" || bad "missing conf spends nothing" "$(cat "$STUB_LOG")"
teardown_sandbox

setup_sandbox
rm "$sandbox/plan/PLAN.md"
out="$("$runner_under_test" claude 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'no plan'; } && ok "missing plan refuses" || bad "missing plan refuses" "rc=$rc $out"
teardown_sandbox

printf '\nrunner: the burn window\n'
setup_sandbox
out="$("$runner_under_test" claude 2>&1)"
calls="$(cat "$STUB_LOG")"
printf '%s' "$calls" | grep -q -- '--model test-model' && ok "claude gets the configured model" || bad "claude gets the configured model" "$calls"
printf '%s' "$calls" | grep -q -- '--permission-mode acceptEdits' && ok "claude gets the permission mode" || bad "claude gets the permission mode" "$calls"
printf '%s' "$calls" | grep -q '/burn-remaining' && ok "claude is handed the skill" || bad "claude is handed the skill" "$calls"
printf '%s' "$out" | grep -qE '[0-9]+h[0-9]+m until hard stop' && ok "logs the time left before the hard stop" || bad "logs the time left before the hard stop" "$out"
teardown_sandbox

setup_sandbox
out="$("$runner_under_test" codex 2>&1)"
calls="$(cat "$STUB_LOG")"
printf '%s' "$calls" | grep -q 'codex exec' && ok "codex runs through exec" || bad "codex runs through exec" "$calls"
printf '%s' "$calls" | grep -q -- '--sandbox workspace-write' && ok "codex gets the sandbox mode" || bad "codex gets the sandbox mode" "$calls"
printf '%s' "$calls" | grep -q 'model_reasoning_effort' && ok "codex gets the reasoning effort" || bad "codex gets the reasoning effort" "$calls"
teardown_sandbox

# A reset already inside the safety margin means the window is gone. Starting work
# there would run straight through the rollover, which is the one thing to avoid.
setup_sandbox
export STUB_RESET="$(python3 -I -c "
from datetime import datetime,timedelta,timezone
print((datetime.now(timezone.utc)+timedelta(minutes=2)).isoformat())")"
out="$("$runner_under_test" claude 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && ! grep -q 'burn-remaining' "$STUB_LOG"; } && ok "a closed window exits clean without working" || bad "a closed window exits clean without working" "rc=$rc $out"
printf '%s' "$out" | grep -qi 'already closed' && ok "says why it did nothing" || bad "says why it did nothing" "$out"
teardown_sandbox

setup_sandbox
export STUB_RESET="2026-13-45T99:99:99"
out="$("$runner_under_test" claude 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && ! grep -q 'burn-remaining' "$STUB_LOG"; } && ok "an unparseable reset time stops the run" || bad "an unparseable reset time stops the run" "rc=$rc $out"
teardown_sandbox

printf '\nrunner: spend guard\n'
setup_sandbox
export STUB_ALLOWED=False STUB_PCT=100
out="$("$runner_under_test" claude 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && ! grep -q 'burn-remaining' "$STUB_LOG"; } && ok "refuses when the provider says no" || bad "refuses when the provider says no" "rc=$rc $out"
teardown_sandbox

setup_sandbox
export STUB_ALLOWED=False STUB_PCT=100
sed -i.bak 's/^allow_overage=false/allow_overage=true/' "$WEEKLY_BURN_CONFIG_DIR/claude.conf"
out="$("$runner_under_test" claude 2>&1)"
grep -q 'burn-remaining' "$STUB_LOG" && ok "allow_overage=true overrides the guard" || bad "allow_overage=true overrides the guard" "$out"
teardown_sandbox

setup_sandbox
cat > "$sandbox/scripts/read-quota.py" <<'STUB'
#!/usr/bin/env python3
import sys; print("the output format changed", file=sys.stderr); sys.exit(1)
STUB
chmod +x "$sandbox/scripts/read-quota.py"
out="$("$runner_under_test" claude 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'unknown'; } && ok "an unreadable quota fails closed" || bad "an unreadable quota fails closed" "rc=$rc $out"
teardown_sandbox

printf '\nrunner: dry run\n'
setup_sandbox
sed -i.bak 's/^dry_run=false/dry_run=true/' "$WEEKLY_BURN_CONFIG_DIR/claude.conf"
out="$("$runner_under_test" claude 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "dry run exits clean" || bad "dry run exits clean" "rc=$rc $out"
! grep -q 'burn-remaining' "$STUB_LOG" && ok "dry run starts no work" || bad "dry run starts no work" "$(cat "$STUB_LOG")"
printf '%s' "$out" | grep -qi 'top of queue' && ok "dry run names the top job" || bad "dry run names the top job" "$out"
printf '%s' "$out" | grep -qi 'guard would' && ok "dry run reports the guard verdict" || bad "dry run reports the guard verdict" "$out"
[ -s "$WEEKLY_BURN_STATE_DIR/last-run.log" ] && ok "dry run writes the log" || bad "dry run writes the log"
teardown_sandbox

setup_sandbox
sed -i.bak 's/^dry_run=false/dry_run=true/' "$WEEKLY_BURN_CONFIG_DIR/claude.conf"
export STUB_ALLOWED=False STUB_PCT=100
out="$("$runner_under_test" claude 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qi 'guard would BLOCK'; } && ok "dry run reports a blocking guard without aborting" || bad "dry run reports a blocking guard without aborting" "rc=$rc $out"
teardown_sandbox

printf '\nquota reader\n'
out="$("$repo_root/scripts/read-quota.py" 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'usage:'; } && ok "no argument prints usage" || bad "no argument prints usage" "$out"
out="$(PATH=/usr/bin:/bin "$repo_root/scripts/read-quota.py" claude 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qiE 'PATH|CLAUDE_BIN'; } && ok "names the PATH problem when claude is unfindable" || bad "names the PATH problem when claude is unfindable" "$out"
out="$(PATH=/usr/bin:/bin "$repo_root/scripts/read-quota.py" codex 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qiE 'PATH|CODEX_BIN'; } && ok "names the PATH problem when codex is unfindable" || bad "names the PATH problem when codex is unfindable" "$out"

printf '\ninstall-global-skill\n'
sandbox="$(mktemp -d)"
HOME="$sandbox" "$repo_root/scripts/install-global-skill.sh" >/dev/null 2>&1
[ "$(readlink "$sandbox/.agents/skills/add-job-to-burn-plan")" = "$repo_root/skills/add-job-to-burn-plan" ] \
  && ok "installs the symlink" || bad "installs the symlink"
HOME="$sandbox" "$repo_root/scripts/install-global-skill.sh" >/dev/null 2>&1 && ok "is idempotent" || bad "is idempotent"
rm -rf "$sandbox/.agents/skills/add-job-to-burn-plan"; mkdir -p "$sandbox/.agents/skills/add-job-to-burn-plan"
HOME="$sandbox" "$repo_root/scripts/install-global-skill.sh" >/dev/null 2>&1 && bad "refuses to clobber a real dir" || ok "refuses to clobber a real dir"
rm -rf "$sandbox"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
