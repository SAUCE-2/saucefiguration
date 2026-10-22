#!/usr/bin/env bash
# Self-check for install.sh helpers. Sources the function half only.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck source=install.sh
SAUCE_LIB_ONLY=1 . "$script_dir/install.sh"

# Octal permission bits, e.g. 600. GNU stat takes -c, BSD (macOS) stat -f.
file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

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
for pm in pacman apk; do
  [ "$(pkg_name "$pm" gh)" = github-cli ] || {
    echo "pkg_name $pm gh" >&2
    exit 1
  }
done
for pm in brew apt-get dnf zypper; do
  [ "$(pkg_name "$pm" gh)" = gh ] || {
    echo "pkg_name $pm gh" >&2
    exit 1
  }
done
for v in go1.24.2 go1.24 go1.25.3 go2.0; do
  go_version_ok "$v" || {
    echo "go_version_ok $v should pass" >&2
    exit 1
  }
done
for v in go1.19.8 go1.23.4 go1.9 devel garbage; do
  go_version_ok "$v" && {
    echo "go_version_ok $v should fail" >&2
    exit 1
  }
done
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
# find_plugin looks in $HOMEBREW_PREFIX first, and the darwin .zshrc exports
# it. Clear it so a brew-installed copy on this machine can't answer.
got=$(HOMEBREW_PREFIX='' HOME="$work/home" find_plugin zsh-autosuggestions) || {
  echo 'find_plugin missed ~/.local/share' >&2
  exit 1
}
[ "$got" = "$work/home/.local/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ] || {
  echo "find_plugin path: $got" >&2
  exit 1
}
mkdir -p "$work/brew/share/zsh-autosuggestions"
touch "$work/brew/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
got=$(HOMEBREW_PREFIX="$work/brew" HOME="$work/home" find_plugin zsh-autosuggestions)
[ "$got" = "$work/brew/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ] || {
  echo "find_plugin should prefer Homebrew's copy: $got" >&2
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
ls "$dest".bak.* >/dev/null 2>&1 && {
  echo 'identical dest should not leave a backup' >&2
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
# The old dest is kept next to it, and the warning says where.
backup=$(printf '%s\n' "$err" | sed -n 's/.*(backup: \(.*\))$/\1/p')
case "$backup" in
  "$dest".bak.[0-9]*) ;;
  *)
    printf 'warning should name a %s.bak.<time> backup\n%s\n' "$dest" "$err" >&2
    exit 1
    ;;
