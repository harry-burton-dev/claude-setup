# Workflow

How Harry's Claude setup fits together, as built on 27 Nov 2026. Where something is planned but not built, it says so.

## The rule behind it

Project repositories hold code and nothing about Claude. Everything Claude needs lives here, in claude-setup, or on the claude.ai account.

## Layers

| Layer | Where it lives | When it runs | What it gives |
|---|---|---|---|
| Account | claude.ai plugins and connectors | Every session, everywhere | Linear, GitHub, Google, Sentry, Todoist connectors; general plugins (`engineering`, `code-review`, …) |
| Machine | `install.sh` here, run by hand on the PC and server, and by `cloud/bootstrap.sh` → `cloud/setup.sh` on each cloud VM build | Once per install or VM build | `~/.claude/CLAUDE.md` (generic rules), the plugins in `plugins.lock`, Node 26 and tools on cloud VMs |
| Session | The `outerpale-startup` plugin's SessionStart hook | Every session start | Each repository's project `CLAUDE.md`, copied from `projects/<repo>.md`, and `.work/` kept out of git: the repository the session starts in, or, when it starts in a non-git folder (a cloud session with several repositories), each git repository directly under it |
| Project | `projects/<repo>.md` here | Loaded as `./CLAUDE.md` | That project's commands, rules and gotchas |
| Global memory | OneDrive `Claude/memory/_global/` | Loaded in every session by `outerpale-mem-global`; consolidated nightly | About Harry, how he works, his environment, cross-project lessons |
| Memory | OneDrive `Claude/memory/<repo>/` | Loaded at session start by `outerpale-mem`; consolidated nightly | What past sessions learned: decisions, preferences, patterns, known issues |

## Plugins every machine installs (`plugins.lock`)

| Plugin | From | Does |
|---|---|---|
| `gsd-core` | open-gsd/gsd-core | The build methodology: discuss → plan → execute → verify → ship, one phase at a time, in fresh-context subagents. State in `.planning/`, committed |
| `outerpale-devops` | harry-burton-dev/outerpale-devops | Project management in Linear (below): the scope question, one PR per issue, Linear writes to the Outer-Pale workspace only. The contract below needs 0.5.0 or later |
| `outerpale-startup` | this repository's marketplace | Project `CLAUDE.md` at session start; `project-claude-md` skill to write one to Anthropic's guidance; the intent reviewer (below) |
| `outerpale-mem` | this repository's marketplace | Memory across sessions, in OneDrive (`docs/memory.md`) |
| `outerpale-mem-global` | this repository's marketplace | Global memory every session shares (`docs/memory.md`) |
| `magister` | this repository's marketplace | Magister, the background second perspective (below) |

## A session, start to finish

1. **VM build (cloud only, about weekly):** the environment's pasted `cloud/bootstrap.sh` clones claude-setup `main` and runs `cloud/setup.sh`. Status in `~/.claude/claude-setup.status`.
2. **Session start:** `outerpale-startup` puts `./CLAUDE.md` in place, or says it looked and asks to write one. `outerpale-devops` asks which Linear issue, project or initiative the session is for, or none.
3. **Work:** by the contract below. One issue, one branch, one PR.
4. **As rules emerge:** when you correct Claude, or a project command has been run three times, `outerpale-startup` prompts Claude to offer a one-line addition to the project `CLAUDE.md`; on a yes, the skill opens a PR to `projects/<repo>.md` here.
5. **Changing the setup itself:** edit this repository, `tests/test.sh`, PR, merge. A hook that works per repository must cover each one: a cloud session with several repositories starts in their non-git parent folder. Find them as `outerpale-startup`'s session-start hook does, and test three cases: one repository, a parent folder holding two, and a folder holding none. Claude may merge PRs in claude-setup when Harry has said so in that session.

## Magister

A second perspective that makes the work better, without being asked and without interrupting. It is its own plugin, `magister`. At design, UI and decision moments a hook reminds Claude of it; Claude decides whether it would add something, and if so runs `magister:magister` in the background. It picks the lenses that help most: **research** (best practice, recent work, with sources), **analysis** (intent against what is being built, assumptions, rules taken too literally), **support** (a choice is sound and should stay) and **alternatives** (examples, another perspective, a built variant). It may say "nothing material to add".

