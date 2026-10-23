# Everything one machine gets. flake.nix builds this once per platform;
# `wsl` is true for the <system>-wsl profiles.
{
  lib,
  pkgs,
  wsl,
  ...
}:
let
  # zsh/install.sh runs home-manager with --impure, so these are the real
  # user. Pure evaluation (nix flake check) gets the placeholders.
  user = builtins.getEnv "USER";
  home = builtins.getEnv "HOME";
in
{
  imports = [
    ./zsh
    ./git
    ./ssh
    ./ohmyposh
    ./direnv
    ./tmux
  ];

  home.username = if user != "" then user else "sauce";
  home.homeDirectory =
    if home != "" then
      home
    else if pkgs.stdenv.hostPlatform.isDarwin then
      "/Users/sauce"
    else
      "/home/sauce";

  # The home-manager release whose defaults this config was written
  # against. Don't bump it with the flake inputs; read the release notes first.
  home.stateVersion = "26.05";

  # The CLI tools the shell config uses. Tools with a programs.* module
  # (git, fzf, zoxide, direnv, tmux, ...) come from that module instead.
  home.packages = [
    pkgs.curl
    pkgs.eza
    pkgs.bat
    pkgs.fd
    pkgs.ripgrep
    pkgs.jq
    pkgs.yq-go
    pkgs.lazygit
    pkgs.gh
    pkgs.micro

    # Node the way nvm used to set it up: the current major, plus pnpm.
    # A project that needs another version pins it in its own flake and
    # direnv loads it (`use flake` in its .envrc).
    pkgs.nodejs_26
    pkgs.pnpm

    # Boot.dev CLI, and the Go it is written in.
    pkgs.go
    pkgs.bootdev-cli
  ]
  # Opens URLs and files in the Windows default app. wslu was dropped
  # from nixpkgs when upstream archived it.
  ++ lib.optional wsl pkgs.wsl-open;

  home.sessionVariables = {
    EDITOR = "micro";
    VISUAL = "micro";
    # The Nix store is read-only, so `npm install --global` goes to
    # ~/.local (bin/ is on PATH).
    NPM_CONFIG_PREFIX = "$HOME/.local";
  }
  // lib.optionalAttrs wsl {
    # gh, xdg-open, Python's webbrowser and friends read BROWSER.
    BROWSER = "wsl-open";
  };

  # XDG_DATA_DIRS, terminfo and locale for Nix programs on a non-NixOS Linux.
  # No GPU driver shim: nothing here draws graphics, and it pulls in Mesa.
  targets.genericLinux = {
    enable = pkgs.stdenv.hostPlatform.isLinux;
    gpu.enable = false;
  };

  # Lets `home-manager` itself run from the shell.
  programs.home-manager.enable = true;

  news.display = "silent";
}
