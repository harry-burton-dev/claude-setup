#!/usr/bin/env node
// Runs Magister on planted cases and grades each run by code.
//   node tests/evals/magister/run.js                 every case
//   node tests/evals/magister/run.js <case-id> ...   just these
// Each case gets a throwaway repo and outbox (MAGISTER_HOME), and nothing is uploaded.
// Results, with each run's cost, go to .work/evals/ in claude-setup (never committed). Read the transcripts too.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { grade } = require('./grade');

const here = __dirname;
const repoRoot = path.resolve(here, '..', '..', '..');
const plugin = path.join(repoRoot, 'plugins', 'magister');
const all = fs.readdirSync(path.join(here, 'cases')).filter(f => f.endsWith('.json')).map(f => f.replace(/\.json$/, '')).sort();
const ids = process.argv.slice(2).length ? process.argv.slice(2) : all;
// Only Magister: other plugins' hooks would ask questions a headless run can't answer.
const settings = JSON.stringify({ enabledPlugins: { 'magister@claude-setup': false, 'outerpale-devops@outerpale': false, 'outerpale-startup@claude-setup': false, 'egm@egm': false } });

function runCase(id) {
  const c = JSON.parse(fs.readFileSync(path.join(here, 'cases', `${id}.json`), 'utf8'));
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), `magister-eval-${id}-`));
  const repo = path.join(tmp, 'repo');
  const mhome = path.join(tmp, 'magister');
  for (const [f, text] of Object.entries(c.files)) { fs.mkdirSync(path.dirname(path.join(repo, f)), { recursive: true }); fs.writeFileSync(path.join(repo, f), text); }
  fs.mkdirSync(path.join(mhome, 'outbox'), { recursive: true });
  execFileSync('git', ['init', '-q', repo]);
  const brief = [
    'Run the magister:magister agent in the foreground and wait for it. Its brief:',
    `- Work: ${c.brief.work}`,
    `- Goal: ${c.brief.goal}`,
    `- Decision at hand: ${c.brief.decision}`,
    `- Files: ${Object.keys(c.files).map(f => path.join(repo, f)).join(', ')}`,
    `- Repository: eval. Scope: none. Session: none. Current time: ${new Date().toISOString()}`,
    `- Outbox: ${path.join(mhome, 'outbox')}. Don't upload.`,
    'Then print exactly what it returned, and nothing else.',
  ].join('\n');
  const t0 = Date.now();
  let out = {};
  try {
    const raw = execFileSync('claude', ['-p', '--output-format', 'json', '--plugin-dir', plugin, '--settings', settings,
      '--allowedTools', `WebSearch,WebFetch,Read,Glob,Grep,Edit(/${mhome}/**)`, '--', brief],
      { cwd: repo, env: { ...process.env, MAGISTER_HOME: mhome }, timeout: 15 * 60 * 1000, maxBuffer: 64 * 1024 * 1024 }).toString();
    out = JSON.parse(raw);
  } catch (err) { out = { result: `run failed: ${err.message.split('\n')[0]}` }; }
  const md = fs.readdirSync(path.join(mhome, 'outbox')).filter(f => f.endsWith('.md')).sort().pop();
  const run = {
    finding: md ? fs.readFileSync(path.join(mhome, 'outbox', md), 'utf8') : null,
    returned: out.result || '',
    variants: fs.readdirSync(path.join(mhome, 'outbox')).filter(f => !f.endsWith('.md')),
  };
  const g = grade(c, run);
  return { id, kind: c.kind, pass: g.pass, checks: g.checks, cost_usd: out.total_cost_usd ?? null, seconds: Math.round((Date.now() - t0) / 1000), returned: run.returned, finding: run.finding, variants: run.variants, workdir: tmp };
}

const results = [];
for (const id of ids) {
  const r = runCase(id);
  results.push(r);
  const failed = r.checks.filter(x => !x.ok).map(x => x.name + (x.detail ? ` (${x.detail})` : '')).join('; ');
  console.log(`${r.pass ? 'pass' : 'FAIL'}  ${id}  ${r.seconds}s  $${r.cost_usd ?? '?'}${failed ? '  - ' + failed : ''}`);
}
const dir = path.join(repoRoot, '.work', 'evals');
fs.mkdirSync(dir, { recursive: true });
const file = path.join(dir, `magister-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
fs.writeFileSync(file, JSON.stringify(results, null, 2));
const cost = results.reduce((s, r) => s + (r.cost_usd || 0), 0);
console.log(`${results.filter(r => r.pass).length}/${results.length} passed, $${cost.toFixed(2)} at API prices. Results: ${file}`);
