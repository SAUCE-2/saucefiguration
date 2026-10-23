# Per-directory env: loads a project's .envrc (or .env, see load_dotenv)
# after `direnv allow`, unloads it on the way out. Its default
# "direnv: loading" / "export +VAR" lines stay on: they show which variables
# a cd just changed.
{ ... }:
{
  programs.direnv = {
    enable = true;
    # `use flake` / `use nix` in an .envrc, with the shell cached so it
    # loads instantly after the first time.
    nix-direnv.enable = true;
    config.global = {
      # Load a directory's .env when it has no .envrc, the way omz's dotenv
      # plugin did. It still needs `direnv allow` first.
      load_dotenv = true;
    };
  };
}
