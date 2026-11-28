#!/usr/bin/env node
// Evals for jit:assessor: planted candidate catches, each with the verdict it should get.
//   node tests/evals/jit/run.js                  every case, with the assessor run headless
//   node tests/evals/jit/run.js <case-id> ...    just these
//   node tests/evals/jit/run.js --check          no model: each case's test really fails on its code
// Each case becomes a throwaway repository holding the code at the change, plus a JiT results file
// with the one candidate catch, the way jit.js run leaves it. Results go to .work/evals/jit/.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');

const here = __dirname;
const repoRoot = path.resolve(here, '..', '..', '..');
const plugin = path.join(repoRoot, 'plugins', 'jit');
const all = fs.readdirSync(path.join(here, 'cases')).filter(f => f.endsWith('.json')).map(f => f.replace(/\.json$/, '')).sort();
// Only the jit plugin: other plugins' hooks would ask questions a headless run can't answer.
const settings = JSON.stringify({ enabledPlugins: { 'jit@claude-setup': false, 'magister@claude-setup': false, 'outerpale-devops@outerpale': false, 'outerpale-startup@claude-setup': false, 'outerpale-mem@claude-setup': false, 'outerpale-mem-global@claude-setup': false } });

const load = id => JSON.parse(fs.readFileSync(path.join(here, 'cases', `${id}.json`), 'utf8'));
const grade = (c, verdicts) => ({ expect: c.expect, got: verdicts[c.test.id] || 'none', pass: verdicts[c.test.id] === c.expect });

// The case as a repository at the change, with the test where JiT would have put it.
function materialise(id, c) {
  const repo = path.join(fs.mkdtempSync(path.join(os.tmpdir(), `jit-eval-${id}-`)), 'repo');
  for (const [f, text] of Object.entries(c.files)) { fs.mkdirSync(path.dirname(path.join(repo, f)), { recursive: true }); fs.writeFileSync(path.join(repo, f), text); }
  const git = (...a) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...a], { cwd: repo, stdio: 'ignore' });
  git('init', '-q'); git('add', '.'); git('commit', '-qm', c.intent);
  const sha = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: repo }).toString().trim();
  const work = path.join(repo, '.work', 'jit', sha);
  const t = c.test;
  fs.mkdirSync(path.dirname(path.join(work, 'tests', t.file)), { recursive: true });
  fs.writeFileSync(path.join(work, 'tests', t.file), t.body);
  const cmd = t.file.endsWith('.js') ? `node ${t.file}` : `bash ${t.file}`;
  fs.writeFileSync(path.join(work, 'results.json'), JSON.stringify({ sha, results: [{ id: t.id, risk: t.risk, file: t.file, cmd, P: t.P, R: t.R,
    decision: 'report', why: t.P === 'pass' ? 'passed before this change, fails after: a possible regression' : 'fails on new functionality', output: t.output }] }, null, 2));
  return { repo, work, cmd };
}

function check() {
  let bad = 0;
  for (const id of all) {
    const c = load(id);
    if (!['should-pass', 'should-fail'].includes(c.expect) || !c.intent || !c.test || !c.test.id || !Object.keys(c.files || {}).length) { console.log(`${id}: malformed`); bad++; continue; }
    const { repo, work, cmd } = materialise(id, c);
    fs.mkdirSync(path.dirname(path.join(repo, c.test.file)), { recursive: true });
    fs.copyFileSync(path.join(work, 'tests', c.test.file), path.join(repo, c.test.file));
    const r = spawnSync('bash', ['-c', cmd], { cwd: repo, encoding: 'utf8' });
    if (r.status === 0) { console.log(`${id}: its test passes on its code, so it is no candidate catch`); bad++; }
  }
  process.exit(bad ? 1 : 0);
}

function runCase(id) {
  const c = load(id);
  const { repo, work } = materialise(id, c);
  const brief = [
    'Run the jit:assessor agent in the foreground and wait for it. Its brief:',
    `- results file: ${path.join(work, 'results.json')}`,
    `- the tests are under ${path.join(work, 'tests')}/`,
    `- the code at the change is the repository ${repo}`,
    `- intent text: ${c.intent}`,
    'Then print exactly what it returned, and nothing else.',
  ].join('\n');
  const t0 = Date.now();
  let out = {};
  try {
    const raw = execFileSync('claude', ['-p', '--output-format', 'json', '--plugin-dir', plugin, '--settings', settings,
      '--allowedTools', `Read,Glob,Grep,Edit(/${work}/**)`, '--', brief],
      { cwd: repo, timeout: 10 * 60 * 1000, maxBuffer: 64 * 1024 * 1024 }).toString();
    out = JSON.parse(raw);
  } catch (err) { out = { result: `run failed: ${err.message.split('\n')[0]}` }; }
  let verdicts = {};
  try { verdicts = JSON.parse(fs.readFileSync(path.join(work, 'verdicts.json'), 'utf8')); } catch {}
  return { id, kind: c.kind, ...grade(c, verdicts), said: out.result, seconds: Math.round((Date.now() - t0) / 1000), cost_usd: out.total_cost_usd, repo };
}

if (require.main === module) {
  const argv = process.argv.slice(2);
  if (argv.includes('--check')) check();
  const results = (argv.length ? argv : all).map(id => { const r = runCase(id); console.log(`${r.pass ? 'pass' : 'FAIL'} ${id}: expected ${r.expect}, got ${r.got} (${r.seconds}s)`); return r; });
  const dir = path.join(repoRoot, '.work', 'evals', 'jit');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(file, JSON.stringify(results, null, 2));
  const passed = results.filter(r => r.pass).length;
  const fp = results.filter(r => r.kind === 'false-positive'), real = results.filter(r => r.kind === 'real-bug');
  console.log(`${passed}/${results.length} passed: false positives dropped ${fp.filter(r => r.pass).length}/${fp.length}, real bugs upheld ${real.filter(r => r.pass).length}/${real.length}. Results: ${file}`);
  process.exit(passed === results.length ? 0 : 1);
}

module.exports = { grade };
