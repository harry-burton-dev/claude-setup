# JiT catching tests, in every repository

Status: **draft for Harry's review. Nothing here is built.**

Decided by Harry on 27 Nov 2026:

- JiT runs **in addition to** write-the-check-first; it doesn't replace it.
- It runs **once before each PR**.
- It applies to all his code, and the whole process lives in claude-setup.

Everything else here is a proposal.

## 1. Goal

Before any branch in any of Harry's repositories becomes a PR, a second, independent test author tries to break the change:

- Tests that fail on the change are reported as candidate bugs ("catching tests").
- Tests that pass are offered as permanent tests ("hardening tests") in that repository's suite.

Why on top of check-first? Today the same model writes the code and the check that proves it, so both share its blind spots. Every escaped bug in section 3 had a check written first, and the check passed.

Why in claude-setup? It bootstraps every machine and cloud VM, and plugins are never committed to project repositories. So the method ships as a plugin here, and per-repository settings live in `projects/<repo>.md`.

## 2. What the sources say

Sources read: the full text of [1]; [2] and [3] through fetched HTML, part of it summarised by the fetch tool.

- [1] Harman, O'Hearn, Sengupta, *Harden and Catch for Just-in-Time Assured LLM-Based Software Testing: Open Research Challenges*, FSE Companion '25 keynote, arXiv 2504.16472.
- [2] Foster et al., *Mutation-Guided LLM-based Test Generation at Meta* (ACH), FSE Companion '25, arXiv 2501.12862.
- [3] Becker et al., *Just-in-Time Catching Test Generation at Meta*, submitted to FSE 2026, arXiv 2601.22832, plus Engineering at Meta's blog post of 29 Oct 2026, "Catching Bugs Before They Land".

### Definitions (verbatim from [1])

- **Hardening test:** "one that seeks to protect against future regressions".
- **Catching test:** "one that catches such a regression or a fault in new functionality introduced by a code change."
- **JiTTest** (Def. 4): "a timely test for R that is not a timely test for Parent(R)". It is constructed "as soon as the revision appears as a pull request". [1] also notes "many engineers do write unit tests just-in-time". Check-first is that hand-written case; this design adds the generated case.
- **Weak catching test** (Def. 10): Fails_R(t). It fails on R, and that may be a false positive.
- **Strong catching test** (Def. 11): Fails_R(t) ∧ Oracle_R(t) = fail. It fails on R, and R really is wrong.
- **Oracle** (Def. 5): "Oracle_R(t) gives the expected result for test t in R". The paper leaves how to get it "deliberately unspecified".
- **Precision target:** R@P = 0.8, so the "ratio of false positives to true positives is no worse than 1:4".

### The decision table ([1] Table 3)

Run every generated test on both R and Parent(R). [1] calls this "always wise". Then:

| Parent(R) | R | Decision |
|---|---|---|
| pass | pass | land, as a hardening test |
| pass | fail | **report**: a possible regression |
| fail | pass | land: R fixed something |
| no build | pass | land: it tests the new functionality |
| no build | fail | **report**: a possible bug in the new functionality |
| pass or fail | no build | give the signal, don't land |
| fail | fail | discard |

"No build" means the test can't run on that revision, for example because the code it calls doesn't exist there yet.

### Other points that shape the design

- **Failure is a trigger, not a verdict.** A failing JiTTest should be "a 'trigger' to do further testing or analysis before troubling the engineer". Friction "is higher for JiTTests than for merely timely tests".
- **Oracle scavenging** ([1] §6). The expected behaviour has to be scavenged from text that isn't code: the PR title, comments, docs and CI history. The source code describes what the system does, "not a description of its intended behaviour".
- **Change-aware generators win** ([3]). Weak catches per diff: TestGen-LLM 3.6%, ACH 1.6%, dodgy diff 4.0%, intent-aware 7.9%.
  - Dodgy diff treats the diff "as if it were already a mutant".
  - Intent-aware generation infers the intent and its risks, turns them into mutants, and kills them on the parent.
- **Assessors** ([3]): rule-based patterns (a broken runner, a broken mock, a server that is down) plus LLM judges. They cut "human review load by 70%".
- **Precision in the field is the risk.**
  - In [3], 8 of 41 reported candidates were real (19.5%).
  - The blog reports 60% at scale.
  - Only 1% of 22,126 generated tests were even weak catches.
