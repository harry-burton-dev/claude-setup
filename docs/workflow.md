# Workflow

How Harry's Claude setup fits together, as built on 27 Nov 2026. Where something is planned but not built, it says so.

## The rule behind it

Project repositories hold code and nothing about Claude. Everything Claude needs lives here, in claude-setup, or on the claude.ai account.

## Layers

| Layer | Where it lives | When it runs | What it gives |
|---|---|---|---|
| Account | claude.ai plugins and connectors | Every session, everywhere | Linear, GitHub, Google, Sentry, Todoist connectors; general plugins (`engineering`, `code-review`, …) |
| Machine | `install.sh` here, run by hand on the PC and server, and by `cloud/bootstrap.sh` → `cloud/setup.sh` on each cloud VM build | Once per install or VM build | `~/.claude/CLAUDE.md` (generic rules), the plugins in `plugins.lock`, Node 26 and tools on cloud VMs |
| Session | The `outerpale-startup` plugin's SessionStart hook | Every session start | The repository's project `CLAUDE.md`, copied from `projects/<repo>.md`, and `.work/` kept out of git |
| Project | `projects/<repo>.md` here | Loaded as `./CLAUDE.md` | That project's commands, rules and gotchas |

## Plugins every machine installs (`plugins.lock`)

| Plugin | From | Does |
|---|---|---|
| `egm` | google/elephant-goldfish-model | Design docs: `/egm:egm-brainstorm` → `/egm:egm-draft` → `/egm:egm-review`, plus drift reports against the code. Vanilla, no templates of Harry's own |
| `outerpale-devops` | harry-burton-dev/outerpale-devops | Project management in Linear (below): the scope question, one PR per issue, Linear writes to the Outer-Pale workspace only, Langfuse traces. The contract below needs 0.5.0 or later |
| `outerpale-startup` | this repository's marketplace | Project `CLAUDE.md` at session start; `project-claude-md` skill to write one to Anthropic's guidance; the companion and the intent reviewer (below) |

## A session, start to finish

1. **VM build (cloud only, about weekly):** the environment's pasted `cloud/bootstrap.sh` clones claude-setup `main` and runs `cloud/setup.sh`. Status in `~/.claude/claude-setup.status`.
2. **Session start:** `outerpale-startup` puts `./CLAUDE.md` in place, or says it looked and asks to write one. `outerpale-devops` asks which Linear issue, project or initiative the session is for, or none.
3. **Work:** by the contract below. One issue, one branch, one PR.
4. **As rules emerge:** when you correct Claude, or a project command has been run three times, `outerpale-startup` prompts Claude to offer a one-line addition to the project `CLAUDE.md`; on a yes, the skill opens a PR to `projects/<repo>.md` here.
5. **Changing the setup itself:** edit this repository, `tests/test.sh`, PR, merge. Claude may merge PRs in claude-setup when Harry has said so in that session.

## The companion

A second perspective that makes the work better, without being asked and without interrupting. At design, UI and decision moments a hook reminds Claude of it; Claude decides whether it would add something, and if so runs `outerpale-startup:companion` in the background. It picks the lenses that help most: **research** (best practice, recent work, with sources), **analysis** (intent against what is being built, assumptions, rules taken too literally), **support** (a choice is sound and should stay) and **alternatives** (examples, another perspective, a built variant). It may say "nothing material to add".

- **Where findings go:** Harry's own log, not the project's: one Markdown file per finding, with a quoted-YAML header, in OneDrive `Claude/companion/`, through the Microsoft 365 connector. Variants are uploaded beside it as `<finding>--<variant>.<ext>`. A viewer lists the folder.
- **How you hear about it:** a short `Companion:` note at the end of a later reply, with the OneDrive link. Deep research is only ever offered ("say 'research it'").
- **What it can touch:** a hook holds it to `.work/` and `~/.companion/`, with no shell. Findings wait in `~/.companion/outbox/` until uploaded; a hook clears each one once it reaches OneDrive, and session start flags any left behind.
- **Intent reviewer:** `outerpale-startup:intent-reviewer`, read-only, checks a branch's diff against its issue's goal and design intent before the PR opens (`outerpale-devops:start-issue`).

## Cloud environments

| Environment | Setup script | Notes |
|---|---|---|
| Outer-Pale | `cloud/bootstrap.sh` (plus a temporary marker test) | Unrestricted network |
| Default | None yet | Paste `cloud/bootstrap.sh` to give other repositories the setup |

A pushed change reaches an environment on its next VM build: within 7 days, or at once after any edit to the pasted script.

## Known gaps

- Unconfirmed: whether a file the setup script writes into a checkout survives a cached VM start (the marker test).
- Langfuse needs keys that cloud sessions don't have, so cloud sessions send no traces.
- EGM's own reviews are thrown away with `.work/`; nothing keeps a record of them yet.

## Project management in Linear

Linear is the record of what is being done. Initiative → project → issue; every PR belongs to one issue, and an issue has one PR.

| Session | Works on | Produces | Linked in Linear by |
|---|---|---|---|
| Design | A project or initiative, through its "Design: …" issue | A design doc in `docs/design/<slug>.md` (EGM's working files in `.work/egm/`) | The design issue's PR, and a link on the project |
| Review and breakdown | A project | The project's issues, each with its implementation plan in the description (`outerpale-devops:break-down`) | The issues themselves |
| Build | One issue | One PR, titled `OUT-123: …` with `Fixes OUT-123` in the body | Linear's GitHub integration, from the ID |
| Other | None | Anything | Nothing |

- **Status sync is Linear's.** The GitHub integration links a PR from the issue ID and moves the issue when the PR merges. Claude moves an issue to In Progress when a session starts on it (`start-issue`), and never sets Done by hand.
- **A builder finds everything from its issue:** the plan in the description, the design doc through its link.
- **Enforced:** `outerpale-devops` refuses a PR without the session's issue ID, or, in a project or initiative session, without any issue ID.
- **In the repository:** only code and `docs/design/`. Scratch, plans and reviews go in `.work/`, which never reaches git.
- **Not designed yet:** the issue builder, and orchestration of agents across a project's issues. This contract is what they will hand out and collect.
