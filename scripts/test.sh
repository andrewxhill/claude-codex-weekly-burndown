#!/usr/bin/env bash
# Quality gate for this repo. Runs every check, prints a summary, exits non-zero on
# the first failure class found. No network, no token spend: `claude` is stubbed.
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
pass=0
fail=0

ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

# --- shellcheck-style syntax check on every script -------------------------
printf '\nshell syntax\n'
while IFS= read -r f; do
  if bash -n "$f" 2>/dev/null; then ok "$(basename "$f") parses"; else bad "$(basename "$f") parses" "$(bash -n "$f" 2>&1 | head -3)"; fi
done < <(find "$repo_root/scripts" -name '*.sh' -type f | sort)

# --- docs must not promise a quota field the tooling does not expose -------
printf '\ndocs match reality\n'
if grep -rniE 'tokens remaining' "$repo_root/docs" "$repo_root/.claude" "$repo_root/.codex" "$repo_root"/*.md >/dev/null 2>&1; then
  bad "no 'tokens remaining' claims" "/usage reports percent used, not a token count"
else
  ok "no 'tokens remaining' claims"
fi

if grep -rniE 'every Sunday' "$repo_root"/*.md >/dev/null 2>&1; then
  bad "no hardcoded reset weekday" "reset day is per-account; read it live"
else
  ok "no hardcoded reset weekday"
fi

# --- PLAN.md in the public repo must carry no live job rows ----------------
printf '\npublic plan is inert\n'
live_rows="$(grep -cE '^- \[ \] \[expires' "$repo_root/PLAN.md" 2>/dev/null || true)"
if [ "${live_rows:-0}" -eq 0 ]; then
  ok "published PLAN.md has no open rows"
else
  bad "published PLAN.md has no open rows" "$live_rows live row(s); real queue lives at plan-path"
fi

# --- every jobs/<slug> link in PLAN.md must resolve ------------------------
dangling=0
while IFS= read -r slug; do
  [ -f "$repo_root/$slug" ] || { dangling=$((dangling+1)); printf '       dangling: %s\n' "$slug"; }
done < <(grep -oE 'jobs/[a-z0-9-]+/readme\.md' "$repo_root/PLAN.md" 2>/dev/null | sort -u)
if [ "$dangling" -eq 0 ]; then ok "no dangling job links"; else bad "no dangling job links" "$dangling broken"; fi

# --- wrapper behavior ------------------------------------------------------
printf '\nburn-wrapper\n'
wrapper="$repo_root/scripts/burn-wrapper.sh"

setup_sandbox() {
  sandbox="$(mktemp -d)"
  export WEEKLY_BURN_CONFIG_DIR="$sandbox/config"
  export WEEKLY_BURN_STATE_DIR="$sandbox/state"
  mkdir -p "$WEEKLY_BURN_CONFIG_DIR" "$sandbox/bin" "$sandbox/plan"
  # stub claude so no test ever spends a token
  cat > "$sandbox/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CLAUDE_STUB_LOG"
case "$*" in
  *"/usage"*) printf 'Current week (all models): %s%% used · resets Nov 11 at 2am (America/Los_Angeles)\n' "${CLAUDE_STUB_PCT:-24}" ;;
  *) printf 'stub burn run\n' ;;
esac
STUB
  chmod +x "$sandbox/bin/claude"
  export CLAUDE_STUB_LOG="$sandbox/claude-calls.log"
  : > "$CLAUDE_STUB_LOG"
  export PATH="$sandbox/bin:$PATH"
  printf '%s\n' "$sandbox/plan/PLAN.md" > "$WEEKLY_BURN_CONFIG_DIR/plan-path"
  printf '%s\n' "$repo_root" > "$WEEKLY_BURN_CONFIG_DIR/repo-path"
  cat > "$WEEKLY_BURN_CONFIG_DIR/claude.conf" <<'CONF'
model=claude-opus-5
effort=high
permission_mode=acceptEdits
dry_run=false
allow_overage=false
CONF
  printf '# Weekly burn plan\n\n## Open jobs, highest priority first\n\n- [ ] [expires 2099-01-01] Do the thing ([jobs/thing](jobs/thing/readme.md)).\n' > "$sandbox/plan/PLAN.md"
}
teardown_sandbox() { rm -rf "$sandbox"; unset WEEKLY_BURN_CONFIG_DIR WEEKLY_BURN_STATE_DIR CLAUDE_STUB_LOG CLAUDE_STUB_PCT; }

# missing config must fail loudly and spend nothing
setup_sandbox
rm "$WEEKLY_BURN_CONFIG_DIR/claude.conf"
out="$("$wrapper" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'claude.conf'; then ok "missing claude.conf fails loudly"; else bad "missing claude.conf fails loudly" "rc=$rc out=$out"; fi
[ ! -s "$CLAUDE_STUB_LOG" ] && ok "missing config spends nothing" || bad "missing config spends nothing" "invoked claude"
teardown_sandbox

# missing plan must fail loudly
setup_sandbox
rm "$sandbox/plan/PLAN.md"
out="$("$wrapper" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'plan'; then ok "missing plan fails loudly"; else bad "missing plan fails loudly" "rc=$rc out=$out"; fi
teardown_sandbox

# dry run reads quota, logs, and never starts a burn
setup_sandbox
sed -i.bak 's/^dry_run=false/dry_run=true/' "$WEEKLY_BURN_CONFIG_DIR/claude.conf"
out="$("$wrapper" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "dry run exits clean" || bad "dry run exits clean" "rc=$rc out=$out"
if grep -q '/usage' "$CLAUDE_STUB_LOG" && ! grep -q 'burn-remaining' "$CLAUDE_STUB_LOG"; then
  ok "dry run reads quota without burning"
else
  bad "dry run reads quota without burning" "$(cat "$CLAUDE_STUB_LOG")"
fi
[ -s "$WEEKLY_BURN_STATE_DIR/last-run.log" ] && ok "dry run writes the log" || bad "dry run writes the log" "no last-run.log"
teardown_sandbox

# live run invokes the burner with the configured model, effort and plan dir
setup_sandbox
out="$("$wrapper" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "live run exits clean" || bad "live run exits clean" "rc=$rc out=$out"
calls="$(cat "$CLAUDE_STUB_LOG")"
for needle in '/burn-remaining' '--model claude-opus-5' '--effort high' '--permission-mode acceptEdits' '--add-dir'; do
  printf '%s' "$calls" | grep -q -- "$needle" && ok "live run passes $needle" || bad "live run passes $needle" "$calls"
done
teardown_sandbox

# overage guard: at 100% used with allow_overage=false the wrapper must refuse
setup_sandbox
export CLAUDE_STUB_PCT=100
out="$("$wrapper" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'overage' && ! grep -q 'burn-remaining' "$CLAUDE_STUB_LOG"; then ok "refuses to burn into overage"; else bad "refuses to burn into overage" "rc=$rc out=$out"; fi
teardown_sandbox

# unparseable quota must fail closed, not guess
setup_sandbox
cat > "$sandbox/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CLAUDE_STUB_LOG"
printf 'the format changed and says nothing useful\n'
STUB
chmod +x "$sandbox/bin/claude"
out="$("$wrapper" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'unknown quota' && ! grep -q 'burn-remaining' "$CLAUDE_STUB_LOG"; then ok "fails closed on unreadable quota"; else bad "fails closed on unreadable quota" "rc=$rc out=$out"; fi
teardown_sandbox

# a dry run never spends, so a full bucket must not turn it into an abort
setup_sandbox
sed -i.bak 's/^dry_run=false/dry_run=true/' "$WEEKLY_BURN_CONFIG_DIR/claude.conf"
export CLAUDE_STUB_PCT=100
out="$("$wrapper" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'burn-remaining' "$CLAUDE_STUB_LOG"; then ok "dry run reports a full bucket instead of aborting"; else bad "dry run reports a full bucket instead of aborting" "rc=$rc out=$out"; fi
printf '%s' "$out" | grep -qi 'guard' && ok "dry run names the guard verdict" || bad "dry run names the guard verdict" "$out"
teardown_sandbox

# launchd hands jobs a minimal PATH that excludes ~/.local/bin, so a wrapper that
# assumes `claude` is findable dies at the first call. Fail loudly instead.
setup_sandbox
out="$(PATH=/usr/bin:/bin "$wrapper" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qiE 'PATH|CLAUDE_BIN'; then ok "names the PATH problem when claude is unfindable"; else bad "names the PATH problem when claude is unfindable" "rc=$rc out=$out"; fi
teardown_sandbox

# an explicit CLAUDE_BIN overrides discovery, which is what the plist will use
setup_sandbox
bin="$sandbox/bin/claude"
out="$(PATH=/usr/bin:/bin CLAUDE_BIN="$bin" "$wrapper" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "CLAUDE_BIN overrides PATH discovery" || bad "CLAUDE_BIN overrides PATH discovery" "rc=$rc out=$out"
teardown_sandbox

# --- install script must refuse to clobber a real directory ---------------
printf '\ninstall-global-skill\n'
sandbox="$(mktemp -d)"
HOME="$sandbox" "$repo_root/scripts/install-global-skill.sh" >/dev/null 2>&1
link="$sandbox/.agents/skills/add-job-to-burn-plan"
[ "$(readlink "$link")" = "$repo_root/skills/add-job-to-burn-plan" ] && ok "installs the symlink" || bad "installs the symlink" "$(ls -l "$link" 2>&1)"
HOME="$sandbox" "$repo_root/scripts/install-global-skill.sh" >/dev/null 2>&1 && ok "second run is idempotent" || bad "second run is idempotent"
rm -rf "$sandbox/.agents/skills/add-job-to-burn-plan"; mkdir -p "$sandbox/.agents/skills/add-job-to-burn-plan"
HOME="$sandbox" "$repo_root/scripts/install-global-skill.sh" >/dev/null 2>&1 && bad "refuses to clobber a real dir" "exited 0" || ok "refuses to clobber a real dir"
rm -rf "$sandbox"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
