#!/usr/bin/env bash
# Pulls the latest tstack (https://github.com/t3dotgg/tstack) and copies its
# skills into every folder agents load skills from. Only the skills tstack
# ships are replaced; other skills in those folders are left alone.
# install.sh puts this at ~/.local/bin/update-tstack and runs it.
#
#   update-tstack
#
# TSTACK_DIR and TSTACK_URL are for tests.
set -euo pipefail

repo_dir="${TSTACK_DIR:-$HOME/.t3/tools/tstack}"
repo_url="${TSTACK_URL:-https://github.com/t3dotgg/tstack}"

if [ -d "$repo_dir/.git" ]; then
  git -C "$repo_dir" pull --ff-only --quiet
else
  mkdir -p "$(dirname "$repo_dir")"
  git clone --quiet "$repo_url" "$repo_dir"
fi
printf 'tstack at %s\n' "$(git -C "$repo_dir" log -1 --format='%h %cs %s')"

# Claude (and T3 Code's Claude provider) reads ~/.claude/skills. Codex, Cursor
# and other agents read ~/.agents/skills.
for target in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
  mkdir -p "$target"
  count=0
  for skill in "$repo_dir"/skills/*/; do
    [ -d "$skill" ] || continue
    name=$(basename "$skill")
    rm -rf "${target:?}/$name"
    cp -R "$skill" "$target/$name"
    count=$((count + 1))
  done
  printf 'updated %s skills in %s\n' "$count" "$target"
done
