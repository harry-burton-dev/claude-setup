import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { ActionItem, Added, Plan, Priority, Project, TaskDraft, View } from '../types'
import { ITEMS_SYSTEM, SHAPE_SYSTEM, clip, listItems, objectsWith, parseJson, planPrompt, str, toItems, toPlan } from './helpers'

const SERVER = 'mcp__14a0f362-ccb1-4e6a-a43c-45d36f83667a'
const LABEL = 'Claude'
const PANE = 'todoist'
const view = atom({ plugin: 'send-to-todoist', key: 'view' } as const, { kind: 'none' } as View, { shape: 'view-1' })
const items = atom({ plugin: 'send-to-todoist', key: 'items' } as const, [] as ActionItem[], { shape: 'items-1' })
const added = atom({ plugin: 'send-to-todoist', key: 'added' } as const, null as Added | null, { shape: 'added-1' })
const projects = atom({ plugin: 'send-to-todoist', key: 'projects' } as const, [] as Project[], { shape: 'projects-1' })
const busy = atom({ plugin: 'send-to-todoist', key: 'busy' } as const, null as string | null)

const PRIORITIES: { value: Priority; label: string }[] = [
  { value: 'p1', label: 'P1 · urgent' },
  { value: 'p2', label: 'P2 · high' },
  { value: 'p3', label: 'P3 · medium' },
  { value: 'p4', label: 'P4 · none' },
]
const MIN_ANSWER = 200

type $ = EngineInterface

type Task = {
  content: string
  description?: string
  dueString?: string
  priority?: Priority
  projectId?: string
  parentId?: string
  labels: string[]
}

// ---- Todoist calls ----

async function todoist($: $, tool: string, input: Record<string, unknown>) {
  const res = await $.tool.call({ tool: `${SERVER}__${tool}`, ...input } as never)
  if ('deny' in res && res.deny) throw new Error(res.deny)
  if (res.isError) throw new Error(`${tool} failed: ${String(res.text ?? '').slice(0, 200)}`)
  return res.result
}

/** Adds tasks; resolves the new task ids (empty when the result names none). */
async function addTasks($: $, tasks: Task[]): Promise<string[]> {
  const result = await todoist($, 'add-tasks', { tasks })
  return [...new Set(objectsWith(result, 'content').map(o => o.id as string))]
}

async function deleteTask($: $, id: string) {
  await todoist($, 'delete-object', { type: 'task', id })
}

async function listProjects($: $): Promise<Project[]> {
  const result = await todoist($, 'find-projects', { limit: 200 })
  const seen = new Map<string, Project>()
  for (const o of objectsWith(result, 'name')) seen.set(o.id as string, { id: o.id as string, name: o.name as string })
  return [...seen.values()]
}

async function sourceLine($: $) {
  const [id, cwd] = await Promise.all([$.session.id(), $.session.cwd()])
  const date = new Date().toISOString().slice(0, 10)
  return `_From Claude Code · ${date} · ${cwd} · session ${id}_`
}

function draftToTask(d: TaskDraft, source: string): Task {
  return {
    content: clip(d.title),
    description: [d.description, source].filter(Boolean).join('\n\n'),
    ...(d.dueString ? { dueString: d.dueString } : {}),
    priority: d.priority,
    projectId: d.projectId,
    labels: [LABEL],
  }
}

/** Adds a plan as a parent task with its subtasks; resolves every new id. */
async function addPlan($: $, plan: Plan, source: string): Promise<string[]> {
  const [parent] = await addTasks($, [draftToTask({ ...plan, projectId: 'inbox' }, source)])
  if (!parent) throw new Error('Todoist did not return the new task id')
  if (plan.subtasks.length === 0) return [parent]
  const subs = await addTasks(
    $,
    plan.subtasks.map(s => ({
      content: clip(s.title),
      ...(s.dueString ? { dueString: s.dueString } : {}),
      parentId: parent,
      labels: [LABEL],
    })),
  )
  return [parent, ...subs]
}

// ---- model calls ----

