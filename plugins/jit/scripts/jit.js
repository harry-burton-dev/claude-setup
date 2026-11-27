#!/usr/bin/env node
// JiT catching tests: the deterministic half (the jit:run skill and its agents are the rest).
// Method: Harman, O'Hearn, Sengupta, "Harden and Catch" (arXiv 2504.16472); design in
// claude-setup docs/design/jit-testing.md. Run from inside a repository, or pass --repo DIR.
//   jit.js triage            decide run or skip for HEAD against its merge-base; a skip writes the report
//   jit.js skip --reason "…" record a judged skip (well tested and reviewed, or low risk)
//   jit.js run               run .work/jit/<sha>/tests.json at HEAD and at its parent, classify
//   jit.js finish            apply the assessor's verdicts, land hardening tests, write the report
//   jit.js hook              PreToolUse on PR creation: needs a JiT report for the PR's branch
//   jit.js guard             PreToolUse: the generator writes only under .work/jit/, the assessor only verdicts.json
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const TINY_LINES = 5; // and one file: smaller than that, a run costs more than it can find
const DEFAULT_SKIP = ['*.md', 'docs/**', '.planning/**', 'LICENSE', '.gitignore', '.gitattributes'];
const TIMEOUT_S = 120;

const git = (dir, ...a) => execFileSync('git', a, { cwd: dir, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
const tryGit = (dir, ...a) => { try { return git(dir, ...a); } catch { return null; } };
const readJson = f => JSON.parse(fs.readFileSync(f, 'utf8'));
const writeJson = (f, o) => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, JSON.stringify(o, null, 2) + '\n'); };

function arg(name) { const i = process.argv.indexOf(name); return i > 0 ? process.argv[i + 1] : undefined; }
function repoDir() { return git(arg('--repo') || process.cwd(), 'rev-parse', '--show-toplevel'); }

// The commit HEAD is measured against: where the branch left the default branch.
function base(dir) {
  const def = (tryGit(dir, 'symbolic-ref', '-q', '--short', 'refs/remotes/origin/HEAD') || '').replace(/^origin\//, '');
  for (const ref of [def && `origin/${def}`, 'origin/main', 'origin/master', 'main', 'master'].filter(Boolean)) {
    const mb = tryGit(dir, 'merge-base', 'HEAD', ref);
    if (mb && mb !== git(dir, 'rev-parse', 'HEAD')) return mb;
  }
  return tryGit(dir, 'rev-parse', 'HEAD^'); // on the default branch itself: the last commit
}

// The repository's JiT settings: an optional "JiT:" line in its CLAUDE.md, or else in claude-setup's
// projects/<repo>.md (for a repository whose own CLAUDE.md is something else, like claude-setup's), e.g.
//   JiT: invariants tests/invariants.sh; skip vendor/**, *.lock; vm-paths cloud/
function config(dir) {
  const out = { skip: [...DEFAULT_SKIP], invariants: null, vm: [] };
  const jitLine = f => { try { return (fs.readFileSync(f, 'utf8').match(/^JiT:\s*(.+)$/m) || [])[1]; } catch { return undefined; } };
  let setup = '';
  try { setup = fs.readFileSync(path.join(os.homedir(), '.claude', 'claude-setup-dir'), 'utf8').trim(); } catch {}
  const line = jitLine(path.join(dir, 'CLAUDE.md')) || (setup && jitLine(path.join(setup, 'projects', `${repoName(dir)}.md`)));
  if (!line) return out;
  for (const part of line.split(';').map(s => s.trim()).filter(Boolean)) {
    const [key, ...rest] = part.split(/\s+/);
    const value = rest.join(' ');
    if (key === 'skip') out.skip.push(...value.split(',').map(s => s.trim()).filter(Boolean));
    if (key === 'invariants') out.invariants = value;
    if (key === 'vm-paths') out.vm.push(...value.split(',').map(s => s.trim()).filter(Boolean).map(p => p.endsWith('/') ? `${p}**` : p));
  }
  return out;
}

function glob(pattern) {
  const re = pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*\*\/?/g, '\u0000').replace(/\*/g, '[^/]*').replace(/\u0000/g, '.*');
  return new RegExp(pattern.includes('/') ? `^${re}$` : `(^|/)${re}$`);
}
const skipped = (file, skip) => skip.some(p => glob(p).test(file));

// Changed files between two commits (or the working tree), with lines added plus deleted.
function changes(dir, from, to) {
  const out = tryGit(dir, 'diff', '--numstat', from, ...(to ? [to] : [])) || '';
  return out.split('\n').filter(Boolean).map(l => {
    const [a, d, ...f] = l.split('\t');
    return { file: f.join('\t'), lines: (a === '-' ? 50 : +a) + (d === '-' ? 50 : +d) };
  });
}

