#!/usr/bin/env node
// Suggest additions to the project CLAUDE.md at the two moments they are most often due:
//   node suggest.js prompt   (UserPromptSubmit) the person has just corrected Claude
//   node suggest.js bash     (PostToolUse on Bash) a project command has now been run three times
// Silent otherwise. Never fails the session: any error prints nothing.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

const SKILL = 'outerpale-startup:project-claude-md';
// Words a correction opens with, or says outright.
const CORRECTION = /^\W*(?:no\b|nope\b|wrong\b|that'?s (?:not|wrong)|not (?:like )?that\b|don'?t\b|do not\b|stop\b|actually\b|again\b|i (?:said|told you|meant)\b)|\b(?:i told you|as i said|i already said|we always|we never|you keep|every time you)\b/i;
// Machine-written prompts (notifications, subagent reports, reminders) are not the person.
const MACHINE = /<(?:task-notification|agent-message|system-reminder|local-command-stdout|wake|relay)\b|\[SYSTEM NOTIFICATION/;
// Commands too everyday to be a project's own.
const EVERYDAY = /^(?:git\s+(?:status|log|diff|show|add|commit|push|pull|fetch|checkout|branch)|ls|cat|cd|pwd|echo|head|tail|grep|rg|find|sed|awk|wc|mkdir|rm|cp|mv|touch|which|true)\b/;
const RUNS = 3;

function stateFile(sid) { return path.join(os.homedir(), '.claude', 'outerpale-startup', `${sid || 'unknown'}.json`); }
function load(sid) { try { return JSON.parse(fs.readFileSync(stateFile(sid), 'utf8')); } catch { return { runs: {}, said: [] }; } }
function save(sid, st) { fs.mkdirSync(path.dirname(stateFile(sid)), { recursive: true }); fs.writeFileSync(stateFile(sid), JSON.stringify(st)); }
function say(event, text) {
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: event, additionalContext: `outerpale-startup: ${text}` } }));
}
// The command as a project would write it: no leading "cd … &&", first line only, spaces collapsed.
function normal(cmd) {
  return String(cmd || '').split('\n')[0].replace(/^\s*(?:cd\s+\S+\s*&&\s*)+/, '').replace(/\s+/g, ' ').trim();
}
function projectFile(cwd) { try { return fs.readFileSync(path.join(cwd || process.cwd(), 'CLAUDE.md'), 'utf8'); } catch { return ''; } }

function main(mode, input) {
  if (mode === 'prompt') {
    const p = String(input.prompt || '');
    if (MACHINE.test(p) || !CORRECTION.test(p)) return;
    say('UserPromptSubmit', `the user has just corrected you. If what they said is a rule, command or gotcha for this project that a future session should know, offer in one line to add it to the project CLAUDE.md (${SKILL} skill), and add it only on a yes. If it is a one-off, say nothing about it.`);
    return;
  }
  if (mode === 'bash' && input.tool_name === 'Bash') {
    const cmd = normal(input.tool_input && input.tool_input.command);
    if (!cmd || EVERYDAY.test(cmd) || projectFile(input.cwd).includes(cmd)) return;
    const st = load(input.session_id);
    st.runs[cmd] = (st.runs[cmd] || 0) + 1;
    const due = st.runs[cmd] >= RUNS && !st.said.includes(cmd);
    if (due) st.said.push(cmd);
    save(input.session_id, st);
    if (due) say('PostToolUse', `\`${cmd}\` has now been run ${st.runs[cmd]} times in this session. If it is one of this project's commands (install, check, test, run), offer in one line to add it to the project CLAUDE.md (${SKILL} skill), and add it only on a yes.`);
  }
}

let raw = '';
process.stdin.on('data', c => (raw += c));
process.stdin.on('end', () => { try { main(process.argv[2], JSON.parse(raw || '{}') || {}); } catch {} });