esac
[ "$(cat "$backup")" = old ] || {
  echo 'backup does not hold the old dest' >&2
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
rm -f "$dest".bak.*
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
ls "$dest".bak.* >/dev/null 2>&1 && {
  echo 'dry-run left a backup' >&2
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
[ "$(file_mode "$mode_dest")" = 600 ] || {
  echo "copy_file mode: $(file_mode "$mode_dest")" >&2
  exit 1
}

# tmux plugins: clone tpm once, then install the declared plugins.
th="$work/tmuxhome"
mkdir -p "$th" "$work/tmuxbin" "$work/notmux"
printf '#!/bin/sh\n' >"$work/tmuxbin/tmux"
chmod +x "$work/tmuxbin/tmux"
out=$(HOME="$th" PATH="$work/tmuxbin" DRY_RUN=1 install_tmux_plugins 2>&1)
printf '%s\n' "$out" | grep -q "would run: git clone --depth 1 https://github.com/tmux-plugins/tpm $th/.tmux/plugins/tpm" || {
  printf 'tmux plugins dry-run missed the tpm clone\n%s\n' "$out" >&2
  exit 1
}
printf '%s\n' "$out" | grep -q "would run: $th/.tmux/plugins/tpm/bin/install_plugins" || {
  printf 'tmux plugins dry-run missed install_plugins\n%s\n' "$out" >&2
  exit 1
}
mkdir -p "$th/.tmux/plugins/tpm"
printf '#!/bin/sh\n' >"$th/.tmux/plugins/tpm/tpm"
chmod +x "$th/.tmux/plugins/tpm/tpm"
out=$(HOME="$th" PATH="$work/tmuxbin" DRY_RUN=1 install_tmux_plugins 2>&1)
printf '%s\n' "$out" | grep -q 'git clone' && {
  printf 'tmux plugins should not re-clone tpm\n%s\n' "$out" >&2
  exit 1
}
printf '%s\n' "$out" | grep -q 'install_plugins' || {
  printf 'tmux plugins should still install plugins with tpm present\n%s\n' "$out" >&2
  exit 1
}
out=$(HOME="$th" PATH="$work/notmux" DRY_RUN=1 install_tmux_plugins 2>&1)
printf '%s\n' "$out" | grep -q 'install_plugins' && {
  printf 'tmux plugins should skip without tmux\n%s\n' "$out" >&2
  exit 1
}

# Full set of repo configs into a fake $HOME.
tree="$work/repo"
home="$work/home"
mkdir -p "$tree/zsh/linux" "$tree/zsh/darwin" "$tree/tmux" "$tree/git" "$tree/ohmyposh" "$tree/ssh"
printf 'zshrc\n' >"$tree/zsh/linux/.zshrc"
printf 'zshrc\n' >"$tree/zsh/darwin/.zshrc"
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
[ "$(file_mode "$home/.ssh")" = 700 ] || {
  echo "ssh dir mode: $(file_mode "$home/.ssh")" >&2
  exit 1
}
[ "$(file_mode "$home/.ssh/config")" = 600 ] || {
  echo "ssh config mode: $(file_mode "$home/.ssh/config")" >&2
  exit 1
}

# authorized_keys on a server: keys only it has survive, after the repo's.
# The repo's line for a key replaces an old one with another comment.
aktree="$work/aktree"
cp -R "$tree" "$aktree"
printf '%s\n' \
  'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIrepo1 s@desktop' \
  'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIrepo2 s@macbook' >"$aktree/ssh/authorized_keys"
akh="$work/akhome"
mkdir -p "$akh/.ssh"
printf '%s\n' \
  'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIrepo1 old-comment' \
  '' \
  'from="10.0.0.0/8",no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIserver deploy@ci' >"$akh/.ssh/authorized_keys"
chmod 600 "$akh/.ssh/authorized_keys"
old_keys=$(cat "$akh/.ssh/authorized_keys")
HOME="$akh" SAUCE_ROOT="$aktree" install_dotfiles >/dev/null 2>&1 || true
want=$(printf '%s\n' \
  'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIrepo1 s@desktop' \
  'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIrepo2 s@macbook' \
  'from="10.0.0.0/8",no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIserver deploy@ci')
[ "$(cat "$akh/.ssh/authorized_keys")" = "$want" ] || {
  printf 'authorized_keys merge\n%s\n' "$(cat "$akh/.ssh/authorized_keys")" >&2
  exit 1
}
ak_backup=$(ls "$akh/.ssh"/authorized_keys.bak.*) || {
  echo 'replaced authorized_keys has no backup' >&2
  exit 1
}
[ "$(cat "$ak_backup")" = "$old_keys" ] || {
  echo 'authorized_keys backup does not hold the old file' >&2
  exit 1
}
# find -perm, not stat: GNU and BSD (macOS) stat take different flags.
for f in "$ak_backup" "$akh/.ssh/authorized_keys"; do
  [ -n "$(find "$f" -perm 600)" ] || {
    echo 'authorized_keys mode is not 600:' >&2
    ls -l "$f" >&2
    exit 1
  }
done
# Re-run: the merge is stable, so nothing is replaced or backed up again.
err=$(HOME="$akh" SAUCE_ROOT="$aktree" install_dotfiles 2>&1 >/dev/null) || true
printf '%s\n' "$err" | grep -q 'replacing' && {
  printf 're-run should replace nothing\n%s\n' "$err" >&2
  exit 1
}

# Real clone: every file in git/, ssh/, ohmyposh/ must land in $HOME.
# zsh/ is only the platform .zshrc; install.sh and tests stay in the clone.
real_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
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
for cmd in bash sh tr mktemp tar find mkdir mv chmod rm cp cmp dirname basename awk date; do
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
# Only the scripts: chmod follows the symlinks above to the real tools, which
# a non-root user (CI) may not change.
chmod +x "$stubs/uname" "$stubs/id" "$stubs/sudo" "$stubs/apt-get" "$stubs/curl" "$stubs/git"
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
