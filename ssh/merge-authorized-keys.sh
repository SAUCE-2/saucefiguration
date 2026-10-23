#!/usr/bin/env bash
# Merges the repo's authorized_keys ($1) into the live one ($2). ssh/default.nix
# runs this on every home-manager switch.
#
# authorized_keys is merged, not replaced: the repo's lines, then any key the
# machine already trusts that the repo does not list. Replacing it would lock
# you out of a server whose key lives only there. Lines match on the base64
# key blob (it always starts "AAAA"), so the repo's line for a key wins over
# an old one with other options or comment.
#
# An unchanged result leaves the file alone. Otherwise the old file is kept as
# $2.bak.<time> and the merge is renamed into place with mode 600.
set -euo pipefail

src=$1
dest=$2
old=/dev/null
[ -f "$dest" ] && old=$dest

merged=$(mktemp "${TMPDIR:-/tmp}/authorized_keys.XXXXXX")
trap 'rm -f "$merged"' EXIT
awk '
  {
    sub(/\r$/, "")
    id = $0
    for (i = 1; i <= NF; i++) if ($i ~ "^AAAA[0-9A-Za-z+/]+=*$") { id = $i; break }
  }
  FILENAME == ARGV[1] { repo[id] = 1; print; next }
  NF && !(id in repo)
' "$src" "$old" >"$merged"

if [ -f "$dest" ] && cmp -s "$merged" "$dest"; then
  exit 0
fi

mkdir -p "$(dirname "$dest")"
if [ -f "$dest" ]; then
  backup="$dest.bak.$(date +%Y%m%d%H%M%S)"
  # -p keeps the mode, so the backup is no more open than the original.
  cp -p "$dest" "$backup"
  printf 'authorized_keys: updated %s (backup: %s)\n' "$dest" "$backup"
fi
# Temp file in the same dir, then rename: sshd never sees a half-written file.
tmp="$dest.tmp.$$"
cp "$merged" "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$dest"
