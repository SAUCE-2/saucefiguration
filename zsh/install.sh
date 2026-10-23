#!/usr/bin/env bash
# Sets this machine up from this clone: installs Nix if it is missing, then
# applies the home-manager profile for this platform (flake.nix), which
# provides every tool and config file. Safe to re-run; check-update.sh runs
# it again when the clone gets new commits. Must stay bash 3.2-safe: on a
# new Mac it runs under /bin/bash before anything else is installed.
#
#   ./install.sh            install
#   ./install.sh --dry-run  install nothing; show what home-manager would change
#
# A file home-manager needs to replace is kept as <file>.bak.<time>.

set -euo pipefail

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# Wraps every mutating command so --dry-run can show it instead.
run() {
  if [ "${DRY_RUN:-0}" = 1 ]; then
    printf '   would run: %s\n' "$*"
  else
    "$@"
  fi
}

# True inside WSL 1 or 2. WSL_DISTRO_NAME is gone under sudo or env -i, so
# also look for the interop handler and the kernel release string.
# SAUCE_WSL_INTEROP is for tests.
is_wsl() {
  [ "$(uname -s)" = Linux ] || return 1
  [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
  [ -e "${SAUCE_WSL_INTEROP:-/proc/sys/fs/binfmt_misc/WSLInterop}" ] && return 0
  case "$(uname -r)" in
    *[Mm]icrosoft* | *WSL*) return 0 ;;
  esac
  return 1
}

# The homeConfigurations name in flake.nix for this machine.
profile_name() {
  local cpu os
  case "$(uname -m)" in
    x86_64 | amd64) cpu=x86_64 ;;
    aarch64 | arm64) cpu=aarch64 ;;
    *) return 1 ;;
  esac
  case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=darwin ;;
    *) return 1 ;;
  esac
  # nixpkgs dropped Intel Macs.
  [ "$cpu-$os" = x86_64-darwin ] && return 1
  if [ "$os" = linux ] && is_wsl; then
    echo "$cpu-$os-wsl"
  else
    echo "$cpu-$os"
  fi
}

# Nix's multi-user install puts nix on PATH from /etc's shell startup files,
# which this already-running shell has not read. SAUCE_NIX_PROFILE_SH is for
# tests.
load_nix() {
  local f
  for f in "${SAUCE_NIX_PROFILE_SH:-/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh}" \
    "$HOME/.nix-profile/etc/profile.d/nix.sh"; do
    if [ -r "$f" ]; then
      set +u
      # shellcheck disable=SC1090
      . "$f"
      set -u
      return 0
    fi
  done
  return 0
}

# Determinate Systems' installer: macOS, Linux, WSL and SteamOS (where it
# keeps /nix on /home, so an OS update does not wipe it). It asks before
# changing anything.
install_nix() {
  log "Installing Nix"
  run bash -c 'curl --proto =https --tlsv1.2 -fsSL https://install.determinate.systems/nix | sh -s -- install'
}

# The old installer copied these into $HOME. git and tmux read them ahead of
# the ~/.config files home-manager writes, so a stale copy would hide every
# change made here. Each is kept as <file>.bak.<time>. ~/.gitconfig comes
# back empty, for machine-local settings and `git config --global` writes
# (home-manager's ~/.config/git/config is read-only).
retire_legacy_files() {
  local stamp=$1 f
  for f in "$HOME/.gitconfig" "$HOME/.tmux.conf"; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    # Already the local-settings file this function leaves behind.
    if [ "$f" = "$HOME/.gitconfig" ] && grep -q '^# saucefiguration: machine-local' "$f"; then
      continue
    fi
    warn "moving the old $f aside (backup: $f.bak.$stamp)"
    run mv "$f" "$f.bak.$stamp"
    if [ "$f" = "$HOME/.gitconfig" ] && [ "${DRY_RUN:-0}" != 1 ]; then
      printf '%s\n' \
        '# saucefiguration: machine-local git settings. The shared ones live in' \
        '# ~/.config/git/config (from the repo); anything here overrides them.' >"$f"
    fi
  done
}