/** Turns a raw selection into a tidy title, a due date it mentions, and notes. */
async function shapeTask($: $, text: string) {
  const r = await $.model.complete({
    model: 'haiku',
    maxTokens: 400,
    timeoutMs: 20000,
    system: SHAPE_SYSTEM,
    prompt: `<selection>\n${text}\n</selection>`,
  })
  const j = r.isAnswered ? parseJson<Record<string, unknown>>(r.text) : undefined
  return {
    title: clip(str(j?.title) ?? text.split('\n')[0] ?? text),
    dueString: str(j?.dueString),
    notes: str(j?.notes),
  }
}

/** The action items the user (not the assistant) still has to do, from a reply. */
async function findActionItems($: $, answer: string): Promise<ActionItem[]> {
  const r = await $.model.complete({
    model: 'haiku',
    maxTokens: 600,
    timeoutMs: 30000,
    system: ITEMS_SYSTEM,
    prompt: `<reply>\n${answer.slice(0, 12000)}\n</reply>`,
  })
  return r.isAnswered ? toItems(r.text) : []
}

/** A fully scoped plan, reasoned over this session's own transcript (system prompt, CLAUDE.md, memory) via a fork. */
async function makePlan($: $, source: string, previous?: Plan, feedback?: string): Promise<Plan> {
  const r = await $.model.fork({ effort: 'medium', prompt: planPrompt(source, previous, feedback) })
  if (!r.isAnswered) throw new Error(`no plan: ${r.reason}`)
  const plan = toPlan(r.text)
  if (!plan) throw new Error('the reply was not a plan')
  return plan
}

// ---- flows ----

/** Runs one Todoist job with a busy line; errors become a toast. */
async function job($: $, label: string, fn: () => Promise<void>) {
  await update($, busy, () => label)
  try {
    await fn()
  } catch (err) {
    $.ui.toast(`Todoist: ${err instanceof Error ? err.message : String(err)}`, { timeoutMs: 8000 })
  } finally {
    await update($, busy, () => null)
  }
}

async function remember($: $, ids: string[], label: string) {
  $.ui.toast(`Added to Todoist: ${label}`)
  await update($, added, () => (ids.length ? { ids, label } : null))
}

const openPane = ($: $, v: View) =>
  update($, view, () => v).then(() => $.ui.open({ id: PANE, title: 'Todoist' }))
const closePane = ($: $) =>
  update($, view, () => ({ kind: 'none' }) as View).then(() => $.ui.close({ id: PANE }))

async function sendQuick($: $, text: string) {
  await job($, 'adding task', async () => {
    const t = await shapeTask($, text)
    const notes = [t.notes, t.title !== clip(text) ? `> ${text.replace(/\n/g, '\n> ')}` : undefined]
    const task = draftToTask(
      { title: t.title, dueString: t.dueString, description: notes.filter(Boolean).join('\n\n'), priority: 'p4', projectId: 'inbox' },
      await sourceLine($),
    )
    await remember($, await addTasks($, [task]), t.title)
  })
}

async function sendMany($: $, list: ActionItem[]) {
  await job($, `adding ${list.length} tasks`, async () => {
    const source = await sourceLine($)
    const tasks = list.map(i => draftToTask({ title: i.title, dueString: i.dueString, priority: 'p4', projectId: 'inbox' }, source))
    await remember($, await addTasks($, tasks), `${list.length} tasks`)
  })
}

async function startPlan($: $, source: string, previous?: Plan, feedback?: string) {
  await openPane($, { kind: 'plan', source, plan: previous })
  await job($, previous ? 'revising plan' : 'planning', async () => {
    try {
      const plan = await makePlan($, source, previous, feedback)
      await update($, view, v => (v.kind === 'plan' && v.source === source ? ({ kind: 'plan', source, plan } as View) : v))
    } catch (err) {
      const error = err instanceof Error ? err.message : String(err)
      await update($, view, v => (v.kind === 'plan' && v.source === source ? { ...v, error } : v))
    }
  })
}

