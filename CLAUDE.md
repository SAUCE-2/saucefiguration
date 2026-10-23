# saucefiguration

Personal dotfiles, managed with Nix and home-manager (standalone, no NixOS
or nix-darwin). The files here are the source of truth. `flake.nix` builds
one home-manager profile per platform from `home.nix`. The profile installs
every tool and links every config file into `$HOME` as a read-only
symlink into the Nix store.

- `flake.nix`: one profile per platform: `x86_64-linux`, `aarch64-linux`,
  `aarch64-darwin`, plus `<system>-wsl`. No Intel Macs, because nixpkgs dropped
  them. Also `checks`, the `nixfmt-tree` formatter, and a dev shell with the
  check tools. `flake.lock` pins nixpkgs (unstable) and home-manager, and
  Dependabot bumps it weekly.
- `home.nix`: the package list, session variables, and the user and home
  directory, read from `$USER`/`$HOME`, so builds use `--impure`.
- `checks.nix`: what `nix flake check` runs.
- Each directory below is a home-manager module (`default.nix`) plus its data:
  - `zsh/`: zsh and Oh My Zsh (`default.nix`), and the hand-written part of
    `~/.zshrc` (`init.zsh`). Also the scripts:
    - `install.sh` installs Nix if it is missing (Determinate Systems
      installer). It moves the old installer's `~/.gitconfig` and
      `~/.tmux.conf` aside, builds the profile and activates it. Then it records
      the clone's path and HEAD in `~/.local/state/saucefiguration/`.
    - `check-update.sh` runs from `.zshrc` at shell start. When the clone has
      moved past the recorded rev, it asks [Y/n], fast-forwards and re-runs
      `install.sh`.
  - `git/` -> `~/.config/git/`. Commits and tags are SSH-signed, and delta is
    the pager. `~/.gitconfig` is left for machine-local settings.
  - `ssh/` -> `~/.ssh/`: client config and `allowed_signers` (linked).
    `authorized_keys` is merged into the existing file by
    `merge-authorized-keys.sh`, not replaced. Public keys only. Apple's ssh
    is used on macOS (for `UseKeychain`), so Nix's OpenSSH is not installed.
  - `ohmyposh/`: prompt theme.
  - `direnv/`: direnv plus nix-direnv.
  - `tmux/` -> `~/.config/tmux/tmux.conf`, with plugins from Nix (no tpm).
- `.github/`: CI, PR title check and labels, Dependabot, stale `claude/*`
  branch pruning. `settings.sh` applies the repo settings and `main` ruleset
  (squash only, auto-delete branches, CI required); the user runs it by hand.

Nix builds only files git tracks, so a new file must be `git add`ed before
it is part of a build or check.

## Rules

- Edit files in this repo only. Never touch the live copies in `$HOME`
  (`~/.zshrc`, `~/.config/`, `~/.ssh/`, ...). home-manager links them there,
  and they are read-only.
- Never read or commit private keys.
- Don't run `zsh/install.sh` without `--dry-run`, or activate a profile,
  unless asked. It installs Nix and replaces files in `$HOME`.
- A new tool goes in `home.packages` in `home.nix`, or comes from its
  `programs.<name>` module. Nix guarantees it is there, so the zsh config
  doesn't guard it.
- One config for every platform. Make macOS-only or WSL-only behavior
  conditional (`isDarwin`, the `wsl` argument, or a runtime check in
  `init.zsh`), not a separate copy.
- `zsh/install.sh` and `zsh/check-update.sh` must stay bash 3.2-safe: they
  run on a fresh Mac before Nix exists.
- Keep the plugin order in `zsh/default.nix`: Oh My Zsh (compinit), then
  fzf-tab, autosuggestions, syntax highlighting. `checks.nix` enforces it.

## Checks

```bash
nix flake check                               # profiles, zshrc startup, nixfmt, shellcheck
nix flake check --all-systems --no-build      # evaluate the other platforms
bash zsh/install.test.sh
bash zsh/check-update.test.sh
nix fmt                                       # format the .nix files
nix develop -c shellcheck zsh/*.sh ssh/*.sh .github/*.sh
```

CI (`.github/workflows/ci.yml`) runs these on Linux and macOS, the script
tests under macOS's `/bin/bash` 3.2. It then runs `zsh/install.sh` for real on
the runner, twice, and checks that zsh finds every tool.

## Commits

Conventional commits scoped by directory: `feat(zsh): ...`, `fix(git): ...`.
Use `nix` for `flake.nix`, `flake.lock`, `home.nix` and `checks.nix`. PRs are
squash-merged with the PR title as the commit, so the title must be one too;
the `pr title` check enforces it. Changes to `main` go through a PR.
