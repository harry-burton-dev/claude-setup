import { expect, test } from 'claude-code/testing'

const T = 'mcp__14a0f362-ccb1-4e6a-a43c-45d36f83667a__'
const P = 'send-to-todoist'
const usage = { inputTokens: 1, outputTokens: 1 }
const ANSWER = 'Here is what is left. '.repeat(20)
const PLAN = {
  title: 'Renew passport',
  description: '## Goal\nNew passport before the trip.',
  dueString: 'next Friday',
  priority: 'p2',
  subtasks: [{ title: 'Book photo' }, { title: 'Fill in form', dueString: 'Monday' }],
}

function stub(on: any) {
  const sent: any[] = []
  const deleted: string[] = []
  let next = 0
  on('session.id', () => ({ value: 'sess-1' }))
  on('session.cwd', () => ({ value: 'C:/dev' }))
  on('ui.toast', () => ({ value: undefined }))
  on('turn.complete', (_: unknown, e: any) => ({ text: e.answer }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.close', () => ({ value: undefined }))
  on('model.complete', (_: unknown, e: any) => ({
    value: {
      isAnswered: true,
      usage,
      text: String(e.system).includes("assistant's reply")
        ? '{"items": [{"title": "Renew passport", "dueString": null}, {"title": "Email landlord", "dueString": "Friday"}]}'
        : '{"title": "x", "dueString": null, "notes": null}',
    },
  }))
  on('model.fork', () => ({ value: { isAnswered: true, usage, effort: 'medium', text: JSON.stringify(PLAN) } }))
  on('tool.call', { tool: `${T}add-tasks` }, (_: unknown, e: any) => {
    sent.push(...e.tasks)
    return { result: { tasks: e.tasks.map((t: any) => ({ id: `t${next++}`, content: t.content })) } }
  })
  on('tool.call', { tool: `${T}delete-object` }, (_: unknown, e: any) => {
    deleted.push(e.id)
    return { result: { ok: true } }
  })
  return { sent, deleted }
}

const turnDone = ($: any) =>
  $.turn.complete({ answer: ANSWER, durationMs: 10, isAborted: false, turnId: 'turn-1', reason: 'completed' } as any)

test('action items in a reply show above the prompt and Add all files them', async ($, on) => {
  const { sent } = stub(on)
  await turnDone($)

  const band = await $.ui.mount({ plugin: P, surface: 'desktop', component: 'AbovePrompt', props: {} } as any)
  expect(await band.find({ type: 'Text', text: /2 action items/ })).toBeDefined()
  await band.press({ key: 'items-add' })

  expect(sent.map(t => t.content)).toEqual(['Renew passport', 'Email landlord'])
  expect(sent[1].dueString).toBe('Friday')
  expect(sent.every(t => t.labels[0] === 'Claude' && t.projectId === 'inbox')).toBe(true)
  await band.unmount()
})

test('a plan is drafted in the side pane, revised, then approved as a parent task with subtasks', async ($, on) => {
  const { sent } = stub(on)
  await turnDone($)

  const band = await $.ui.mount({ plugin: P, surface: 'desktop', component: 'AbovePrompt', props: {} } as any)
  await band.press({ key: 'items-review' })
  const pane = await $.ui.mount({ plugin: P, surface: 'desktop', component: 'Pane', requestId: 'todoist', props: {} } as any)
  await pane.press({ key: 'item-plan-0' })

  expect(await pane.find({ type: 'Markdown' })).toBeDefined()
  expect(await pane.find({ type: 'Input', key: 'revise' })).toBeDefined()
  expect(sent.length).toBe(0) // nothing goes to Todoist before approval

  await pane.press({ key: 'plan-approve' })
  expect(sent.map(t => t.content)).toEqual(['Renew passport', 'Book photo', 'Fill in form'])
  expect(sent[0].priority).toBe('p2')
  expect(sent[0].description).toContain('## Goal')
  expect(sent[1].parentId).toBe('t0')
  expect(sent[2].dueString).toBe('Monday')
  await pane.unmount()
  await band.unmount()
})

test('Undo deletes what was just added', async ($, on) => {
  const { deleted } = stub(on)
  await turnDone($)
  const band = await $.ui.mount({ plugin: P, surface: 'desktop', component: 'AbovePrompt', props: {} } as any)
  await band.press({ key: 'items-add' })
  await band.press({ key: 'undo' })

  expect(deleted.sort()).toEqual(['t0', 't1'])
  await band.unmount()
})
