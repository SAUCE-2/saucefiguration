# saucefiguration

Personal dotfiles. The files here are the source of truth; nothing is
symlinked. The user copies them into place by hand.

- `zsh/` — per-OS `.zshrc` (`darwin/`, `linux/`), `install.sh` (installs the
  tools the zshrc expects), `check-update.sh` (notices new commits since the
  last install).
- `git/.gitconfig`: global git config. Commits and tags are SSH-signed.
- `ssh/`: client config, `authorized_keys` and `allowed_signers`. Public keys only.
- `ohmyposh/theme.omp.json`: prompt theme.
- `tmux/.tmux.conf`: tmux config, copied to `~/.tmux.conf`.
- `.github/`: CI, PR title check and labels, Dependabot, stale `claude/*`
  branch pruning. `settings.sh` applies the repo settings and `main` ruleset
  (squash only, auto-delete branches, CI required); the user runs it by hand.

## Rules

- Edit files in this repo only. Never touch the live copies in `$HOME`
  (`~/.zshrc`, `~/.gitconfig`, `~/.tmux.conf`, `~/.ssh/`, `~/.config/`).
- Never read or commit private keys.
- Don't run `zsh/install.sh` without `--dry-run` unless asked. It installs
  system packages.
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
