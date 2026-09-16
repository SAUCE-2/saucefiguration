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
# asks for the passphrase once.
# These zstyles must be set before oh-my-zsh.sh sources the plugin.
zstyle :omz:plugins:ssh-agent identities id_ed25519
zstyle :omz:plugins:ssh-agent quiet yes

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

# Fast Node version manager.
export PATH="$HOME/.local/share/fnm:$PATH"

# Node version management.
if (( $+commands[fnm] )); then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi

# Better directory jumping: `z partial-directory-name`.
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

# Fuzzy history search with Ctrl+R and file search with Ctrl+T.
# `fzf --zsh` needs fzf 0.48+; older distro packages ship the scripts on disk.
if (( $+commands[fzf] )); then
  if fzf_init="$(fzf --zsh 2>/dev/null)"; then
    eval "$fzf_init"
  else
    for fzf_file in /usr/share/doc/fzf/examples/{key-bindings,completion}.zsh; do
      [ -f "$fzf_file" ] && source "$fzf_file"
    done
    unset fzf_file
  fi
  unset fzf_init
fi

# Preferred interactive commands. Each one is guarded because a replacement
# that is not installed would otherwise shadow the real cat, find or grep.
if (( $+commands[eza] )); then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -lah --icons --group-directories-first'
  alias la='eza -a --icons --group-directories-first'
fi

# Debian and Ubuntu rename these two; other distros keep the upstream names.
if (( $+commands[batcat] )); then
  alias bat='batcat'
  alias cat='batcat'
elif (( $+commands[bat] )); then
  alias cat='bat'
fi

if (( $+commands[fdfind] )); then
  alias fd='fdfind'
  alias find='fdfind'
elif (( $+commands[fd] )); then
  alias find='fd'
fi

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

# Debian and Fedora put these under /usr/share, Arch and Alpine under
# /usr/share/zsh/plugins, so try each location and source the first hit.
_source_zsh_plugin() {
  local dir
  for dir in /usr/share /usr/share/zsh/plugins /usr/local/share; do
    if [ -f "$dir/$1/$1.zsh" ]; then
      source "$dir/$1/$1.zsh"
      return
    fi
  done
}

# Inline grey history suggestions. Accept with Right Arrow.
_source_zsh_plugin zsh-autosuggestions

# Keep this last: syntax highlighting must load after all other shell setup.
_source_zsh_plugin zsh-syntax-highlighting

unset -f _source_zsh_plugin
