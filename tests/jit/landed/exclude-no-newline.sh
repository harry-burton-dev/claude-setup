#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
hook="$repo/plugins/outerpale-startup/hooks/session-start.sh"
[ -f "$hook" ] && grep -q "\.work" "$hook" || exit 77
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home/.claude"
export HOME="$work/home"
g() { git -c user.name=t -c user.email=t@t "$@"; }
# A hand-edited exclude file whose last line has no newline: the hook must not glue /.work/ onto it.
g init -q "$work/r" && printf '# own\n' > "$work/r/CLAUDE.md"
printf 'secret.txt' > "$work/r/.git/info/exclude"
(cd "$work/r" && bash "$hook") >/dev/null
mkdir -p "$work/r/.work" && touch "$work/r/.work/x" "$work/r/secret.txt"
st="$(git -C "$work/r" status --porcelain)"
[ "$st" = "?? CLAUDE.md" ] || fail "status after hook was: $st"
echo "ok: existing pattern and /.work/ both work when exclude lacks a trailing newline"
