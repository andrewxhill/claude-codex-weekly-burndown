#!/usr/bin/env bash
# Install add-job-to-burn-plan so any agent session on this machine can file a
# job. The two agents discover it differently:
#
#   Claude Code scans a skills directory, so the skill gets symlinked there.
#   Codex has no skill mechanism, so it gets a pointer in the instruction file
#   it loads globally. A pointer in an always-loaded file and a skill
#   description do the same job: they say what the material is and when to
#   reach for it.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
src="$repo_root/skills/add-job-to-burn-plan"
begin='<!-- weekly-burn:add-job-to-burn-plan -->'
end='<!-- /weekly-burn:add-job-to-burn-plan -->'

# Stock macOS readlink has no -f, so resolve through python3, which this repo
# already depends on for reading quota.
resolve() { python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }

# --- Claude Code ---------------------------------------------------------
# Prefer a directory it already scans. Resolve symlinks first, so a managed
# dotfile setup gets written at the real path rather than through a read-only
# link.
dest_dir=""
for cand in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
  [ -e "$cand" ] || continue
  r="$(resolve "$cand")"
  if [ -d "$r" ] && [ -w "$r" ]; then dest_dir="$r"; break; fi
done
[ -n "$dest_dir" ] || dest_dir="$HOME/.agents/skills"
mkdir -p "$dest_dir"
dest="$dest_dir/add-job-to-burn-plan"

if [ -L "$dest" ]; then
  current="$(readlink "$dest")"
  if [ "$current" = "$src" ]; then
    echo "claude: already installed, $dest -> $src"
  else
    echo "claude: replacing symlink $dest (was -> $current)"
    rm "$dest"
    ln -s "$src" "$dest"
    echo "claude: installed $dest -> $src"
  fi
elif [ -e "$dest" ]; then
  echo "refusing to clobber non-symlink at $dest" >&2
  exit 1
else
  ln -s "$src" "$dest"
  echo "claude: installed $dest -> $src"
fi

# --- Codex ---------------------------------------------------------------
block="$(cat <<BLOCK
$begin
## Deferred work

When the user parks work until the weekly quota resets, saying "add that to the burn list", "burn it later", or otherwise deferring it to whatever weekly budget is left over, follow \`$dest/SKILL.md\`. It writes the brief, inserts one row in the plan named by \`~/.config/weekly-burn/plan-path\`, and hands back the task you interrupted.

That plan lives outside your workspace, so a sandboxed run needs its directory added as writable before the row can be written.
$end
BLOCK
)"

if [ ! -d "$HOME/.codex" ]; then
  echo "codex: no ~/.codex, skipping the Codex pointer"
  exit 0
fi

target="$HOME/.codex/AGENTS.md"
[ -e "$target" ] && target="$(resolve "$target")"

if [ -e "$target" ] && [ ! -w "$target" ]; then
  echo "codex: $target is not writable, so add this block to whatever renders it:" >&2
  printf '\n%s\n\n' "$block" >&2
  exit 1
fi

mkdir -p "$(dirname "$target")"
BEGIN="$begin" END="$end" BLOCK="$block" TARGET="$target" python3 -I - <<'PY'
import os, pathlib, re
target = pathlib.Path(os.environ["TARGET"])
begin, end, block = os.environ["BEGIN"], os.environ["END"], os.environ["BLOCK"]
text = target.read_text() if target.exists() else ""
pattern = re.compile(re.escape(begin) + r".*?" + re.escape(end), re.S)
if pattern.search(text):
    new = pattern.sub(lambda _: block, text, count=1)
    action = "already present, refreshed"
else:
    new = text.rstrip("\n") + ("\n\n" if text.strip() else "") + block + "\n"
    action = "pointer added"
if new != text:
    target.write_text(new)
print(f"codex: {action} in {target}")
PY
