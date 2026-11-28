# Project CLAUDE.md files

One file per project repository, named after the repository folder: `projects/<repo-name>.md`. The `outerpale-startup` plugin copies it to `./CLAUDE.md` in that repository at session start and keeps it out of git there. Write and change them with the plugin's `project-claude-md` skill.

`claude-setup.md` is the exception. claude-setup's own `CLAUDE.md` is the global one, so this file is never copied in. JiT reads its `JiT:` line instead, and so does any repository whose `CLAUDE.md` has no `JiT:` line of its own.
