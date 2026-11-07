#!/usr/bin/env bash
# Symlink the add-job-to-burn-plan skill into ~/.agents/skills so every agent
# session on this machine can trigger it.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
src="$repo_root/skills/add-job-to-burn-plan"
dest_dir="$HOME/.agents/skills"
dest="$dest_dir/add-job-to-burn-plan"

mkdir -p "$dest_dir"

if [ -L "$dest" ]; then
  current="$(readlink "$dest")"
  if [ "$current" = "$src" ]; then
    echo "already installed: $dest -> $src"
    exit 0
  fi
  echo "replacing existing symlink: $dest (was -> $current)"
  rm "$dest"
elif [ -e "$dest" ]; then
  echo "refusing to clobber non-symlink at $dest" >&2
  exit 1
fi

ln -s "$src" "$dest"
echo "installed: $dest -> $src"
