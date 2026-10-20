#!/usr/bin/env bash
# Self-check for check-update.sh: fake clone, stamp a rev, add a commit, expect
# the notice to name that commit and the config file it touched. An upstream
# commit we have not fetched is not a prompt. Y pulls when upstream is ahead.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)

# Darwin still ships bash 3.2; ;& / ;;& are bash 4+.
if grep -nE ';;?&' "$root/zsh/check-update.sh"; then
  printf 'bash 4+ case fallthrough is not portable to macOS /bin/bash\n' >&2
  exit 1
fi

work=$(mktemp -d)
pair=
trap 'rm -rf "$work" ${pair:-}' EXIT

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
# Skip the daily GitHub/fetch path unless a test is exercising it.
printf '%s\n' "$(date +%s)" >"$state/last_fetch"

printf 'new plugin\n' >"$work/zsh/linux/.zshrc"
git -C "$work" add zsh/linux/.zshrc
git -C "$work" commit -q -m 'feat(zsh): add a plugin you should copy'

out=$(SAUCE_STATE_DIR="$state" bash "$root/zsh/check-update.sh" || true)

printf '%s\n' "$out" | grep -q "It's time to update" || {
  printf 'missing omz-style reminder\n%s\n' "$out" >&2
  exit 1
}
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

printf '%s\n' '#!/bin/sh' "echo ran >\"$state/installed\"" >"$work/zsh/install.sh"
chmod +x "$work/zsh/install.sh"
git -C "$work" add zsh/install.sh
git -C "$work" commit -q -m 'feat(zsh): installer records that it ran'
printf '%s\n' "$old" >"$state/sha"

out=$(SAUCE_UPDATE_ANSWER=y SAUCE_STATE_DIR="$state" bash "$root/zsh/check-update.sh" || true)
[ -f "$state/installed" ] || {
  printf 'Y did not run the installer\n%s\n' "$out" >&2
  exit 1
}

# Upstream is ahead: y has to pull before installing, or the next shell asks again.
pair=$(mktemp -d)
git init -q "$pair/origin"
git -C "$pair/origin" config user.email test@example.com
git -C "$pair/origin" config user.name test
git -C "$pair/origin" config commit.gpgsign false
git -C "$pair/origin" config tag.gpgsign false
mkdir -p "$pair/origin/zsh"
printf 'old\n' >"$pair/origin/zsh/install.sh"
git -C "$pair/origin" add zsh/install.sh
git -C "$pair/origin" commit -q -m 'base'
git -C "$pair/origin" branch -M main
git clone -q "$pair/origin" "$pair/clone"
printf '%s\n' '#!/bin/sh' "echo pulled >\"$state/pulled\"" >"$pair/origin/zsh/install.sh"
git -C "$pair/origin" commit -q -am 'feat(zsh): real update'
printf '%s\n' "$pair/clone" >"$state/repo"
printf '%s\n' "$(git -C "$pair/clone" rev-parse HEAD)" >"$state/sha"
rm -f "$state/snooze"
# Origin moved but the clone has not fetched it: nothing to install, no prompt.
out=$(SAUCE_STATE_DIR="$state" bash "$root/zsh/check-update.sh" || true)
[ -z "$out" ] || {
  printf 'prompted for a commit that is not in the clone\n%s\n' "$out" >&2
  exit 1
}
git -C "$pair/clone" fetch -q
out=$(SAUCE_UPDATE_ANSWER=y SAUCE_STATE_DIR="$state" bash "$root/zsh/check-update.sh" || true)
[ "$(git -C "$pair/clone" rev-parse HEAD)" = "$(git -C "$pair/origin" rev-parse HEAD)" ] || {
  printf 'Y did not pull\n%s\n' "$out" >&2
  exit 1
}
[ -f "$state/pulled" ] || {
  printf 'Y installed the pre-pull tree\n%s\n' "$out" >&2
  exit 1
}

printf '%s\n' "$work" >"$state/repo"
printf '%s\n' "$old" >"$state/sha"
rm -f "$state/snooze"
out=$(SAUCE_UPDATE_ANSWER=n SAUCE_STATE_DIR="$state" bash "$root/zsh/check-update.sh" || true)
printf '%s\n' "$out" | grep -q 'You can update manually' || {
  printf 'n did not print the omz manual-update line\n%s\n' "$out" >&2
  exit 1
}
[ -f "$state/snooze" ] || {
  printf 'n did not snooze\n%s\n' "$out" >&2
  exit 1
}
out=$(SAUCE_STATE_DIR="$state" bash "$root/zsh/check-update.sh" || true)
[ -z "$out" ] || {
  printf 'expected silence while snoozed\n%s\n' "$out" >&2
  exit 1
}

# The clone is also where the repo gets edited, and install.sh copies the
# working tree. Y must not install uncommitted work, nor snooze the update.
# Untracked files only count in a dir install.sh copies whole ($state is not).
rm -f "$state/snooze" "$state/installed"
for dirty in unstaged staged untracked; do
  case "$dirty" in
    unstaged) printf 'half done\n' >>"$work/zsh/linux/.zshrc" ;;
    staged)
      printf 'half done\n' >>"$work/zsh/linux/.zshrc"
      git -C "$work" add zsh/linux/.zshrc
      ;;
    untracked) mkdir -p "$work/ssh" && printf 'Host draft\n' >"$work/ssh/config" ;;
  esac
  out=$(SAUCE_UPDATE_ANSWER=y SAUCE_STATE_DIR="$state" bash "$root/zsh/check-update.sh" || true)
  [ ! -f "$state/installed" ] || {
    printf 'Y installed %s changes\n%s\n' "$dirty" "$out" >&2
    exit 1
  }
  printf '%s\n' "$out" | grep -q 'uncommitted changes' || {
    printf 'no uncommitted-changes notice for %s changes\n%s\n' "$dirty" "$out" >&2
    exit 1
  }
  [ ! -f "$state/snooze" ] || {
    printf '%s changes snoozed the update\n%s\n' "$dirty" "$out" >&2
    exit 1
  }
  git -C "$work" reset -q --hard
  rm -rf "$work/ssh"
done
out=$(SAUCE_UPDATE_ANSWER=y SAUCE_STATE_DIR="$state" bash "$root/zsh/check-update.sh" || true)
[ -f "$state/installed" ] || {
  printf 'Y did not install once the tree was clean again\n%s\n' "$out" >&2
  exit 1
}

echo ok
