# Shell command hygiene

- Don't let exploratory/probing commands end with a non-zero exit code. A non-zero exit makes the app show the whole output in red as "Failed" even when everything worked. When a command checks for things that may not exist (`which`, `ls`, `cat`, `test`, `grep`), add `2>/dev/null` to the individual probes and end the command with `; true` (or `|| true`). Use a real non-zero exit only when something actually went wrong.
- In PowerShell 5.1, don't use `2>&1` on native executables (e.g. `wsl.exe`). It wraps stderr lines as errors. Redirect stderr inside the bash command instead.
- For WSL work, put the redirects and `; true` inside the `bash -lc '...'` string, since that's where the exit code comes from.

# tstack defaults (T3 Code)

- When I ask for a code change in one of my repos (SAUCE-2/*) and don't name a mode, work as if I said **"full stop"**: prove it, review it, file the PR, babysit it, and leave it ready for me to merge. Only merge when I explicitly say **"full send"**.
- Never commit straight to `main`, including in private repos like da2 and da3. Branch and open a PR.
- Never merge a PR (with `gh pr merge` or anything else) while its checks are pending or failing.
- **council** members: Claude Opus (latest, via Claude), GPT Sol (latest, via Cursor), Gemini (latest flagship, via Cursor; currently `gemini-4-hydrogen`). Use high reasoning effort.
- **sol-loop**: GPT Sol runs through the Cursor provider in T3 (Codex is disabled).
- In NiceNovember, changes to the judge's scoring, prompt or thresholds get a **council** review before the PR is filed.
- Before closing an old or stale PR, run **modernize** on it and give me its verdict instead of closing silently.

# Git workflow (all repos)

- Don't stage or commit unless I ask, or a mode like **full stop** calls for it.
- Before pushing, rebase onto the latest `main` unless I say otherwise. Then check `git log` and squash any wip or fixup commits into logical ones.
- Commit messages are one short sentence in conventional-commit form (`feat(scope): ...`), unless the repo sets its own style.
- Outside SAUCE-2 repos, don't open a PR unless I ask.

# Tests

- Prefer tests that run real code over mocks. When logic can only be tested through mocks, say so and suggest how to split it out.
- While working, run only the tests for what you're changing. Run the full suite before filing a PR.

# Project rules files (AGENTS.md / CLAUDE.md)

- When a project needs a rules file, write `AGENTS.md` and make `CLAUDE.md` the single line `@AGENTS.md`, so every agent reads the same rules.
- Include only what an agent needs at the start of every session: style rules with a short good/bad example, how to run one test and the full suite, where the database schema lives, a high-level directory overview, and project scripts the agent should use.
- Leave out what the README already says (link to it instead), what the model already knows, secrets, and repeated rules. A stale directory overview is worse than none, so keep it brief.
- When I correct or undo something you wrote, suggest an `AGENTS.md` edit that would prevent it (a one-line reason and an example) and ask before making it.
- A stale rule is worse than none. When a change renames or moves important directories, changes test, lint or build commands, adds or removes a major dependency, or starts or retires a convention, update `AGENTS.md` in the same change.
- When you notice a rule the model no longer needs, suggest removing it.

# Machines and Tailscale

- Tailnet devices: `macbook` (macOS), `steampc` (SteamOS), `desktop` (Windows), `desktop-wsl` (WSL in `desktop`), `iphone`.
- `ssh steampc` goes over Tailscale SSH and logs in as `deck` (from `ssh/config`). There's no `s` user on it.
- The tailnet policy's SSH rule is `"action": "accept"` (`autogroup:member` → `autogroup:self`), so connecting never asks for a Google login.
- On the Mac, the `tailscale` CLI is `/Applications/Tailscale.app/Contents/MacOS/Tailscale` when it isn't on `PATH`.
