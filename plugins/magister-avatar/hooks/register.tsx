import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Avatar, Mood } from '../types'

// Magister advises Harry, not the session: while it runs its avatar shows in a
// side pane, and its report reaches the session as its finding's link alone.
const AGENT = 'magister:magister'
const PANE = 'magister'
const avatar = atom(
  { plugin: 'magister-avatar', key: 'avatar' } as const,
  { running: 0, last: 'idle' } as Avatar,
  { shape: 'avatar-1' },
)

const WORDS: Record<Mood | 'running', string> = {
  running: 'Thinking it over…',
  filed: 'Finding filed for you.',
  nothing: 'Nothing material to add.',
  stopped: 'Stopped before filing.',
  idle: 'Waiting.',
}
const COLOR: Record<Mood | 'running', string> = {
  running: '#d9a43b',
  filed: '#4f9d69',
  nothing: '#8a8f98',
  stopped: '#c0564b',
  idle: '#8a8f98',
}

// A hooded sage: a robe, a face in shadow, two eyes. A halo pulses while it runs.
function svg(mood: Mood | 'running'): string {
  const c = COLOR[mood]
  const halo =
    mood === 'running'
      ? `<circle cx="60" cy="60" r="54" fill="none" stroke="${c}" stroke-width="4"><animate attributeName="opacity" values="1;0.2;1" dur="1.6s" repeatCount="indefinite"/></circle>`
      : `<circle cx="60" cy="60" r="54" fill="none" stroke="${c}" stroke-width="4"/>`
  const eyes =
    mood === 'running'
      ? `<g fill="#f4e3b2"><ellipse cx="50" cy="56" rx="4" ry="4"><animate attributeName="ry" values="4;4;0.5;4" keyTimes="0;0.9;0.95;1" dur="3s" repeatCount="indefinite"/></ellipse><ellipse cx="70" cy="56" rx="4" ry="4"><animate attributeName="ry" values="4;4;0.5;4" keyTimes="0;0.9;0.95;1" dur="3s" repeatCount="indefinite"/></ellipse></g>`
      : `<g fill="#f4e3b2"><circle cx="50" cy="56" r="4"/><circle cx="70" cy="56" r="4"/></g>`
  const badge =
    mood === 'filed'
      ? `<circle cx="92" cy="92" r="14" fill="${c}"/><path d="M85 92l5 5 9-10" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>`
      : ''

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120"><clipPath id="m"><circle cx="60" cy="60" r="50"/></clipPath><circle cx="60" cy="60" r="50" fill="#232733"/>${halo}<g clip-path="url(#m)"><path d="M20 120c4-40 16-66 40-86 24 20 36 46 40 86z" fill="#3b3f6b"/><path d="M38 70c0-18 10-30 22-36 12 6 22 18 22 36-6 6-14 9-22 9s-16-3-22-9z" fill="#14161f"/>${eyes}</g><path d="M60 34l-3 -14h6z" fill="${c}"/>${badge}</svg>`
}

// The lines of a report the session may see: a finding's link, nothing of the finding.
function links(text: string): string[] {
  return [...text.matchAll(/Finding filed:\s*(\S+)/g)].map(m => m[1]!)
}

export const register: Register = on => {
  on('agent.spawn', { subagentType: AGENT }, async ($, e, next) => {
    const started = await next(e)
    await update($, avatar, a => ({ ...a, running: a.running + 1 }))
    void $.ui.open({ id: PANE, title: 'Magister' })

    return started
  })

  on('agent.report', { subagentType: AGENT }, async ($, e, next) => {
    await next(e)
    const found = links(e.text)
    const last: Mood =
      e.status !== 'completed' ? 'stopped' : found.length ? 'filed' : 'nothing'
    const link = found.find(l => l.startsWith('https://'))
    await update($, avatar, a => ({
      running: Math.max(0, a.running - 1),
      last,
      link: link ?? a.link,
    }))
    if (e.status !== 'completed') return { text: `Magister ${e.status} before filing.` }

    return {
      text: found.length
        ? found.map(l => `Finding filed: ${l}`).join('\n')
        : 'Nothing material to add.',
    }
  }).catch(() => ({
    text: 'Magister reported; its findings are in OneDrive Claude/magister/.',
  }))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const el = $.ui.resolve(e)
    const { Box, Text, Link } = el
    const a = await read($, avatar)
    const mood = a.running > 0 ? 'running' : a.last
    const words = WORDS[mood]

    return (
      <Box flexDirection="column" alignItems="center" gap={1}>
        {'Svg' in el ? (
          <el.Svg source={svg(mood)} alt={`Magister: ${words}`} width={120} height={120} />
        ) : (
          <Text color={COLOR[mood]}>(◕‿◕) Magister</Text>
        )}
        <Text bold>Magister</Text>
        <Text dimColor>{a.running > 1 ? `${words} (${a.running} running)` : words}</Text>
        {mood === 'filed' && a.link && <Link href={a.link} label="Open the finding in OneDrive" />}
      </Box>
    )
  })
}