const reportDir = (dir, sha) => path.join(dir, '.work', 'jit', sha);
function writeReport(dir, sha, report) { writeJson(path.join(reportDir(dir, sha), 'report.json'), { sha, repo: repoName(dir), at: new Date().toISOString(), ...report }); }

function triage(dir) {
  const sha = git(dir, 'rev-parse', 'HEAD');
  const parent = base(dir);
  const cfg = config(dir);
  const files = parent ? changes(dir, parent, sha) : [];
  const code = files.filter(f => !skipped(f.file, cfg.skip));
  const lines = code.reduce((n, f) => n + f.lines, 0);
  let decision = 'run', reason = `${code.length} code file(s), ${lines} line(s) changed`;
  if (!parent) { decision = 'skip'; reason = 'no parent revision to compare with'; }
  else if (!files.length) { decision = 'skip'; reason = 'no changes'; }
  else if (!code.length) { decision = 'skip'; reason = 'only docs or other skipped paths changed'; }
  else if (lines <= TINY_LINES && code.length === 1) { decision = 'skip'; reason = `tiny change (${lines} line(s))`; }
  if (decision === 'skip') writeReport(dir, sha, { status: 'skipped', reason, by: 'triage' });
  const vm = code.some(f => skipped(f.file, cfg.vm));
  return { sha, parent, decision, reason, files: code.map(f => f.file), invariants: cfg.invariants, vm, dir: reportDir(dir, sha) };
}

// One test at one revision: pass, fail, timeout, or nobuild when the code it exercises isn't there:
// a subject file is missing, its "exists" check fails, or the test exits 77.
const NOBUILD = 77;
function sh(tree, command, timeout) {
  const r = spawnSync('bash', ['-c', command], { cwd: tree, encoding: 'utf8', timeout: timeout * 1000,
    env: { ...process.env, HOME: fs.mkdtempSync(path.join(path.dirname(tree), 'home-')) } });
  return { r, output: ((r.stdout || '') + (r.stderr || '')).slice(-2000) };
}
// A test marked "vm" runs as root in a fresh Ubuntu 24.04 container, the way a cloud VM's setup
// script does, with the revision at /repo. The image (git, node, curl) is built once per machine.
const VM_IMAGE = 'jit-vm:ubuntu-24.04';
const VM_TIMEOUT_S = 600;
const docker = (args, timeout) => spawnSync('docker', args, { encoding: 'utf8', timeout: (timeout || 60) * 1000 });
function vmImage() {
  if (docker(['image', 'inspect', VM_IMAGE]).status === 0) return VM_IMAGE;
  const name = `jit-vm-build-${process.pid}`;
  for (const base of ['ubuntu:24.04', 'mirror.gcr.io/library/ubuntu:24.04']) { // Docker Hub rate-limits; the mirror doesn't
    docker(['rm', '-f', name]);
    const built = docker(['run', '--name', name, base, 'bash', '-c',
      'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git ca-certificates curl nodejs npm >/dev/null'], 900);
    const ok = built.status === 0 && docker(['commit', name, VM_IMAGE], 120).status === 0;
    docker(['rm', '-f', name]);
    if (ok) return VM_IMAGE;
  }
  return null;
}
function vmSh(image, tree, command, timeout) {
  const name = `jit-vm-${process.pid}-${Date.now()}`;
  const r = docker(['run', '--rm', '--name', name, '-v', `${tree}:/repo`, '-w', '/repo', image, 'bash', '-c', command], timeout);
  if (r.error) docker(['rm', '-f', name]);
  return { r, output: ((r.stdout || '') + (r.stderr || '')).slice(-2000) };
}

function runOne(tree, t, vm) {
  if ((t.subject || []).some(s => !fs.existsSync(path.join(tree, s)))) return { outcome: 'nobuild', output: '' };
  if (t.exists && sh(tree, t.exists, 30).r.status !== 0) return { outcome: 'nobuild', output: '' };
  if (t.vm && !vm) return { outcome: 'novm', output: '' };
  const { r, output } = t.vm ? vmSh(vm, tree, t.cmd, t.timeout || VM_TIMEOUT_S) : sh(tree, t.cmd, t.timeout || TIMEOUT_S);
  if (r.error && r.error.code === 'ETIMEDOUT') return { outcome: 'timeout', output };
  if (r.status === NOBUILD) return { outcome: 'nobuild', output };
  return { outcome: r.status === 0 ? 'pass' : 'fail', code: r.status, output };
}

