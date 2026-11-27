import { expect, test } from 'claude-code/testing'

const PANE = {
  plugin: 'magister-avatar',
  component: 'Pane',
  requestId: 'magister',
  props: {
    title: 'Magister',
    isFocused: false,
    bodyColumns: 40,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 20 },
    view: {},
  },
} as const
const REPORT = {
  agentId: 'a1',
  subagentType: 'magister:magister',
  provider: { plugin: 'magister', tier: 'user' },
  status: 'completed',
} as const
const LINK = 'https://x-my.sharepoint.com/Claude/magister/2026-11-27-retries.md'

function engine(on: any) {
  // Each hook here stands for the engine beneath the mod.
  on('agent.spawn', () => ({ model: 'opus', agentId: 'a1' }))
  on('agent.report', (_: unknown, e: { text: string }) => ({ text: e.text }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
}

test('the session gets only the link, never the finding', async ($, on) => {
  engine(on)
  const r = await $.agent.report({
    ...REPORT,
    text: 'Retries will deliver duplicates without an idempotency key.\nFinding filed: ' + LINK,
  })
  expect(r.text).toBe('Finding filed: ' + LINK)
})

test('a report with no link becomes "Nothing material to add."', async ($, on) => {
  engine(on)
  const r = await $.agent.report({ ...REPORT, text: 'Use a queue instead; it is simpler.' })
  expect(r.text).toBe('Nothing material to add.')
})

test('another agent\'s report is untouched', async ($, on) => {
  engine(on)
  const r = await $.agent.report({ ...REPORT, subagentType: 'Explore', text: 'found it in a.ts' })
  expect(r.text).toBe('found it in a.ts')
})

test('the avatar thinks while Magister runs, then links the finding', async ($, on) => {
  engine(on)
  await $.agent.spawn({
    tool_use_id: 't1',
    prompt: 'brief',
    description: 'Magister',
    subagentType: 'magister:magister',
    provider: { plugin: 'magister', tier: 'user' },
    parentModel: 'opus',
    background: true,
    fork: false,
  })
  for (const surface of ['desktop', 'terminal'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /Thinking/ }))?.text).toBe('Thinking it over…')
    await ui.unmount()
  }

  await $.agent.report({ ...REPORT, text: 'Finding filed: ' + LINK })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /filed/ }))?.text).toBe('Finding filed for you.')
  expect((await ui.find({ type: 'Link' }))?.props.href).toBe(LINK)
  expect(await ui.find({ type: 'Svg' })).toBeTruthy()
  await ui.unmount()
})
