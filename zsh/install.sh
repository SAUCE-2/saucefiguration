#!/usr/bin/env bash
# Installs everything the .zshrc files in this directory expect to find.
# Run this after zsh itself is installed. Safe to re-run. Copies this
# clone's configs into $HOME and warns when it replaces a file that
# already exists, keeping the old one as <file>.bak.<time>. Stamps this
# clone's HEAD so the next shell can notice new commits and offer to
# update (see check-update.sh).
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
  tmux:tmux
  zsh-autosuggestions:
  zsh-syntax-highlighting:
"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mskip:\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# For a step that errored (no sudo, broken apt repo, offline). Under set -e it
# would end the run before the configs are copied and the rev stamped, so warn,
# keep going, and list it at the end.
failed=
fail() {
  warn "$1 failed${2:+; $2}"
  failed="${failed:+$failed, }$1"
}

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
    apt-get:go) echo golang-go ;;
    dnf:go) echo golang ;;
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

# Boot.dev CLI's go.mod wants Go 1.24. Distro Go often lags (Debian 12 ships
# 1.19), and Debian and Fedora pin GOTOOLCHAIN=local, so an old go will not
# fetch a newer toolchain by itself.
go_min_minor=24

# True when Go is at least 1.$go_min_minor. $1 is a version string such as
# go1.24.2 (for tests); without it, ask the go on PATH.
go_new_enough() {
  local v=${1:-} major minor
  if [ -z "$v" ]; then
    have go || return 1
    v=$(go env GOVERSION 2>/dev/null) || return 1
  fi
  v=${v#go}
  major=${v%%.*}
  minor=${v#*.}
  minor=${minor%%[!0-9]*}
  case "$major:$minor" in
    *[!0-9:]* | :* | *:) return 1 ;;
  esac
  [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge "$go_min_minor" ]; }
}

# Latest Go from go.dev into ~/.local/go, replacing any older copy there.
# Linux only; Homebrew's go is current.
install_go_user() {
  local arch ver tmp
  case $(uname -m) in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) return 1 ;;
  esac
  [ "${DRY_RUN:-0}" = 1 ] && {
    printf '   would install Go (linux-%s) into ~/.local/go\n' "$arch"
    return 0
  }
  ver=$(curl -fsSL 'https://go.dev/VERSION?m=text') || return 1
  ver=${ver%%$'\n'*}
  case "$ver" in
    go[0-9]*) ;;
    *) return 1 ;;
  esac
  tmp=$(mktemp -d) || return 1
  if ! curl -fsSL "https://go.dev/dl/${ver}.linux-${arch}.tar.gz" | tar -xz -C "$tmp"; then
    rm -rf "$tmp"
    return 1
  fi
  mkdir -p "$HOME/.local"
  rm -rf "$HOME/.local/go"
  mv "$tmp/go" "$HOME/.local/go"
  rm -rf "$tmp"
}

# Copy $1 onto $2. Identical dest is a no-op. Anything else already there
# is kept as $2.bak.<time>, then overwritten after a warning. Local edits,
# such as git config --global writes, would be lost otherwise. $3 is an
# optional chmod mode.
copy_file() {
  local src=$1 dest=$2 mode=${3:-} backup=
  if [ ! -f "$src" ]; then
    warn "missing $src"
    return 1
  fi

  if [ -L "$dest" ] || [ -f "$dest" ]; then
    if cmp -s "$src" "$dest"; then
      return 0
    fi
    # A dangling symlink has nothing to keep.
    [ -f "$dest" ] && backup="$dest.bak.$(date +%Y%m%d%H%M%S)"
    printf '\033[1;33mwarn:\033[0m replacing %s%s\n' "$dest" "${backup:+ (backup: $backup)}" >&2
  elif [ -e "$dest" ]; then
    warn "not a file: $dest"
    return 1
  fi

  if [ "${DRY_RUN:-0}" = 1 ]; then
    printf '   would copy %s -> %s\n' "$src" "$dest"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"
  # -p keeps the mode, so a backup in ~/.ssh is no more open than the original.
  if [ -n "$backup" ]; then
    cp -p "$dest" "$backup" || return 1
  fi
  # Write a temp file and rename it over dest. Rewriting dest in place would
  # corrupt a shell still reading it: the update check runs this from inside
  # ~/.zshrc. Renaming also replaces a dest symlink instead of writing through.
  local tmp="$dest.tmp.$$"
  cp "$src" "$tmp" || return 1
  if [ -n "$mode" ]; then
    chmod "$mode" "$tmp"
  fi
  mv -f "$tmp" "$dest"
}

