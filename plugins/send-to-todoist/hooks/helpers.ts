// Pure helpers (no `$`): the engine only follows `$` within register.tsx.
import type { ActionItem, Plan, Priority } from '../types'

const TITLE_MAX = 200

/** Every object anywhere in `x` that has a string `id` (and a string `field`, if named). */
export function objectsWith(x: unknown, field?: string, out: Record<string, unknown>[] = []) {
  if (typeof x === 'string') {
    try {
      return objectsWith(JSON.parse(x), field, out)
    } catch {
      return out
    }
  }
  if (Array.isArray(x)) {
    for (const v of x) objectsWith(v, field, out)
  } else if (x && typeof x === 'object') {
    const o = x as Record<string, unknown>
    if (typeof o.id === 'string' && (!field || typeof o[field] === 'string')) out.push(o)
    for (const v of Object.values(o)) objectsWith(v, field, out)
  }
  return out
}

export function clip(s: string, max = TITLE_MAX) {
  const line = s.trim()
  return line.length > max ? `${line.slice(0, max - 1)}…` : line
}

export function parseJson<T>(text: string): T | undefined {
  const start = text.indexOf('{')
  const end = text.lastIndexOf('}')
  if (start < 0 || end <= start) return undefined
  try {
    return JSON.parse(text.slice(start, end + 1)) as T
  } catch {
    return undefined
  }
}

export const str = (v: unknown) => (typeof v === 'string' && v.trim() ? v.trim() : undefined)
const prio = (v: unknown): Priority => (v === 'p1' || v === 'p2' || v === 'p3' ? v : 'p4')

export function toItems(text: string): ActionItem[] {
  const j = parseJson<{ items?: unknown }>(text)
  if (!Array.isArray(j?.items)) return []
  return j.items
    .map(i => i as Record<string, unknown>)
    .filter(i => str(i.title))
    .map(i => ({ title: clip(str(i.title)!), dueString: str(i.dueString) }))
}

export function toPlan(text: string): Plan | undefined {
  const j = parseJson<Record<string, unknown>>(text)
  if (!j || !str(j.title)) return undefined
  const subtasks = Array.isArray(j.subtasks) ? j.subtasks.map(s => s as Record<string, unknown>) : []
  return {
    title: clip(str(j.title)!),
    description: str(j.description) ?? '',
    dueString: str(j.dueString),
    priority: prio(j.priority),
    subtasks: subtasks
      .filter(s => str(s.title))
      .map(s => ({ title: clip(str(s.title)!), dueString: str(s.dueString) })),
  }
}

/** Bulleted or numbered lines of a selection, when it holds two or more. */
export function listItems(text: string): string[] {
  const items = text
    .split('\n')
    .map(l => /^\s*(?:[-*•]|\d+[.)])\s+(.+)$/.exec(l)?.[1]?.trim())
    .filter((l): l is string => !!l)
  return items.length >= 2 ? items : []
}

export const SHAPE_SYSTEM =
  'You turn text a user selected into one Todoist task. Reply with JSON only: ' +
  '{"title": string, "dueString": string|null, "notes": string|null}. ' +
  'title: a short, actionable imperative (max 80 chars). ' +
  'dueString: a due date the text states, in natural language Todoist parses ("Friday", "tomorrow 3pm"), else null. Never invent one. ' +
  'notes: details from the text worth keeping that the title drops, else null.'

export const ITEMS_SYSTEM =
  "You read an AI assistant's reply and list concrete action items the USER still has to do " +
  '(things the reply asks or advises them to do). Not things the assistant did or will do, not optional ideas. ' +
  'Reply with JSON only: {"items": [{"title": string, "dueString": string|null}]}, at most 8, ' +
  'titles short and imperative, dueString only when the reply states a date. {"items": []} when there are none.'

export function planPrompt(source: string, previous?: Plan, feedback?: string) {
  const revise = previous
    ? `\n\nYour previous draft:\n${JSON.stringify(previous)}\n\nRevise it with this feedback from the user: ${feedback}`
    : ''
  return (
    '[Side request from the send-to-todoist mod. Do not continue the main task and call no tools.]\n' +
    'Using everything in this conversation, the project context and your memory, write a fully scoped plan ' +
    `for this action item so it can live in Todoist:\n\n"${source}"\n\n` +
    'Make it specific to this user and project: the goal, relevant context and constraints you know, ' +
    'concrete steps, open questions, and what "done" looks like. ' +
    'Reply with JSON only: {"title": string (short imperative), "description": string (Markdown: ' +
    '## Goal, ## Context, ## Steps, ## Open questions, ## Done when), "dueString": string|null, ' +
    '"priority": "p1"|"p2"|"p3"|"p4", "subtasks": [{"title": string, "dueString": string|null}] (3-8 steps)}' +
    revise
  )
}
