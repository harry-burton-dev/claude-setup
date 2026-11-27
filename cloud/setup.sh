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

# Plugins for this environment only, on top of plugins.lock (which every machine gets).
# Plugins are never committed to project repositories: a project's environment lists its own here.
# One per line: plugin@marketplace  marketplace-source (owner/repo or git URL)
ENV_PLUGINS="
"

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
else
  # Claude cloud VMs put /opt/node22/bin ahead of /usr/local/bin on PATH, so n replaces the node there.
  n_prefix=/usr/local
  [ -d /opt/node22/bin ] && n_prefix=/opt/node22
  if npm install -g -s n >/dev/null 2>&1; then
    N_PREFIX="$n_prefix" n -q "$NODE_MAJOR" >/dev/null 2>&1 || true
  fi
  hash -r
  if node --version 2>/dev/null | grep -q "^v$NODE_MAJOR\."; then
    log "node $(node --version) installed in $n_prefix"
  else
    warn "node $(node --version 2>/dev/null || echo none) on PATH, not v$NODE_MAJOR (is nodejs.org allowed? which -a node: $(which -a node | tr '\n' ' '))"
  fi
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
plugins_lock="$(mktemp)"
cat "$src/plugins.lock" > "$plugins_lock"
printf '%s\n' "$ENV_PLUGINS" >> "$plugins_lock"
PLUGINS_LOCK="$plugins_lock" bash "$src/install.sh"
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
