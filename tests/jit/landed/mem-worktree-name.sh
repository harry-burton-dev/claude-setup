#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
memjs="$repo/plugins/outerpale-mem/hooks/mem.js"
[ -f "$memjs" ] || { echo "no outerpale-mem hook"; exit 77; }
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# A git worktree's folder name is not the repository's name: memory must still go to Claude/memory/<repo>/.
git init -q "$work/myrepo"
git -C "$work/myrepo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$work/myrepo" worktree add -q --detach "$work/wt-feature-x"
out="$(cd "$work/myrepo" && HOME="$work/h" node "$memjs" session-start <<<'{}')"
grep -q 'Claude/memory/myrepo/' <<<"$out" || fail "the main checkout did not use its repository name"
out="$(cd "$work/wt-feature-x" && HOME="$work/h" node "$memjs" session-start <<<'{}')"
grep -q 'Claude/memory/myrepo/' <<<"$out" || fail "a worktree used its folder name, not the repository's: $out"
echo ok
