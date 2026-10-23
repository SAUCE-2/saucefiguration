# zsh with Oh My Zsh. Every tool below comes from Nix, so unlike the old
# hand-copied .zshrc nothing needs a "(( $+commands[...] ))" guard.
# home-manager assembles ~/.zshrc from initContent blocks sorted by
# lib.mkOrder: 500s before compinit, 800 is oh-my-zsh.sh (which runs
# compinit), 1000 is the default, then aliases (1100) and zoxide (2000).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
in
{
  programs.zsh = {
    enable = true;

    # Persistent shell history.
    history = {
      path = "$HOME/.zsh_history";
      size = 100000;
      save = 100000;
      append = true;
      share = true;
      ignoreDups = true;
      expireDuplicatesFirst = true;
      findNoDups = true;
      # home-manager defaults this on; the old .zshrc never set it.
      ignoreSpace = false;
    };

    oh-my-zsh = {
      enable = true;
      plugins = [
        "aliases"
        "alias-finder"
        "eza"
        "fzf"
        "gh"
        "git"
        "git-commit"
        "gitfast"
        "node"
        "npm"
        "ssh"
        "ssh-agent"
        "tailscale"
        "tmux"
        "zoxide"
        "zsh-interactive-cd"
      ]
      ++ lib.optionals isDarwin [
        "brew"
        "macos"
      ];
      # Plugin settings, which must be set before oh-my-zsh.sh sources them.
      extraConfig = ''
        # After each command, print any shorter alias you could have used instead.
        zstyle ':omz:plugins:alias-finder' autoload yes
        zstyle ':omz:plugins:alias-finder' cheaper yes

        # Start one ssh-agent for the session. Lazy: don't ssh-add at shell start,
        # because tools like IntelliJ run `zsh -l -i -c ...` with no terminal and the
        # passphrase prompt hangs them. AddKeysToAgent in ~/.ssh/config loads the key
        # on first use by ssh (git push, pull); on macOS UseKeychain then keeps the
        # passphrase. Signing is handled by git() in init.zsh.
        zstyle :omz:plugins:ssh-agent lazy yes
        zstyle :omz:plugins:ssh-agent quiet yes
      '';
    };

    shellAliases = {
      ls = "eza --icons --group-directories-first";
      ll = "eza -lah --icons --group-directories-first";
      la = "eza -a --icons --group-directories-first";
      cat = "bat";
      find = "fd";
      grep = "rg";
      lg = "lazygit";
      # Boot.dev submit.
      bdev = "yes | bootdev run -s";
    };

    initContent = lib.mkMerge [
      # PATH, before anything runs a command. Homebrew is optional now (GUI
      # apps); its shellenv prepends its bin, so the Nix profile goes back in
      # front of it afterwards, or an old brew eza would shadow Nix's.
      # ~/.local/bin: `npm install --global` and other user installs.
      # ~/go/bin: `go install`.
      (lib.mkOrder 505 ''
        ${lib.optionalString isDarwin ''
          if [ -x /opt/homebrew/bin/brew ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"     # Apple Silicon
          elif [ -x /usr/local/bin/brew ]; then
            eval "$(/usr/local/bin/brew shellenv)"        # Intel
          fi
        ''}
        path=("${config.home.profileDirectory}/bin" "$HOME/.local/bin" "$HOME/go/bin" $path)
      '')

      (lib.mkOrder 1000 (builtins.readFile ./init.zsh))

      # Widget wrappers, in the order their READMEs ask for: fzf-tab after
      # compinit, then autosuggestions, then syntax highlighting last.
      # Sourced here rather than through programs.zsh.autosuggestion, which
      # home-manager loads before oh-my-zsh and so before fzf-tab.
      (lib.mkOrder 1200 ''
        source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh
        # Inline grey history suggestions. Accept with Right Arrow.
        source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
        source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
      '')
    ];
  };

  # Fuzzy history search with Ctrl+R and file search with Ctrl+T.
  programs.fzf.enable = true;

  # Better directory jumping: `cd partial-directory-name`, `cdi` to pick with
  # fzf. omz's zoxide plugin still sets up `z` and `zi`.
  programs.zoxide = {
    enable = true;
    options = [
      "--cmd"
      "cd"
    ];
  };

  # Syntax-highlighted cat. Aliased above; this module also caches its themes.
  programs.bat.enable = true;
}