# Builds the profile and runs its activation script, which links the
# configs into $HOME and runs the activation steps (ssh/default.nix).
# --impure: home.nix reads $USER and $HOME.
switch_profile() {
  local root=$1 profile=$2 stamp=$3 gen
  log "Building home-manager profile $profile"
  gen=$(nix --extra-experimental-features 'nix-command flakes' build --no-link --print-out-paths \
    --impure "$root#homeConfigurations.$profile.activationPackage") || return 1
  log "Activating $gen"
  if [ "${DRY_RUN:-0}" = 1 ]; then
    DRY_RUN=1 "$gen/activate"
  else
    # Where home-manager keeps its generations. Nix creates it on first use
    # of a user profile, which a fresh install has not had yet.
    mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles"
    HOME_MANAGER_BACKUP_EXT="bak.$stamp" "$gen/activate"
  fi
}

# Stamp this clone so a later shell can offer to update (see check-update.sh).
# SAUCE_ROOT / SAUCE_STATE_DIR are for tests; live runs use this script's path.
record_install_rev() {
  local root sha state
  root=${SAUCE_ROOT:-$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)} || return 0
  sha=$(git -C "$root" rev-parse HEAD 2>/dev/null) || return 0
  state="${SAUCE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/saucefiguration}"
  if [ "${DRY_RUN:-0}" = 1 ]; then
    printf '   would record %s in %s\n' "$sha" "$state"
    return 0
  fi
  mkdir -p "$state"
  printf '%s\n' "$root" >"$state/repo"
  printf '%s\n' "$sha" >"$state/sha"
  rm -f "$state/snooze"
}

# What the old installer put in $HOME that Nix now provides. Nothing reads
# these any more; they are listed, not deleted.
report_leftovers() {
  local found='' p
  for p in .nvm .oh-my-zsh .tmux/plugins .local/go .gitignore_global .config/ohmyposh \
    .local/share/fzf-tab .local/share/zsh-autosuggestions .local/share/zsh-syntax-highlighting \
    .local/bin/eza .local/bin/bat .local/bin/fd .local/bin/rg .local/bin/fzf .local/bin/zoxide \
    .local/bin/direnv .local/bin/lazygit .local/bin/micro .local/bin/delta .local/bin/jq \
    .local/bin/yq .local/bin/gh .local/bin/oh-my-posh .local/bin/dotenv .local/bin/dotenv-linter; do
    if [ -e "$HOME/$p" ] || [ -L "$HOME/$p" ]; then
      found="$found  ~/$p"$'\n'
    fi
  done
  [ -n "$found" ] || return 0
  warn "left over from the pre-Nix setup and no longer used; delete when ready:"
  printf '%s' "$found" >&2
}

# install.test.sh sources this file for the functions above and nothing else.
if [ "${SAUCE_LIB_ONLY:-0}" = 1 ]; then
  return 0
fi

case "${1:-}" in
  "") DRY_RUN=${DRY_RUN:-0} ;;
  --dry-run) DRY_RUN=1 ;;
  *)
    echo "usage: $0 [--dry-run]" >&2
    exit 64
    ;;
esac

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
export USER="${USER:-$(id -un)}"
stamp=$(date +%Y%m%d%H%M%S)

profile=$(profile_name) || {
  echo "No profile in flake.nix for $(uname -s) $(uname -m)." >&2
  exit 1
}
log "Profile $profile"

have nix || load_nix
if ! have nix; then
  install_nix || {
    echo "Nix install failed; re-run $0 to retry." >&2
    exit 1
  }
  load_nix
  if ! have nix; then
    [ "$DRY_RUN" = 1 ] && exit 0
    echo "Nix is installed but not on PATH; open a new terminal and re-run $0." >&2
    exit 1
  fi
fi

retire_legacy_files "$stamp"
switch_profile "$root" "$profile" "$stamp" || {
  echo "home-manager switch failed; fix the error above and re-run $0." >&2
  exit 1
}
record_install_rev
report_leftovers

# The system's zsh works with this config. Nix's would first need a line in
# /etc/shells, which an OS update can reset.
case "${SHELL:-}" in
  */zsh) ;;
  *)
    for zsh in /bin/zsh /usr/bin/zsh; do
      if [ -x "$zsh" ]; then
        warn "your login shell is ${SHELL:-unset}; switch with: chsh -s $zsh"
        break
      fi
    done
    [ -x "${zsh:-}" ] ||
      warn "your login shell is ${SHELL:-unset} and the system has no zsh; install it with the system's package manager, then chsh -s to it"
    ;;
esac

log "Done."
