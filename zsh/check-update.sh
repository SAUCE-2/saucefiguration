#!/usr/bin/env bash
# Oh My Zsh-style prompt for this clone. .zshrc runs it on interactive start.
# If HEAD, upstream, or GitHub has moved past the rev install.sh recorded, the
# first prompt of the session asks whether to update — same [Y/n] as omz.
# Re-running the installer copies the updated configs.
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

remote_sha=
[ -f "$state/remote_sha" ] && remote_sha=$(tr -d '\r\n' <"$state/remote_sha")

# Same trick OMZ uses: ask GitHub for the branch tip so THIS shell, not the
# next one, can see origin move. 2s cap so a dead network cannot stall the prompt.
github_head() {
  local url repo_slug branch
  url=$(git_c config remote.origin.url 2>/dev/null) || return 1
  case "$url" in
    https://github.com/*) repo_slug=${url#https://github.com/} ;;
    git@github.com:*) repo_slug=${url#git@github.com:} ;;
    *) return 1 ;;
  esac
  repo_slug=${repo_slug%.git}
  repo_slug=${repo_slug%/}
  branch=$(git_c rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=main
  [ "$branch" = HEAD ] && branch=main
  [ -n "$repo_slug" ] && [ -n "$branch" ] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  curl --connect-timeout 2 --max-time 2 -fsSL \
    -H 'Accept: application/vnd.github.v3.sha' \
    "https://api.github.com/repos/${repo_slug}/commits/${branch}" 2>/dev/null
}

# Daily: sync GitHub check (notice on first open) plus a background fetch so
# later shells can list the new commits. BatchMode/prompt=0: never block the
# prompt on SSH or a credential helper.
if [ $((now - last_fetch)) -ge 86400 ]; then
  sha=$(github_head || true)
  sha=$(printf '%s' "$sha" | tr -d '\r\n')
  if [ ${#sha} -eq 40 ]; then
    printf '%s\n' "$sha" >"$state/remote_sha"
    remote_sha=$sha
  fi
  printf '%s\n' "$now" >"$state/last_fetch"
  (
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=2}" \
      git -C "$repo" fetch --quiet --no-tags
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
if [ ${#remote_sha} -eq 40 ] && git_c cat-file -e "$remote_sha^{commit}" 2>/dev/null; then
  ranges="$ranges $last_sha..$remote_sha"
fi

# Word splitting of $ranges is the git rev-list / log range list.
# shellcheck disable=SC2086
count=$(git_c rev-list --count $ranges 2>/dev/null) || count=0

# GitHub knows about a commit we have not fetched yet.
remote_only=0
if [ "$count" -eq 0 ] && [ ${#remote_sha} -eq 40 ] && [ "$remote_sha" != "$last_sha" ]; then
  if git_c cat-file -e "$remote_sha^{commit}" 2>/dev/null; then
    git_c merge-base --is-ancestor "$remote_sha" "$last_sha" 2>/dev/null || remote_only=1
  else
    remote_only=1
  fi
fi

[ "$count" -gt 0 ] || [ "$remote_only" = 1 ] || exit 0

# Same line omz prints when it cannot prompt (pipes, tests, typed-ahead input).
msg "It's time to update! You can do that by running \`$repo/zsh/install.sh\`"

if [ "$count" -gt 0 ]; then
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
      if git_c rev-parse @{u} >/dev/null 2>&1; then
        git_c --no-pager diff --name-only "$last_sha" @{u}
      fi
      if [ ${#remote_sha} -eq 40 ] && git_c cat-file -e "$remote_sha^{commit}" 2>/dev/null; then
        git_c --no-pager diff --name-only "$last_sha" "$remote_sha"
      fi
    } | sort -u
  )
  if [ -n "$files" ]; then
    printf '  files the installer will copy:\n'
    printf '%s\n' "$files" | sed 's/^/    /'
    echo
  fi
fi

# omz prompt mode: Y/n on a tty. Pipes and tests skip unless they set an answer.
if [ -z "${SAUCE_UPDATE_ANSWER+x}" ]; then
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    exit 0
  fi
  # timeout 0: data waiting? do not consume it (user already started typing).
  if read -r -t 0; then
    exit 0
  fi
  printf '[saucefiguration] Would you like to update? [Y/n] '
  read -r -n 1 option || option=n
  [ "$option" = $'\n' ] || echo
else
  option=$SAUCE_UPDATE_ANSWER
fi

case "$option" in
  y | Y | '')
    (
      GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=2}" \
        git -C "$repo" fetch --quiet --no-tags
    ) >/dev/null 2>&1 || true
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
  n | N)
    # Duplicate the default message: bash 3.2 (macOS) has no case fallthrough.
    echo $((now + 86400)) >"$state/snooze"
    msg "You can update manually by running \`$repo/zsh/install.sh\`"
    ;;
  *)
    msg "You can update manually by running \`$repo/zsh/install.sh\`"
    ;;
esac
