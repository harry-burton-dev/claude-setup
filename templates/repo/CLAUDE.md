# <project>

## Where work happens

- Code and docs live in this repository. Its `main` branch on GitHub is the source of truth, so run `git fetch` first.
- Every session works on its own branch and opens a pull request. Harry merges.

## Commands

| What | Command |
|---|---|
| Install | `pnpm install` |
| Check (lint, types, tests) | `pnpm check` |
| Start what the tests need | `<command>`. In the cloud, start it in the background: services do not survive between sessions |

## Rules for this project

- A change is done when `pnpm check` passes and the change's own test exists. Say which command you ran and what it printed.
- <the project's own facts, which Claude should not have to rediscover>
