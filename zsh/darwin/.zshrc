# Homebrew. Keep this first: PATH, MANPATH and FPATH for everything below.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"     # Apple Silicon
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"        # Intel
fi

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""

# User-installed tools, including Oh My Posh, Go from go.dev (~/.local/go)
# and `go install` binaries.
export PATH="$HOME/.local/bin:$HOME/.local/go/bin:$HOME/go/bin:$PATH"

# Prevent duplicate PATH and completion entries.
typeset -U path fpath

plugins=(
  aliases
  alias-finder
  brew
  command-not-found
  eza
  fzf
  git
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

# omz's gh plugin builds its completions by running gh, so it needs gh.
(( $+commands[gh] )) && plugins+=(gh)

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

# Node version management (nvm, installed by install.sh). Sourcing nvm.sh
# costs a few hundred ms, so put the default Node's bin on PATH by hand and
# load nvm on its first call. Before oh-my-zsh.sh so the npm plugin sees npm.
# Follows alias chains like default -> lts/* -> lts/krypton -> v24.22.1 and
# takes the newest installed match, as nvm does; no subprocesses.
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  () {
    local v dirs n
    [ -r "$NVM_DIR/alias/default" ] && v=$(<"$NVM_DIR/alias/default")
    for n in 1 2 3 4 5; do
      [[ -n $v && -f $NVM_DIR/alias/$v ]] || break
      v=$(<"$NVM_DIR/alias/$v")
    done
    v=${v#v}
    if [[ $v == (node|stable) ]]; then
      dirs=("$NVM_DIR"/versions/node/v*(N/nOn))
    elif [[ $v == <->(|.<->)(|.<->) ]]; then
      dirs=("$NVM_DIR"/versions/node/v$v(|.*)(N/nOn))
    fi
    (( $#dirs )) && path=("$dirs[1]/bin" $path)
  }

  # The inner anonymous function keeps nvm's arguments out of nvm.sh's $@.
  nvm() {
    unset -f nvm
    () { . "$NVM_DIR/nvm.sh" }
    [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
    nvm "$@"
  }
fi

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
# so micro and GNU nano receive it as Save. Apple's /usr/bin/nano is Pico and ignores it.
# Terminal only: under IntelliJ's `zsh -l -i -c ...` stty has none and errors.
if [[ -t 0 ]]; then
  stty -ixon
fi

# Persistent shell history.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_FIND_NO_DUPS

# Cloudflare CLI completion, written by install.sh. Tab still runs `cf`.
[ -f "$HOME/.config/cf/complete.zsh" ] && . "$HOME/.config/cf/complete.zsh"

# Better directory jumping: `cd partial-directory-name`, `cdi` to pick with fzf.
# omz's zoxide plugin still sets up `z` and `zi`.
if (( $+commands[zoxide] )); then
  eval "$(zoxide init --cmd cd zsh)"
fi

# Editor for git commit, crontab -e and the rest. git falls through to
# $VISUAL/$EDITOR because .gitconfig sets no core.editor. micro is optional.
if (( $+commands[micro] )); then
  export EDITOR=micro
else
  export EDITOR=nano
fi
export VISUAL=$EDITOR

# Per-directory env: loads a project's .envrc (or .env, see
# direnv/direnv.toml) after `direnv allow`, unloads it on the way out.
# Replaces omz's dotenv plugin. A plain hook rather than omz's direnv plugin,
# matching zoxide above. Its default "direnv: loading" / "export +VAR" lines
# stay on: they show which variables a cd just changed.
if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
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

# Syntax-highlighted git diffs. Set here rather than as core.pager in
# .gitconfig, so git on a machine without delta keeps using less.
(( $+commands[delta] )) && export GIT_PAGER=delta

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