export const register: Register = on => {
  // A new prompt retires the last turn's offers.
  on('prompt.submit', async ($, e, next) => {
    await update($, added, () => null)
    await update($, items, () => [])
    return next(e)
  })

  // After each main-loop reply, look for things the user still has to do.
  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    if (!e.agentId && !e.isAborted && e.answer.length >= MIN_ANSWER) {
      const found = await findActionItems($, e.answer).catch(() => [] as ActionItem[])
      await update($, items, () => found)
    }
    return r
  })

  on('ui.render', { component: 'ContextMenu' }, ($, e, next) => {
    const selected = e.props.selection?.text.trim()
    if (!selected) return next(e)

    const { Box, Button, Text } = $.ui.resolve(e)
    const list = listItems(selected)

    const choose = () =>
      job($, 'reading selection', async () => {
        if ((await read($, projects)).length === 0) {
          const list = await listProjects($).catch(() => [] as Project[])
          await update($, projects, () => list)
        }
        const t = await shapeTask($, selected)
        await openPane($, {
          kind: 'draft',
          draft: { title: t.title, dueString: t.dueString, description: t.notes, priority: 'p4', projectId: 'inbox' },
        })
      })

    return (
      <Box flexDirection="column">
        <Button key="todoist" onPress={() => sendQuick($, selected)}>
          Send to Todoist <Text dimColor>Inbox · @{LABEL}</Text>
        </Button>
        <Button key="todoist-choose" onPress={choose}>
          Send to Todoist… <Text dimColor>project, priority, date</Text>
        </Button>
        {list.length > 0 && (
          <Button key="todoist-list" onPress={() => sendMany($, list.map(title => ({ title: clip(title) })))}>
            Send as {list.length} tasks
          </Button>
        )}
      </Box>
    )
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const [last, found, working] = await Promise.all([read($, added), read($, items), read($, busy)])
    if (!last && found.length === 0 && !working) return next(e)

    const { Box, Button, Text } = $.ui.resolve(e)
    const undo = () =>
      job($, 'undoing', async () => {
        for (const id of [...(last?.ids ?? [])].reverse()) await deleteTask($, id)
        await update($, added, () => null)
        $.ui.toast('Removed from Todoist')
      })

    // One flat row: the desktop app stacks a fragment's children, so each state
    // gets its own row Box with the Text and Buttons as direct children.
    if (working) {
      return (
        <Box flexDirection="row" alignItems="center" gap={1}>
          <Text dimColor>Todoist: {working}…</Text>
        </Box>
      )
    }
    if (last) {
      return (
        <Box flexDirection="row" alignItems="center" gap={1}>
          <Text dimColor>Added {last.label}</Text>
          <Button key="undo" label="Undo" onPress={undo} />
          <Button key="undo-hide" label="×" onPress={() => update($, added, () => null)} />
        </Box>
      )
    }
    return (
      <Box flexDirection="row" alignItems="center" gap={1}>
        <Text dimColor>
          {found.length} action item{found.length === 1 ? '' : 's'} in that reply
        </Text>
        <Button key="items-add" label="Add all" onPress={() => sendMany($, found)} />
        <Button key="items-review" label="Review…" onPress={() => openPane($, { kind: 'items' })} />
        <Button key="items-hide" label="×" onPress={() => update($, items, () => [])} />
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Input, Markdown, Select, Text } = $.ui.resolve(e)
    const [v, found, working, projectList] = await Promise.all([read($, view), read($, items), read($, busy), read($, projects)])

    if (v.kind === 'draft') {
      const d = v.draft
      const set = (patch: Partial<typeof d>) =>
        update($, view, cur => (cur.kind === 'draft' ? ({ kind: 'draft', draft: { ...cur.draft, ...patch } } as View) : cur))
      const send = () =>
        job($, 'adding task', async () => {
          const ids = await addTasks($, [draftToTask(d, await sourceLine($))])
          await closePane($)
          await remember($, ids, d.title)
        })
      const options = [{ value: 'inbox', label: 'Inbox' }, ...projectList.map(p => ({ value: p.id, label: p.name }))]
      return (
        <Box flexDirection="column" gap={1}>
          <Input key="title" label="Task" value={d.title} onInput={title => set({ title })} onSubmit={title => set({ title })} />
          <Input key="due" label="Due" placeholder="e.g. Friday 3pm" value={d.dueString ?? ''} onInput={dueString => set({ dueString })} onSubmit={dueString => set({ dueString })} />
          <Select key="project" label="Project" options={options} value={d.projectId} onSelect={projectId => set({ projectId })} />
          <Select key="priority" label="Priority" options={PRIORITIES} value={d.priority} onSelect={p => set({ priority: p as Priority })} />
          <Input key="notes" label="Notes" rows={4} value={d.description ?? ''} onInput={description => set({ description })} onSubmit={description => set({ description })} />
          <Box flexDirection="row" gap={1}>
            <Button key="draft-send" label={working ? 'Sending…' : 'Send to Todoist'} onPress={send} />
            <Button key="draft-cancel" label="Cancel" onPress={() => closePane($)} />
          </Box>
          <Text dimColor>Labelled @{LABEL}.</Text>
        </Box>
      )
    }

    if (v.kind === 'items') {
      return (
        <Box flexDirection="column" gap={1}>
          {found.length === 0 && <Text dimColor>No action items left.</Text>}
          {found.map((item, i) => (
            <Box flexDirection="column">
              <Text>
                {item.title}
                {item.dueString ? <Text dimColor> · {item.dueString}</Text> : null}
              </Text>
              <Box flexDirection="row" gap={1}>
                <Button
                  key={`item-add-${i}`}
                  label="Add"
                  onPress={async () => {
                    await sendMany($, [item])
                    await update($, items, list => list.filter(x => x.title !== item.title))
                  }}
                />
                <Button key={`item-plan-${i}`} label="Plan it…" onPress={() => startPlan($, item.title)} />
              </Box>
            </Box>
          ))}
          {found.length > 1 && (
            <Box flexDirection="row" gap={1}>
              <Button key="items-all" label="Add all" onPress={() => sendMany($, found).then(() => closePane($))} />
              <Button key="items-plan-all" label="Plan all as one…" onPress={() => startPlan($, found.map(i => `- ${i.title}`).join('\n'))} />
            </Box>
          )}
          <Button key="items-close" label="Close" onPress={() => closePane($)} />
        </Box>
      )
    }

    if (v.kind === 'plan') {
      const plan = v.plan
      const approve = () =>
        plan &&
        job($, 'adding plan', async () => {
          const ids = await addPlan($, plan, await sourceLine($))
          await closePane($)
          await remember($, ids, `plan “${plan.title}”`)
        })
      const meta = plan ? [plan.priority.toUpperCase(), plan.dueString].filter(Boolean).join(' · ') : ''
      return (
        <Box flexDirection="column" gap={1}>
          <Text dimColor>Planning: {clip(v.source, 120)}</Text>
          {working && <Text dimColor>Claude is {working}… (reads this conversation and memory)</Text>}
          {v.error && <Text color="red">Couldn't plan: {v.error}</Text>}
          {plan && (
            <Markdown
              text={`# ${plan.title}\n_${meta}_\n\n${plan.description}\n\n## Subtasks\n${plan.subtasks
                .map(s => `- [ ] ${s.title}${s.dueString ? ` _(${s.dueString})_` : ''}`)
                .join('\n')}`}
            />
          )}
          {plan && !working && (
            <Input
              key="revise"
              label="Revise"
              placeholder="Tell Claude what to change, then Enter"
              submitLabel="Revise"
              rows={2}
              onSubmit={feedback => feedback.trim() && startPlan($, v.source, plan, feedback.trim())}
            />
          )}
          <Box flexDirection="row" gap={1}>
            {plan && !working && <Button key="plan-approve" label="Approve → Todoist" onPress={approve} />}
            {!working && <Button key="plan-again" label="Regenerate" onPress={() => startPlan($, v.source)} />}
            <Button key="plan-discard" label="Discard" onPress={() => closePane($)} />
          </Box>
        </Box>
      )
    }

    return <Text dimColor>Nothing to send. Select text and right-click, or wait for action items.</Text>
  })
}
