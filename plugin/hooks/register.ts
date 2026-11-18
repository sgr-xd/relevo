import type { EngineInterface, Register } from 'claude-code'

// Slash commands for the relevo CLI that answer by themselves, without a model turn.
// The CLI (bin/relevo) does all the work; this module only passes it the session's
// environment and shows what it printed.

const CLI = 'relevo'
// What /relevo may run inside a session. Never `run`/`<name>` (that would start a nested
// Claude Code) or `add` (a browser sign-in belongs in a terminal).
const IN_SESSION = ['list', 'rename', 'names', 'new', 'fix', 'install', 'help']

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
      name: CLI,
      description: 'Accounts: list, rename, names, install',
      argumentHint: 'list | rename <name> <new> | names | install',
    })
    // Keep the installed copy on PATH (relevo install) in step with this plugin version.
    void relevo($, ['_sync'], warnDays).catch(() => undefined)
    return next(e)
  })

  on('command.run', { command: 'switch' }, async ($, e) => {
    const name = e.args.trim()
    const ran = await relevo($, name ? ['_switch', name] : ['_switch'], warnDays)
    if (ran.code === 0) {
      // Close this session once the command has answered; the relevo wrapper that started it
      // then reopens the same conversation on the other account. /exit is the normal way out.
      $.clock.after(300, () => {
        $.command.run({ command: 'exit' }).catch(() => {
          if (/^\d+$/.test(ran.pid ?? '')) void $.process.run(['kill', '-TERM', ran.pid])
        })
      })
    }
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
}
