#!/usr/bin/env bash
# Self-check for install.sh helpers (sourced, function half only) and
# ssh/merge-authorized-keys.sh. Writes only to a mktemp dir and runs no Nix.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
# shellcheck source=install.sh
SAUCE_LIB_ONLY=1 . "$script_dir/install.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A fake uname answers -s with $FAKE_S, -r with $FAKE_R and -m with $FAKE_M.
mkdir -p "$work/uname"
cat >"$work/uname/uname" <<'EOF'
#!/bin/sh
case "$1" in -r) echo "$FAKE_R" ;; -m) echo "$FAKE_M" ;; *) echo "$FAKE_S" ;; esac
EOF
chmod +x "$work/uname/uname"
touch "$work/uname/WSLInterop"

wsl_case() { # expect(0|1) uname-s uname-r WSL_DISTRO_NAME interop-file
  local got=0
  PATH="$work/uname:$PATH" FAKE_S=$2 FAKE_R=$3 WSL_DISTRO_NAME=$4 SAUCE_WSL_INTEROP=$5 is_wsl || got=1
  [ "$got" = "$1" ] || {
    echo "is_wsl -s '$2' -r '$3' distro '$4' interop '$5': want $1, got $got" >&2
    exit 1
  }
}
wsl_case 1 Linux 6.8.0-45-generic '' "$work/uname/none"
wsl_case 1 Darwin 23.6.0 Ubuntu "$work/uname/WSLInterop"
wsl_case 0 Linux 6.6.87.2-microsoft-standard-WSL2 '' "$work/uname/none"
wsl_case 0 Linux 4.4.0-19041-Microsoft '' "$work/uname/none"
wsl_case 0 Linux 6.8.0-45-generic Ubuntu "$work/uname/none"
wsl_case 0 Linux 6.8.0-45-generic '' "$work/uname/WSLInterop"

profile_case() { # want uname-s uname-m uname-r ('' = no profile)
  local got
  got=$(PATH="$work/uname:$PATH" FAKE_S=$2 FAKE_M=$3 FAKE_R=$4 WSL_DISTRO_NAME='' \
    SAUCE_WSL_INTEROP="$work/uname/none" profile_name) || got=''
  [ "$got" = "$1" ] || {
    echo "profile_name $2 $3 $4: want '$1', got '$got'" >&2
    exit 1
  }
}
profile_case x86_64-linux Linux x86_64 6.8.0-45-generic
profile_case aarch64-linux Linux aarch64 6.8.0-45-generic
profile_case x86_64-linux-wsl Linux x86_64 6.6.87.2-microsoft-standard-WSL2
profile_case aarch64-darwin Darwin arm64 23.6.0
profile_case '' Darwin x86_64 23.6.0
profile_case '' Linux riscv64 6.8.0
profile_case '' FreeBSD amd64 14.1

# Every profile_name answer must exist in flake.nix, and the reverse.
for p in x86_64-linux aarch64-linux x86_64-linux-wsl aarch64-linux-wsl aarch64-darwin; do
  case "$p" in
    *-wsl) sys=${p%-wsl} ;;
    *) sys=$p ;;
  esac
  grep -q "\"$sys\"" "$root/flake.nix" || {
    echo "flake.nix has no system $sys for profile $p" >&2
    exit 1
  }
done

# Legacy files: moved aside once, and ~/.gitconfig comes back as the
# machine-local file that later runs leave alone.
lh="$work/legacy"
mkdir -p "$lh"
printf '[user]\n\tname = old\n' >"$lh/.gitconfig"
printf 'set -g mouse on\n' >"$lh/.tmux.conf"
HOME="$lh" retire_legacy_files 20260101000000 2>/dev/null
[ "$(cat "$lh/.gitconfig.bak.20260101000000")" = "$(printf '[user]\n\tname = old')" ] || {
  echo 'retire_legacy_files lost the old .gitconfig' >&2
  exit 1
}
grep -q '^# saucefiguration: machine-local' "$lh/.gitconfig" || {
  echo 'retire_legacy_files did not leave a machine-local .gitconfig' >&2
  exit 1
}
[ -f "$lh/.tmux.conf.bak.20260101000000" ] && [ ! -e "$lh/.tmux.conf" ] || {
  echo 'retire_legacy_files did not move .tmux.conf aside' >&2
  exit 1
}
printf '[credential]\n\thelper = store\n' >>"$lh/.gitconfig"
err=$(HOME="$lh" retire_legacy_files 20260202000000 2>&1)
[ -z "$err" ] && [ ! -e "$lh/.gitconfig.bak.20260202000000" ] || {
  printf 're-run touched the machine-local .gitconfig\n%s\n' "$err" >&2
  exit 1
}
# A symlink (someone else's dotfile manager) is not ours to move.
sh2="$work/legacy2"
mkdir -p "$sh2"
printf 'x\n' >"$work/other.conf"
ln -s "$work/other.conf" "$sh2/.tmux.conf"
HOME="$sh2" retire_legacy_files 20260101000000 2>/dev/null
[ -L "$sh2/.tmux.conf" ] || {
  echo 'retire_legacy_files moved a symlink' >&2
  exit 1
}
# Dry run: says what it would move, moves nothing.
dh="$work/legacy-dry"
mkdir -p "$dh"
printf 'old\n' >"$dh/.gitconfig"
out=$(HOME="$dh" DRY_RUN=1 retire_legacy_files 20260101000000 2>&1)
printf '%s\n' "$out" | grep -q "would run: mv $dh/.gitconfig" && [ "$(cat "$dh/.gitconfig")" = old ] || {
  printf 'dry-run retire_legacy_files\n%s\n' "$out" >&2
  exit 1
}

