# Hand-written part of ~/.zshrc. zsh/default.nix places it after Oh My Zsh
# and before the fzf-tab / autosuggestions / syntax-highlighting plugins.

# git signs commits with ssh-keygen, which never adds the key to the agent, so
# AddKeysToAgent doesn't help there: every commit would ask for the passphrase.
# Load the key on the first git command in a terminal instead. The -t check
# keeps IntelliJ's `zsh -l -i -c ...` from hanging on the prompt. On macOS,
# Keychain holds the passphrase after the first unlock.
git() {
  if [[ -t 0 ]]; then
    ssh-add -l >/dev/null 2>&1
    if (( $? == 1 )); then
      if [[ $OSTYPE == darwin* ]]; then
        ssh-add --apple-use-keychain -q
      else
        ssh-add -q
      fi
    fi
  fi
  command git "$@"
}

# macOS uses Ctrl+S as XOFF, which freezes the terminal. Turn that off so
# micro receives it as Save. Terminal only: under IntelliJ's
# `zsh -l -i -c ...` stty has none and errors.
if [[ $OSTYPE == darwin* && -t 0 ]]; then
  stty -ixon
fi

# WSL: `open` is macOS muscle memory for wsl-open (BROWSER is set in
# home.nix), aliased only where no real `open` exists.
if (( $+commands[wsl-open] )) && ! (( $+commands[open] )); then
  alias open='wsl-open'
fi

# Tab completion through fzf (fzf-tab, sourced right after this file).
# omz sets `menu select` on this exact pattern; a shorter one would lose to it.
zstyle ':completion:*:*:*:*:*' menu no
# fzf-tab shows these as group headers; switch groups with < and >.
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':fzf-tab:*' switch-group '<' '>'
# Keep git checkout's branch order (recent first) instead of alphabetical.
zstyle ':completion:*:git-checkout:*' sort false
# Preview the directory under the cursor when completing cd.
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --icons --color=always $realpath'

# Same idea as omz's update prompt: if install.sh recorded this clone and it
# has moved, the first prompt asks Y/n whether to update. Re-running the
# installer applies the new commits with home-manager. No-op until that stamp
# exists. Skipped under `zsh -i -c` (IDE environment readers): nobody can answer.
if [[ -o interactive && -t 1 && -z ${ZSH_EXECUTION_STRING:-} && -z ${SAUCE_DISABLE_UPDATE_CHECK:-} ]]; then
  _sauce_state="${XDG_STATE_HOME:-$HOME/.local/state}/saucefiguration"
  if [[ -f $_sauce_state/repo ]]; then
    _sauce_root=$(tr -d '\r\n' <"$_sauce_state/repo")
    [[ -f $_sauce_root/zsh/check-update.sh ]] && bash "$_sauce_root/zsh/check-update.sh"
  fi
  unset _sauce_state _sauce_root
fi