- **ACH's assurances** ([2]): it builds; it passes consistently (not flaky); it catches a fault no existing test catches; a human judges it relevant. Engineers accepted 73% of ACH's tests.

## 3. Evidence from this repository's history

These are the bugs `tests/test.sh` let through, from `git log` (53 commits):

| # | Introduced | Fixed | Bug | Executable oracle? |
|---|---|---|---|---|
| B1 | e853a90, 09b5369 | dd39928 | outerpale-startup's SessionStart hook exits silently when a cloud session starts in the non-git parent folder of several repositories | yes |
| B2 | 064a7d5 | b2959fd | outerpale-mem's SessionStart hook: the same bug, written independently | yes |
| B3 | 35d73b4 | 6dde42e, then c28869c | Node 26 shadowed by `/opt/node22/bin` on cloud VMs. The first fix, 6dde42e, did not fix it | yes, needs `tests/test.sh --vm` (Docker) |
| B4 | 35d73b4 | a9e048c | scripts committed without the executable bit | yes |
| B5 | 3a0dc70 | 04dffb4 | the companion agent's brief has no current time | no: prompt-only |
| B6 | (in the test) | d085db5 | a `--vm` check for pnpm failed silently | no: a bug in the test itself |

Lessons that hold beyond this repository:

1. **Most escaped bugs are in new code.** They are the "no build on parent" rows, so the oracle has to come from intent, not from the parent's behaviour.
2. **The deciding fact often lives in the environment, not in the diff.** For B1 and B2 it was the fact that a cloud session with several repositories starts in a non-git parent folder. Oracle scavenging has to read the memories and the cloud-environment docs as well as the PR.
3. **Some invariants are known ahead of time and need no LLM.** A deterministic probe ran each historical version of the hook in a non-git folder holding two repositories. It passed when the hook covered both. It is scratch, not committed:

   ```
   09b5369  session-start.sh  repos covered 0/2      064a7d5  mem.js  repos named 0/2
   dd39928^ session-start.sh  repos covered 0/2      b2959fd^ mem.js  repos named 0/2
   dd39928  session-start.sh  repos covered 2/2      b2959fd  mem.js  repos named 2/2
   ```

   So JiT has two layers: fixed checks for invariants we already know, and generated tests for the ones we don't.

## 4. Design

### 4.1 What ships, all in claude-setup

| Piece | Where | Purpose |
|---|---|---|
| Plugin `jit` | `plugins/jit/`, added to `plugins.lock` | Installed on every machine and VM by `install.sh` and `cloud/setup.sh`, like the other plugins here |
| Skill `jit:run` | `plugins/jit/skills/run/SKILL.md` | The procedure in 4.3. Run before each PR, or on demand |
| Agent `jit:generator` | `plugins/jit/agents/` | Writes intent, mutants and tests from the inputs. Read-only on the repository; writes only under `.work/jit/` |
| Agent `jit:assessor` | `plugins/jit/agents/` | The LLM judge: given the intent text, should this failure happen on R? Read-only |
| Runner `jit.js` | `plugins/jit/scripts/` | Deterministic: worktrees, runs on both revisions, retries for flakiness, the rule-based assessor, classification by the decision table, and the report file |
| Pre-PR hook | `plugins/jit/hooks/` | See 4.4 |
| Per-repository settings | `projects/<repo>.md` | No new file. JiT reads the existing `# Commands` test line, plus an optional `JiT:` line (4.2) |
| Global rule | `CLAUDE.md` §4 | One sentence: "Before a PR opens, run `jit:run`; it adds to the checks you wrote first and doesn't replace them." |
| Tests and evals | `tests/test.sh`, `tests/evals/jit/`, `tests/jit-backtest.sh` | Section 6 |

**Why its own plugin, not part of `outerpale-startup`:** JiT is a method with its own version, evals and backtest, and it applies in sessions with no Linear scope too. `intent-reviewer` stays where it is, and both run at the same moment.

### 4.2 Per-repository settings

JiT works in any language, because it uses the repository's own test command and framework.

