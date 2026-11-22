<!-- My global rules for every agent, in every project, on every machine. Source: agents/AGENTS.md in SAUCE-2/saucefiguration; install.sh copies it into place. Edit it there, not here. -->

# How I like to work

- **British English, always:** in code identifiers, endpoints, UI text, comments, docs, commit messages and replies. Framework names stay as they are.
  - Good: `analyse`, `uncategorised`, `normalise`, `colour`
  - Bad: `analyze`, `uncategorized`, `normalize`, `color`
- **Call out inaccurate or misleading names**, including mine and ones in a plan, instead of carrying them over. Suggest a better name.
- **Justify suggestions on their merits.** Say when an idea is copied from another project or plan, and check that it still fits.

# Second brain: `~/ClaudeBrain`

The agents' shared long-term memory of everything we work on together. Use it in every session, whatever the working directory. It is an Obsidian vault, synced between my machines with Remotely Save; it will move to a server on my tailnet, and this section will say so when it does.

- **Start of real work:** read `CRITICAL_FACTS.md` and `index.md` (Claude gets them from a session hook), then the relevant project note in `wiki/projects/` and recent `wiki/logs/`. Search the vault for the topic before asking me to re-explain.
- **After meaningful work, without being asked:** write a session log in `wiki/logs/YYYY-MM-DD - Description.md`, update or create the project note, append to `wiki/daily/YYYY-MM-DD.md` and `log.md`, and add new notes to `index.md`.
- Note which machine the work happened on when it matters (paths or tools that exist on one machine only).
- Never store secrets there. Note where a secret lives, never its value.
- Full rules, read when writing to the vault: `~/ClaudeBrain/_CLAUDE.md`.

# My personal vault: `~/Obby`

Reference only. Never create, edit, move or delete anything there, except in `~/Obby/+/Agents/`, for notes I should see in my own vault. Match Obby's frontmatter: `tags`, `up`, `sources`, `related`, `created: "[[YYYY-MM-DD]]"`.

# Git

- Never commit straight to `main`, including in private repos like da2 and da3. Branch and open a PR.
- Don't stage or commit unless I ask, or a mode like **full stop** calls for it.
- Before pushing, rebase onto the latest `main` unless I say otherwise, and squash wip or fixup commits into logical ones.
- Commit messages are one short sentence in conventional-commit form (`feat(scope): ...`), unless the repo sets its own style.
- Outside SAUCE-2 repos, don't open a PR unless I ask.
- Never merge a PR while its checks are pending or failing.

# Tests

- Prefer tests that run real code over mocks. When logic can only be tested through mocks, say so and suggest how to split it out.
- While working, run only the tests for what you're changing. Run the full suite before filing a PR.

# Project rules files

- A project's agent rules go in `AGENTS.md`. Make `CLAUDE.md` the single line `@AGENTS.md`, so every agent reads the same rules.
- It is loaded every session, so keep it to what an agent needs every time: style rules with a good/bad example, how to run one test and the full suite, where the database schema lives, a high-level directory overview, and the project's scripts. Use a nested `AGENTS.md` for rules that only apply to one package.
- Human setup and narrative belong in the README; detailed docs (API, spec) go in `docs/`. Link to them instead of repeating them. Leave out secrets and what the model already knows.
- A stale rule is worse than none. When a change renames important directories, changes test, lint or build commands, adds or removes a major dependency, or starts or retires a convention, update `AGENTS.md` in the same change.
- When I correct or undo something you wrote, suggest an `AGENTS.md` edit that would prevent it and ask before making it. Suggest removing rules the model no longer needs.

# Shell commands

- Probing commands (`which`, `ls`, `cat`, `test`, `grep` on things that may not exist) must not end with a non-zero exit, or T3 Code shows the output as "Failed". Add `2>/dev/null` to each probe and end the command with `; true`.
- In PowerShell 5.1, don't use `2>&1` on native executables such as `wsl.exe`. Redirect stderr inside the bash command instead. For WSL, put the redirects and `; true` inside the `bash -lc '...'` string.

# T3 Code modes (tstack)

- A code change in one of my repos (SAUCE-2/*) with no mode named means **full stop**: prove it, review it, file the PR, babysit it, and leave it ready for me to merge. Merge only when I say **full send**.
- **council:** Claude Opus (latest, via Claude), GPT Sol (latest, via Cursor) and Gemini (latest flagship, via Cursor; currently `gemini-4-hydrogen`), all at high reasoning effort.
- **sol-loop:** GPT Sol runs through the Cursor provider (Codex is disabled).
- In NiceNovember, changes to the judge's scoring, prompt or thresholds get a **council** review before the PR is filed.
- Before closing an old or stale PR, run **modernize** on it and give me its verdict.

# Machines

- Tailnet: `macbook` (macOS), `steampc` (SteamOS), `desktop` (Windows), `desktop-wsl` (WSL in `desktop`), `iphone`.
- `ssh steampc` uses Tailscale SSH and logs in as `deck`; there is no `s` user. The tailnet SSH rule is `accept`, so it never asks for a Google login.
- On the Mac, the `tailscale` CLI is `/Applications/Tailscale.app/Contents/MacOS/Tailscale` when it isn't on `PATH`.
