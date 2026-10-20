# Homebrew. Keep this first: PATH, MANPATH and FPATH for everything below.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"     # Apple Silicon
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"        # Intel
fi

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""

# User-installed tools, including Oh My Posh and `go install` binaries.
export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"

# Prevent duplicate PATH and completion entries.
typeset -U path fpath

plugins=(
  aliases
  alias-finder
  brew
  command-not-found
  dotenv
  eza
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

# omz's tmux plugin prints an error at every start if tmux is missing.
(( $+commands[tmux] )) && plugins+=(tmux)

# After each command, print any shorter alias you could have used instead.
zstyle ':omz:plugins:alias-finder' autoload yes
zstyle ':omz:plugins:alias-finder' cheaper yes

# Start one ssh-agent for the session. Lazy: don't ssh-add at shell start,
# because tools like IntelliJ run `zsh -l -i -c ...` with no terminal and the
# passphrase prompt hangs them. AddKeysToAgent and UseKeychain in
# ~/.ssh/config load the key on first use, with Keychain holding the
# passphrase after the first unlock.
# These zstyles must be set before oh-my-zsh.sh sources the plugin.
zstyle :omz:plugins:ssh-agent lazy yes
zstyle :omz:plugins:ssh-agent quiet yes

source "$ZSH/oh-my-zsh.sh"

# git signs commits with ssh-keygen, which never adds the key to the agent, so
# AddKeysToAgent doesn't help there: every commit would ask for the passphrase.
# Load the key on the first git command in a terminal instead. The -t check
# keeps IntelliJ's `zsh -l -i -c ...` from hanging on the prompt.
git() {
  if [[ -t 0 ]]; then
    ssh-add -l >/dev/null 2>&1
    (( $? == 1 )) && ssh-add --apple-use-keychain -q
  fi
  command git "$@"
}

# macOS uses Ctrl+S as XOFF, which freezes the terminal. Turn that off
# so GNU nano receives it as Save. Apple's /usr/bin/nano is Pico and ignores it.
stty -ixon

# Persistent shell history.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_FIND_NO_DUPS

# Node version management (nvm, installed by install.sh).
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

# Cloudflare CLI completion, written by install.sh. Tab still runs `cf`.
[ -f "$HOME/.config/cf/complete.zsh" ] && . "$HOME/.config/cf/complete.zsh"

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
# has moved, the first prompt asks Y/n whether to update. Re-running the
# installer copies the updated configs. No-op until that stamp exists.
# Skipped under `zsh -i -c` (IDE environment readers): nobody can answer.
if [[ -o interactive && -t 1 && -z ${ZSH_EXECUTION_STRING:-} && -z ${SAUCE_DISABLE_UPDATE_CHECK:-} ]]; then
  _sauce_state="${XDG_STATE_HOME:-$HOME/.local/state}/saucefiguration"
  if [[ -f $_sauce_state/repo ]]; then
    _sauce_root=$(tr -d '\r\n' <"$_sauce_state/repo")
    [[ -f $_sauce_root/zsh/check-update.sh ]] && bash "$_sauce_root/zsh/check-update.sh"
  fi
  unset _sauce_state _sauce_root
fi