- **Test command:** the `Test:` line in `projects/<repo>.md` `# Commands`. For example, outerpale-devops has `node --test tests/` and claude-setup has `tests/test.sh`. If a repository has no test command, JiT reports that it can't run there and asks once whether to add one through `outerpale-startup:project-claude-md`.
- **Generated test style:** the same framework as the existing tests. JiT looks at the files under the test directory and follows how they are written.
- **Optional `JiT:` line,** for each repository's known invariants and run limits, for example:

  ```
  JiT: invariants tests/invariants.sh; vm-paths cloud/; skip docs/**, *.md
  ```

  - `invariants` is the repository's fixed checks (layer 1).
  - `vm-paths` are paths whose changes need the slow environment run.
  - `skip` are paths that never trigger generation.

  Without the line, JiT uses defaults: no invariants script, no VM run, and docs-only diffs skipped.

Layer 1 for claude-setup is the hook contract check: it runs every hook in `plugins/*/hooks/hooks.json` in three folder shapes (one repository, a non-git folder holding two, a folder holding none). It is generated from `hooks.json`, so a new plugin's hook is covered automatically. Other repositories write their own when an invariant becomes known. A confirmed JiT catch is usually how one becomes known.

### 4.3 The procedure (`jit:run`)

1. **Scope.**
   - R is HEAD and Parent(R) is `git merge-base HEAD origin/<default>`.
   - If the diff touches only `skip` paths, write a "skipped: no code" report and stop.
   - In a cloud session that started in a parent folder holding several repositories, run once for each repository whose branch has changes, and name the repository in each report.
2. **Layer 1.** If there is an invariants script, run it on R. Any failure is reported as a catch with no LLM involved.
3. **Scavenge the oracle.** Collect, cut at R:
   - the diff and the branch's commit messages
   - the Linear issue's goal and acceptance criteria, if the session has one
   - the GSD phase's `PLAN.md`, if there is one
   - any design doc
   - the repository's project CLAUDE.md gotchas
   - repository and global memory
   - `docs/cloud-environment.md` for cloud facts
4. **Generate** (`jit:generator`).
   - Write the change's intent as 3 to 7 one-line risks, each a plausible way R could be wrong.
   - For each risk, write a test that should pass if R is right.
   - Then a dodgy-diff pass: tests that the diff, read as a mutant of the parent, would break.
   - At most N tests (open question 2).
5. **Run** (`jit.js`).
   - Each test runs at R and at Parent(R), each in its own `git worktree` under `.work/jit/<sha>/`, with a temporary `HOME`.
   - The VM run happens only when the diff touches `vm-paths`.
   - Each failing test is rerun 3 times, and a flaky one is dropped.
6. **Classify** with the decision table in section 2.
7. **Assess** each test that fails on R.
   - Rules first: the test errored before its assertion, needs a network host it can't reach, depends on connectors (which `claude -p` lacks), or writes under `~/.claude/`.
   - Then `jit:assessor`, a single judge rather than an ensemble at this scale, with the step-3 intent text.
   - Only "should fail" verdicts are reported.
8. **Report** to `.work/jit/<sha>/report.json` and as a short note at the end of Claude's reply, which matches "notified, never interrupted".
   - **Catches:** each with the test, its outcomes on the parent and on R, and the risk it checks, asked as "Was this change expected?"
   - **Hardening tests offered:** the "land" rows.
9. **Land on Harry's word.**
   - A confirmed catch gets fixed on the branch. Its test is landed with the fix, as a regression test.
   - Hardening tests that Harry accepts are copied into the repository's test directory and committed in the same PR.
   - Nothing lands without his OK. Unlanded tests stay in `.work/`, which is never committed.

### 4.4 The trigger: before each PR, in every repository

The flow today goes GSD verify, then `intent-reviewer`, then the PR. `outerpale-devops:build-issue` lives in another repository, and this process has to live in claude-setup. So the trigger is a hook in the `jit` plugin rather than an edit to build-issue:

- A **PreToolUse hook on PR creation.** The matcher covers both GitHub MCP spellings, `mcp__github__create_pull_request` and `mcp__GitHub__create_pull_request`.
- It checks for `.work/jit/<head-sha>/report.json`. If the report is missing, it denies once, with "run the `jit:run` skill first, then open the PR".
- It gates on JiT **having run**, never on what it found. A run with catches still lets the PR open, and the catches go in the PR body. That keeps [1]'s "trigger, not verdict" while making sure the step happens every time.
- It fails open on any internal error, like the outerpale-devops hooks.
- Draft PRs that hold only docs, such as this one, are covered by the "skipped: no code" report.

