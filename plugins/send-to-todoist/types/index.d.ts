export type Priority = 'p1' | 'p2' | 'p3' | 'p4'

export type TaskDraft = {
  title: string
  description?: string
  dueString?: string
  priority: Priority
  projectId: string
}

export type ActionItem = { title: string; dueString?: string }

export type Plan = {
  title: string
  description: string
  dueString?: string
  priority: Priority
  subtasks: ActionItem[]
}

export type Project = { id: string; name: string }

/** What the side pane is showing. */
export type View =
  | { kind: 'none' }
  | { kind: 'draft'; draft: TaskDraft }
  | { kind: 'items' }
  | { kind: 'plan'; source: string; plan?: Plan; error?: string }

export type Added = { ids: string[]; label: string }

declare module 'claude-code' {
  interface PluginState {
    'send-to-todoist': {
      view: Shaped<View>
      items: Shaped<ActionItem[]>
      added: Shaped<Added | null>
      projects: Shaped<Project[]>
      busy: string | null
    }
  }
}
