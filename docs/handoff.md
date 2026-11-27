# Handoff, 27 Nov 2026

The state of Harry's Claude setup at the end of the session that built most of it. How the pieces fit is in `docs/workflow.md`. This page covers what's live, what isn't verified yet, and what comes next.

## What's live

| Piece | Where | Version | Docs |
|---|---|---|---|
| User `CLAUDE.md`, `install.sh`, `cloud/bootstrap.sh` → `cloud/setup.sh` | claude-setup | `main` | `README.md`, `docs/cloud-environment.md` |
| `gsd-core` (the build methodology; replaced EGM) | open-gsd/gsd-core | 1.23.0 | its docs |
| `outerpale-devops`: scope question, one PR per issue, Linear guard | harry-burton-dev/outerpale-devops | 0.7.0 (one Linear issue per GSD phase) | its README |
| `outerpale-startup`: project `CLAUDE.md` from `projects/`, `.work/` kept out of git, suggestion hooks, intent reviewer | claude-setup `plugins/` | 0.5.0 | `docs/workflow.md` |
| `magister`: background second perspective, findings in OneDrive `Claude/magister/` | claude-setup `plugins/` | 0.1.0 | `docs/magister.md` |
| `outerpale-mem`: repository memory in OneDrive `Claude/memory/<repo>/` | claude-setup `plugins/` | 0.2.0 | `docs/memory.md` |
| `outerpale-mem-global`: global memory in OneDrive `Claude/memory/_global/` | claude-setup `plugins/` | 0.1.0 | `docs/memory.md` |
| Nightly dream: scheduled task "outerpale-mem nightly dream", 03:42 London, Microsoft 365 connector attached | claude.ai | | `docs/memory.md` |
| Tracing: Langfuse's `langfuse-observability` plugin to Harry's Langfuse | `plugins.lock`; keys as a network secret | 1.2.2 | `docs/workflow.md`, Known gaps |

The Outer-Pale cloud environment runs exactly `cloud/bootstrap.sh`; the temporary marker test has been removed. The Default environment has no setup script.

## Memory seeded

Six proposals are pending in OneDrive; the first nightly dream will consolidate them:

- **Global memory, 5 proposals:**
  - cloud session quirks;
  - how Langfuse tracing is wired;
  - the OneDrive connector;
  - how Harry works;
  - his profile.
- **`claude-setup` memory, 1 proposal:** merges and tests.

## Not yet verified

1. **Tracing, from a new session.** Switched to the `langfuse-observability` plugin on 27 Nov. Checked that day from a cloud VM: with the network secret saved, a POST with placeholder auth to `harry-msi-server.tailfb071b.ts.net/api/public/otel/v1/traces` returns 200 (401 without the secret), and the plugin's hook, run on its own `tool_turn` fixture with placeholder keys, flushed four spans carrying `langfuse.observation.input` and `.output` with no export errors. In a new session, check the plugin is enabled, then look in Langfuse for a "Claude Code - Turn" trace with Input and Output filled; if none, read `~/.claude/state/langfuse_hook.log`.
2. **The first nightly dream (28 Nov, 03:42).** Look for `Claude/memory/*/dreams/2026-11-28.md` and `.committed` markers.
3. **Whether the new plugins load in a fresh session.** Mostly confirmed on 27 Nov, in a session built from `ddac595`: all six `plugins.lock` plugins were enabled at the versions above; the scope question, the global memory loader and the correction hook fired; Magister ran and uploaded its note; and both outboxes emptied after upload. Still to see: the Stop gate, and the intent reviewer in an issue session.
4. **Repository memory in a session with several repositories.** Resolved in code by `outerpale-mem` 0.2.0, which asks for each repository's memory by name, and `tests/test.sh` covers it. Still to see: a fresh session with claude-setup and outerpale-devops loads both.

## Next

- **Harry:**
  - start a new Outer-Pale session to confirm tracing;
  - paste `cloud/bootstrap.sh` into the Default environment, if other repositories should get the setup;
  - run `install.sh` on the PC and server, and set the `LANGFUSE_*` variables there locally for the Langfuse plugin (keeping the keys out of any committed file);
  - build the viewer against `docs/magister.md` and `docs/memory.md`.
- **Build system:** the research report (sent as a zip, not in this repo) recommends four phases, each closed by a check:
  - **0:** branch protection and a PR-title CI check;
  - **1:** a `build-issue` skill, with the intent reviewer and a Stop hook that runs the project's check;
  - **2:** independent review and `/autofix-pr`;
  - **3:** `break-down`, already built, plus a readiness review;
  - **4:** a dispatch orchestrator, at most 2–3 sessions at a time, later trialling Claude Projects.

  Phase 0 is next.
- **Magister:**
  - a harder eval set: subtle flaws, sound designs that already cover the obvious gap, and genuine trade-offs;
  - turn findings rated noise or wrong into new eval cases;
  - measure whether its trigger fires at the right moments.
- **Memory:** run a memory-on versus memory-off comparison on real tasks once there is some memory.

## Loose ends to decide

- **Conflicting rules:** `README.md` "What goes where" still lets project repositories hold `.claude/settings.json` and `.claude/skills/`, while `docs/workflow.md` says they hold nothing about Claude.
- **Overlap:** `templates/repo/CLAUDE.md` overlaps with the `project-claude-md` skill.
- **Dead pattern:** `outerpale-devops`'s `scripts/week-audit.js` still counts the old "UNFILED" message.
