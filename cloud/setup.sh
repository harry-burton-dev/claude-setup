#!/usr/bin/env bash
# Claude Code cloud environment setup script.
# Paste this file into the environment's "Setup script" field on claude.ai.
# It runs as root on Ubuntu 24.04 the first time a session starts in the environment.
# The resulting filesystem is cached for about 7 days, and the script runs again whenever
# it, or the allowed domains, change. Background processes do not survive the cache.
#
# Allowed domains it needs besides the default list: nodejs.org (for Node $NODE_MAJOR).
set -euo pipefail

SETUP_REPO="https://github.com/harry-burton-dev/claude-setup.git"   # public, holds no secrets
SETUP_REF="main"
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
if node --version 2>/dev/null | grep -q "^v$NODE_MAJOR\."; then
  log "node $(node --version) already present"
elif npm install -g -s n >/dev/null 2>&1 && n -q "$NODE_MAJOR" >/dev/null 2>&1; then
  hash -r
  log "node $(node --version) installed"
else
  warn "node $NODE_MAJOR not installed (is nodejs.org allowed?); keeping $(node --version 2>/dev/null || echo none)"
fi
# Node 25 and later no longer bundle corepack, so it is installed from npm first.
if { command -v corepack >/dev/null 2>&1 || npm install -g -s corepack >/dev/null 2>&1; } && corepack enable >/dev/null 2>&1; then
  log "corepack enabled (pnpm and yarn follow each repo's packageManager field)"
else
  warn "corepack enable failed"
fi

# 3. The user-level Claude setup: CLAUDE.md, skills, agents, commands and plugins.
#    SETUP_SRC lets a test point at a local copy instead of cloning.
src="${SETUP_SRC:-/opt/claude-setup}"
if [ -z "${SETUP_SRC:-}" ]; then
  rm -rf "$src"
  git clone -q --depth 1 --branch "$SETUP_REF" "$SETUP_REPO" "$src"
fi
"$src/install.sh"
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
