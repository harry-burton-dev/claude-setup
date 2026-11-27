'use strict';
// The grader, on fixture findings: no model needed.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const { grade, header } = require('./grade');
const fx = n => fs.readFileSync(path.join(__dirname, 'fixtures', n), 'utf8');
const flaw = { kind: 'flaw', expect: { mention_any: ['idempot', 'duplicate'] } };

test('the header is read, quoted values and block lists included', () => {
  const h = header(fx('caught.md'));
  assert.equal(h.topic, 'Webhook retries: duplicates without an idempotency key');
  assert.deepEqual(h.lenses, ['analysis']);
  assert.deepEqual(h.attachments, []);
});

test('a planted flaw that is named passes; one that is missed fails', () => {
  assert.equal(grade(flaw, { finding: fx('caught.md') }).pass, true);
  const r = grade(flaw, { finding: fx('missed.md') });
  assert.equal(r.pass, false);
  assert.ok(r.checks.some(c => c.name === 'caught' && !c.ok));
});

test('a research finding needs sources', () => {
  const r = grade({ kind: 'flaw', expect: { mention_any: ['queue'] } }, { finding: fx('missed.md') });
  assert.ok(r.checks.some(c => c.name === 'research has sources' && !c.ok));
});

test('a sound design passes on support or "nothing material", and fails on an invented blocker', () => {
  const sound = { kind: 'sound', expect: { must_not: ['must fix', 'critical'] } };
  assert.equal(grade(sound, { finding: null, returned: 'Nothing material to add.' }).pass, true);
  const supportive = fx('caught.md').replace('"analysis"', '"support"').replace('will deliver duplicates', 'is sound');
  assert.equal(grade(sound, { finding: supportive }).pass, true);
  assert.equal(grade(sound, { finding: fx('caught.md').replace('will deliver', 'is a critical flaw that will deliver') }).pass, false);
});

test('a UI case needs a built variant', () => {
  const ui = { kind: 'variant', expect: {} };
  assert.equal(grade(ui, { finding: fx('caught.md'), variants: [] }).pass, false);
  assert.equal(grade(ui, { finding: fx('caught.md'), variants: ['x--alt.html'] }).pass, true);
});

test('no finding and no "nothing material" fails, and a broken header fails', () => {
  assert.equal(grade(flaw, { finding: null, returned: 'done' }).pass, false);
  assert.equal(grade(flaw, { finding: '# no header\nidempotency' }).pass, false);
});

test('a run that returns any of its finding to the session fails; a link or "nothing material" passes', () => {
  const sound = { kind: 'sound', expect: {} };
  assert.equal(grade(sound, { finding: null, returned: 'Nothing material to add.' }).pass, true);
  assert.equal(grade(flaw, { finding: fx('caught.md'), returned: 'Finding filed: https://x.sharepoint.com/f.md' }).pass, true);
  const leaked = grade(flaw, { finding: fx('caught.md'), returned: 'Retries will deliver duplicates. Finding filed: https://x/f.md' });
  assert.equal(leaked.pass, false);
  assert.ok(leaked.checks.some(c => c.name === 'returned only the link' && !c.ok));
});