// The rule-based assessor: failures that say nothing about the change.
const ENV_RULES = [
  [/ENOTFOUND|ECONNREFUSED|EAI_AGAIN|Could not resolve host|getaddrinfo|Network is unreachable/i, 'needs the network'],
  [/command not found/i, 'a command is missing'],
  [/(EACCES|EPERM|Permission denied).*\.claude/i, 'writes under ~/.claude'],
];
function envFailure(res) {
  if (res.outcome === 'timeout') return 'timed out';
  if (res.code === 127) return 'a command is missing';
  for (const [re, why] of ENV_RULES) if (re.test(res.output)) return why;
  return null;
}

// Harden and Catch, Table 3, with one choice of ours: a test that passes on both revisions
// says nothing about this change, so it is dropped rather than landed (it would only grow the suite).
function decide(p, r) {
  if (r === 'novm' || p === 'novm') return ['discard', "needs the VM run, and Docker isn't available here"];
  if (r === 'nobuild') return ['signal', 'cannot run on this revision'];
  if (r === 'pass') return p === 'pass' ? ['discard', 'passes before and after: says nothing about this change'] : ['land', p === 'nobuild' ? 'tests new functionality' : 'tests what this change fixed'];
  if (p === 'pass') return ['report', 'passed before this change, fails after: a possible regression'];
  if (p === 'nobuild') return ['report', 'fails on new functionality'];
  return ['discard', 'fails before and after'];
}

function worktree(dir, sha, name) {
  const wt = path.join(reportDir(dir, sha), name);
  tryGit(dir, 'worktree', 'remove', '--force', wt);
  fs.rmSync(wt, { recursive: true, force: true });
  git(dir, 'worktree', 'add', '--detach', '-q', wt, sha);
  return wt;
}

function run(dir) {
  const sha = git(dir, 'rev-parse', 'HEAD');
  const parent = base(dir);
  const work = reportDir(dir, sha);
  const manifest = readJson(path.join(work, 'tests.json'));
  const cfg = config(dir);
  const trees = { R: worktree(dir, sha, 'wt-R'), P: worktree(dir, parent, 'wt-P') };
  const vm = (manifest.tests || []).some(t => t.vm) ? vmImage() : null;
  const results = [];
  try {
    if (cfg.invariants) {
      const res = runOne(trees.R, { cmd: cfg.invariants });
      if (res.outcome !== 'pass') results.push({ id: 'invariants', risk: 'a known invariant of this repository', P: '-', R: res.outcome, decision: 'report', why: 'a fixed invariant check fails', assessed: 'rule', output: res.output });
    }
    for (const t of manifest.tests || []) {
      const src = path.join(work, 'tests', t.file);
      const out = {};
      for (const k of ['P', 'R']) {
        fs.mkdirSync(path.dirname(path.join(trees[k], t.file)), { recursive: true });
        fs.copyFileSync(src, path.join(trees[k], t.file));
        out[k] = runOne(trees[k], t, vm);
      }
      let [decision, why] = decide(out.P.outcome, out.R.outcome);
      const env = out.R.outcome !== 'pass' && envFailure(out.R);
      if (env && decision !== 'signal') [decision, why] = ['discard', `environment: ${env}`];
      if (decision === 'report' && [1, 2].some(() => runOne(trees.R, t, vm).outcome === 'pass')) [decision, why] = ['discard', 'flaky on this revision'];
      results.push({ id: t.id, risk: t.risk, file: t.file, cmd: t.cmd, vm: !!t.vm, P: out.P.outcome, R: out.R.outcome, decision, why, output: out.R.output });
    }
  } finally {
    for (const wt of Object.values(trees)) tryGit(dir, 'worktree', 'remove', '--force', wt);
  }
  writeJson(path.join(work, 'results.json'), { sha, parent, results });
  return { sha, parent, results };
}

