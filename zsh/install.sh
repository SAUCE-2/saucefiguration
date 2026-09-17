#!/usr/bin/env bash
# Installs everything the .zshrc files in this directory expect to find.
# Run this after zsh itself is installed. Safe to re-run. Does not touch
# your dotfiles. Stamps this clone's HEAD so the next shell can notice
# new commits and offer to re-run (see check-update.sh).
#
#   ./install.sh            install
#   ./install.sh --dry-run  print the commands instead of running them
#
# Supports Darwin (Homebrew) plus apt, dnf, pacman, zypper and apk. Every tool
# here is optional to the shell itself, because the .zshrc guards each one, so a
# package your distro does not carry only produces a warning.

set -euo pipefail

# The one list to edit when the .zshrc starts using a new tool. Each entry is
# a package name, then the binaries the shell config looks for: Debian renames
# some of them, so a tool can answer to more than one name. An empty binary
# list means the plugin file probe verifies it instead of a command lookup.
# This drives both the install loop and the verify pass.
packages="
  git:git
  curl:curl
  eza:eza
  bat:bat,batcat
  fd:fd,fdfind
  ripgrep:rg
  fzf:fzf
  zoxide:zoxide
  lazygit:lazygit
  zsh-autosuggestions:
  zsh-syntax-highlighting:
"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mskip:\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# Wraps every mutating command so --dry-run can show it instead.
run() {
  if [ "${DRY_RUN:-0}" = 1 ]; then
    printf '   would run: %s\n' "$*"
  else
    "$@"
  fi
}

if [ "$(id -u)" -eq 0 ] || ! have sudo; then
  as_root() { run "$@"; }
else
  as_root() { run sudo "$@"; }
fi

# Darwin always means Homebrew; on Linux the first manager present wins.
detect_pm() {
  local candidate
  if [ "$(uname -s)" = Darwin ]; then
    echo brew
    return
  fi
  for candidate in apt-get dnf pacman zypper apk; do
    if have "$candidate"; then
      echo "$candidate"
      return
    fi
  done
}

# Canonical name -> package name. Only the renames need an entry.
pkg_name() {
  case "$1:$2" in
    apt-get:fd | dnf:fd) echo fd-find ;;
    dnf:command-not-found) echo PackageKit-command-not-found ;;
    pacman:command-not-found) echo pkgfile ;;
    dnf:openssh-client) echo openssh-clients ;;
    pacman:openssh-client | zypper:openssh-client) echo openssh ;;
    *) echo "$2" ;;
  esac
}

install_pkg() {
  local pkg
  pkg=$(pkg_name "$PM" "$1")
  case "$PM" in
    brew) run brew install "$pkg" ;;
    apt-get) as_root apt-get install -y "$pkg" ;;
    dnf) as_root dnf install -y "$pkg" ;;
    pacman) as_root pacman -S --needed --noconfirm "$pkg" ;;
    zypper) as_root zypper install -y "$pkg" ;;
    apk) as_root apk add "$pkg" ;;
  esac
}

# Reports which of $2.. resolved for the tool named $1. Debian renames some
# binaries (batcat, fdfind), so a tool can answer to more than one name.
check() {
  local label=$1 cmd
  shift
  for cmd in "$@"; do
    if have "$cmd"; then
      printf '  ok       %-22s %s\n' "$label" "$cmd"
      return 0
    fi
  done
  printf '  missing  %s\n' "$label"
  return 1
}

# zsh plugin files land in different directories depending on the packager.
find_plugin() {
  local dir
  for dir in "${HOMEBREW_PREFIX:-}/share" /usr/share /usr/share/zsh/plugins /usr/local/share; do
    if [ -f "$dir/$1/$1.zsh" ]; then
      echo "$dir/$1/$1.zsh"
      return 0
    fi
  done
  return 1
}

# Stamp this clone so a later shell can notice new commits (see check-update.sh).
# SAUCE_ROOT / SAUCE_STATE_DIR are for tests; live runs use this script's path.
record_install_rev() {
  local root sha state
  root=${SAUCE_ROOT:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)} || return 0
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

PM=$(detect_pm)
if [ -z "$PM" ]; then
  echo "No supported package manager found (brew, apt-get, dnf, pacman, zypper, apk)." >&2
  exit 1
fi
log "Using $PM on $(uname -s) $(uname -m)"

# Homebrew is the one package manager we can install ourselves.
if [ "$PM" = brew ] && ! have brew; then
  log "Installing Homebrew"
  run bash -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  for prefix in /opt/homebrew /usr/local; do
    if [ -x "$prefix/bin/brew" ]; then
      eval "$("$prefix/bin/brew" shellenv)"
      break
    fi
  done
