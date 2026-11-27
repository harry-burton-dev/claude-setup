# JiT catching tests for claude-setup

Status: **draft for Harry's review. Nothing here is built or decided.**

## 1. Goal

Catch bugs in a change before its PR merges, for the bugs that `tests/test.sh` lets through. The approach is Meta's just-in-time (JiT) catching tests, adapted to a solo repository of bash and JS hooks. Acceptance is a backtest against the bugs that got through here (section 6).

## 2. What the sources say

Sources read: the full text of [1]; [2] and [3] through fetched HTML, part of it summarised by the fetch tool.

- [1] Harman, O'Hearn, Sengupta, *Harden and Catch for Just-in-Time Assured LLM-Based Software Testing: Open Research Challenges*, FSE Companion '25 keynote, arXiv 2504.16472.
- [2] Foster et al., *Mutation-Guided LLM-based Test Generation at Meta* (ACH), FSE Companion '25, arXiv 2501.12862.
- [3] Becker et al., *Just-in-Time Catching Test Generation at Meta*, submitted to FSE 2026, arXiv 2601.22832, plus Engineering at Meta's blog post of 29 Oct 2026, "Catching Bugs Before They Land".

### Definitions (verbatim from [1])

- **Hardening test:** "one that seeks to protect against future regressions".
- **Catching test:** "one that catches such a regression or a fault in new functionality introduced by a code change."
- **JiTTest** (Def. 4): "a timely test for R that is not a timely test for Parent(R)". It is constructed "as soon as the revision appears as a pull request".
- **Weak catching test** (Def. 10): Catching_R(t) ⇔ Fails_R(t). It fails on R, and that may be a false positive.
- **Strong catching test** (Def. 11): Fails_R(t) ∧ Oracle_R(t) = fail. It fails on R, and R really is wrong.
- **Oracle** (Def. 5): "Oracle_R(t) gives the expected result for test t in R". The paper leaves "how one determines the oracle deliberately unspecified".
- **Regression catching** (Def. 12/13): the test passes on Parent(R) and fails on R.
- **Functionality catching** (Def. 14/15): the test fails on R and is not a hardening test for the parent, because it doesn't build there or fails there.
- **Precision target:** R@P = 0.8, "ensuring that the ratio of false positives to true positives is no worse than 1:4". The paper calls 0.8 "a conservative choice".

### The decision table ([1] Table 3)

Run every generated test on both R and Parent(R). [1] calls this "always wise", and it is the paper's main actionable conclusion. Then:

| Parent(R) | R | Decision |
|---|---|---|
| pass | pass | land, as a hardening test |
| pass | fail | **report**: a possible regression |
| fail | pass | land: R fixed something |
| no build | pass | land: it tests the new functionality |
| no build | fail | **report**: a possible bug in the new functionality |
| pass or fail | no build | give the signal, don't land |
| fail | fail | discard |

"No build" means the test can't run on that revision, for example because the hook it calls doesn't exist yet.

### Other points that apply

- **Failure is a trigger, not a verdict.** [1] says a failing JiTTest should be "a 'trigger' to do further testing or analysis before troubling the engineer". The risk of friction "is higher for JiTTests than for merely timely tests", because often the JiTTest is the only test that says anything about the change.
- **Oracle scavenging** ([1] §6). The only oracle is often the PR's own text, such as its title, comments and CI history. The paper's worked examples weed out false positives using that text alone, for example "the title 'said it all'".
- **Which generators work** ([3]). Change-aware generation beats generic generation:
  - Weak catches per diff were 3.6% for TestGen-LLM, 1.6% for ACH, 4.0% for "dodgy diff" and 7.9% for intent-aware generation.
  - Dodgy diff treats the diff "as if it were already a mutant".
  - Intent-aware generation has an LLM infer the change's intent and risks, turn them into mutants, and generate tests that kill them on the parent.
- **Assessors** ([3]): rule-based patterns (a broken runner, a broken mock, a server that is down) and an ensemble of LLM judges. They "reduce human review load by 70%".
- **Real-world precision is low, and that is the risk.**
  - In [3], 8 of 41 candidates reported to engineers were confirmed (19.5% true positives), even after the assessors.
  - The blog reports 60% true positives later, at scale.
  - Of 22,126 generated tests, only 1% were even weak catches.
- **ACH's assurances** ([2]): buildable, a valid non-flaky regression test, hardening (catches a fault no existing test catches), then relevance as judged by a human. Engineers accepted 73% of ACH's tests.

## 3. The benchmark: bugs that got past `tests/test.sh`