// Verdicts from jit:assessor, {"<id>": "should-fail" | "should-pass"}: a report the assessor judges a
// false positive is dropped. Tests marked "land" are copied into the repository's working tree.
function finish(dir) {
  const sha = git(dir, 'rev-parse', 'HEAD');
  const work = reportDir(dir, sha);
  const { results } = readJson(path.join(work, 'results.json'));
  let verdicts = {};
  try { verdicts = readJson(path.join(work, 'verdicts.json')); } catch {}
  const catches = [], landed = [];
  for (const r of results) {
    if (r.decision === 'report' && r.assessed !== 'rule') {
      if (verdicts[r.id] === 'should-pass') { r.decision = 'discard'; r.why = 'assessor: the change meant this'; continue; }
      if (verdicts[r.id] !== 'should-fail') { r.decision = 'discard'; r.why = 'not assessed'; continue; }
    }
    if (r.decision === 'report') catches.push(r);
    if (r.decision === 'land') {
      const dest = path.join(dir, r.file);
      if (!fs.existsSync(dest)) { fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.copyFileSync(path.join(work, 'tests', r.file), dest); landed.push(r.file); }
    }
  }
  const notRun = results.filter(r => r.P === 'novm' || r.R === 'novm').map(r => r.id); // VM tests with no Docker: say so
  const report = { status: 'ran', tests: results.length, catches: catches.map(({ id, risk, file, cmd, P, R, why }) => ({ id, risk, file, cmd, P, R, why })), landed, notRun };
  writeReport(dir, sha, report);
  return report;
}

// --- The pre-PR hook. Fails open: any error here allows the PR. ---

// A repository's name, not its folder's: a linked worktree's folder can be called anything.
function repoName(top) {
  const common = path.resolve(top, git(top, 'rev-parse', '--git-common-dir'));
  return path.basename(common) === '.git' ? path.basename(path.dirname(common)) : path.basename(top);
}

function prRepoDir(cwd, name) {
  const top = tryGit(cwd, 'rev-parse', '--show-toplevel');
  if (top && (!name || repoName(top) === name)) return top;
  if (name && fs.existsSync(path.join(cwd, name, '.git'))) return path.join(cwd, name);
  return null;
}

// A report counts for HEAD if it is for HEAD, or for an earlier commit on the branch with only
// landed tests or a tiny change since (committing the landed tests moves HEAD).
function covered(dir) {
  const parent = base(dir);
  const commits = (tryGit(dir, 'rev-list', parent ? `${parent}..HEAD` : 'HEAD') || '').split('\n').filter(Boolean);
  if (!commits.length) return true;
  for (const c of commits) {
    let report;
    try { report = readJson(path.join(reportDir(dir, c), 'report.json')); } catch { continue; }
    const since = changes(dir, c, 'HEAD').filter(f => !(report.landed || []).includes(f.file) && !skipped(f.file, config(dir).skip));
    return since.reduce((n, f) => n + f.lines, 0) <= TINY_LINES;
  }
  return false;
}

function hook(input) {
  const ti = input.tool_input || {};
  const dir = prRepoDir(input.cwd || process.cwd(), ti.repo);
  if (!dir || covered(dir)) return;
  const sha = git(dir, 'rev-parse', '--short', 'HEAD');
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny',
    permissionDecisionReason: `jit: ${repoName(dir)} has no JiT report for ${sha}. Run the jit:run skill first (it skips tiny or low-risk changes itself), then open the PR.` } }));
}

// Confines the agents' writes. Other sessions and agents pass untouched.
function guard(input) {
  const who = input.agent_type, file = (input.tool_input || {}).file_path || (input.tool_input || {}).notebook_path || '';
  const ok = who === 'jit:generator' ? /[\\/]\.work[\\/]jit[\\/]/.test(file)
    : who === 'jit:assessor' ? /[\\/]\.work[\\/]jit[\\/][^\\/]+[\\/]verdicts\.json$/.test(file) : true;
  if (!ok) process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny',
    permissionDecisionReason: `jit: ${who} may write only ${who === 'jit:generator' ? 'under .work/jit/' : '.work/jit/<sha>/verdicts.json'}` } }));
}

const cmd = process.argv[2];
if (require.main !== module) {
  // required by tests: nothing runs
} else if (cmd === 'hook' || cmd === 'guard') {
  let s = '';
  process.stdin.on('data', c => (s += c)).on('end', () => { try { (cmd === 'hook' ? hook : guard)(JSON.parse(s || '{}')); } catch {} });
} else {
  const dir = repoDir();
  const print = o => process.stdout.write(JSON.stringify(o, null, 2) + '\n');
  if (cmd === 'triage') print(triage(dir));
  else if (cmd === 'skip') {
    const reason = arg('--reason');
    if (!reason) { console.error('jit skip needs --reason'); process.exit(2); }
    const sha = git(dir, 'rev-parse', 'HEAD');
    writeReport(dir, sha, { status: 'skipped', reason, by: 'judgement' });
    print({ sha, status: 'skipped', reason });
  }
  else if (cmd === 'run') print(run(dir));
  else if (cmd === 'finish') print(finish(dir));
  else { console.error('usage: jit.js triage|skip --reason …|run|finish|hook [--repo DIR]'); process.exit(2); }
}

module.exports = { decide, glob, envFailure, config };
