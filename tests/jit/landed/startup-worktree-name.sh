#!/usr/bin/env bash
# A git worktree's folder name is not the repository's name: the project CLAUDE.md is still projects/<repo>.md.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
hook="$repo/plugins/outerpale-startup/hooks/session-start.sh"
fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/h/.claude" "$work/store/projects"
printf '%s' "$work/store" > "$work/h/.claude/claude-setup-dir"
printf '# myrepo project\n' > "$work/store/projects/myrepo.md"
git init -q "$work/myrepo"
git -C "$work/myrepo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$work/myrepo" worktree add -q --detach "$work/wt-feature-x"
(cd "$work/wt-feature-x" && HOME="$work/h" bash "$hook") >/dev/null
cmp -s "$work/store/projects/myrepo.md" "$work/wt-feature-x/CLAUDE.md" || fail "a worktree did not get projects/myrepo.md"
git -C "$work/wt-feature-x" check-ignore -q .work/x || fail ".work/ not ignored in the worktree"
echo ok
