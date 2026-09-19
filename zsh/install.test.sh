#!/usr/bin/env bash
# Self-check for install.sh helpers. Sources the function half only.
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=install.sh
SAUCE_LIB_ONLY=1 . "$script_dir/install.sh"

[ "$(pkg_name pacman openssh-client)" = openssh ] || {
  echo 'pkg_name pacman openssh-client' >&2
  exit 1
}
[ "$(pkg_name apt-get fd)" = fd-find ] || {
  echo 'pkg_name apt-get fd' >&2
  exit 1
}
[ "$(pkg_name pacman eza)" = eza ] || {
  echo 'pkg_name passthrough' >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

printf '%s\n' '#!/bin/sh' 'echo ro,relatime' >"$work/findmnt"
chmod +x "$work/findmnt"
PATH="$work:$PATH" fs_readonly /var/lib/pacman || {
  echo 'expected read-only mount' >&2
  exit 1
}
PATH="$work:$PATH" pm_can_write pacman && {
  echo 'pacman should not write on a read-only db' >&2
  exit 1
}

printf '%s\n' '#!/bin/sh' 'echo rw,relatime' >"$work/findmnt"
PATH="$work:$PATH" fs_readonly /var/lib/pacman && {
  echo 'expected writable mount' >&2
  exit 1
}
PATH="$work:$PATH" pm_can_write pacman || {
  echo 'pacman should write on a writable db' >&2
  exit 1
}

pm_can_write brew || {
  echo 'brew should always look writable' >&2
  exit 1
}

mkdir -p "$work/home/.local/share/zsh-autosuggestions"
touch "$work/home/.local/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
got=$(HOME="$work/home" find_plugin zsh-autosuggestions) || {
  echo 'find_plugin missed ~/.local/share' >&2
  exit 1
}
[ "$got" = "$work/home/.local/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ] || {
  echo "find_plugin path: $got" >&2
  exit 1
}

out=$(DRY_RUN=1 install_user eza)
printf '%s\n' "$out" | grep -q 'would install eza into ~/.local' || {
  printf 'missing dry-run line\n%s\n' "$out" >&2
  exit 1
}

echo ok
