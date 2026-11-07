# Config

Setup writes three things under `~/.config/weekly-burn/`. The burner and the global skill read them at runtime. Nothing here is secret, and nothing here belongs in a commit.

## `plan-path`

One line: the absolute path to your real `PLAN.md`.

`add-job-to-burn-plan` reads this from any repo on the machine, which is the whole reason it is a bare file rather than a key inside a provider config. Job briefs live beside it, under `<dirname>/jobs/<slug>/readme.md`.

Setup defaults it to `~/.local/state/weekly-burn/plan/PLAN.md`. Point it at this repo's own `PLAN.md` only if you are fine publishing every brief you ever defer.

## `repo-path`

One line: the absolute path to this repo's checkout.

The burner needs it to find `docs/quota-detection.md` at fire time. Without it, moving the plan out of the repo leaves the burner unable to find the quota recipe.

## `claude.conf`

`key=value` lines, `#` for comments. Every key is required, and the wrapper refuses to run when one is empty.

```ini
# Model the burner runs on. Decides which weekly bucket drains.
model=claude-opus-5

# low | medium | high | xhigh | max
effort=high

# launchd | cloud-routine
trigger=launchd

# acceptEdits | auto | dontAsk | bypassPermissions | manual | plan
# Nobody is awake to answer a prompt, so `manual` hangs until the window shuts.
permission_mode=acceptEdits

# true: read quota, name the top job, write the log, spend nothing.
# Leave it true until you have watched one fire land.
dry_run=true

# false: refuse to run once the bucket hits 100%. Subscription tokens are
# already paid for; overage is not.
allow_overage=false

# ISO 8601 reset time the trigger was built around. The burner compares the
# live reset against this and re-arms when they drift past 15 minutes.
reset_anchor=2026-11-11T02:00:00-08:00

# Minutes before the reset that the trigger fires.
lead_minutes=120

# Set by setup. launchd label, or the routine id when trigger=cloud-routine.
trigger_id=sh.weekly-burn.claude
```

## `codex.conf`

Same shape, for the Codex burner. Setup leaves it unwritten while `docs/quota-detection.md` still lists the Codex quota read as unresolved.

## Environment the trigger needs

`scripts/burn-wrapper.sh` reads three environment overrides, all optional except on launchd:

- `CLAUDE_BIN`, the absolute path to the `claude` binary. Required in a launchd plist, because launchd's PATH excludes wherever `claude` actually lives. `docs/scheduling.md` has a worked plist.
- `WEEKLY_BURN_CONFIG_DIR`, defaulting to `~/.config/weekly-burn`.
- `WEEKLY_BURN_STATE_DIR`, defaulting to `~/.local/state/weekly-burn`.

The last two exist so `scripts/test.sh` can run against a sandbox. Leave them unset in the plist.

## State

`~/.local/state/weekly-burn/last-run.log` gets one tab-separated line per event, UTC timestamps. The wrapper creates the directory. Nothing rotates it, and `.gitignore` covers `*.log` so a plan kept inside the repo will not drag the log along.
