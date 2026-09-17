#!/usr/bin/env bash
# Self-check for check-update.sh: fake clone, stamp a rev, add a commit, expect
# the notice to name that commit and the config file it touched.
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git -C "$work" init -q
git -C "$work" config user.email test@example.com
git -C "$work" config user.name test
git -C "$work" config commit.gpgsign false
git -C "$work" config tag.gpgsign false
mkdir -p "$work/zsh/linux"
printf 'old\n' >"$work/zsh/linux/.zshrc"
git -C "$work" add zsh/linux/.zshrc
git -C "$work" commit -q -m 'feat(zsh): initial zshrc'
old=$(git -C "$work" rev-parse HEAD)

state="$work/state"
mkdir -p "$state"
printf '%s\n' "$work" >"$state/repo"
printf '%s\n' "$old" >"$state/sha"

printf 'new plugin\n' >"$work/zsh/linux/.zshrc"
git -C "$work" add zsh/linux/.zshrc
git -C "$work" commit -q -m 'feat(zsh): add a plugin you should copy'

out=$(SAUCE_STATE_DIR="$state" bash "$root/zsh/check-update.sh" || true)

printf '%s\n' "$out" | grep -q 'feat(zsh): add a plugin you should copy' || {
  printf 'missing commit subject\n%s\n' "$out" >&2
  exit 1
}
printf '%s\n' "$out" | grep -q 'zsh/linux/.zshrc' || {
  printf 'missing changed file\n%s\n' "$out" >&2
  exit 1
}
printf '%s\n' "$out" | grep -q 'install.sh' || {
  printf 'missing installer path\n%s\n' "$out" >&2
  exit 1
}

printf '%s\n' "$(git -C "$work" rev-parse HEAD)" >"$state/sha"
out=$(SAUCE_STATE_DIR="$state" bash "$root/zsh/check-update.sh" || true)
[ -z "$out" ] || {
  printf 'expected silence when stamp matches HEAD\n%s\n' "$out" >&2
  exit 1
}

echo ok
