#!/usr/bin/env node
// outerpale-startup's in-session hooks. Silent unless there is something to say; any error prints nothing.
//   node suggest.js prompt   (UserPromptSubmit) a correction: suggest a project CLAUDE.md line.
//   node suggest.js bash     (PostToolUse on Bash) a project command's third run: suggest adding it.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

const SKILL = 'outerpale-startup:project-claude-md';
// A correction says so outright. A bare "no" isn't one: "no thats okay" agrees.
const CORRECTION = /^\W*(?:no\s*[,.!-]\s*(?!(?:that'?s|thats|it'?s|its)\s+(?:ok|okay|fine|good|great))\S|nope\b|wrong\b|that'?s (?:not right|not what|wrong)|not (?:like )?that\b)|\b(?:i told you|i said|i meant|as i said|i already said|we always|we never|you keep|every time you)\b/i;
// Machine-written prompts (notifications, subagent reports, reminders) are not the person.
const MACHINE = /<(?:task-notification|agent-message|system-reminder|local-command-stdout|wake|relay)\b|\[SYSTEM NOTIFICATION/;
// Commands too everyday to be a project's own.
const EVERYDAY = /^(?:git\s+(?:status|log|diff|show|add|commit|push|pull|fetch|checkout|branch)|ls|cat|cd|pwd|echo|head|tail|grep|rg|find|sed|awk|wc|mkdir|rm|cp|mv|touch|which|true)\b/;
// Inline scripts (python3 - <<EOF, node -e …) are Claude's own one-offs, not a project's command.
const INLINE = /^(?:python3?|node|bash|sh)\s+-[ec]?(?:\s|$)/;
const RUNS = 3;

function stateFile(sid) { return path.join(os.homedir(), '.claude', 'outerpale-startup', `${sid || 'unknown'}.json`); }
function load(sid) { try { return JSON.parse(fs.readFileSync(stateFile(sid), 'utf8')); } catch { return { runs: {}, said: [] }; } }
function save(sid, st) { fs.mkdirSync(path.dirname(stateFile(sid)), { recursive: true }); fs.writeFileSync(stateFile(sid), JSON.stringify(st)); }
function say(event, lines) {
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: event, additionalContext: lines.map(l => `outerpale-startup: ${l}`).join('\n') } }));
}
// The command as a project would write it: no leading "cd … &&", first line only, spaces collapsed.
function normal(cmd) {
  return String(cmd || '').split('\n')[0].replace(/^\s*(?:cd\s+\S+\s*&&\s*)+/, '').replace(/\s+/g, ' ').trim();
}
function projectFile(cwd) { try { return fs.readFileSync(path.join(cwd || process.cwd(), 'CLAUDE.md'), 'utf8'); } catch { return ''; } }

function main(mode, input) {
  if (mode === 'prompt') {
    const p = String(input.prompt || '');
    if (MACHINE.test(p)) return;
    const lines = [];
    if (CORRECTION.test(p)) lines.push(`the user has just corrected you. If what they said is a rule, command or gotcha for this project that a future session should know, offer in one line to add it to the project CLAUDE.md (${SKILL} skill), and add it only on a yes. If it is a one-off, say nothing about it.`);
    if (lines.length) say('UserPromptSubmit', lines);
    return;
  }
  if (mode === 'bash' && input.tool_name === 'Bash') {
    const cmd = normal(input.tool_input && input.tool_input.command);
    if (!cmd || EVERYDAY.test(cmd) || INLINE.test(cmd) || projectFile(input.cwd).includes(cmd)) return;
    const st = load(input.session_id);
    st.runs[cmd] = (st.runs[cmd] || 0) + 1;
    const due = st.runs[cmd] >= RUNS && !st.said.includes(cmd);
    if (due) st.said.push(cmd);
    save(input.session_id, st);
    if (due) say('PostToolUse', [`\`${cmd}\` has now been run ${st.runs[cmd]} times in this session. If it is one of this project's commands (install, check, test, run), offer in one line to add it to the project CLAUDE.md (${SKILL} skill), and add it only on a yes.`]);
  }
}

let raw = '';
process.stdin.on('data', c => (raw += c));
process.stdin.on('end', () => { try { main(process.argv[2], JSON.parse(raw || '{}') || {}); } catch {} });