Found by mining `git log` (53 commits) for fix commits, then tracing each fixed file back to the commit that introduced the bug.

| # | Introduced | Fixed | Bug | Executable oracle? |
|---|---|---|---|---|
| B1 | e853a90 (lookup), 09b5369 (`.work/`) | dd39928 | outerpale-startup's SessionStart hook exits silently (`git rev-parse` fails) when a cloud session starts in the non-git parent folder of several repositories | yes |
| B2 | 064a7d5 | b2959fd | outerpale-mem's SessionStart hook: the same bug, written independently | yes |
| B3 | 35d73b4 | 6dde42e, then c28869c | Node 26 shadowed by `/opt/node22/bin` on cloud VMs. **The first fix, 6dde42e, did not fix it** | yes, needs `tests/test.sh --vm` (Docker) |
| B4 | 35d73b4 | a9e048c | `install.sh`, `cloud/setup.sh` and `tests/test.sh` committed without the executable bit | yes |
| B5 | 3a0dc70 | 04dffb4 | the companion agent's brief has no current time, and the agent has no clock | no: prompt-only |
| B6 | (in the test) | d085db5 | a `--vm` check for pnpm failed silently | no: a bug in the test itself |
| — | outerpale-devops 0.6.0 | — | a bundled AskUserQuestion answer was misread as "scope undecided" | not in this repository |

Patterns:

1. Most of these bugs are in **new** code (B1, B2, B4, B5). So the parent has no behaviour to compare against: these are [1]'s "no build on parent" rows, and the oracle has to come from intent.
2. The intent that would have caught B1 and B2 was **not in the diff or the commit message**. It is a fact about the environment: a cloud session with several repositories starts in a non-git parent folder. That fact is now in global memory as a lesson. Oracle scavenging has to read environment facts as well as the PR.
3. B3's first fix (6dde42e) is the one case that matches the paper's regression and fix-check pattern: the commit message states the intent ("Node 26 the default node"), and a test of that intent fails on the "fix".

### Probe already run (evidence, not a proposal)

A deterministic probe ran each historical version of the hook in a non-git folder holding two fresh repositories. It passed when the hook covered both. The probe is scratch, not committed.

```
09b5369  outerpale-startup session-start.sh  repos covered 0/2
dd39928^ outerpale-startup session-start.sh  repos covered 0/2
dd39928  outerpale-startup session-start.sh  repos covered 2/2
064a7d5  outerpale-mem mem.js session-start  repos named   0/2
b2959fd^ outerpale-mem mem.js session-start  repos named   0/2
b2959fd  outerpale-mem mem.js session-start  repos named   2/2
```

A fixed test with no LLM catches B1 and B2. Run against the introducing commits, it is [1]'s "no build on parent, fails on R" row, and so a true functionality catch.

## 4. Recommendation: two layers, cheapest first

### Layer 1: hook contract checks (deterministic, in `tests/test.sh`)

Every hook in `plugins/*/hooks/hooks.json` runs in the three session shapes from the global-memory lesson:

- one repository
- a non-git folder holding two
- a folder holding none

It must not exit non-zero, must stay silent with none, and must name each repository with two. Each plugin then asserts its own behaviour on top.

- **Generated, not hand-written:** the harness is generated from every hook command in `hooks.json`, so a new plugin's hook is covered without anyone remembering to add it. This is the step that would have stopped B2 from repeating B1.
- **Why first:** it catches B1 and B2 now, costs nothing per PR, and has no false positives.
- **What it misses:** bugs where no rule is known ahead of time. That gap is what Layer 2 is for.
- **Simpler alternative to weigh:** Layer 1 alone may be enough for this repository's size (see Q1).

### Layer 2: a JiT catching step (LLM, report-only)

A skill, `outerpale-startup:jit`, plus a read-only agent, run once before a PR opens. It runs at the same moment as `intent-reviewer` and reports alongside it.

1. **Inputs (oracle scavenging):**
   - the diff
   - the commit messages and PR body
   - the Linear issue's plan, if there is one
   - the design doc, if there is one
   - the environment facts:
     - `docs/cloud-environment.md`
     - the three session shapes
     - the cloud quirks in global memory (writes under `~/.claude/` refused, no connectors in `claude -p`, and so on)