- **Where findings go:** Harry's own log, not the project's: one Markdown file per finding, with a quoted-YAML header, in OneDrive `Claude/magister/`, through the Microsoft 365 connector. Variants are uploaded beside it as `<finding>--<variant>.<ext>` and listed in its `attachments`. The viewer's contract, including ratings, is in `docs/magister.md`.
- **How you hear about it:** a short `Magister:` note at the end of a later reply, with the OneDrive link. Deep research is only ever offered ("say 'research it'").
- **What it can touch:** a hook holds it to `.work/` and `~/.magister/`, with no shell. Findings wait in `~/.magister/outbox/` until uploaded; a hook clears each one once it reaches OneDrive, and session start flags any left behind.
- **Evals:** `tests/evals/magister/` (see `docs/magister.md`).

The intent reviewer, `outerpale-startup:intent-reviewer`, read-only, checks a branch's diff against its issue's goal and design intent before the PR opens (`outerpale-devops:build-issue`).

## Cloud environments

| Environment | Setup script | Notes |
|---|---|---|
| Outer-Pale | `cloud/bootstrap.sh` (plus a temporary marker test) | Unrestricted network |
| Default | None yet | Paste `cloud/bootstrap.sh` to give other repositories the setup |

A pushed change reaches an environment on its next VM build: within 7 days, or at once after any edit to the pasted script.

## Known gaps

- Unconfirmed: whether a file the setup script writes into a checkout survives a cached VM start (the marker test).
- Session traces go to Langfuse through Langfuse's `langfuse-observability` plugin (`plugins.lock`). Its Stop and SessionEnd hook reads the transcript and sends each turn with its prompt, model output and tool calls as Input and Output. Claude Code's own OpenTelemetry export was dropped on 27 Nov 2026: its spans carry content only in attributes Langfuse doesn't map (`user_prompt`, a `tool.output` event), and no model output without debug-only detailed tracing. In cloud the keys are a network secret on the Funnel host, and the environment holds only `LANGFUSE_BASE_URL`, placeholder keys and `CC_LANGFUSE_CAPTURE_IMAGES=false` (the Funnel exposes only `/api/public/otel`, not media upload). On a local machine set the real `LANGFUSE_*` variables, or use `/plugin configure`. The hook's log is `~/.claude/state/langfuse_hook.log`; `CC_LANGFUSE_DEBUG=true` adds detail.

## Project management in Linear

Linear is the record of what is being done. Initiative → project → issue; every PR belongs to one issue, and an issue has one PR.

| Session | Works on | Produces | Linked in Linear by |
|---|---|---|---|
| Design | A project or initiative, through its "Design: …" issue | GSD's roadmap and phases in `.planning/`, through its discuss and plan steps | The design issue's PR, and a link on the project |
| Review and breakdown | A project | One Linear issue per GSD phase: goal, acceptance criteria and a link to the phase (`outerpale-devops:break-down`) | The issues themselves |
| Build | One issue, which is one GSD phase | The phase executed and verified by GSD, then one PR titled `OUT-123: …` with `Fixes OUT-123` in the body | Linear's GitHub integration, from the ID |
| Other | None | Anything | Nothing |

- **Status sync is Linear's.** The GitHub integration links a PR from the issue ID and moves the issue when the PR merges. Claude moves an issue to In Progress when a session starts on it (`build-issue`), and never sets Done by hand.
- **Linear holds what and when; `.planning/` holds how.** A builder finds its phase from the issue. The plan is the phase's `PLAN.md`, written and read by GSD's agents, never by hand.
- **Enforced:** `outerpale-devops` refuses a PR without the session's issue ID, or, in a project or initiative session, without any issue ID.
- **In the repository:** code and GSD's `.planning/`. Scratch and reviews go in `.work/`, which never reaches git.
- **Building and orchestration are GSD's:** `/gsd-execute-phase` runs plans in parallel waves of fresh-context subagents, and `/gsd-manager` and `/gsd-autonomous` drive several phases. What remains is phase 0 of the research report: branch protection and a PR-title check.
