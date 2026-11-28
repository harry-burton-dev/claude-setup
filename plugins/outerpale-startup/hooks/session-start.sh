#!/usr/bin/env bash
# SessionStart: keep .work/ (scratch and reviews) out of git, and give each
# repository its project CLAUDE.md, which lives in claude-setup's projects/<repo>.md and never
# in the repository itself. Silent when there is nothing to say.
# A session covers the repository it starts in; a cloud session with several repositories starts
# in their non-git parent folder, so then it covers each git repository directly under it.
# What it prints is added to Claude's context.
set -euo pipefail

setup="$(cat "$HOME/.claude/claude-setup-dir" 2>/dev/null || true)"

# A cloud VM keeps the claude-setup it was built from for about 7 days, so plugins added since then
# would be missing. Only cloud/setup.sh writes the status file, so with it the clone is the VM's own
# copy, never a working clone on Harry's machines, and is safe to reset to main.
status="$HOME/.claude/claude-setup.status"
if [ -n "$setup" ] && [ -f "$status" ] && git -C "$setup" fetch -q --depth 1 origin main 2>/dev/null; then
  old="$(git -C "$setup" rev-parse --short HEAD)"
  new="$(git -C "$setup" rev-parse --short FETCH_HEAD)"
  if [ "$old" != "$new" ]; then
    git -C "$setup" reset -q --hard FETCH_HEAD
    sed -i "1s/.*/claude-setup $new, updated $(date -u +%Y-%m-%dT%H:%M:%SZ) by outerpale-startup/" "$status"
    if bash "$setup/install.sh" >/dev/null 2>&1; then
      printf 'outerpale-startup: claude-setup on this VM was updated %s → %s; plugins and skills it added load from the next session.\n' "$old" "$new"
    else
      printf 'outerpale-startup: WARNING claude-setup on this VM was updated %s → %s, but install.sh failed; run bash %s/install.sh to see why.\n' "$old" "$new" "$setup"
    fi
  fi
fi

one_repo() {  # $1 the repository root, $2 how to show its folder ("." or its name), $3 what to call it
  local root="$1" rel="$2" label="$3" exclude name src common
  exclude="$(git -C "$root" rev-parse --git-path info/exclude)"
  case "$exclude" in /*) ;; *) exclude="$root/$exclude" ;; esac
  mkdir -p "$(dirname "$exclude")"
  keep_out() {
    grep -qx "$1" "$exclude" 2>/dev/null && return
    # A hand-edited exclude file may lack its last newline; don't glue the pattern onto that line.
    [ -s "$exclude" ] && [ -n "$(tail -c1 "$exclude")" ] && echo >> "$exclude"
    echo "$1" >> "$exclude"
  }
  keep_out '/.work/'
  [ -f "$root/CLAUDE.md" ] && return 0
  # The repository's name, not the folder's: a linked worktree's folder can be called anything.
  common="$(cd "$root" && cd "$(git rev-parse --git-common-dir)" && pwd)"
  if [ "$(basename "$common")" = .git ]; then name="$(basename "$(dirname "$common")")"; else name="$(basename "$root")"; fi
  src="$setup/projects/$name.md"
  # The clone can be days old (a cloud VM clones it once per build), so pull before giving up.
  [ -n "$setup" ] && [ ! -f "$src" ] && { git -C "$setup" pull -q --ff-only >/dev/null 2>&1 || true; }

  if [ -n "$setup" ] && [ -f "$src" ]; then
    cp "$src" "$root/CLAUDE.md"
    keep_out '/CLAUDE.md'
    printf 'outerpale-startup: copied claude-setup projects/%s.md to %s/CLAUDE.md (kept out of git). These are %s'"'"'s instructions:\n\n' "$name" "$rel" "${label/this repository/this project}"
    cat "$src"
  else
    cat <<EOF
outerpale-startup: $label has no $rel/CLAUDE.md, and I looked for claude-setup projects/$name.md${setup:+ in $setup} but didn't find it.
Tell the user that in one line, then ask with one AskUserQuestion whether to write ${label/this repository/this project}'s CLAUDE.md now with the outerpale-startup:project-claude-md skill: "Write it now" (recommended), "Later". On "Write it now", run that skill.
EOF
  fi
}

if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  one_repo "$root" . 'this repository'
  exit 0
fi
for d in */; do
  [ -e "$d.git" ] || continue
  one_repo "$PWD/${d%/}" "${d%/}" "${d%/}"
done