# authorized_keys is merged, not replaced: the repo's lines, then any key the
# machine already trusts that the repo does not list. Replacing it would lock
# you out of a server whose key lives only there. Lines match on the base64
# key blob (it always starts "AAAA"), so the repo's line for a key wins over
# an old one with other options or comment.
merge_authorized_keys() {
  local src=$1 dest=$2 old=/dev/null merged rc=0
  [ -f "$dest" ] && old=$dest
  merged=$(mktemp "${TMPDIR:-/tmp}/authorized_keys.XXXXXX") || return 1
  awk '
    {
      sub(/\r$/, "")
      id = $0
      for (i = 1; i <= NF; i++) if ($i ~ "^AAAA[0-9A-Za-z+/]+=*$") { id = $i; break }
    }
    FILENAME == ARGV[1] { repo[id] = 1; print; next }
    NF && !(id in repo)
  ' "$src" "$old" >"$merged" && copy_file "$merged" "$dest" 600 || rc=$?
  rm -f "$merged"
  return "$rc"
}

# Repo configs -> the paths the shell, git and ssh already look at.
# SAUCE_ROOT is for tests; live runs use this script's path.
install_dotfiles() {
  local root platform
  root=${SAUCE_ROOT:-$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)} || return 1
  case "$(uname -s)" in
    Darwin) platform=darwin ;;
    *) platform=linux ;;
  esac

  log "Copying config files"
  copy_file "$root/zsh/$platform/.zshrc" "$HOME/.zshrc"
  copy_file "$root/tmux/.tmux.conf" "$HOME/.tmux.conf"

  # These dirs map 1:1 onto a dest dir. Copy every file so a new one cannot
  # sit in the clone unused (.[!.]* covers .gitconfig / .gitignore_global).
  for src in "$root/git"/* "$root/git"/.[!.]*; do
    [ -f "$src" ] || continue
    copy_file "$src" "$HOME/$(basename "$src")"
  done
  for src in "$root/ohmyposh"/* "$root/ohmyposh"/.[!.]*; do
    [ -f "$src" ] || continue
    copy_file "$src" "$HOME/.config/ohmyposh/$(basename "$src")"
  done

  if [ "${DRY_RUN:-0}" != 1 ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
  fi
  for src in "$root/ssh"/* "$root/ssh"/.[!.]*; do
    [ -f "$src" ] || continue
    name=$(basename "$src")
    case "$name" in
      config) copy_file "$src" "$HOME/.ssh/$name" 600 ;;
      authorized_keys) merge_authorized_keys "$src" "$HOME/.ssh/$name" ;;
      *) copy_file "$src" "$HOME/.ssh/$name" ;;
    esac
  done
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

# webinstall.dev package whose binary name matches the package name.
# Lands in ~/.local/bin, which both .zshrc files already put on PATH.
# https://webinstall.dev/dotenv
# https://webinstall.dev/dotenv-linter
#
# webi appends `source ~/.config/envman/load.sh` to shell rc files it finds.
# This repo dropped envman; put those files back. ponytail: a symlink rc is
# restored as a symlink, so an append that followed the link stays in the
# target. Upgrade: snapshot the target's bytes too.
webi_rcs() {
  printf '%s\n' \
    "$HOME/.profile" \
    "$HOME/.bashrc" \
    "$HOME/.zshrc" \
    "$HOME/.config/fish/config.fish"
}

webi_rc_snapshot() {
  local rc n=0
  _webi_snap=$(mktemp -d)
  while IFS= read -r rc; do
    n=$((n + 1))
    if [ -e "$rc" ] || [ -L "$rc" ]; then
      cp -a "$rc" "$_webi_snap/$n.file"
    else
      : >"$_webi_snap/$n.absent"
    fi
  done < <(webi_rcs)
}

webi_rc_restore() {
  local rc n=0
  [ -n "${_webi_snap:-}" ] && [ -d "$_webi_snap" ] || return 0
  while IFS= read -r rc; do
    n=$((n + 1))
    if [ -f "$_webi_snap/$n.absent" ]; then
      rm -f "$rc"
    elif [ -e "$_webi_snap/$n.file" ] || [ -L "$_webi_snap/$n.file" ]; then
      rm -f "$rc"
      cp -a "$_webi_snap/$n.file" "$rc"
    fi
  done < <(webi_rcs)
  rm -rf "$_webi_snap"
  unset _webi_snap
}

install_webi() {
  local pkg=$1
  if have "$pkg"; then
    log "$pkg already installed"
    return 0
  fi
  log "Installing $pkg"
  if [ "${DRY_RUN:-0}" = 1 ]; then
    run bash -c "curl -fsSL https://webi.sh/${pkg}@stable | sh"
    return 0
  fi
  webi_rc_snapshot
  bash -c "curl -fsSL https://webi.sh/${pkg}@stable | sh" ||
    warn "could not install $pkg"
  webi_rc_restore
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
  run bash -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' ||
    fail "Homebrew install"
  for prefix in /opt/homebrew /usr/local; do
    if [ -x "$prefix/bin/brew" ]; then
      eval "$("$prefix/bin/brew" shellenv)"
      break
    fi
  done
fi

if [ "$PM" = apt-get ] && [ "$PM_WRITE" = 1 ]; then
  log "Refreshing apt package lists"
  as_root apt-get update || fail "apt-get update" "installing from the cached package lists"
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
  # KEEP_ZSHRC stops omz writing a default .zshrc; we copy this repo's one
  # later. CHSH leaves the login shell alone, RUNZSH keeps this script going.
  run bash -c 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' ||
    fail "Oh My Zsh install"
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

# Node.js the way nodejs.org suggests: nvm, then Node, then pnpm via Corepack.
# Same on Darwin; nvm does not support its Homebrew formula.
node_major=26
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  log "nvm already installed"
else
  log "Installing nvm into ~/.nvm"
  # PROFILE=/dev/null: the .zshrc in this repo already sources nvm.sh.
  run bash -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | PROFILE=/dev/null bash' ||
    fail "nvm install"
fi

# nvm is a shell function, so load it here. nvm.sh trips over `set -u`.
if [ -s "$NVM_DIR/nvm.sh" ]; then
  set +u
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  log "Installing Node.js $node_major"
  run nvm install "$node_major" || warn "nvm could not install Node.js $node_major"
  run nvm alias default "$node_major" || warn "nvm could not make Node.js $node_major its default"
  set -u
elif [ "${DRY_RUN:-0}" = 1 ]; then
  log "Installing Node.js $node_major"
  printf '   would run: nvm install %s\n' "$node_major"
else
  warn "no nvm; install Node.js yourself"
fi

if have pnpm; then
  log "pnpm already installed"
elif have npm || [ "${DRY_RUN:-0}" = 1 ]; then
  log "Installing pnpm with Corepack"
  run npm install --global corepack || warn "npm could not install corepack"
  run corepack enable pnpm || warn "corepack could not enable pnpm"
else
  warn "no npm; pnpm needs Node.js (npm install --global corepack && corepack enable pnpm)"
fi

if have oh-my-posh; then
  log "Oh My Posh already installed"
elif [ "$PM" = brew ]; then
  log "Installing Oh My Posh"
  run brew install oh-my-posh || run brew install jandedobbeleer/oh-my-posh/oh-my-posh ||
    fail "Oh My Posh install"
else
  log "Installing Oh My Posh into ~/.local/bin"
  run bash -c 'curl -fsSL https://ohmyposh.dev/install.sh | bash -s' ||
    fail "Oh My Posh install"
fi

# Cloudflare CLI (`cf`), now in beta. Not in distro repos; the npm package
# needs Node.js 22.18+ (the Node above is newer).
# https://developers.cloudflare.com/changelog/post/2026-09-28-cloudflare-cli-beta/
# npm's global bin is not always on PATH yet.
if have npm; then
  npm_prefix=$(npm prefix -g 2>/dev/null) || npm_prefix=
  if [ -n "${npm_prefix}" ] && [ -d "${npm_prefix}/bin" ]; then
    export PATH="${npm_prefix}/bin:${PATH}"
  fi
fi

if have cf; then
  log "Cloudflare CLI already installed"
elif have npm; then
  log "Installing Cloudflare CLI"
  run npm install --global cf || warn "npm could not install cf (needs Node 22.18+)"
else
  warn "no npm; Cloudflare CLI needs Node 22.18+ (npm install --global cf)"
fi

# Completion bootstrap only. Tab still shells out to `cf` later. The .zshrc
# sources this file; this script does not edit dotfiles.
if have cf; then
  if [ "${DRY_RUN:-0}" = 1 ]; then
    printf '   would write cf completion to %s\n' "$HOME/.config/cf/complete.zsh"
  else
    log "Writing Cloudflare CLI zsh completion"
    mkdir -p "$HOME/.config/cf"
    if ! cf complete zsh >"$HOME/.config/cf/complete.zsh"; then
      rm -f "$HOME/.config/cf/complete.zsh"
      warn "could not write cf zsh completion"
    fi
  fi
fi

# Boot.dev CLI. Lands in ~/go/bin (on PATH above).
# https://github.com/bootdotdev/bootdev
# ~/.local/go/bin goes first so the go.dev Go wins over an old distro one.
export PATH="$HOME/.local/go/bin:$HOME/go/bin:$PATH"
if have bootdev; then
  log "Boot.dev CLI already installed"
else
  if ! go_new_enough; then
    if [ "$PM" = brew ]; then
      log "Installing Go (needed for Boot.dev CLI)"
      install_pkg go || warn "brew could not install go"
    elif [ "$PM_WRITE" = 1 ] && ! have go; then
      log "Installing Go (needed for Boot.dev CLI)"
      install_pkg go || warn "$PM has no '$(pkg_name "$PM" go)'"
    fi
    # Distro Go too old, missing, or the package db is read-only.
    if [ "$PM" != brew ] && ! go_new_enough; then
      log "Installing Go 1.$go_min_minor+ from go.dev into ~/.local/go"
      install_go_user || warn "could not install Go; install Go 1.$go_min_minor+ yourself for bootdev"
    fi
  fi
  if go_new_enough || [ "${DRY_RUN:-0}" = 1 ]; then
    log "Installing Boot.dev CLI"
    run go install github.com/bootdotdev/bootdev@latest ||
      warn "go install bootdev failed"
  fi
fi

# Tailscale. Official Linux installer picks the right package repo; Homebrew
# prefers the Mac app cask (CLI included) and falls back to the formula.
# Does not run `tailscale up` — auth stays interactive.
if have tailscale; then
  log "Tailscale already installed"
elif [ "$PM" = brew ]; then
  log "Installing Tailscale"
  run brew install --cask tailscale ||
    run brew install tailscale ||
    warn "brew could not install Tailscale"
elif [ "$PM_WRITE" = 1 ]; then
  log "Installing Tailscale"
  run bash -c 'curl -fsSL https://tailscale.com/install.sh | sh' ||
    warn "Tailscale install script failed"
else
  warn "package db is read-only; install Tailscale yourself if you want it"
fi

# dotenv runs a command with a .env loaded. dotenv-linter checks .env files.
# https://webinstall.dev/dotenv
# https://webinstall.dev/dotenv-linter
for pkg in dotenv dotenv-linter; do
  install_webi "$pkg"
done

# Apple's /usr/bin/nano is Pico: save is Ctrl+O, and it cannot be rebound.
# GNU nano (Homebrew) saves with Ctrl+S once XOFF is off. `command -v nano`
# hits Pico, so that check cannot decide this.
if [ "$PM" = brew ] && [ "$PM_WRITE" = 1 ]; then
  if [ -x /opt/homebrew/bin/nano ] || [ -x /usr/local/bin/nano ]; then
    log "GNU nano already installed"
  else
    log "Installing GNU nano"
    install_pkg nano || warn "brew could not install nano; Ctrl+S save needs it"
  fi
fi

log "Verifying what the shell config will find"
missing=0
# zsh is a prerequisite rather than a package here. Vendor CLIs above;
# ssh-agent ships with OpenSSH.
for tool in zsh nvm node pnpm oh-my-posh cf go bootdev tailscale dotenv dotenv-linter ssh-agent ssh-add; do
  check "$tool" "$tool" || missing=$((missing + 1))
done

for entry in $packages; do
  binaries=${entry#*:}
  # Entries with no binary are plugin files, checked by the probe below.
  [ -n "$binaries" ] || continue
  # Word splitting on the comma list is deliberate: one tool, several names.
  # shellcheck disable=SC2046
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

install_dotfiles
# Stamp even when a step failed: the configs are in, and an unstamped rev
# would have every new shell offer the same update again.
record_install_rev
if [ -n "$failed" ]; then
  printf '\033[1;31mfailed:\033[0m %s. Configs are copied; re-run %s to retry.\n' "$failed" "$0" >&2
  exit 1
fi
log "Done."
