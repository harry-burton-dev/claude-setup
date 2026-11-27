# claude-setup

This is Harry's user-level Claude Code setup: the same instructions and tools on the PC, on the server and on every Claude cloud VM. It holds no secrets, so it can be public. Cloud setup scripts clone it without credentials.

| File | What it is |
|---|---|
| `CLAUDE.md` | The user instructions. Installed as `~/.claude/CLAUDE.md` |
| `skills.lock` | Skills to install, each pinned to a commit. Empty for now |
| `plugins.lock` | Plugins every machine gets, at user scope: EGM (Google's Elephant-Goldfish Model) for design docs, and `outerpale-devops`. A plugin for one project goes in `ENV_PLUGINS` in that environment's pasted `cloud/bootstrap.sh`, never in the project repository |
| `plugins/outerpale-startup/` | A plugin, from this repository's own marketplace (`.claude-plugin/marketplace.json`). At session start it copies `projects/<repo>.md` to the repository's `./CLAUDE.md`, kept out of git, or asks to write one with its `project-claude-md` skill. During a session it prompts Claude to suggest an addition after a correction, or when a project command has run three times. It also carries the intent reviewer; see `docs/workflow.md` |
| `plugins/outerpale-mem/` | Memory that survives cloud sessions: each repository's memory in OneDrive `Claude/memory/<repo>/`, in auto memory's format, loaded at session start and consolidated by a nightly dream. See `docs/memory.md` |
| `plugins/outerpale-mem-global/` | Global memory every session shares, in any repository or none: who Harry is, how he works, cross-project lessons, his environment. OneDrive `Claude/memory/_global/`. See `docs/memory.md` |
| `plugins/magister/` | Magister, a background second perspective at design, UI and decision moments, whose findings go to OneDrive `Claude/magister/`. See `docs/magister.md` |
| `plugins/send-to-todoist/` | A mod for the desktop app: right-click selected text to send it to the Todoist Inbox labelled `Claude`, with a tidied title, due date, project and priority. After each reply it offers the action items it found, and can draft a full plan for one in a side pane, which goes to Todoist as a task with subtasks once approved. Uses the claude.ai Todoist connector. Not in `plugins.lock` |
| `projects/` | Each project's `CLAUDE.md`, as `<repo-name>.md`. Project repositories never hold their own |
| `agents/`, `commands/` | Copied into `~/.claude/` if present. None yet |
| `install.sh` | Installs all of the above into `~/.claude`. Safe to run again |
| `cloud/bootstrap.sh` | The script to paste into a claude.ai cloud environment, once. It clones this repository and runs `cloud/setup.sh` |
| `cloud/setup.sh` | What a cloud VM runs: tools, then `install.sh` |
| `templates/repo/` | What each project repository should carry for itself |
| `tests/test.sh` | The tests. `--vm` also runs `cloud/setup.sh` in a fresh `ubuntu:24.04` container |
| `docs/handoff.md` | The latest handoff between sessions: what's live, what isn't verified, what's next |
| `docs/workflow.md` | How the layers fit together, a session start to finish, known gaps, and what's next |
| `docs/cloud-environment.md` | The recommended cloud environment settings, and why |

## Use it

- **PC or server:** `git clone https://github.com/harry-burton-dev/claude-setup ~/claude-setup && ~/claude-setup/install.sh`. Run `git pull && ./install.sh` to update.
- **Cloud:** paste `cloud/bootstrap.sh` into the environment's setup script field, once. See `docs/cloud-environment.md`.

## What goes where

- **Here:** only what every project and every machine should have.
- **In `projects/<repo-name>.md` here:** a project's `CLAUDE.md`. The `outerpale-startup` plugin puts it in place at session start.
- **In a project repository:** anything else about one project. That means its `.claude/settings.json` (hooks and permissions, never plugins), its `.claude/skills/`, and how to run and test it. Cloud sessions load those straight from the repository.
- **On claude.ai:** account-wide plugins and connectors. Don't repeat them here.

## Change it

1. Edit the file.
2. Run `tests/test.sh`, plus `tests/test.sh --vm` on a machine with Docker.
3. Commit and push.

Cloud environments pick up the change when their setup script next runs. That happens when the script or the allowed domains change, or when the 7-day cache expires.
