#!/usr/bin/env bash
# Oh My Zsh-style prompt for this clone. .zshrc runs it on interactive start.
# If HEAD or upstream has moved past the rev install.sh recorded, the first
# prompt of the session asks whether to update — same [Y/n] as omz.
# A daily background fetch updates the upstream ref; we only prompt once
# those commits are in the clone. Saying yes fast-forwards, then re-runs the installer.
#
#   SAUCE_DISABLE_UPDATE_CHECK=1   skip
#   SAUCE_STATE_DIR                override the state directory (tests)
#   SAUCE_UPDATE_ANSWER            tests: y/n without a tty

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

last_fetch=0
[ -f "$state/last_fetch" ] && last_fetch=$(tr -d '\r\n' <"$state/last_fetch")
[ -n "$last_fetch" ] || last_fetch=0

# Fetch GitHub SSH remotes over anonymous HTTPS: at shell start there is often
# no ssh-agent yet, and a BatchMode SSH fetch then fails silently every day.
# BatchMode/prompt=0 still cover other remotes, so nothing blocks on a password.
fetch_upstream() {
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=2}" \
    git -C "$repo" -c url.https://github.com/.insteadOf=git@github.com: \
    fetch --quiet --no-tags
}

# ponytail: fetch is background, so the shell that starts it does not see the
# new commits; the next one does. A sync fetch here would block the prompt.
if [ $((now - last_fetch)) -ge 86400 ]; then
  printf '%s\n' "$now" >"$state/last_fetch"
  fetch_upstream >/dev/null 2>&1 &
fi

if ! git_c cat-file -e "$last_sha^{commit}" 2>/dev/null; then
  msg "last install rev $last_sha is gone; re-run $repo/zsh/install.sh"
  exit 0
fi

ranges="$last_sha..HEAD"
if git_c rev-parse '@{u}' >/dev/null 2>&1; then
  ranges="$last_sha..HEAD $last_sha..@{u}"
fi

# Word splitting of $ranges is the git rev-list / log range list.
# shellcheck disable=SC2086
count=$(git_c rev-list --count $ranges 2>/dev/null) || count=0

[ "$count" -gt 0 ] || exit 0

# Same line omz prints when it cannot prompt (pipes, tests, typed-ahead input).
msg "It's time to update! You can do that by running \`$repo/zsh/install.sh\`"

echo
msg "$count new commit(s) since last install. Re-run the installer to copy them:"
echo
# shellcheck disable=SC2086
git_c --no-pager log -15 --format='  %h %s' $ranges
if [ "$count" -gt 15 ]; then
  printf '  ... and %s more\n' $((count - 15))
fi
echo

files=$(
  {
    git_c --no-pager diff --name-only "$last_sha" HEAD
    if git_c rev-parse '@{u}' >/dev/null 2>&1; then
      git_c --no-pager diff --name-only "$last_sha" '@{u}'
    fi
  } | sort -u
)
if [ -n "$files" ]; then
  printf '  files the installer will copy:\n'
  printf '%s\n' "$files" | sed 's/^/    /'
  echo
fi

# install.sh copies the working tree, not HEAD, and this clone is where the
# repo gets edited. Don't let Enter install half-done work: tracked changes
# (staged or not), or new files in the dirs install.sh copies whole. No snooze,
# so the prompt is back once the tree is clean.
if ! git_c diff --quiet HEAD -- ||
  [ -n "$(git_c ls-files --others --exclude-standard -- git ohmyposh ssh)" ]; then
  msg "the clone has uncommitted changes; commit or stash them, then run \`$repo/zsh/install.sh\`"
  exit 0
fi

# omz prompt mode: Y/n on a tty. Pipes and tests skip unless they set an answer.
if [ -z "${SAUCE_UPDATE_ANSWER+x}" ]; then
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    exit 0
  fi
  # Data waiting? The user already started typing: leave it for zsh, no prompt.
  # bash 4+ peeks with read -t 0. bash 3.2 (macOS /bin/bash) fails that without
  # looking, so the prompt ate the first key; zsh's zselect peeks instead.
  if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
    read -r -t 0 && exit 0
  else
    zsh -fc 'zmodload zsh/zselect && zselect -t 0 -r 0' 2>/dev/null && exit 0
  fi
  printf '[saucefiguration] Would you like to update? [Y/n] '
  read -r -n 1 option || option=n
  [ "$option" = $'\n' ] || echo
else
  option=$SAUCE_UPDATE_ANSWER
fi

case "$option" in
  y | Y | '')
    fetch_upstream >/dev/null 2>&1 || msg "fetch failed; installing what the clone already has"
    head=$(git_c rev-parse HEAD)
    if up=$(git_c rev-parse '@{u}' 2>/dev/null) && [ "$head" != "$up" ]; then
      # Merge the ref we just fetched: a pull would hit the network again (SSH)
      # and follow pull.rebase, which refuses a dirty tree.
      msg "git merge --ff-only @{u}"
      if ! git_c merge --ff-only --quiet '@{u}'; then
        # Same 24h as "n". A dirty tree fails every new shell otherwise.
        echo $((now + 86400)) >"$state/snooze"
        msg "fast-forward failed; fix the clone then run: \`$repo/zsh/install.sh\`"
        exit 1
      fi
    fi
    bash "$repo/zsh/install.sh"
    ;;
  n | N)
    # Duplicate the default message: bash 3.2 (macOS) has no case fallthrough.
    echo $((now + 86400)) >"$state/snooze"
    msg "You can update manually by running \`$repo/zsh/install.sh\`"
    ;;
  *)
    msg "You can update manually by running \`$repo/zsh/install.sh\`"
    ;;
esac
