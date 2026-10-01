#!/usr/bin/env bash
# Self-check for check-update.sh: fake clone, stamp a rev, add a commit, expect
# the notice to name that commit and the config file it touched. Also: GitHub
# tip cached from the daily check still sees origin, and Y/n matches omz.
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

# Darwin still ships bash 3.2; ;& / ;;& are bash 4+.
if grep -nE ';;?&' "$root/zsh/check-update.sh"; then
  printf 'bash 4+ case fallthrough is not portable to macOS /bin/bash\n' >&2
  exit 1
fi

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

# Origin moved, clone has not been fetched yet: cached GitHub sha is enough
# for the next terminal to say an update is available.
printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' >"$state/remote_sha"
out=$(SAUCE_STATE_DIR="$state" bash "$root/zsh/check-update.sh" || true)
printf '%s\n' "$out" | grep -q "It's time to update" || {
  printf 'missing reminder for unfetched origin\n%s\n' "$out" >&2
  exit 1
}

# Daily check uses curl like omz, so the first open of the day sees origin.
rm -f "$state/remote_sha"
printf '0\n' >"$state/last_fetch"
git -C "$work" remote add origin https://github.com/example/saucefiguration.git
mkdir -p "$work/bin"
printf '%s\n' '#!/bin/sh' 'echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' >"$work/bin/curl"
chmod +x "$work/bin/curl"
out=$(PATH="$work/bin:$PATH" SAUCE_STATE_DIR="$state" bash "$root/zsh/check-update.sh" || true)
printf '%s\n' "$out" | grep -q "It's time to update" || {
  printf 'missing reminder from GitHub check\n%s\n' "$out" >&2
  exit 1
}
got=$(tr -d '\r\n' <"$state/remote_sha")
[ "$got" = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ] || {
  printf 'did not cache GitHub sha: %s\n' "$got" >&2
  exit 1
}

printf '%s\n' '#!/bin/sh' "echo ran >\"$state/installed\"" >"$work/zsh/install.sh"
chmod +x "$work/zsh/install.sh"

out=$(SAUCE_UPDATE_ANSWER=y SAUCE_STATE_DIR="$state" bash "$root/zsh/check-update.sh" || true)
[ -f "$state/installed" ] || {
  printf 'Y did not run the installer\n%s\n' "$out" >&2
  exit 1
}

rm -f "$state/installed"
printf '%s\n' "$old" >"$state/sha"
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

echo ok