2. **Generate.** An intent-aware generator writes the change's intent and risks as one-line mutant descriptions. Then it writes up to N throwaway bash tests that would kill those mutants. A dodgy-diff pass treats the diff itself as a possible mutant of the parent.
3. **Run on both revisions.** Run each test at HEAD and at `git merge-base HEAD origin/main`, each in its own `git worktree` under `.work/jit/`, with a temporary `HOME`, as `tests/test.sh` already does. Use the `--vm` path only when the diff touches `cloud/setup.sh`.
4. **Classify** each result with the decision table in section 2. Discard tests that fail on both revisions. Rerun each failing test 3 times to drop flaky ones.
5. **Assessors.**
   - Rules first: the test errored before its assertion, depends on the network, uses `claude -p` for connector work, or writes under `~/.claude/`.
   - Then one LLM judge (not an ensemble, at this scale). It asks: given the intent text, should this test fail on R?
6. **Report, never block.**
   - Output is a short list of candidate catches. Each shows the test, its outcomes on the parent and on R, and the one-line intent it checks, in a "Was this change expected?" form.
   - The report goes at the end of the reply, matching Harry's "notified, never interrupted" preference.
   - Tests are thrown away. One that Harry confirms can be promoted into `tests/test.sh` as a hardening test: the "land" rows.

**Trigger: recommended.** Invoke it on purpose in the pre-PR step, next to `intent-reviewer`. Don't use a blocking PreToolUse hook on `create_pull_request`, because:

- [1] says failing JiT signals carry high friction and should be a trigger for more analysis, not a gate.
- Its precision in the field was 19.5–60%.
- A hook would add per-PR minutes and tokens to doc-only PRs.

Optionally, a PreToolUse hook can *remind* Claude to run it when the diff touches `plugins/*/hooks/`, `install.sh` or `cloud/`.

**False-positive budget.** Per [1], at least 0.8 precision on what reaches Harry, and in absolute terms at most one false alarm per five PRs. If the backtest's precision falls below that, the step reports less, rather than reporting more and asking Harry to filter.

**Cost budget, to measure.** Measure through Langfuse `claude_code.interaction` traces: at most 10 minutes and a fixed token ceiling per run (the figure is open, Q4).

## 5. Cloud-session cases

Both layers run in all three shapes. The worktrees live under each repository's `.work/jit/`, which is never committed. Layer 2 reads no connectors, so it works under `claude -p`. The LLM judge runs as a subagent of the real session.

## 6. Acceptance: the backtest

Interface, written before any implementation:

```
tests/jit-backtest.sh [--layer 1|2] [--vm]
  reads  tests/jit/benchmark.tsv   # columns: id  buggy_rev  fixed_rev  paths  intent
  reads  tests/jit/clean.tsv       # commits believed bug-free: rev  paths  intent
  for each row: worktree at buggy_rev (as R) and buggy_rev^ (as parent); run the layer;
                then worktree at fixed_rev and expect no report
  prints one line per row:  B1 caught|missed|false-alarm  <test name>  <parent>/<R> outcome
  final line:               caught=X/Y  false_alarms=F/M  precision=P
  exit 0 iff the thresholds below hold
```

Thresholds:

- **Layer 1:** catches B1 and B2, with 0 false alarms on `clean.tsv`.
- **Layer 2:** catches at least 2 of B1, B2, B3 (6dde42e as R) and B4, without being given the fix. It has at most 1 false alarm across at least 10 clean commits (M ≥ 10), and precision of at least 0.8 on what it reports.
- **Out of scope:** B5 (no executable oracle; that belongs in evals) and B6 (a bug in a test).

**The backtest is a smoke test, not proof.** Once Layer 1 exists, only B3 and B4 are left for Layer 2 to catch. That is too few to measure precision. Real acceptance for Layer 2 is a trial over the next 15–20 PRs, logging each report as confirmed or false alarm.

**Leakage guard.** Layer 2 must not see the fix commit, later commits, or memories written after the bug. Its inputs are cut at `buggy_rev`. The cloud-shapes lesson is in memory only because of B1, so the backtest runs twice, with and without the environment-facts input. That shows how much of the catch comes from the oracle and how much from the generator.

## 7. Open questions for Harry

1. **Layer 1 only, or both?** Layer 1 alone catches the two bugs that actually escaped through hooks. Layer 2 earns its cost only if it also catches B3 or B4 in the backtest.
2. **Trigger:** an on-demand pre-PR step (recommended), or a blocking hook?
3. **Where it lives:** in `outerpale-startup` next to `intent-reviewer` (recommended), or as its own plugin?
4. **Token and time ceiling** per run.
5. **Doc location.** The installed global `CLAUDE.md` says design docs go in `docs/design/`, but this repository's `CLAUDE.md` now says work runs through GSD `.planning/`. Should this design become a GSD phase?
6. Should confirmed JiT tests be promoted into `tests/test.sh` automatically, or only when Harry agrees to each one?
