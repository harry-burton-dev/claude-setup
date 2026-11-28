# cowork-setup

Bootstraps knowledge-work cloud VMs: research, writing and notes, saved to Google Drive. VMs don't use this repo for work: their setup script clones `main` into `/opt/cowork-setup` and installs `~/.claude`. Editing this repo changes every future knowledge-work VM.

# Commands

- Test: `tests/test.sh`. It uses a stand-in `claude` CLI. CI (`.github/workflows/test.yml`) runs it on every PR.
- End-to-end check, as a VM would see it: copy only `cloud/bootstrap.sh` into an empty folder under `/tmp` and run it with `HOME` set to a fresh folder under `/tmp`. Then run `claude -p` from an unrelated folder with `--disallowedTools "Read,Bash,Glob,Grep"` and ask for the Drive folder ID. It should answer `1Q1NXLoVyE_B8zmrAYFymTNf0l-utzoUU`. Also check that `claude plugin list` shows every plugin in `plugins.lock` enabled. Run it before merging a change to `cloud/`, `install.sh`, `plugins.lock` or `home/CLAUDE.md`.

# Where work happens

- One branch and one PR per change. Claude may merge its own PRs: turn on auto-merge for the PR, and GitHub merges it once the `test` check passes.
- The bootstrap clones `main`, so a change reaches VMs only once it's merged.

# Conventions

- `home/CLAUDE.md` is the VM's user CLAUDE.md. It stays out of the repo root so a session in this repo doesn't load it.
- `cloud/setup.sh` must never fail because of a plugin. A failure goes in `~/.claude/cowork-setup.status` as a warning, because a failing setup script stops every session in the environment.

# Gotchas

- Claude Code never loads a CLAUDE.md under a session scratchpad or `.artifact-work`. A fake `HOME` there makes the memory check fail when nothing is wrong.
