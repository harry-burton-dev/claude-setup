import { expect, test } from 'claude-code/testing'

const ADD = 'mcp__14a0f362-ccb1-4e6a-a43c-45d36f83667a__add-tasks'
const MENU = { plugin: 'send-to-todoist', surface: 'desktop', component: 'ContextMenu' } as const

function stub(on: any, sent: any[], toasts: string[]) {
  on('session.id', () => ({ value: 'sess-1' }))
  on('session.cwd', () => ({ value: 'C:/dev' }))
  on('ui.toast', (_: unknown, e: any) => {
    toasts.push(e.text ?? String(e))
    return { value: undefined }
  })
  on('model.complete', () => ({
    value: {
      isAnswered: true,
      text: '{"title": "Email Sam the report", "dueString": "Friday", "notes": null}',
      usage: { inputTokens: 1, outputTokens: 1 },
    },
  }))
  on('tool.call', { tool: ADD }, (_: unknown, e: any) => {
    sent.push(...e.tasks)
    return { result: { tasks: e.tasks.map((t: any, i: number) => ({ id: `t${i}`, content: t.content })) } }
  })
}

test('quick send shapes the task and files it in the Inbox labelled Claude', async ($, on) => {
  const sent: any[] = []
  const toasts: string[] = []
  stub(on, sent, toasts)
  const ui = await $.ui.mount({ ...MENU, props: { selection: { text: 'remember to email sam the report by friday' } } })
  await ui.press({ key: 'todoist' })

  expect(toasts).toEqual(['Added to Todoist: Email Sam the report'])
  expect(sent.length).toBe(1)
  expect(sent[0].content).toBe('Email Sam the report')
  expect(sent[0].dueString).toBe('Friday')
  expect(sent[0].projectId).toBe('inbox')
  expect(sent[0].labels).toEqual(['Claude'])
  await ui.unmount()
})

test('a bulleted selection offers one task per line', async ($, on) => {
  const sent: any[] = []
  stub(on, sent, [])
  const ui = await $.ui.mount({ ...MENU, props: { selection: { text: '- buy milk\n- call mum\n- fix bike' } } })
  await ui.press({ key: 'todoist-list' })

  expect(sent.map(t => t.content)).toEqual(['buy milk', 'call mum', 'fix bike'])
  await ui.unmount()
})

test('no selection, no rows', async $ => {
  const ui = await $.ui.mount({ ...MENU, props: {} })
  expect(await ui.find({ type: 'Button' })).toBeUndefined()
  await ui.unmount()
})