This composes with outerpale-devops' own guard on the same tool. Both have to allow the call, and each says why it refused.

### 4.5 Budgets

- **False alarms:** at least 0.8 precision on what reaches Harry, and in absolute terms at most one false alarm per five PRs across all repositories. When precision drops below that, the assessor's threshold goes up: JiT reports less rather than more.
- **Time and tokens:** measured through Langfuse `claude_code.interaction` traces. The proposal is at most 10 minutes per run and a token ceiling set per repository (open question 2).

## 5. Cloud-session cases

- **Three shapes.** Every hook and script works in all three: one repository, a non-git parent folder holding two, a folder holding none. With none, JiT does nothing.
- **Worktrees** go under each repository's `.work/jit/`.
- **Connectors.** JiT needs none, so it also works under `claude -p`. The assessor runs as a subagent of the real session.
- **`HOME`.** Writes under `~/.claude/` are refused in the cloud, so temporary `HOME` folders live in `.work/jit/`.

## 6. Acceptance

The checks, written before any implementation:

1. **`tests/test.sh` covers the plugin.**
   - The hook denies without a report and allows with one, including a report with catches.
   - It fails open on bad input, and both GitHub tool spellings match.
   - `jit.js` classifies each row of the decision table from canned outcomes.
   - Everything works in the three folder shapes.
2. **`tests/jit-backtest.sh`.** It replays the escaped bugs with inputs cut at the buggy revision (the leakage guard).

   ```
   tests/jit-backtest.sh [--repo <path>] [--layer 1|2] [--vm]
     reads  tests/jit/benchmarks/<repo>.tsv   # id  buggy_rev  fixed_rev  paths  intent
     reads  tests/jit/clean/<repo>.tsv        # rev  paths  intent (commits believed bug-free)
     prints one line per row: B1 caught|missed|false-alarm  <test>  <parent>/<R>
     final:  caught=X/Y  false_alarms=F/M  precision=P; exit 0 iff thresholds hold
   ```

   The benchmark files for every repository live here in claude-setup. outerpale-devops' bundled-answer bug (0.6.0) is its first row, with its revisions still to be found in that repository.

   Thresholds:
   - **Layer 1 on claude-setup:** catches B1 and B2, with 0 false alarms.
   - **Layer 2:** catches at least 2 of B1 to B4 without being given the fix, with at most 1 false alarm in at least 10 clean commits.
   - **Two runs:** with and without memory as an input, which shows how much depends on oracle scavenging.
3. **A prospective trial.** The backtest has too few bugs to measure precision, so it is a smoke test. Real acceptance is the next 20 PRs across all repositories, each report logged as confirmed or false alarm in `.work/jit/trial.tsv`, and copied to repository memory so it survives the VM. The 0.8 precision target applies there.
4. **Evals** in `tests/evals/jit/`: canned diffs with known intent, where the assessor has to separate the paper's two weed-out examples (§6.2 and §6.3): a "the title said it all" false catch, and a failure that breaks an assumption a code comment states.

## 7. Build order (each its own PR, on Harry's go)

1. Layer 1 for claude-setup: the hook contract check in `tests/test.sh`. It is small, needs no LLM, and catches B1 and B2.
2. `jit.js` (worktrees, runs on both revisions, classification, report) and its tests.
3. The generator and assessor agents, the `jit:run` skill, the evals, and the backtest.
4. The pre-PR hook, the `plugins.lock` entry, and the `CLAUDE.md` §4 sentence. JiT goes live everywhere at this step.
5. The 20-PR trial. Then Harry decides whether to keep it, tune it or drop it.

## 8. Open questions

1. Is the gate in 4.4 right? It denies PR creation until JiT has run, without blocking on what it finds. A non-blocking reminder is the softer choice.
2. Limits: the maximum number of tests per run, the time, and the token ceiling.
3. Should a catch go in the PR body automatically, or only after Harry has seen it?
4. **Doc location.** The installed global `CLAUDE.md` says design docs go in `docs/design/`, but this repository's `CLAUDE.md` now says work runs through GSD's `.planning/`. Should this design become a GSD phase, or phases?
