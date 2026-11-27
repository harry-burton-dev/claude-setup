#!/usr/bin/env node
// outerpale-mem's hooks. Silent unless there is something to say; any error prints nothing.
//   node mem.js session-start  (SessionStart) load this repository's memory; flag proposals not yet uploaded
//   node mem.js stop           (Stop) don't finish with proposals not yet uploaded (once; never loops)
//   node mem.js uploaded       (PostToolUse on the OneDrive upload) a proposal that arrived leaves the outbox
//   node mem.js guard          (PreToolUse) the loader only reads
// OUTERPALE_MEM_HOME (default ~/.outerpale-mem) holds the outbox.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const LOADER = 'outerpale-mem:loader';
function outbox() { return path.join(process.env.OUTERPALE_MEM_HOME || path.join(os.homedir(), '.outerpale-mem'), 'outbox'); }
function pending() { try { return fs.readdirSync(outbox()).filter(f => f.endsWith('.md')); } catch { return []; } }
function repo(cwd) {
  try { return path.basename(execFileSync('git', ['rev-parse', '--show-toplevel'], { cwd, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim()); } catch { return null; }
}
function out(obj) { process.stdout.write(JSON.stringify(obj)); }

const modes = {
  'session-start'(input) {
    const name = repo(input.cwd || process.cwd());
    const lines = [];
    if (name) lines.push(`this repository's memory is in OneDrive Claude/memory/${name}/. Before other work, run the ${LOADER} agent in the foreground with the repository name "${name}", and keep what it returns as this session's memory. As you learn something worth remembering, save it as the outerpale-mem:memory skill's "Save" section says.`);
    const n = pending().length;
    if (n) lines.push(`${n} memory proposal(s) in ${outbox()} didn't reach OneDrive. Upload them as the outerpale-mem:memory skill's "Save" section says.`);
    if (lines.length) out({ hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: lines.map(l => `outerpale-mem: ${l}`).join('\n') } });
  },
  stop(input) {
    if (input.stop_hook_active) return;               // already sent back once: never hold the session in a loop
    const n = pending().length;
    if (n) out({ decision: 'block', reason: `outerpale-mem: ${n} memory proposal(s) in ${outbox()} haven't reached OneDrive. Upload them as the outerpale-mem:memory skill's "Save" section says, then finish. Don't mention it unless an upload fails.` });
  },
  uploaded(input) {
    const name = path.basename(String((input.tool_input || {}).filename || ''));
    const resp = typeof input.tool_response === 'string' ? input.tool_response : JSON.stringify(input.tool_response || '');
    if (!/\.md$/.test(name) || !/webUrl/.test(resp) || /\berror\b/i.test(resp)) return;
    fs.rmSync(path.join(outbox(), name), { force: true });
  },
  guard(input) {
    if (input.agent_type !== LOADER || !/^(?:Bash|Write|Edit|MultiEdit|NotebookEdit)$/.test(input.tool_name)) return;
    out({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: 'outerpale-mem: the loader only reads memory; it never writes or runs commands.' } });
  },
};

let raw = '';
process.stdin.on('data', c => (raw += c));
process.stdin.on('end', () => { try { const m = modes[process.argv[2]]; if (m) m(JSON.parse(raw || '{}') || {}); } catch {} });
