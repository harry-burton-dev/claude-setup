'use strict';
// Grades one Magister run against its case, by code. Each check names what it tested.
//   case.kind: flaw (a planted flaw must be named), literal (a rule taken against its intent must be named),
//              sound (support or "nothing material", no invented blocker), variant (a built alternative)
//   run: { finding: <markdown or null>, returned: <what the agent returned>, variants: [<file names>] }

// The finding's header: quoted strings, block lists and [] are what Magister writes.
function header(md) {
  const m = String(md || '').match(/^---\n([\s\S]*?)\n---/);
  if (!m) return null;
  const out = {};
  let key = null;
  for (const line of m[1].split('\n')) {
    const item = line.match(/^\s+-\s+"?(.*?)"?\s*$/);
    if (item && key) { out[key].push(item[1]); continue; }
    const kv = line.match(/^([a-z_]+):\s*(.*)$/);
    if (!kv) continue;
    key = kv[1];
    const v = kv[2].trim();
    out[key] = v === '' || v === '[]' ? [] : v.replace(/^"(.*)"$/, '$1');
  }
  return out;
}

function grade(c, run) {
  const checks = [];
  const add = (name, ok, detail) => checks.push({ name, ok: !!ok, ...(detail ? { detail } : {}) });
  const e = c.expect || {};
  const nothing = /nothing material/i.test(run.returned || '') || /nothing material/i.test(run.finding || '');
  if (!run.finding) {
    add('finding written', c.kind === 'sound' && nothing, nothing ? 'nothing material' : 'no finding and no "nothing material"');
    return { pass: checks.every(x => x.ok), checks };
  }
  const h = header(run.finding);
  add('valid header', h && h.topic && h.date && Array.isArray(h.lenses) && h.lenses.length && h.confidence);
  const text = run.finding.toLowerCase();
  const hit = list => (list || []).find(k => new RegExp(k, 'i').test(text));
  if (h && Array.isArray(h.lenses) && h.lenses.includes('research')) add('research has sources', Array.isArray(h.sources) && h.sources.length);
  if (c.kind === 'flaw' || c.kind === 'literal') add('caught', hit(e.mention_any), `looked for: ${(e.mention_any || []).join(', ')}`);
  if (c.kind === 'sound') {
    add('supports or adds nothing', nothing || (h && Array.isArray(h.lenses) && h.lenses.includes('support')));
    const bad = hit(e.must_not);
    add('no invented blocker', !bad, bad ? `said: ${bad}` : undefined);
  }
  if (c.kind === 'variant') add('built a variant', (run.variants || []).length || (h && Array.isArray(h.attachments) && h.attachments.length));
  return { pass: checks.every(x => x.ok), checks };
}

module.exports = { grade, header };
