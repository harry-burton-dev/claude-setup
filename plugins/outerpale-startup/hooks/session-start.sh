#!/usr/bin/env bash
# SessionStart: keep .work/ (scratch, EGM working files, reviews) out of git, and give this
# repository its project CLAUDE.md, which lives in claude-setup's projects/<repo>.md and never
# in the repository itself. Silent when there is nothing to say.
# What it prints is added to Claude's context.
set -euo pipefail

# Companion findings an earlier session wrote but didn't get into OneDrive.
unsent="$( (find "$HOME/.companion/outbox" -maxdepth 1 -name '*.md' 2>/dev/null || true) | wc -l | tr -d ' ')"
if [ "${unsent:-0}" -gt 0 ]; then
  echo "outerpale-startup: $unsent companion finding(s) in ~/.companion/outbox/ didn't reach OneDrive. Upload them as the outerpale-startup:companion skill's \"Upload\" section says, in the background, without mentioning it unless it fails."
fi

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
exclude="$(git -C "$root" rev-parse --git-path info/exclude)"
case "$exclude" in /*) ;; *) exclude="$root/$exclude" ;; esac
mkdir -p "$(dirname "$exclude")"
keep_out() { grep -qx "$1" "$exclude" 2>/dev/null || echo "$1" >> "$exclude"; }
keep_out '/.work/'
[ -f "$root/CLAUDE.md" ] && exit 0
name="$(basename "$root")"
setup="$(cat "$HOME/.claude/claude-setup-dir" 2>/dev/null || true)"
src="$setup/projects/$name.md"
# The clone can be days old (a cloud VM clones it once per build), so pull before giving up.
[ -n "$setup" ] && [ ! -f "$src" ] && { git -C "$setup" pull -q --ff-only >/dev/null 2>&1 || true; }

if [ -n "$setup" ] && [ -f "$src" ]; then
  cp "$src" "$root/CLAUDE.md"
  keep_out '/CLAUDE.md'
  printf 'outerpale-startup: copied claude-setup projects/%s.md to ./CLAUDE.md (kept out of git). These are this project'"'"'s instructions:\n\n' "$name"
  cat "$src"
else
  cat <<EOF
outerpale-startup: this repository has no ./CLAUDE.md, and I looked for claude-setup projects/$name.md${setup:+ in $setup} but didn't find it.
Tell the user that in one line, then ask with one AskUserQuestion whether to write this project's CLAUDE.md now with the outerpale-startup:project-claude-md skill: "Write it now" (recommended), "Later". On "Write it now", run that skill.
EOF
fi
