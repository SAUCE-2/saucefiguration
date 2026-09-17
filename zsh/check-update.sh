#!/usr/bin/env bash
# Oh My Zsh-style notice for this clone. .zshrc runs it on interactive start.
# Compares HEAD / upstream to the rev install.sh recorded and, if they differ,
# lists the commits (and files) so you know which configs to copy again.
#
#   SAUCE_DISABLE_UPDATE_CHECK=1   skip
#   SAUCE_STATE_DIR                override the state directory (tests)

set -u

[ -z "${SAUCE_DISABLE_UPDATE_CHECK:-}" ] || exit 0

state="${SAUCE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/saucefiguration}"
[ -f "$state/repo" ] && [ -f "$state/sha" ] || exit 0

repo=$(tr -d '\r\n' <"$state/repo")
last_sha=$(tr -d '\r\n' <"$state/sha")
[ -n "$repo" ] && [ -n "$last_sha" ] || exit 0

msg() { printf '\033[1;34m[saucefiguration]\033[0m %s\n' "$*"; }

if [ ! -d "$repo/.git" ]; then
  msg "clone not found at $repo; re-run zsh/install.sh from the new location"
  exit 0
fi

git_c() { git -C "$repo" "$@"; }

if ! git_c rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

now=$(date +%s)
snooze=0
[ -f "$state/snooze" ] && snooze=$(tr -d '\r\n' <"$state/snooze")
[ -n "$snooze" ] || snooze=0
if [ "$snooze" -gt "$now" ] 2>/dev/null; then
  exit 0
fi

# Background fetch at most once a day so the next shell sees origin moving.
# BatchMode/prompt=0: never block the prompt on SSH or a credential helper.
last_fetch=0
[ -f "$state/last_fetch" ] && last_fetch=$(tr -d '\r\n' <"$state/last_fetch")
[ -n "$last_fetch" ] || last_fetch=0
if [ $((now - last_fetch)) -ge 86400 ]; then
  (
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=2}" \
      git -C "$repo" fetch --quiet --no-tags
    date +%s >"$state/last_fetch"
  ) >/dev/null 2>&1 &
fi

if ! git_c cat-file -e "$last_sha^{commit}" 2>/dev/null; then
  msg "last install rev $last_sha is gone; re-run $repo/zsh/install.sh"
  exit 0
fi

ranges="$last_sha..HEAD"
if git_c rev-parse @{u} >/dev/null 2>&1; then
  ranges="$last_sha..HEAD $last_sha..@{u}"
fi

# Word splitting of $ranges is the git rev-list / log range list.
# shellcheck disable=SC2086
count=$(git_c rev-list --count $ranges 2>/dev/null) || count=0
[ "$count" -gt 0 ] || exit 0

msg "$count new commit(s) since last install. Re-run the installer, then copy any configs you still want:"
echo
# shellcheck disable=SC2086
git_c log -15 --format='  %h %s' $ranges
if [ "$count" -gt 15 ]; then
  printf '  ... and %s more\n' $((count - 15))
fi
echo

files=$(
  {
    git_c diff --name-only "$last_sha" HEAD
    if git_c rev-parse @{u} >/dev/null 2>&1; then
      git_c diff --name-only "$last_sha" @{u}
    fi
  } | sort -u
)
if [ -n "$files" ]; then
  printf '  files (copy again if you use them):\n'
  printf '%s\n' "$files" | sed 's/^/    /'
  echo
fi

printf '  %s\n' "$repo/zsh/install.sh"
echo

# Non-tty (tests, pipes): print the changelog and stop. Same as omz reminder mode.
if [ ! -t 0 ] || [ ! -t 1 ]; then
  exit 0
fi

printf '[saucefiguration] Re-run the installer now? [Y/n] '
read -r -n 1 option || option=n
[ "$option" = $'\n' ] || echo
case "$option" in
  y | Y | '')
    head=$(git_c rev-parse HEAD)
    if up=$(git_c rev-parse @{u} 2>/dev/null) && [ "$head" != "$up" ]; then
      msg "git pull --ff-only"
      if ! git_c pull --ff-only; then
        msg "pull failed; fix the clone then run: $repo/zsh/install.sh"
        exit 1
      fi
    fi
    bash "$repo/zsh/install.sh"
    ;;
  *)
    echo $((now + 86400)) >"$state/snooze"
    msg "Okay. Re-run later: $repo/zsh/install.sh"
    ;;
esac
