# saucefiguration

Personal dotfiles. The files here are the source of truth. Nothing is
symlinked: `zsh/install.sh` copies them into place, and `check-update.sh`
offers to pull and re-run it when the clone gets new commits.

- `zsh/`: per-OS `.zshrc` (`darwin/`, `linux/`) and the scripts.
  - `install.sh` installs the tools the zshrc expects (packages, Oh My Zsh,
    nvm/Node/pnpm, Oh My Posh, Go, tmux plugins, ...), then copies the
    configs below into `$HOME` and records the clone's path and HEAD in
    `~/.local/state/saucefiguration/`.
  - `check-update.sh` runs from `.zshrc` at shell start. When the clone has
    moved past the recorded rev, it asks [Y/n], fast-forwards and re-runs
    `install.sh`.
- `git/` -> `~/` (`.gitconfig`, `.gitignore_global`). Commits and tags are
  SSH-signed.
- `ssh/` -> `~/.ssh/`: client config, `authorized_keys` (merged with the
  existing file, not replaced) and `allowed_signers`. Public keys only.
- `ohmyposh/` -> `~/.config/ohmyposh/`: prompt theme.
- `direnv/` -> `~/.config/direnv/`.
- `tmux/.tmux.conf` -> `~/.tmux.conf`.
- `.github/`: CI, PR title check and labels, Dependabot, stale `claude/*`
  branch pruning. `settings.sh` applies the repo settings and `main` ruleset
  (squash only, auto-delete branches, CI required); the user runs it by hand.

`install.sh` copies whole directories, so a new file in `git/`, `ssh/`,
`ohmyposh/` or `direnv/` ships on its own. A new config directory needs a
line in `install_dotfiles`. An existing destination that differs is backed
up as `<file>.bak.<time>` before it is replaced.

## Rules

- Edit files in this repo only. Never touch the live copies in `$HOME`
  (`~/.zshrc`, `~/.gitconfig`, `~/.tmux.conf`, `~/.ssh/`, `~/.config/`);
  `install.sh` puts them there.
- Never read or commit private keys.
- Don't run `zsh/install.sh` without `--dry-run` unless asked. It installs
  system packages and overwrites the files in `$HOME`.
- A new tool used by a `.zshrc` goes in the `packages` list at the top of
  `install.sh`, and the `.zshrc` must guard it (it is optional).
- Keep `darwin/` and `linux/` `.zshrc` in step unless a difference is
  platform-specific.

## Checks

```bash
bash zsh/install.test.sh
bash zsh/check-update.test.sh
shellcheck zsh/*.sh .github/*.sh
zsh -n zsh/linux/.zshrc zsh/darwin/.zshrc
```

CI (`.github/workflows/ci.yml`) runs these on Linux and macOS, the tests
under macOS's `/bin/bash` 3.2.

## Commits

Conventional commits scoped by directory: `feat(zsh): ...`, `fix(git): ...`.
PRs are squash-merged with the PR title as the commit, so the title must be
one too; the `pr title` check enforces it. Changes to `main` go through a PR.
