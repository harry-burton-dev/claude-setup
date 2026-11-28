#!/usr/bin/env bash
# Claude Code cloud VM setup. cloud/bootstrap.sh, pasted into the environment's
# "Setup script" field on claude.ai, clones this repository and runs this file from the clone,
# so a change here reaches every environment on its next build without pasting anything.
# It runs as root on Ubuntu 24.04 the first time a session starts in the environment.
# The resulting filesystem is cached for about 7 days, and the script runs again whenever
# the pasted script, or the allowed domains, change. Background processes do not survive the cache.
#
# Allowed domains it needs besides the default list: nodejs.org (for Node $NODE_MAJOR).
#
#   ENV_PLUGINS  plugins for this environment only, on top of plugins.lock, set by bootstrap.sh
set -euo pipefail

NODE_MAJOR="26"

warnings=()
warn() { warnings+=("$*"); printf 'setup: WARNING %s\n' "$*"; }
log()  { printf 'setup: %s\n' "$*"; }

# 1. Tools every project uses. Docker, git and Node 22 are already installed.
if apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq jq shellcheck ripgrep >/dev/null; then
  log "apt tools installed"
else
  warn "apt install failed"
fi

# 2. Node $NODE_MAJOR as the default node, with pnpm through corepack.
is_node_major() { node --version 2>/dev/null | grep -q "^v$NODE_MAJOR\."; }
if ! is_node_major && npm install -g -s n >/dev/null 2>&1 && n -q "$NODE_MAJOR" >/dev/null 2>&1; then
  hash -r
  # n installs into /usr/local, but cloud VMs put /opt/node22/bin ahead of it on PATH.
  # Install over whichever node comes first, so that one is $NODE_MAJOR too.
  is_node_major || { N_PREFIX="$(dirname "$(dirname "$(command -v node)")")" n -q "$NODE_MAJOR" >/dev/null 2>&1; hash -r; }
fi
if is_node_major; then
  log "node $(node --version) is the default node"
else
  warn "node $NODE_MAJOR is not the default node (is nodejs.org allowed?); node is $(node --version 2>/dev/null || echo none)"
fi
# Node 25 and later no longer bundle corepack, so it is installed from npm first.
if { command -v corepack >/dev/null 2>&1 || npm install -g -s corepack >/dev/null 2>&1; } && corepack enable >/dev/null 2>&1; then
  log "corepack enabled (pnpm and yarn follow each repo's packageManager field)"
else
  warn "corepack enable failed"
fi

# 3. The user-level Claude setup from the clone this script is in:
#    CLAUDE.md, skills, agents, commands and plugins.
src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugins_lock="$(mktemp)"
cat "$src/plugins.lock" > "$plugins_lock"
printf '%s\n' "${ENV_PLUGINS:-}" >> "$plugins_lock"
# A failing setup script stops every session in the environment from starting, so a skill or plugin
# that fails to install is a warning in the status file, not a failed setup.
install_log="$(mktemp)"
install_status=0
PLUGINS_LOCK="$plugins_lock" bash "$src/install.sh" > "$install_log" 2>&1 || install_status=$?
cat "$install_log"
[ "$install_status" -eq 0 ] || warn "install.sh: $(grep -E 'failed|skipped|no SKILL.md' "$install_log" | sed 's/^claude-setup: //' | paste -sd ';' -)"
rm -f "$install_log"
rm -f "$plugins_lock"
commit="$(git -C "$src" rev-parse --short HEAD 2>/dev/null || echo unknown)"

# 4. A status file, so a session can check what this VM was given.
mkdir -p "$HOME/.claude"
{
  printf 'claude-setup %s, installed %s\n' "$commit" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'node %s, pnpm via corepack, docker %s\n' "$(node --version 2>/dev/null || echo none)" "$(docker --version 2>/dev/null | awk '{print $3}' | tr -d , || echo none)"
  if [ "${#warnings[@]}" -eq 0 ]; then
    printf 'warnings: none\n'
  else
    printf 'warning: %s\n' "${warnings[@]}"
  fi
} > "$HOME/.claude/claude-setup.status"
cat "$HOME/.claude/claude-setup.status"
