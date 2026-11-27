# Workflow

How Harry's Claude setup fits together, as built on 27 Nov 2026. Where something is planned but not built, it says so.

## The rule behind it

Project repositories hold code and nothing about Claude. Everything Claude needs lives here, in claude-setup, or on the claude.ai account.

## Layers

| Layer | Where it lives | When it runs | What it gives |
|---|---|---|---|
| Account | claude.ai plugins and connectors | Every session, everywhere | Linear, GitHub, Google, Sentry, Todoist connectors; general plugins (`engineering`, `code-review`, …) |
| Machine | `install.sh` here, run by hand on the PC and server, and by `cloud/bootstrap.sh` → `cloud/setup.sh` on each cloud VM build | Once per install or VM build | `~/.claude/CLAUDE.md` (generic rules), the plugins in `plugins.lock`, Node 26 and tools on cloud VMs |
| Session | The `outerpale-startup` plugin's SessionStart hook | Every session start | The repository's project `CLAUDE.md`, copied from `projects/<repo>.md` |
| Project | `projects/<repo>.md` here | Loaded as `./CLAUDE.md` | That project's commands, rules and gotchas |

## Plugins every machine installs (`plugins.lock`)

| Plugin | From | Does |
|---|---|---|
| `egm` | google/elephant-goldfish-model | Design docs: `/egm:egm-brainstorm` → `/egm:egm-draft` → `/egm:egm-review`, plus drift reports against the code. Vanilla, no templates of Harry's own |
| `outerpale-devops` | harry-burton-dev/outerpale-devops | Ties threads to Linear epics and issues in the Outer-Pale workspace only; the epic question at the start of a thread; `epics/` and `masters/` folder rules; Langfuse traces |
| `outerpale-startup` | this repository's marketplace | Project `CLAUDE.md` at session start; `project-claude-md` skill to write one to Anthropic's guidance |

## A session, start to finish

1. **VM build (cloud only, about weekly):** the environment's pasted `cloud/bootstrap.sh` clones claude-setup `main` and runs `cloud/setup.sh`. Status in `~/.claude/claude-setup.status`.
2. **Session start:** `outerpale-startup` puts `./CLAUDE.md` in place, or says it looked and asks to write one. `outerpale-devops` asks whether the thread is an epic, "no epic", or "not Outer-Pale work".
3. **Work:** on a branch, with a pull request. Design work goes through EGM. Linear issues are started and closed with `outerpale-devops:start-issue` and `close-issue`.
4. **As rules emerge:** Claude suggests additions to the project `CLAUDE.md`; on a yes, the skill opens a PR to `projects/<repo>.md` here.
5. **Changing the setup itself:** edit this repository, `tests/test.sh`, PR, merge. Claude may merge PRs in claude-setup when Harry has said so in that session.

## Cloud environments

| Environment | Setup script | Notes |
|---|---|---|
| Outer-Pale | `cloud/bootstrap.sh` (plus a temporary marker test) | Unrestricted network |
| Default | None yet | Paste `cloud/bootstrap.sh` to give other repositories the setup |

A pushed change reaches an environment on its next VM build: within 7 days, or at once after any edit to the pasted script.

## Known gaps

- Mid-session suggestions for the project `CLAUDE.md` depend on Claude following one line in the generic `CLAUDE.md`. A hook is agreed but not built.
- Unconfirmed: whether a file the setup script writes into a checkout survives a cached VM start (the marker test).
- Langfuse needs keys that cloud sessions don't have, so cloud sessions send no traces.

## Next: Linear in the wider workflow

`outerpale-devops` works, but on its own terms. Where it doesn't yet fit the rest:

| Gap | Today | Fit with the rule above |
|---|---|---|
| Project files | It wants `CLAUDE.md`, `.claude/settings.json` and a `.gitignore` line committed in the project | Its `CLAUDE.md` content belongs in `projects/<repo>.md`; `.linear-link/` can go in `.git/info/exclude` at session start |
| Where `epics/` and `masters/` live | In the project's git repository | Decide: in the code repository, or in claude-setup alongside `projects/` |
| Design docs | EGM writes to the working folder | Point EGM at the current epic's folder with its `EGM artifact directory:` line |
| Pull requests | Session branches are `claude/…`; nothing links a PR to its issue | Put the issue ID (`OUT-123`) in the PR title or body so Linear links them, and close the issue when the PR merges |
| Telemetry | Langfuse keys only on the PC | Keys through the environment's secrets, if cloud traces are wanted |