# Leftovers are listed, never deleted.
oh="$work/leftovers"
mkdir -p "$oh/.nvm" "$oh/.local/bin"
touch "$oh/.local/bin/eza"
err=$(HOME="$oh" report_leftovers 2>&1)
case "$err" in
  *'/.nvm'*'/.local/bin/eza'*) ;;
  *)
    printf 'report_leftovers missed a leftover\n%s\n' "$err" >&2
    exit 1
    ;;
esac
[ -d "$oh/.nvm" ] && [ -f "$oh/.local/bin/eza" ] || {
  echo 'report_leftovers deleted something' >&2
  exit 1
}
err=$(HOME="$work/empty-home" report_leftovers 2>&1)
[ -z "$err" ] || {
  printf 'report_leftovers spoke with nothing left over\n%s\n' "$err" >&2
  exit 1
}

# The stamp check-update.sh reads.
git -C "$work" init -q stamprepo
git -C "$work/stamprepo" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false \
  commit -q --allow-empty -m init
SAUCE_ROOT="$work/stamprepo" SAUCE_STATE_DIR="$work/state" record_install_rev
[ "$(cat "$work/state/repo")" = "$work/stamprepo" ] &&
  [ "$(cat "$work/state/sha")" = "$(git -C "$work/stamprepo" rev-parse HEAD)" ] || {
  echo 'record_install_rev wrote the wrong stamp' >&2
  exit 1
}

# Whole script, dry run, on a machine without Nix: it offers to install Nix
# and changes nothing. PATH holds only stubs and basic tools.
stubs="$work/stubs"
mkdir -p "$stubs"
for cmd in bash sh dirname date id cat; do
  ln -s "$(command -v "$cmd")" "$stubs/$cmd"
done
cat >"$stubs/uname" <<'EOF'
#!/bin/sh
case "$1" in -m) echo x86_64 ;; -r) echo 6.8.0-45-generic ;; *) echo Linux ;; esac
EOF
chmod +x "$stubs/uname"
dry_home="$work/dryhome"
mkdir -p "$dry_home"
status=0
out=$(env -i HOME="$dry_home" PATH="$stubs" SAUCE_WSL_INTEROP="$work/uname/none" SAUCE_NIX_PROFILE_SH=/nonexistent \
  "$BASH" "$script_dir/install.sh" --dry-run 2>&1) || status=$?
[ "$status" = 0 ] || {
  printf 'dry run without Nix should exit 0, got %s\n%s\n' "$status" "$out" >&2
  exit 1
}
case "$out" in
  *'Profile x86_64-linux'*'would run: '*'install.determinate.systems/nix'*) ;;
  *)
    printf 'dry run should name the profile and the Nix installer\n%s\n' "$out" >&2
    exit 1
    ;;
esac
[ -z "$(ls -A "$dry_home")" ] || {
  echo "dry run wrote to $dry_home" >&2
  exit 1
}

status=0
"$BASH" "$script_dir/install.sh" --bogus >/dev/null 2>&1 || status=$?
[ "$status" = 64 ] || {
  echo "unknown flag should exit 64, got $status" >&2
  exit 1
}

# authorized_keys on a server: keys only it has survive, after the repo's.
# The repo's line for a key replaces an old one with another comment.
merge="$root/ssh/merge-authorized-keys.sh"
printf '%s\n' \
  'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIrepo1 s@desktop' \
  'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIrepo2 s@macbook' >"$work/repo_keys"
akh="$work/akhome"
mkdir -p "$akh/.ssh"
printf '%s\n' \
  'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIrepo1 old-comment' \
  '' \
  'from="10.0.0.0/8",no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIserver deploy@ci' >"$akh/.ssh/authorized_keys"
chmod 600 "$akh/.ssh/authorized_keys"
old_keys=$(cat "$akh/.ssh/authorized_keys")
bash "$merge" "$work/repo_keys" "$akh/.ssh/authorized_keys" >/dev/null
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
out=$(bash "$merge" "$work/repo_keys" "$akh/.ssh/authorized_keys")
backups=0
for f in "$akh/.ssh"/authorized_keys.bak.*; do
  backups=$((backups + 1))
done
[ -z "$out" ] && [ "$backups" = 1 ] || {
  printf 're-run should change nothing\n%s\n' "$out" >&2
  exit 1
}
# No authorized_keys yet: the repo's keys, no backup.
fresh="$work/akfresh/.ssh/authorized_keys"
bash "$merge" "$work/repo_keys" "$fresh" >/dev/null
[ "$(cat "$fresh")" = "$(cat "$work/repo_keys")" ] && [ -n "$(find "$fresh" -perm 600)" ] || {
  echo 'fresh authorized_keys is wrong' >&2
  exit 1
}

echo ok
