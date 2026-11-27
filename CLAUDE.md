# User instructions

The same file is used on every machine. Each repository's own `CLAUDE.md` says where its work happens and which commands to run, and that file wins for its repository.

In a cloud session, `~/.claude/claude-setup.status` says which tools this VM was given and whether setup warned about anything. Read it when a tool seems to be missing. Memory carries between sessions through `outerpale-mem`: each repository's memory is in OneDrive `Claude/memory/<repo>/`, loaded at session start. Save what a future session should know there; what holds across repositories (about Harry, how he works, his environment, cross-project lessons) goes in the global memory, `outerpale-mem-global`, in `Claude/memory/_global/`. A rule that must always hold goes in a `CLAUDE.md` instead.

## 1. Think before coding

- State your assumptions. If you are unsure, ask.
- If there is more than one reading, say so; don't pick one silently.
- If a simpler approach exists, say so, and push back when it is warranted.
- If something is unclear, stop, name what is confusing, and ask.
- Treat design talk as work in progress. Don't build, commit or record what I say as decided until I say to go ahead.

## 2. Simplicity first

Write the minimum that solves the problem, with nothing speculative: no extra features, no single-use abstractions, no configurability nobody asked for, no handling for impossible cases. If 200 lines could be 50, rewrite it.

## 3. Surgical changes

- Touch only what the request needs. Match the existing style.
- Don't improve adjacent code, comments or formatting, and don't refactor what isn't broken.
- Mention unrelated dead code; don't delete it. Remove only what your own change left unused.

## 4. Done means a check passed

Turn each task into a check that can run, such as a test, a script or a command with expected output. Write the check first, and the task is done when it passes. Say which check you ran and what it printed. If something can't be checked, say so plainly.

## Docs and scratch

- Work runs through GSD. Its `.planning/` (roadmap, state, each phase's context and plan) is the project's plan and is committed with the work. One Linear issue is one GSD phase.
- In a GSD project, set `claude_md_assembly.mode` to `link` (`/gsd-settings`), so GSD's sections live in `.planning/` and `CLAUDE.md` only needs `@.planning/...` lines, which belong in the project's `projects/<repo>.md`.
- Scratch and review reports go in `.work/`, which is never committed (the startup hook keeps it out of git).

## Setup improvement advice

Tell me when any of these happen:

- Claude gets a convention or command wrong twice.
- I keep typing the same prompt to start a task.
- I paste the same playbook or procedure for the third time.
- I keep copying data from a browser tab or app Claude can't see.
- Claude reads many files to find where a symbol is defined or used.
- A side task floods the conversation with output I won't use again.
- Something should happen every time without being asked.
- A second repository needs the same setup.

When a rule, command or gotcha for this project emerges, suggest adding it to the project's `CLAUDE.md` with the `outerpale-startup:project-claude-md` skill. A project's `CLAUDE.md` is stored in claude-setup's `projects/`, never in its own repository.
