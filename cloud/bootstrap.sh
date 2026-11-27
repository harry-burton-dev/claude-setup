#!/usr/bin/env bash
# Paste this file into a claude.ai cloud environment's "Setup script" field, once.
# It clones claude-setup and runs cloud/setup.sh from the clone, so changes to the repository
# reach the environment on its next build with nothing to paste again.
set -euo pipefail

# Plugins for this environment only, on top of plugins.lock (which every machine gets).
# Plugins are never committed to project repositories: a project's environment lists its own here.
# One per line: plugin@marketplace  marketplace-source (owner/repo or git URL)
export ENV_PLUGINS="
"

rm -rf /opt/claude-setup
git clone -q --depth 1 --branch main https://github.com/harry-burton-dev/claude-setup.git /opt/claude-setup
bash /opt/claude-setup/cloud/setup.sh
