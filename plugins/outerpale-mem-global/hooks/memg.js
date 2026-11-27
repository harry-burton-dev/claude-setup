#!/usr/bin/env node
// outerpale-mem-global's hooks. Silent unless there is something to say; any error prints nothing.
//   node memg.js session-start  (SessionStart) load the global memory; flag proposals not yet uploaded
//   node memg.js stop           (Stop) don't finish with proposals not yet uploaded (once; never loops)
//   node memg.js uploaded       (PostToolUse on the OneDrive upload) a proposal that arrived leaves the outbox
//   node memg.js guard          (PreToolUse) the loader only reads
// OUTERPALE_MEM_GLOBAL_HOME (default ~/.outerpale-mem-global) holds the outbox.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

const LOADER = 'outerpale-mem-global:loader';
function outbox() { return path.join(process.env.OUTERPALE_MEM_GLOBAL_HOME || path.join(os.homedir(), '.outerpale-mem-global'), 'outbox'); }
function pending() { try { return fs.readdirSync(outbox()).filter(f => f.endsWith('.md')); } catch { return []; } }
function out(obj) { process.stdout.write(JSON.stringify(obj)); }

const modes = {
  'session-start'() {
    // Every session, in any repository or none.
    const lines = [`Harry's global memory is in OneDrive Claude/memory/_global/. Before other work, run the ${LOADER} agent in the foreground and keep what it returns. As you learn something that would still be true in another repository, save it as the outerpale-mem-global:memory skill's "Save" section says.`];
    const n = pending().length;
    if (n) lines.push(`${n} global memory proposal(s) in ${outbox()} didn't reach OneDrive. Upload them as the outerpale-mem-global:memory skill's "Save" section says.`);
    out({ hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: lines.map(l => `outerpale-mem-global: ${l}`).join('\n') } });
  },
  stop(input) {
    if (input.stop_hook_active) return;               // already sent back once: never hold the session in a loop
    const n = pending().length;
    if (n) out({ decision: 'block', reason: `outerpale-mem-global: ${n} global memory proposal(s) in ${outbox()} haven't reached OneDrive. Upload them as the outerpale-mem-global:memory skill's "Save" section says, then finish. Don't mention it unless an upload fails.` });
  },
  uploaded(input) {
    const name = path.basename(String((input.tool_input || {}).filename || ''));
    const resp = typeof input.tool_response === 'string' ? input.tool_response : JSON.stringify(input.tool_response || '');
    if (!/\.md$/.test(name) || !/webUrl/.test(resp) || /\berror\b/i.test(resp)) return;
    fs.rmSync(path.join(outbox(), name), { force: true });
  },
  guard(input) {
    if (input.agent_type !== LOADER || !/^(?:Bash|Write|Edit|MultiEdit|NotebookEdit)$/.test(input.tool_name)) return;
    out({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: 'outerpale-mem-global: the global loader only reads memory; it never writes or runs commands.' } });
  },
};

let raw = '';
process.stdin.on('data', c => (raw += c));
process.stdin.on('end', () => { try { const m = modes[process.argv[2]]; if (m) m(JSON.parse(raw || '{}') || {}); } catch {} });
