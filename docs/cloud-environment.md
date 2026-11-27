# Cloud environment settings

Checked against code.claude.com on 26 Nov 2026 (cloud-environments, claude-code-on-the-web, routines and plugins/install).

## Settings

| Setting | Use | Why |
|---|---|---|
| **Setup script** | `cloud/setup.sh`, pasted in (64 KB limit) | It runs as root on Ubuntu 24.04. The result is cached for about 7 days, and the script runs again when it or the allowed domains change |
| **Network access** | **Limited**, with **Allow package managers** ticked | The default list already covers GitHub, npm, Docker Hub and ghcr.io. Full access is not needed |
| **Allowed domains** | `nodejs.org` | Node 26 is downloaded from there. Add a project's own registries (for example `quay.io` for Debezium images) in **that project's** environment, not here |
| **Environment variables** | None in the generic environment | Tokens go into a project's environment, never into the setup script, which is not secret |
| **Number of environments** | One generic environment, plus one per project whose domains or secrets differ | Each environment has its own allowlist and variables |

## What a cloud VM gets, and from where

| Thing | Comes from | Notes |
|---|---|---|
| User `CLAUDE.md` | `cloud/setup.sh`, through `install.sh` | Documented to load. Check it with `/context`, under Memory files |
| Skills, agents, commands in `~/.claude` | `install.sh` | **Not confirmed by the docs.** The docs only promise skills from the repository's `.claude/` and from claude.ai. Check them in the first session |
| Plugins in `plugins.lock` and the script's `ENV_PLUGINS` | `install.sh`, through `claude plugin install` | Documented as a setup-script use, but the docs do not confirm they load. Check them in the first session |
| Plugins and connectors on claude.ai | Your account | They load in cloud sessions |
| Project `CLAUDE.md`, `.claude/settings.json`, `.claude/skills/` | The repository | Loaded in a single-repository session, not in project threads |
| User `settings.json` hooks | Nothing | **User-level hooks do not run in the cloud.** Put hooks in the repository |
| Memory | Nothing | It does not carry between cloud sessions |
| Docker and `docker compose` | Already on the VM | Containers and background services must be started again in every session |
| Node 26, pnpm, jq, shellcheck, ripgrep | `cloud/setup.sh` | Node 22 is already installed in `/opt/node22`, which comes before `/usr/local/bin` on a session's PATH, so the script installs 26 over it there. If `node --version` still isn't 26 afterwards, the status file has a warning. The script also puts corepack back, because Node 25 and later no longer bundle it |

## Limits that shape how projects run in the cloud

- **Commands time out** after 2 minutes by default, and 10 minutes at most. Run long work, such as bringing up a full Compose stack, in the background.
- **Idle VMs pause** and can be reclaimed. Nothing running survives, only files do.
- **GitHub access** goes through a proxy, and only for the repositories attached to the session. Cloning a public repository such as this one is expected to work, because `github.com` is on the allowlist, but the docs do not say so outright. If the clone fails, attach `claude-setup` to the environment as a second repository and set `SETUP_SRC` to its path.
- **Running when your PC is off:** sessions and routines (`/schedule`: hourly at most, plus API triggers and GitHub pull request, release and issue events) run on Anthropic's machines. Auto-fix watches pull requests for CI failures and review comments.

## First-session checklist

Run these once, in a new session, after you change the environment:

1. `cat ~/.claude/claude-setup.status`. It should say `warnings: none`.
2. `/context`. `/root/.claude/CLAUDE.md` should be listed under Memory files.
3. `node --version` should print v26, and `pnpm --version` should print a version.
4. Once skills or plugins are listed: check that they show in the skill and plugin lists. If they don't, move them into each repository's `.claude/`, which is documented to load.

## Claude.ai account plugins

These load everywhere, cloud included, so every one costs context in every session. Enabled on 26 Nov 2026:

- **Coding:** `code-review`, `engineering`, `ci-optimizer`, `claude-code-setup`, `github`, `frontend-design`
- **Not coding:** `product-management`, `design`, `productivity`, `cowork-plugin-management`, `project-artifact`, `langfuse`, `deeper-tasks`
- **Desktop only, no use in the cloud:** `desktop-commander`
- **One project only:** `outerpale-devops`. Take it off the account and list it in `ENV_PLUGINS` in the Outer-Pale environment's setup script. Plugins are never committed to project repositories

Turn off what a coding session doesn't need, at https://claude.ai/customize/plugins.
