# saucefiguration

Personal dotfiles. The files here are the source of truth. Nothing is
symlinked: `zsh/install.sh` copies them into place, and `check-update.sh`
offers to pull and re-run it when the clone gets new commits.

- `zsh/`: per-OS `.zshrc` (`darwin/`, `linux/`) and the scripts.
  - `install.sh` installs the tools the zshrc expects (packages, Oh My Zsh,
    nvm/Node/pnpm, Oh My Posh, Go, OpenJDK, tmux plugins, ...), then copies the
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
- `agents/`: the user's global agent setup, not this repo's.
  `AGENTS.md` is the global agent rules, copied to `~/.codex/AGENTS.md`,
  `~/.config/opencode/AGENTS.md` and `~/.claude/AGENTS.md`.
  `~/.claude/CLAUDE.md` is never replaced, since other tools keep blocks in
  it; it only gains an `@~/.claude/AGENTS.md` import line if missing (and
  loses the old `@~/.claude/saucefiguration.md` one). Claude and T3 Code's
  Claude provider read it.
  `update-tstack.sh` ->
  `~/.local/bin/update-tstack`, which `install.sh` then runs: it clones or
  pulls github.com/t3dotgg/tstack into `~/.t3/tools/tstack` and copies its
  skills into `~/.claude/skills` and `~/.agents/skills`, leaving other skills
  there alone.
- `.github/`: CI, PR title check and labels, Dependabot, stale `claude/*`
  branch pruning. `settings.sh` applies the repo settings and `main` ruleset
  (squash only, auto-delete branches, CI required); the user runs it by hand.

`install.sh` copies whole directories, so a new file in `git/`, `ssh/`,
`ohmyposh/` or `direnv/` ships on its own. A new config directory needs a
line in `install_dotfiles`. An existing destination that differs is backed
up as `<file>.bak.<time>` before it is replaced.

## This repo is public

Everything here is public for good: files, commit messages, PR titles and
bodies, branch names, CI logs, and git history (deleting a line later does
not remove it). Keep what makes the dotfiles work on any machine. Leave out
what maps the user's network, machines or private work.

Never commit:

- Secrets: private keys, tokens, passwords, `.env` files, API keys.
- Network details: Tailscale/tailnet device lists, the tailnet name or
  `*.ts.net` domains, IPs (`100.x`, LAN ranges), ACL or SSH policy, which
  login provider guards it, open ports, router or VPN setup.
- Machine details: which hosts exist, their OS, per-host usernames
  (`Host steampc` + `User deck`), absolute home paths (`/Users/s/...`).
- Private work: names or contents of private repos, employers, clients.
- Personal details: any email other than `s@sauce2.com`, real names,
  locations, phone numbers, account IDs.

Those go in untracked per-machine files instead, such as
`~/.ssh/config.d/<host>` (pulled in by `Include` in `ssh/config`), or in the
user's private agent notes, not in `agents/AGENTS.md` (which is published
like everything else).

```
# bad: ssh/config                 # good: ssh/config
Host steampc                      Include config.d/*
  User deck
```

Fine to commit: public keys (`ssh/`), `s@sauce2.com`, the `SAUCE-2` org,
public tool and repo URLs, `$HOME`- or `~`-relative paths, generic config.

If you find something that shouldn't be public, already committed or not,
stop and tell the user. Don't rewrite history or force-push on your own.

## Rules

- Edit files in this repo only. Never touch the live copies in `$HOME`
  (`~/.zshrc`, `~/.gitconfig`, `~/.tmux.conf`, `~/.ssh/`, `~/.config/`);
  `install.sh` puts them there.
- Never read private keys.
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
shellcheck zsh/*.sh .github/*.sh agents/*.sh
zsh -n zsh/linux/.zshrc zsh/darwin/.zshrc
# Before committing: every hit in the added lines must be safe to publish.
git diff main -U0 | grep '^+' | grep -nEi 'ts\.net|tailnet|100\.[0-9]+\.[0-9]+\.|192\.168\.|/Users/|/home/|PRIVATE KEY|token|password|@[a-z0-9-]+\.[a-z]{2,}'
```

CI (`.github/workflows/ci.yml`) runs these on Linux and macOS, the tests
under macOS's `/bin/bash` 3.2.

## Commits

Conventional commits scoped by directory: `feat(zsh): ...`, `fix(git): ...`.
PRs are squash-merged with the PR title as the commit, so the title must be
one too; the `pr title` check enforces it. Changes to `main` go through a PR.
