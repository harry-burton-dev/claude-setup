---
name: run
description: Run just-in-time catching tests on this branch before its PR opens, in any repository. It generates tests from the change's intent, runs them on the change and on its parent, reports likely bugs, and lands tests that pin the change. Use before every PR (the jit hook refuses PR creation until it has run, or skipped), or on demand when a change feels risky.
---

JiT gives every change a second, independent test author that tries to break it. It runs on top of the checks you wrote first, and doesn't replace them. The method is Meta's Harden and Catch (arXiv 2504.16472), and the design is in claude-setup's `docs/design/jit-testing.md`.

`jit.js` is `<this skill's base directory>/../../scripts/jit.js`. Run it from the repository, or pass `--repo <path>`. In a session with several repositories, do each repository whose branch has changes.

## 1. Triage: is it worth running?

Run `node jit.js triage`.

- **`decision: skip`:** it already wrote the report, and you are done. Say why in one line.
- **`decision: run`:** decide whether a run is worth it.
  - Skip it with `node jit.js skip --reason "<why>"` when the change is low risk or low impact, or already well tested and reviewed. Examples: a rename, a config value, a revert, or a change whose own new tests already pin the behaviour and have been reviewed.
  - Otherwise carry on. Don't spend ten minutes testing a change that can't break anything that matters.

## 2. Generate

Start the `jit:generator` agent in the foreground. Give it:

- the repository path
- `sha` and `parent` from the triage
- the report folder, `.work/jit/<sha>/`
- the branch's commit messages
- the Linear issue's goal and acceptance criteria, if the session has an issue
- the GSD phase's `PLAN.md`, if there is one
- any design doc

The generator also reads the repository's `CLAUDE.md` and the memory this session loaded. Pass on any cloud or environment facts that bear on the change, for example that a cloud session with several repositories starts in their non-git parent folder.

If the triage says `vm: true`, the change touches the repository's `vm-paths`, such as a cloud setup script. Tell the generator, so that it marks the tests that need a cloud VM's conditions with `"vm": true`: root, a fresh Ubuntu 24.04, another tool earlier on `PATH`. Those tests run in a container, and need Docker.

It writes `tests.json` and the test files under `.work/jit/<sha>/tests/`.

## 3. Run

Run `node jit.js run`. It runs each test, and the repository's `invariants` check if its `JiT:` line names one, at the change and at its parent in throwaway worktrees. Then it classifies each test:

| Decision | Meaning |
|---|---|
| `report` | Passed before, or didn't exist before, and fails now: a candidate catch |
| `land` | Fails or doesn't exist before, and passes now: it pins what this change does |
| `signal` | Can't run on this revision |
| `discard` | Passes on both, fails on both, flaky, failed for environment reasons, or needs the VM with no Docker here |

## 4. Assess the candidate catches

If any result is `report` and isn't `assessed: "rule"`, start the `jit:assessor` agent in the foreground. Give it the results file, `.work/jit/<sha>/results.json`, and the same intent text you gave the generator. It writes `.work/jit/<sha>/verdicts.json`.

## 5. Finish

Run `node jit.js finish`.

- It drops the catches the assessor judged false positives.
- It copies the `land` tests into the repository's working tree.
- It writes `.work/jit/<sha>/report.json`, which is what the PR hook looks for.

## 6. Act on it

- **Each catch:** look at it.
  - If it's a real bug, fix it on the branch. The catching test then passes. Keep it: commit it with the fix as a regression test.
  - If it's a false positive, say so in one line.
- **Landed tests:** they go in the PR. Make sure the repository's own test command picks them up and passes, then commit them.
- **Tell Harry** in a short note at the end of your reply, and put the same lines in the PR body under "JiT". Cover the catches (risk, before and after, and what you did) and the tests landed. Or say "JiT: ran N tests, nothing caught" or "JiT: skipped, <reason>". If the report's `notRun` lists VM tests, say they didn't run because Docker isn't available here.

Committing after the report is fine. The hook accepts a report from an earlier commit on the branch when only landed tests, or a tiny change, came after it.