fi

if [ "$PM" = apt-get ]; then
  log "Refreshing apt package lists"
  as_root apt-get update
fi

log "Installing packages"
for entry in $packages; do
  pkg=${entry%%:*}
  install_pkg "$pkg" ||
    warn "$PM has no '$(pkg_name "$PM" "$pkg")'; install it yourself if you want it"
done

# Homebrew merged this into brew itself. Tapping the old repo is now a hard
# error ("this tap is now empty") and would abort the rest of this script.
if [ "$PM" != brew ]; then
  log "Installing the command-not-found handler"
  install_pkg command-not-found ||
    warn "no command-not-found backend for $PM; the plugin will stay quiet"
fi

if [ -d "$HOME/.oh-my-zsh" ]; then
  log "Oh My Zsh already installed"
else
  log "Installing Oh My Zsh"
  # KEEP_ZSHRC stops the installer replacing the .zshrc from this repo, CHSH
  # leaves the login shell alone, RUNZSH keeps this script going.
  run bash -c 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
fi

# ssh-agent ships with OpenSSH. Skip Homebrew: Apple's /usr/bin/ssh is what
# understands UseKeychain, which brew's portable OpenSSH does not.
if [ "$PM" != brew ]; then
  log "Installing OpenSSH client (ssh-agent)"
  install_pkg openssh-client ||
    warn "$PM has no '$(pkg_name "$PM" openssh-client)'; install ssh-agent yourself if you want it"
fi

if have fnm; then
  log "fnm already installed"
elif [ "$PM" = brew ]; then
  log "Installing fnm"
  install_pkg fnm || warn "brew could not install fnm"
else
  log "Installing fnm into ~/.local/share/fnm"
  install_pkg unzip || warn "no unzip; the fnm installer needs it"
  # --skip-shell: the .zshrc in this repo already runs `fnm env`.
  run bash -c 'curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell'
fi

if have oh-my-posh; then
  log "Oh My Posh already installed"
elif [ "$PM" = brew ]; then
  log "Installing Oh My Posh"
  run brew install oh-my-posh || run brew install jandedobbeleer/oh-my-posh/oh-my-posh
else
  log "Installing Oh My Posh into ~/.local/bin"
  run bash -c 'curl -fsSL https://ohmyposh.dev/install.sh | bash -s'
fi

# Vite+ is not in distro repos. CI=true is silent/--yes; VP_NODE_MANAGER=yes
# skips the Node-manager prompt. The .zshrc sources ~/.config/vite-plus/env.
if have vp || [ -x "$HOME/.local/share/vite-plus/bin/vp" ]; then
  log "Vite+ already installed"
else
  log "Installing Vite+"
  if [ "$PM" = apk ]; then
    install_pkg libstdc++ || warn "no libstdc++; Vite+'s managed Node needs it"
  fi
  run bash -c 'curl -fsSL https://vite.plus | CI=true VP_NODE_MANAGER=yes bash'
fi

if [ -f "$HOME/.config/vite-plus/env" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.config/vite-plus/env"
fi

log "Verifying what the shell config will find"
missing=0
# zsh is a prerequisite rather than a package here. fnm, oh-my-posh and Vite+
# are installed by vendor scripts above; ssh-agent ships with OpenSSH.
for tool in zsh fnm oh-my-posh vp ssh-agent ssh-add; do
  check "$tool" "$tool" || missing=$((missing + 1))
done

for entry in $packages; do
  binaries=${entry#*:}
  # Entries with no binary are plugin files, checked by the probe below.
  [ -n "$binaries" ] || continue
  # Word splitting on the comma list is deliberate: one tool, several names.
  check "${entry%%:*}" $(echo "$binaries" | tr ',' ' ') || missing=$((missing + 1))
done

for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  if plugin_path=$(find_plugin "$plugin"); then
    printf '  ok       %-22s %s\n' "$plugin" "$plugin_path"
  else
    printf '  missing  %s\n' "$plugin"
    missing=$((missing + 1))
  fi
done

if [ -d "$HOME/.oh-my-zsh" ]; then
  printf '  ok       %-22s %s\n' oh-my-zsh "$HOME/.oh-my-zsh"
else
  printf '  missing  %s\n' oh-my-zsh
  missing=$((missing + 1))
fi

if [ "$missing" -gt 0 ]; then
  warn "$missing item(s) unavailable. The .zshrc guards each one, so zsh still starts."
fi

record_install_rev
log "Done."
