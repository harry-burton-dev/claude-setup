# outerpale-devops

Claude Code plugin for Outer-Pale project management in Linear: session scope, one PR per issue, Linear writes to Outer-Pale only. Plain Node 18+ CommonJS, no dependencies.

# Commands

- Test: `node --test tests/`. No CI runs it, so run it before every push.
- Try a working copy: `claude --plugin-dir <path to this repo>`. Connectors (Linear, GitHub) don't load in `claude -p`, so check connector behaviour in a real session or a subagent.

# Releasing

- Every change bumps `version` in `.claude-plugin/plugin.json` and adds a `CHANGELOG.md` entry. Without the bump, installs don't update.
- Other sessions merge to `main` in parallel, and two branches can claim the same version. Before opening or updating a PR, merge `main` and take the next free version.
- Harry approves each PR here; Claude doesn't merge.

# Conventions

- Hooks fail open on any internal error, except before a Linear write, which they refuse (`hooks/run.js` header).
- Session state lives in `~/.linear-link/sessions/`, never in the project's repository. Tests use a fake `HOME`.
- A behaviour change starts with a test in `tests/contract.test.js` that fails first.
- Skills set the scope through `scripts/ll.js scope …`; the hooks only read prompts.

# Gotchas

- Don't install alongside endstate-ops or linear-link: they answer the same hooks.
