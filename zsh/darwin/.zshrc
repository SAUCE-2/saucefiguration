# Homebrew. Keep this first: PATH, MANPATH and FPATH for everything below.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"     # Apple Silicon
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"        # Intel
fi

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""

# User-installed tools, including Oh My Posh.
export PATH="$HOME/.local/bin:$PATH"

# Prevent duplicate PATH and completion entries.
typeset -U path fpath

plugins=(
  aliases
  alias-finder
  brew
  command-not-found
  dotenv
  eza
  fnm
  fzf
  git
  git-auto-fetch
  git-commit
  gitfast
  macos
  node
  npm
  ssh
  ssh-agent
  tailscale
  zoxide
  zsh-interactive-cd
)

# After each command, print any shorter alias you could have used instead.
zstyle ':omz:plugins:alias-finder' autoload yes
zstyle ':omz:plugins:alias-finder' cheaper yes

# Start one ssh-agent for the session and load id_ed25519 so git only
# asks for the passphrase once. Keychain holds the passphrase after the
# first unlock.
# These zstyles must be set before oh-my-zsh.sh sources the plugin.
zstyle :omz:plugins:ssh-agent identities id_ed25519
zstyle :omz:plugins:ssh-agent quiet yes
zstyle :omz:plugins:ssh-agent ssh-add-args --apple-use-keychain --apple-load-keychain

source "$ZSH/oh-my-zsh.sh"

# Persistent shell history.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_FIND_NO_DUPS

# Node version management.
if (( $+commands[fnm] )); then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi

# Vite+ (vp): toolchain plus node/npm/pnpm shims. After fnm so the shims win.
[ -f "$HOME/.config/vite-plus/env" ] && . "$HOME/.config/vite-plus/env"

# Better directory jumping: `z partial-directory-name`.
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

# Fuzzy history search with Ctrl+R and file search with Ctrl+T.
if (( $+commands[fzf] )); then
  source <(fzf --zsh)
fi

# Preferred interactive commands. Each one is guarded because a replacement
# that is not installed would otherwise shadow the real cat, find or grep.
if (( $+commands[eza] )); then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -lah --icons --group-directories-first'
  alias la='eza -a --icons --group-directories-first'
fi

(( $+commands[bat] )) && alias cat='bat'
(( $+commands[fd] )) && alias find='fd'
(( $+commands[rg] )) && alias grep='rg'
(( $+commands[lazygit] )) && alias lg='lazygit'

# Generated for envman. Do not edit.
[ -s "$HOME/.config/envman/load.sh" ] \
  && source "$HOME/.config/envman/load.sh"

# Bootdev submit.
alias bdev='yes | bootdev run -s'

# Oh My Posh prompt.
# It only loads after its binary and config file exist.
export POSH_THEME="$HOME/.config/ohmyposh/theme.omp.json"

if (( $+commands[oh-my-posh] )) && [ -f "$POSH_THEME" ]; then
  eval "$(
    oh-my-posh init zsh \
      --config "$POSH_THEME"
  )"
fi

# Inline grey history suggestions. Accept with Right Arrow.
if [ -f "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
  source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# Keep this last among plugins: syntax highlighting must load after other shell setup.
if [ -f "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# Same idea as omz's update prompt: if install.sh recorded this clone and it
# has moved, list the commits (configs you may want to copy again) and offer
# to re-run the installer. No-op until that stamp exists.
if [[ -o interactive && -t 1 && -z ${SAUCE_DISABLE_UPDATE_CHECK:-} ]]; then
  _sauce_state="${XDG_STATE_HOME:-$HOME/.local/state}/saucefiguration"
  if [[ -f $_sauce_state/repo ]]; then
    _sauce_root=$(tr -d '\r\n' <"$_sauce_state/repo")
    [[ -f $_sauce_root/zsh/check-update.sh ]] && bash "$_sauce_root/zsh/check-update.sh"
  fi
  unset _sauce_state _sauce_root
fi
