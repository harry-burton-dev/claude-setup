# claude-setup

This is Harry's user-level Claude Code setup: the same instructions and tools on the PC, on the server and on every Claude cloud VM. It holds no secrets, so it can be public. Cloud setup scripts clone it without credentials.

| File | What it is |
|---|---|
| `CLAUDE.md` | The user instructions. Installed as `~/.claude/CLAUDE.md` |
| `skills.lock` | Skills to install, each pinned to a commit. Empty for now |
| `plugins.lock` | Plugins every machine gets, at user scope. Empty for now. A plugin for one project goes in `ENV_PLUGINS` in that environment's copy of `cloud/setup.sh`, never in the project repository |
| `agents/`, `commands/` | Copied into `~/.claude/` if present. None yet |
| `install.sh` | Installs all of the above into `~/.claude`. Safe to run again |
| `cloud/setup.sh` | The script to paste into a claude.ai cloud environment |
| `templates/repo/` | What each project repository should carry for itself |
| `tests/test.sh` | The tests. `--vm` also runs `cloud/setup.sh` in a fresh `ubuntu:24.04` container |
| `docs/cloud-environment.md` | The recommended cloud environment settings, and why |

## Use it

- **PC or server:** `git clone https://github.com/harry-burton-dev/claude-setup ~/claude-setup && ~/claude-setup/install.sh`. Run `git pull && ./install.sh` to update.
- **Cloud:** paste `cloud/setup.sh` into the environment's setup script field. See `docs/cloud-environment.md`.

## What goes where

- **Here:** only what every project and every machine should have.
- **In a project repository:** anything about one project. That means its `CLAUDE.md`, its `.claude/settings.json` (hooks and permissions, never plugins), its `.claude/skills/`, and how to run and test it. Cloud sessions load those straight from the repository.
- **On claude.ai:** account-wide plugins and connectors. Don't repeat them here.

## Change it

1. Edit the file.
2. Run `tests/test.sh`, plus `tests/test.sh --vm` on a machine with Docker.
3. Commit and push.

Cloud environments pick up the change when their setup script next runs. That happens when the script or the allowed domains change, or when the 7-day cache expires.
