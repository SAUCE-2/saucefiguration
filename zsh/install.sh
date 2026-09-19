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
# package your distro does not carry only produces a warning. SteamOS and other
# immutable roots still have pacman, but the db is read-only: missing tools go
# in ~/.local instead of unlocking the OS (which an update would wipe).

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
  for dir in "${HOMEBREW_PREFIX:-}/share" "$HOME/.local/share" /usr/share /usr/share/zsh/plugins /usr/local/share; do
    if [ -f "$dir/$1/$1.zsh" ]; then
      echo "$dir/$1/$1.zsh"
      return 0
    fi
  done
  return 1
}

# True when $1's mount is read-only. No findmnt => assume writable.
fs_readonly() {
  local opts
  opts=$(findmnt -n -o OPTIONS -T "$1" 2>/dev/null) || return 1
  case ",$opts," in
    *,ro,*) return 0 ;;
    *) return 1 ;;
  esac
}

# Homebrew writes to its prefix. Distro managers need a writable package db.
pm_can_write() {
  local dir
  case "$1" in
    brew) return 0 ;;
    pacman) dir=/var/lib/pacman ;;
    apt-get) dir=/var/lib/dpkg ;;
    dnf) dir=/var/lib/dnf ;;
    zypper) dir=/var/lib/zypp ;;
    apk) dir=/lib/apk ;;
    *) return 0 ;;
  esac
  ! fs_readonly "$dir"
}

github_latest_tag() {
  local url
  url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest") || return 1
  printf '%s\n' "${url##*/}"
}

# Unpack $1 (tar.gz URL) and move the file named $2 into ~/.local/bin.
install_gh_tar() {
  local url=$1 bin=$2 tmp found
  tmp=$(mktemp -d) || return 1
  if ! curl -fsSL "$url" | tar -xz -C "$tmp"; then
    rm -rf "$tmp"
    return 1
  fi
  found=$(find "$tmp" -type f -name "$bin")
  case "$found" in
    '' | *$'\n'*)
      rm -rf "$tmp"
      return 1
      ;;
  esac
  mkdir -p "$HOME/.local/bin"
  mv "$found" "$HOME/.local/bin/$bin"
  chmod +x "$HOME/.local/bin/$bin"
  rm -rf "$tmp"
}

# User-space copy of a tool the distro manager could not install. Linux only.
install_user() {
  local pkg=$1 tag ver cpu goarch farch dest
  [ "${DRY_RUN:-0}" = 1 ] && {
    printf '   would install %s into ~/.local\n' "$pkg"
    return 0
  }

  case "$pkg" in
    git | curl) return 1 ;;
    zsh-autosuggestions | zsh-syntax-highlighting)
      dest="$HOME/.local/share/$pkg"
      [ -f "$dest/$pkg.zsh" ] && return 0
      log "Installing $pkg into ~/.local/share"
      mkdir -p "$HOME/.local/share"
      rm -rf "$dest"
      git clone --depth 1 "https://github.com/zsh-users/${pkg}.git" "$dest"
      return
      ;;
  esac

  case $(uname -m) in
    x86_64 | amd64) cpu=x86_64 ;;
    aarch64 | arm64) cpu=aarch64 ;;
    *) return 1 ;;
  esac

  mkdir -p "$HOME/.local/bin"
  log "Installing $pkg into ~/.local/bin"

  case "$pkg" in
    eza)
      if [ "$cpu" = x86_64 ]; then
        install_gh_tar "https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-musl.tar.gz" eza
      else
        install_gh_tar "https://github.com/eza-community/eza/releases/latest/download/eza_aarch64-unknown-linux-gnu.tar.gz" eza
      fi
      ;;
    bat)
      tag=$(github_latest_tag sharkdp/bat) || return 1
      install_gh_tar "https://github.com/sharkdp/bat/releases/download/${tag}/bat-${tag}-${cpu}-unknown-linux-musl.tar.gz" bat
      ;;
    fd)
      tag=$(github_latest_tag sharkdp/fd) || return 1
      install_gh_tar "https://github.com/sharkdp/fd/releases/download/${tag}/fd-${tag}-${cpu}-unknown-linux-musl.tar.gz" fd
      ;;
    ripgrep)
      tag=$(github_latest_tag BurntSushi/ripgrep) || return 1
      ver=${tag#v}
      install_gh_tar "https://github.com/BurntSushi/ripgrep/releases/download/${tag}/ripgrep-${ver}-${cpu}-unknown-linux-musl.tar.gz" rg
      ;;
    fzf)
      tag=$(github_latest_tag junegunn/fzf) || return 1
      ver=${tag#v}
      farch=amd64
      [ "$cpu" = aarch64 ] && farch=arm64
      install_gh_tar "https://github.com/junegunn/fzf/releases/download/${tag}/fzf-${ver}-linux_${farch}.tar.gz" fzf
      ;;
    zoxide)
      curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
      ;;
    lazygit)
      tag=$(github_latest_tag jesseduffield/lazygit) || return 1
      ver=${tag#v}
      goarch=$cpu
      [ "$cpu" = aarch64 ] && goarch=arm64
      install_gh_tar "https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${ver}_linux_${goarch}.tar.gz" lazygit
      ;;
    *) return 1 ;;
  esac
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

