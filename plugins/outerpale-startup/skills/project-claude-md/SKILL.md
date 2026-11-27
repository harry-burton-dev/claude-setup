---
name: project-claude-md
description: Write or update a repository's project CLAUDE.md with the user, to Anthropic's guidance, and save it to claude-setup's projects/<repo>.md. Use when the session-start hook reports no project CLAUDE.md, when the user asks to write or review one, or mid-session when a rule, command or gotcha for this project emerges that belongs in it (suggest it first, write only on a yes).
---

A project's `CLAUDE.md` never lives in its own repository. The stored copy is `projects/<repo>.md` in `harry-burton-dev/claude-setup`, where `<repo>` is the repository folder's name. The outerpale-startup session-start hook copies it to `./CLAUDE.md` in each session, and keeps it out of git there. So an edit to `./CLAUDE.md` alone is lost; it has to go back to claude-setup.

## What goes in (Anthropic's guidance)

Sources: https://code.claude.com/docs/en/memory.md and https://code.claude.com/docs/en/best-practices.md.

- Only what Claude can't work out from the code: the exact install, test, typecheck and lint commands; where the code misleads; decisions that aren't written down in the repo; anything Claude got wrong twice.
- Project-level facts and rules, not personal preferences: those are in the user's `~/.claude/CLAUDE.md` already, so don't repeat them.
- Specific and checkable: "Run `pnpm check` before committing", not "test your changes"; "API handlers live in `src/api/handlers/`", not "keep files organised".
- No architecture or file-layout tour: Claude reads the repository itself.
- Under 200 lines, grouped under headings with bullets, for example `# Commands`, `# Where work happens`, `# Conventions`, `# Gotchas`. No two lines that contradict each other.
- Leave out what belongs elsewhere: a multi-step procedure is a skill; a rule for one part of the code is a `.claude/rules/` file with `paths:`; something that must happen every time is a hook or a deny rule, not a line in CAPITALS.

## Writing it with the user

A fresh repository has no code to learn from, so ask rather than guess.

1. Read what exists: the repository's README, package or build files, CI config, and the current `./CLAUDE.md` if there is one. Say in one line what you found, or that there is nothing yet.
2. Ask, with one AskUserQuestion at a time, only for what you couldn't find: what the project is for, the commands to install, check and run it, where its work happens (branches, PRs, who merges), and any rule Claude must follow here. Offer the answers you can infer as options.
3. Draft the file in the shape above and show it to the user. Revise until they agree.
4. Save it (below), then copy it to `./CLAUDE.md` so this session uses it.

## Suggesting additions during a session

When a rule, command or gotcha for this project emerges (the user corrects Claude twice, a command turns out to be the right one, a decision gets made), say in one line what you'd add to the project `CLAUDE.md` and ask. On a yes, edit `projects/<repo>.md` and save it as below. Don't edit it unasked.

## Saving to claude-setup

1. Find the clone: the path in `~/.claude/claude-setup-dir`. In a cloud session, pushing needs claude-setup in the session: if it isn't, add it with the add_repo tool (push access) and work in that checkout instead.
2. Write `projects/<repo>.md` on a new branch, commit, push, and open a pull request. Merge it only if the user has said Claude may merge claude-setup pull requests.
3. Tell the user the pull request link. Later sessions get the file once it is merged and claude-setup is pulled (the cloud setup script clones `main` on every VM build).
