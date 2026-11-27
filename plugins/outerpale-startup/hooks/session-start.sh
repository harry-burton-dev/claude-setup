#!/usr/bin/env bash
# SessionStart: give this repository its project CLAUDE.md, which lives in claude-setup's
# projects/<repo>.md and never in the repository itself. Silent when there is nothing to do.
# What it prints is added to Claude's context.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$root/CLAUDE.md" ] && exit 0
name="$(basename "$root")"
setup="$(cat "$HOME/.claude/claude-setup-dir" 2>/dev/null || true)"
src="$setup/projects/$name.md"
# The clone can be days old (a cloud VM clones it once per build), so pull before giving up.
[ -n "$setup" ] && [ ! -f "$src" ] && { git -C "$setup" pull -q --ff-only >/dev/null 2>&1 || true; }

if [ -n "$setup" ] && [ -f "$src" ]; then
  cp "$src" "$root/CLAUDE.md"
  exclude="$(git -C "$root" rev-parse --git-path info/exclude)"
  case "$exclude" in /*) ;; *) exclude="$root/$exclude" ;; esac
  mkdir -p "$(dirname "$exclude")"
  grep -qx '/CLAUDE.md' "$exclude" 2>/dev/null || echo '/CLAUDE.md' >> "$exclude"
  printf 'outerpale-startup: copied claude-setup projects/%s.md to ./CLAUDE.md (kept out of git). These are this project'"'"'s instructions:\n\n' "$name"
  cat "$src"
else
  cat <<EOF
outerpale-startup: this repository has no ./CLAUDE.md, and I looked for claude-setup projects/$name.md${setup:+ in $setup} but didn't find it.
Tell the user that in one line, then ask with one AskUserQuestion whether to write this project's CLAUDE.md now with the outerpale-startup:project-claude-md skill: "Write it now" (recommended), "Later". On "Write it now", run that skill.
EOF
fi
