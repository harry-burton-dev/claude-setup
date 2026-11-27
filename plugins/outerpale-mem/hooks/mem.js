#!/usr/bin/env node
// outerpale-mem's hooks. Silent unless there is something to say; any error prints nothing.
//   node mem.js session-start  (SessionStart) load each repository's memory; flag proposals not yet uploaded
//   node mem.js stop           (Stop) don't finish with proposals not yet uploaded (once; never loops)
//   node mem.js uploaded       (PostToolUse on the OneDrive upload) a proposal that arrived leaves the outbox
//   node mem.js guard          (PreToolUse) the loader only reads
// OUTERPALE_MEM_HOME (default ~/.outerpale-mem) holds the outbox.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

// What the loader may not do: run commands, edit files, or change OneDrive through the connector.
const WRITES = /^(?:Bash|Write|Edit|MultiEdit|NotebookEdit|mcp__.+__sharepoint_(?:upload_file|update_file|delete_item|move_item|rename_item|copy_item|create_folder))$/;
const LOADER = 'outerpale-mem:loader';
function outbox() { return path.join(process.env.OUTERPALE_MEM_HOME || path.join(os.homedir(), '.outerpale-mem'), 'outbox'); }
function pending() { try { return fs.readdirSync(outbox()).filter(f => f.endsWith('.md')); } catch { return []; } }
// Where the pending proposals go, from each one's repo: header ("" when a file has none).
function destinations() {
  const repos = pending().map(f => { try { return (fs.readFileSync(path.join(outbox(), f), 'utf8').match(/^repo:\s*"?([^"\n]+)"?\s*$/m) || [])[1] || ''; } catch { return ''; } });
  const names = [...new Set(repos.filter(Boolean))].sort();
  return names.length ? ` (for ${names.map(r => `Claude/memory/${r}/`).join(', ')})` : '';
}
// The session's repositories, found as outerpale-startup's session-start hook finds them: the one it
// starts in, or, from a non-git folder (a cloud session with several), each git repository directly under it.
function repos(cwd) {
  try { return [path.basename(execFileSync('git', ['rev-parse', '--show-toplevel'], { cwd, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim())]; } catch {}
  try { return fs.readdirSync(cwd).filter(n => fs.existsSync(path.join(cwd, n, '.git'))).sort(); } catch { return []; }
}
function out(obj) { process.stdout.write(JSON.stringify(obj)); }

const modes = {
  'session-start'(input) {
    const names = repos(input.cwd || process.cwd());
    const lines = [];
    if (names.length === 1) lines.push(`this repository's memory is in OneDrive Claude/memory/${names[0]}/. Before other work, run the ${LOADER} agent in the foreground with the repository name "${names[0]}", and keep what it returns as this session's memory. As you learn something worth remembering, save it as the outerpale-mem:memory skill's "Save" section says.`);
    if (names.length > 1) {
      lines.push(`this session has ${names.length} repositories (${names.join(', ')}), each with its own memory in OneDrive Claude/memory/<repo>/. Before other work, run the ${LOADER} agent in the foreground once for each:`);
      for (const r of names) lines.push(`- repository name "${r}" (Claude/memory/${r}/): keep what it returns as ${r}'s memory.`);
      lines.push(`As you learn something worth remembering, save it as the outerpale-mem:memory skill's "Save" section says, with repo set to the repository it belongs to.`);
    }
    const n = pending().length;
    if (n) lines.push(`${n} memory proposal(s) in ${outbox()}${destinations()} didn't reach OneDrive. Upload them as the outerpale-mem:memory skill's "Save" section says.`);
    if (lines.length) out({ hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: lines.map(l => `outerpale-mem: ${l}`).join('\n') } });
  },
  stop(input) {
    if (input.stop_hook_active) return;               // already sent back once: never hold the session in a loop
    const n = pending().length;
    if (n) out({ decision: 'block', reason: `outerpale-mem: ${n} memory proposal(s) in ${outbox()}${destinations()} haven't reached OneDrive. Upload them as the outerpale-mem:memory skill's "Save" section says, then finish. Don't mention it unless an upload fails.` });
  },
  uploaded(input) {
    const name = path.basename(String((input.tool_input || {}).filename || ''));
    const resp = typeof input.tool_response === 'string' ? input.tool_response : JSON.stringify(input.tool_response || '');
    // "error" counts only outside the file's own name and URL (a proposal may be called …-error-handling.md).
    const said = resp.split(name).join('').replace(/https?:\/\/\S+/g, '');
    if (!/\.md$/.test(name) || !/webUrl/.test(resp) || /\berror\b/i.test(said)) return;
    fs.rmSync(path.join(outbox(), name), { force: true });
  },
  guard(input) {
    if (input.agent_type !== LOADER || !WRITES.test(input.tool_name)) return;
    out({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: 'outerpale-mem: the loader only reads memory; it never writes or runs commands.' } });
  },
};

let raw = '';
process.stdin.on('data', c => (raw += c));
process.stdin.on('end', () => { try { const m = modes[process.argv[2]]; if (m) m(JSON.parse(raw || '{}') || {}); } catch {} });
