#!/usr/bin/env node
// Magister's hooks. Silent unless there is something to say; any error prints nothing.
//   node magister.js session-start  (SessionStart) findings an earlier session didn't get into OneDrive
//   node magister.js prompt         (UserPromptSubmit) a design or decision moment: suggest Magister, in the background
//   node magister.js guard          (PreToolUse) Magister writes only to .work/ and its outbox, and runs no shell
//   node magister.js uploaded       (PostToolUse on the OneDrive upload) a finding that arrived leaves the outbox
// MAGISTER_HOME (default ~/.magister) holds the outbox; the eval runner points it elsewhere.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

const AGENT = 'magister:magister';
// Design, UI and decision work, where a second perspective is most often worth having.
const MOMENT = /\b(?:design|architect\w*|approach|alternatives?|options?|trade-?offs?|should we|let'?s go with|i think we should|what if|ui|ux|layout|component|pattern|workflow|strategy|decide|decision|best practice|plan(?:ning)?|structure)\b/i;
// Machine-written prompts (notifications, subagent reports, reminders) are not the person.
const MACHINE = /<(?:task-notification|agent-message|system-reminder|local-command-stdout|wake|relay)\b|\[SYSTEM NOTIFICATION/;

function home() { return process.env.MAGISTER_HOME || path.join(os.homedir(), '.magister'); }
function outbox() { return path.join(home(), 'outbox'); }
function context(event, text) {
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: event, additionalContext: `magister: ${text}` } }));
}
function deny(reason) {
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: `magister: ${reason}` } }));
}
function inside(file, dir) { const r = path.relative(dir, file); return r !== '' && !r.startsWith('..') && !path.isAbsolute(r); }

const modes = {
  'session-start'() {
    let n = 0;
    try { n = fs.readdirSync(outbox()).filter(f => f.endsWith('.md')).length; } catch {}
    if (n) context('SessionStart', `${n} Magister finding(s) in ${outbox()} didn't reach OneDrive. Upload them as the magister skill's "Upload" section says, in the background, without mentioning it unless it fails.`);
  },
  prompt(input) {
    const p = String(input.prompt || '');
    if (MACHINE.test(p) || !MOMENT.test(p)) return;
    context('UserPromptSubmit', `this is design or decision work. If a second perspective would make it better (research, analysis of intent and assumptions, confirmation that a choice is sound, or an alternative), launch the ${AGENT} agent in the background as the magister skill says, carry on without waiting, and pass on its note when it reports. If nothing would add much, don't launch it and don't mention it.`);
  },
  guard(input) {
    if (input.agent_type !== AGENT) return;
    const tool = input.tool_name;
    if (tool === 'Bash') return deny('Magister runs no shell commands. Read, search the web, and write findings to its outbox or .work/.');
    if (!/^(?:Write|Edit|MultiEdit|NotebookEdit)$/.test(tool)) return;
    const ti = input.tool_input || {};
    const cwd = input.cwd || process.cwd();
    const file = path.resolve(cwd, ti.file_path || ti.notebook_path || '');
    if (![path.join(cwd, '.work'), home()].some(d => inside(file, d))) return deny(`Magister writes only into .work/ and ${home()}, never into the project itself: ${file}`);
  },
  uploaded(input) {
    const name = path.basename(String((input.tool_input || {}).filename || ''));
    const resp = typeof input.tool_response === 'string' ? input.tool_response : JSON.stringify(input.tool_response || '');
    // "error" counts only outside the file's own name and URL (a proposal may be called …-error-handling.md).
    const said = resp.split(name).join('').replace(/https?:\/\/\S+/g, '');
    if (!/\.md$/.test(name) || !/webUrl/.test(resp) || /\berror\b/i.test(said)) return;
    fs.rmSync(path.join(outbox(), name), { force: true });
  },
};

let raw = '';
process.stdin.on('data', c => (raw += c));
process.stdin.on('end', () => { try { const m = modes[process.argv[2]]; if (m) m(JSON.parse(raw || '{}') || {}); } catch {} });
