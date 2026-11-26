#!/usr/bin/env bash
# Install this repository's user-level Claude Code setup into ~/.claude.
# The same script is used on the PC, the server and every cloud VM. It is safe to run again:
# anything already up to date is left alone.
#
#   CLAUDE_HOME   where to install (default: $HOME/.claude)
#   SKILLS_LOCK   skills list to use (default: skills.lock next to this script)
#   PLUGINS_LOCK  plugins list to use (default: plugins.lock next to this script)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="${CLAUDE_HOME:-$HOME/.claude}"
skills_lock="${SKILLS_LOCK:-$here/skills.lock}"
plugins_lock="${PLUGINS_LOCK:-$here/plugins.lock}"
mkdir -p "$dest/skills"

log() { printf 'claude-setup: %s\n' "$*"; }

# 1. User instructions.
if cmp -s "$here/CLAUDE.md" "$dest/CLAUDE.md" 2>/dev/null; then
  log "CLAUDE.md up to date"
else
  if [ -f "$dest/CLAUDE.md" ]; then
    cp "$dest/CLAUDE.md" "$dest/CLAUDE.md.bak-$(date +%Y%m%d%H%M%S)"
    log "backed up the existing CLAUDE.md"
  fi
  cp "$here/CLAUDE.md" "$dest/CLAUDE.md"
  log "CLAUDE.md installed"
fi

# 2. Skills, each pinned to a commit in skills.lock.
install_skill() {
  local name="$1" repo="$2" commit="$3" path="$4"
  local target="$dest/skills/$name" stamp="$repo $commit $path"
  if [ -f "$target/.claude-setup-source" ] && [ "$(cat "$target/.claude-setup-source")" = "$stamp" ]; then
    log "skill $name up to date"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  git -C "$tmp" fetch -q --depth 1 "$repo" "$commit"
  git -C "$tmp" -c advice.detachedHead=false checkout -q FETCH_HEAD
  if [ ! -f "$tmp/$path/SKILL.md" ]; then
    rm -rf "$tmp"
    log "skill $name: no SKILL.md at $path in $repo@$commit"
    return 1
  fi
  rm -rf "$target"
  mkdir -p "$target"
  (cd "$tmp/$path" && tar --exclude=.git -cf - .) | (cd "$target" && tar -xf -)
  printf '%s' "$stamp" > "$target/.claude-setup-source"
  rm -rf "$tmp"
  log "skill $name installed ($commit)"
}

failed=0
while read -r name repo commit path; do
  case "$name" in ''|'#'*) continue ;; esac
  install_skill "$name" "$repo" "$commit" "$path" || failed=1
done < "$skills_lock"

# 3. Agents and commands kept in this repository, copied as they are.
for kind in agents commands; do
  if [ -d "$here/$kind" ] && [ -n "$(ls -A "$here/$kind")" ]; then
    mkdir -p "$dest/$kind"
    cp -R "$here/$kind/." "$dest/$kind/"
    log "$kind installed"
  fi
done

# 4. Plugins from plugins.lock, through the claude CLI.
while read -r plugin marketplace; do
  case "$plugin" in ''|'#'*) continue ;; esac
  if ! command -v claude >/dev/null 2>&1; then
    log "plugin $plugin skipped: no claude CLI on PATH"
    failed=1
    continue
  fi
  claude plugin marketplace add "$marketplace" >/dev/null 2>&1 || true
  if claude plugin install "$plugin" --scope user >/dev/null 2>&1; then
    log "plugin $plugin installed"
  else
    log "plugin $plugin failed to install"
    failed=1
  fi
done < <(cat "$plugins_lock" 2>/dev/null || true)

if [ "$failed" -ne 0 ]; then
  log "finished with errors"
  exit 1
fi
log "done: $dest"
