export type Mood = 'idle' | 'filed' | 'nothing' | 'stopped'
export type Avatar = { running: number; last: Mood; link?: string }

declare module 'claude-code' {
  interface PluginState {
    'magister-avatar': { avatar: Shaped<Avatar> }
  }
}