# Vendor scripts and the ~/.local fallback drop binaries here; the verify
# pass in this same run needs to see them.
export PATH="$HOME/.local/bin:$PATH"

PM=$(detect_pm)
if [ -z "$PM" ]; then
  echo "No supported package manager found (brew, apt-get, dnf, pacman, zypper, apk)." >&2
  exit 1
fi
log "Using $PM on $(uname -s) $(uname -m)"

PM_WRITE=1
if ! pm_can_write "$PM"; then
  PM_WRITE=0
  warn "$PM cannot write (read-only filesystem). Missing tools install into ~/.local instead."
fi

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

if [ "$PM" = apt-get ] && [ "$PM_WRITE" = 1 ]; then
  log "Refreshing apt package lists"
  as_root apt-get update
fi

log "Installing packages"
for entry in $packages; do
  pkg=${entry%%:*}
  binaries=${entry#*:}
  if [ -n "$binaries" ]; then
    present=0
    # Word splitting on the comma list is deliberate: one tool, several names.
    for cmd in $(echo "$binaries" | tr ',' ' '); do
      if have "$cmd"; then
        present=1
        break
      fi
    done
    [ "$present" = 1 ] && continue
  elif find_plugin "$pkg" >/dev/null; then
    continue
  fi
  if [ "$PM_WRITE" = 1 ] && install_pkg "$pkg"; then
    continue
  fi
  if [ "$(uname -s)" != Darwin ] && install_user "$pkg"; then
    continue
  fi
  warn "$PM has no '$(pkg_name "$PM" "$pkg")'; install it yourself if you want it"
done

# Homebrew merged this into brew itself. Tapping the old repo is now a hard
# error ("this tap is now empty") and would abort the rest of this script.
if [ "$PM" != brew ] && [ "$PM_WRITE" = 1 ]; then
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
  if have ssh-agent && have ssh-add; then
    log "OpenSSH client already installed"
  elif [ "$PM_WRITE" = 1 ]; then
    log "Installing OpenSSH client (ssh-agent)"
    install_pkg openssh-client ||
      warn "$PM has no '$(pkg_name "$PM" openssh-client)'; install ssh-agent yourself if you want it"
  fi
fi

if have fnm; then
  log "fnm already installed"
elif [ "$PM" = brew ]; then
  log "Installing fnm"
  install_pkg fnm || warn "brew could not install fnm"
else
  log "Installing fnm into ~/.local/share/fnm"
  if ! have unzip && [ "$PM_WRITE" = 1 ]; then
    install_pkg unzip || warn "no unzip; the fnm installer needs it"
  fi
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
  if [ "$PM" = apk ] && [ "$PM_WRITE" = 1 ]; then
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
