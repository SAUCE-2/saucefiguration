# tmux, written to ~/.config/tmux/tmux.conf. A leftover ~/.tmux.conf would
# win over it, so zsh/install.sh moves the one the old installer copied out
# of the way. Plugins come from Nix, so tpm is gone: no prefix + I / U.
{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    historyLimit = 100000;
    # Short wait after Esc, so vim and the zsh line editor don't lag.
    escapeTime = 10;
    # Count windows and panes from 1, to match the number row.
    baseIndex = 1;
    # Keep tmux's own socket dir (/tmp), as before. home-manager would move
    # it to $XDG_RUNTIME_DIR, which WSL does not always have.
    secureSocket = false;

    # A plugin's options must be set before it loads, so they go in its
    # extraConfig. continuum stays last: it hooks the status line.
    plugins = [
      {
        # Sessions survive a reboot. prefix + Ctrl-s saves, prefix + Ctrl-r restores.
        plugin = pkgs.tmuxPlugins.resurrect;
        extraConfig = "set -g @resurrect-capture-pane-contents 'on'";
      }
      {
        # Saves every 15 minutes and restores the last save when tmux starts.
        plugin = pkgs.tmuxPlugins.continuum;
        extraConfig = "set -g @continuum-restore 'on'";
      }
    ];

    extraConfig = builtins.readFile ./tmux.conf;
  };
}
