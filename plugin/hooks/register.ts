import type { EngineInterface, Register } from 'claude-code'

// Slash commands for the relevo CLI that answer by themselves, without a model turn, and a
// notice when a turn stops on a rate limit. The CLI (bin/relevo) does all the work; this
// module passes it the session's environment and shows what it printed. Nothing here ever
// switches accounts on its own: only the person's /switch does.

const CLI = 'relevo'
// What /relevo may run inside a session. Never `run`/`<name>` (that would start a nested
// Claude Code) or `add` (a browser sign-in belongs in a terminal).
const IN_SESSION = ['list', 'account', 'rename', 'names', 'new', 'fix', 'install', 'help']
const STAY = 'Stay on this account'
const ANYWAY = 'Switch anyway'

// Runs the CLI with the session's environment (session id, Claude's process id, project dir)
// on top of Claude Code's own, so it knows which profile and session it serves.
async function relevo($: EngineInterface, args: readonly string[], warnDays: string) {
  const env = await $.process.hookEnv()
  const run = await $.process.run([`${env.CLAUDE_PLUGIN_ROOT}/bin/${CLI}`, ...args], {
    env: { ...env, RELEVO_WARN_DAYS: warnDays },
    timeoutMs: 60_000,
  })
  const text = `${run.stdout}${run.stderr}`.trim() || `${CLI} exited with code ${run.exitCode}`
  return { code: run.exitCode, text, pid: env.CLAUDE_PID }
}

// Close this session once the command has answered; the relevo wrapper that started it then
// reopens the same conversation on the other account. /exit is the normal way out.
function closeSoon($: EngineInterface, pid: string | undefined) {
  $.clock.after(300, () => {
    $.command.run({ command: 'exit' }).catch(() => {
      if (/^\d+$/.test(pid ?? '')) void $.process.run(['kill', '-TERM', pid as string])
    })
  })
}

export const register: Register = (on, options) => {
  const days = Number(options.warn_days)
  const warnDays = Number.isInteger(days) && days > 0 ? String(days) : '5'

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'switch',
      description: 'Continue this conversation on another account',
      argumentHint: '<name>',
    })
    await $.command.register({
      name: 'account',
      description: 'Your accounts: login expiry and 5-hour / weekly usage',
    })
    await $.command.register({
      name: CLI,
      description: 'Accounts: list, account, rename, names, install',
      argumentHint: 'list | account | rename <name> <new> | names | install',
    })
    // Save the plugin's settings for the terminal CLI, and keep the copy on PATH current.
    void relevo($, ['_sync'], warnDays).catch(() => undefined)
    return next(e)
  })

  on('command.run', { command: 'switch' }, async ($, e) => {
    const words = e.args.trim().split(/\s+/).filter(Boolean)
    let ran = await relevo($, ['_switch', ...words], warnDays)
    if (ran.code === 4) {
      // That account is at a usage limit: ask before switching, never decide for the person.
      const pick = await $.ui
        .ask(`${ran.text} Switch anyway?`, { header: 'Usage limit', options: [STAY, ANYWAY] })
        .catch(() => STAY)
      if (pick !== ANYWAY) return { text: `${ran.text} Staying on this account.`, isTextDisplayOnly: true }
      ran = await relevo($, ['_switch', ...words, '--anyway'], warnDays)
    }
    if (ran.code === 0) closeSoon($, ran.pid)
    return { text: ran.text, isTextDisplayOnly: true }
  })

  on('command.run', { command: 'account' }, async $ => {
    const ran = await relevo($, ['account'], warnDays)
    return { text: ran.text, isTextDisplayOnly: true }
  })

  on('command.run', { command: CLI }, async ($, e) => {
    const args = e.args.trim().split(/\s+/).filter(Boolean)
    const sub = args[0] ?? 'help'
    if (!IN_SESSION.includes(sub)) {
      return {
        text: `/${CLI} ${sub} does not run inside a session. In a terminal:  ${CLI} ${e.args.trim()}`,
        isTextDisplayOnly: true,
      }
    }
    const ran = await relevo($, args.length ? args : ['help'], warnDays)
    return { text: ran.text, isTextDisplayOnly: true }
  })

  // A turn ended on a rate limit: say where the conversation could continue. Never switch.
  on('classic.StopFailure', async ($, e, next) => {
    if (e.error === 'rate_limit') {
      try {
        const ran = await relevo($, ['_limited'], warnDays)
        $.ui.log(ran.text)
        void $.ui.notify(ran.text, { title: 'Relevo' }).catch(() => undefined)
      } catch {
        // a notice is best effort; the stop itself is Claude Code's to report
      }
    }
    return next(e)
  })
}
