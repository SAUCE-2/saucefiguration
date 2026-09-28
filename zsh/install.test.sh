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

src="$work/src.txt"
dest="$work/dest.txt"
printf 'new\n' >"$src"

copy_file "$src" "$dest"
[ "$(cat "$dest")" = new ] || {
  echo 'copy_file did not create dest' >&2
  exit 1
}

# Identical dest: no warning, leave it.
err=$(copy_file "$src" "$dest" 2>&1 >/dev/null) || true
[ -z "$err" ] || {
  printf 'identical dest should be silent\n%s\n' "$err" >&2
  exit 1
}

printf 'old\n' >"$dest"
err=$(copy_file "$src" "$dest" 2>&1 >/dev/null) || true
printf '%s\n' "$err" | grep -q "replacing $dest" || {
  printf 'missing replacement warning\n%s\n' "$err" >&2
  exit 1
}
[ "$(cat "$dest")" = new ] || {
  echo 'copy_file did not replace dest' >&2
  exit 1
}

printf 'old\n' >"$dest"
err=$(DRY_RUN=1 copy_file "$src" "$dest" 2>&1) || true
printf '%s\n' "$err" | grep -q "replacing $dest" || {
  printf 'dry-run missing replacement warning\n%s\n' "$err" >&2
  exit 1
}
printf '%s\n' "$err" | grep -q "would copy $src -> $dest" || {
  printf 'dry-run missing would-copy\n%s\n' "$err" >&2
  exit 1
}
[ "$(cat "$dest")" = old ] || {
  echo 'dry-run replaced dest' >&2
  exit 1
}

other="$work/other.txt"
printf 'other\n' >"$other"
ln -s "$other" "$work/link.txt"
copy_file "$src" "$work/link.txt" 2>/dev/null
[ ! -L "$work/link.txt" ] || {
  echo 'copy_file left dest as a symlink' >&2
  exit 1
}
[ "$(cat "$work/link.txt")" = new ] || {
  echo 'copy_file did not replace symlink' >&2
  exit 1
}
[ "$(cat "$other")" = other ] || {
  echo 'copy_file wrote through the symlink' >&2
  exit 1
}

mode_dest="$work/mode.txt"
copy_file "$src" "$mode_dest" 600
[ "$(stat -c %a "$mode_dest")" = 600 ] || {
  echo "copy_file mode: $(stat -c %a "$mode_dest")" >&2
  exit 1
}

# Full set of repo configs into a fake $HOME.
tree="$work/repo"
home="$work/home"
mkdir -p "$tree/zsh/linux" "$tree/git" "$tree/ohmyposh" "$tree/ssh"
printf 'zshrc\n' >"$tree/zsh/linux/.zshrc"
printf 'gitconfig\n' >"$tree/git/.gitconfig"
printf 'omp\n' >"$tree/ohmyposh/theme.omp.json"
printf 'sshconfig\n' >"$tree/ssh/config"
printf 'keys\n' >"$tree/ssh/authorized_keys"
printf 'signers\n' >"$tree/ssh/allowed_signers"
mkdir -p "$home"
printf 'old-zshrc\n' >"$home/.zshrc"

err=$(HOME="$home" SAUCE_ROOT="$tree" install_dotfiles 2>&1 >/dev/null) || true
printf '%s\n' "$err" | grep -q "replacing $home/.zshrc" || {
  printf 'install_dotfiles missing zshrc replacement warning\n%s\n' "$err" >&2
  exit 1
}
[ "$(cat "$home/.zshrc")" = zshrc ] || {
  echo 'install_dotfiles missed .zshrc' >&2
  exit 1
}
[ "$(cat "$home/.gitconfig")" = gitconfig ] || {
  echo 'install_dotfiles missed .gitconfig' >&2
  exit 1
}
[ "$(cat "$home/.config/ohmyposh/theme.omp.json")" = omp ] || {
  echo 'install_dotfiles missed ohmyposh theme' >&2
  exit 1
}
[ "$(cat "$home/.ssh/config")" = sshconfig ] || {
  echo 'install_dotfiles missed ssh config' >&2
  exit 1
}
[ "$(cat "$home/.ssh/authorized_keys")" = keys ] || {
  echo 'install_dotfiles missed authorized_keys' >&2
  exit 1
}
[ "$(cat "$home/.ssh/allowed_signers")" = signers ] || {
  echo 'install_dotfiles missed allowed_signers' >&2
  exit 1
}
[ "$(stat -c %a "$home/.ssh")" = 700 ] || {
  echo "ssh dir mode: $(stat -c %a "$home/.ssh")" >&2
  exit 1
}
[ "$(stat -c %a "$home/.ssh/config")" = 600 ] || {
  echo "ssh config mode: $(stat -c %a "$home/.ssh/config")" >&2
  exit 1
}

echo ok
