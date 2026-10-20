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
[ "$(pkg_name apt-get go)" = golang-go ] || {
  echo 'pkg_name apt-get go' >&2
  exit 1
}
[ "$(pkg_name dnf go)" = golang ] || {
  echo 'pkg_name dnf go' >&2
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

out=$(PATH=/usr/bin:/bin DRY_RUN=1 install_webi dotenv-linter)
printf '%s\n' "$out" | grep -q 'https://webi.sh/dotenv-linter@stable' || {
  printf 'install_webi dry-run missed the webinstall URL\n%s\n' "$out" >&2
  exit 1
}
mkdir -p "$work/bin"
printf '#!/bin/sh\necho dotenv-linter 1\n' >"$work/bin/dotenv-linter"
chmod +x "$work/bin/dotenv-linter"
out=$(PATH="$work/bin:/usr/bin:/bin" DRY_RUN=1 install_webi dotenv-linter)
printf '%s\n' "$out" | grep -q 'dotenv-linter already installed' || {
  printf 'install_webi should skip an existing binary\n%s\n' "$out" >&2
  exit 1
}

weh="$work/weh"
mkdir -p "$weh"
printf 'keep\n' >"$weh/.bashrc"
HOME="$weh" webi_rc_snapshot
printf '\nenvman\n' >>"$weh/.bashrc"
printf 'created\n' >"$weh/.zshrc"
HOME="$weh" webi_rc_restore
[ "$(cat "$weh/.bashrc")" = 'keep' ] || {
  echo 'webi_rc_restore did not put .bashrc back' >&2
  exit 1
}
[ ! -e "$weh/.zshrc" ] || {
  echo 'webi_rc_restore left a .zshrc webi created' >&2
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

# A shell sourcing ~/.zshrc runs the update, which copies a new .zshrc while
# zsh is still reading the old one. Replace the file, don't rewrite it in place.
printf 'old\n' >"$dest"
exec 3<"$dest"
copy_file "$src" "$dest" 2>/dev/null
[ "$(cat <&3)" = old ] || {
  echo 'copy_file rewrote dest in place under an open reader' >&2
  exit 1
}
exec 3<&-

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
mkdir -p "$tree/zsh/linux" "$tree/tmux" "$tree/git" "$tree/ohmyposh" "$tree/ssh"
printf 'zshrc\n' >"$tree/zsh/linux/.zshrc"
printf 'tmux\n' >"$tree/tmux/.tmux.conf"
printf 'gitconfig\n' >"$tree/git/.gitconfig"
printf 'ignore\n' >"$tree/git/.gitignore_global"
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
[ "$(cat "$home/.tmux.conf")" = tmux ] || {
  echo 'install_dotfiles missed .tmux.conf' >&2
  exit 1
}
[ "$(cat "$home/.gitconfig")" = gitconfig ] || {
  echo 'install_dotfiles missed .gitconfig' >&2
  exit 1
}
[ "$(cat "$home/.gitignore_global")" = ignore ] || {
  echo 'install_dotfiles missed .gitignore_global' >&2
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

# Real clone: every file in git/, ssh/, ohmyposh/ must land in $HOME.
# zsh/ is only the platform .zshrc; install.sh and tests stay in the clone.
real_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
real_home="$work/realhome"
mkdir -p "$real_home"
HOME="$real_home" SAUCE_ROOT="$real_root" install_dotfiles >/dev/null
case "$(uname -s)" in
  Darwin) platform=darwin ;;
  *) platform=linux ;;
esac
cmp -s "$real_root/zsh/$platform/.zshrc" "$real_home/.zshrc" || {
  echo "install_dotfiles missed real zsh/$platform/.zshrc" >&2
  exit 1
}
cmp -s "$real_root/tmux/.tmux.conf" "$real_home/.tmux.conf" || {
  echo 'install_dotfiles missed real tmux/.tmux.conf' >&2
  exit 1
}
for src in "$real_root/git"/* "$real_root/git"/.[!.]*; do
  [ -f "$src" ] || continue
  cmp -s "$src" "$real_home/$(basename "$src")" || {
    echo "install_dotfiles missed real git/$(basename "$src")" >&2
    exit 1
  }
done
for src in "$real_root/ohmyposh"/* "$real_root/ohmyposh"/.[!.]*; do
  [ -f "$src" ] || continue
  cmp -s "$src" "$real_home/.config/ohmyposh/$(basename "$src")" || {
    echo "install_dotfiles missed real ohmyposh/$(basename "$src")" >&2
    exit 1
  }
done
for src in "$real_root/ssh"/* "$real_root/ssh"/.[!.]*; do
  [ -f "$src" ] || continue
  cmp -s "$src" "$real_home/.ssh/$(basename "$src")" || {
    echo "install_dotfiles missed real ssh/$(basename "$src")" >&2
    exit 1
  }
done

# Whole run on a Linux box with no sudo rights and every installer script
# failing. PATH holds only these stubs and basic tools, so nothing real runs.
# Configs must still land and the rev be stamped, or the update prompt asks
# again in every new shell.
stubs="$work/stubs"
mkdir -p "$stubs"
for cmd in bash sh tr mktemp tar find mkdir mv chmod rm cp cmp dirname basename; do
  ln -s "$(command -v "$cmd")" "$stubs/$cmd"
done
cat >"$stubs/uname" <<'EOF'
#!/bin/sh
case "$1" in -m) echo x86_64 ;; *) echo Linux ;; esac
EOF
printf '%s\n' '#!/bin/sh' 'echo 1000' >"$stubs/id"
printf '%s\n' '#!/bin/sh' 'echo "sudo: a password is required" >&2' 'exit 1' >"$stubs/sudo"
printf '%s\n' '#!/bin/sh' 'exit 100' >"$stubs/apt-get"
# A script that fails, for the installers piped from curl into a shell.
printf '%s\n' '#!/bin/sh' 'echo "exit 7"' 'exit 22' >"$stubs/curl"
printf '%s\n' '#!/bin/sh' 'case "$*" in *rev-parse*) echo 1111111111111111111111111111111111111111 ;; *) exit 128 ;; esac' >"$stubs/git"
chmod +x "$stubs"/*
fail_home="$work/failhome"
mkdir -p "$fail_home"
status=0
out=$(env -i HOME="$fail_home" PATH="$stubs" SAUCE_ROOT="$tree" SAUCE_STATE_DIR="$work/failstate" \
  "$BASH" "$script_dir/install.sh" 2>&1) || status=$?
[ "$status" = 1 ] || {
  printf 'failed install should exit 1, got %s\n%s\n' "$status" "$out" >&2
  exit 1
}
[ "$(cat "$fail_home/.zshrc" 2>/dev/null)" = zshrc ] || {
  printf 'failed install skipped the configs\n%s\n' "$out" >&2
  exit 1
}
[ "$(cat "$work/failstate/sha" 2>/dev/null)" = 1111111111111111111111111111111111111111 ] || {
  printf 'failed install did not stamp the rev\n%s\n' "$out" >&2
  exit 1
}
printf '%s\n' "$out" | grep -q 'apt-get update, Oh My Zsh install, nvm install, Oh My Posh install\. Configs are copied' || {
  printf 'missing summary of failed steps\n%s\n' "$out" >&2
  exit 1
}
# No sudo still falls back to ~/.local.
printf '%s\n' "$out" | grep -q 'Installing eza into ~/.local/bin' || {
  printf 'no ~/.local fallback without sudo\n%s\n' "$out" >&2
  exit 1
}

echo ok
