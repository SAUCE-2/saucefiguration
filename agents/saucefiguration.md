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
