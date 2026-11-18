// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The Relevo authors
import type { EngineInterface, Register } from 'claude-code'

// One slash command, /relevo, that answers by itself without a model turn; and a notice when a
// turn stops on a rate limit. Every subcommand lives under /relevo, so a Claude Code built-in can
// never collide with ours. The CLI (bin/relevo) does all the work; this module passes it the
// session's environment and shows what it printed. Nothing here ever switches accounts on its
// own: only the person's /relevo switch does.

const CLI = 'relevo'
// What /relevo runs inside a session besides `switch`, which is handled below. Never `run`/
// `<name>` (that would start a nested Claude Code) or `add` (a browser sign-in belongs in a
// terminal). Must equal IN_SESSION in bin/relevo; test/run.sh checks that it does.
const IN_SESSION = ['account', 'list', 'rename', 'names', 'new', 'fix', 'install', 'help']
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

// /relevo switch <name>: the CLI checks and writes the switch request; at a usage limit (exit 4)
// the person decides, never this module.
async function switchTo($: EngineInterface, words: readonly string[], warnDays: string) {
  let ran = await relevo($, ['_switch', ...words], warnDays)
  if (ran.code === 4) {
    const pick = await $.ui
      .ask(`${ran.text} Switch anyway?`, { header: 'Usage limit', options: [STAY, ANYWAY] })
      .catch(() => STAY)
    if (pick !== ANYWAY) return `${ran.text} Staying on this account.`
    ran = await relevo($, ['_switch', ...words, '--anyway'], warnDays)
  }
  if (ran.code === 0) closeSoon($, ran.pid)
  return ran.text
}

export const register: Register = (on, options) => {
  const days = Number(options.warn_days)
  const warnDays = Number.isInteger(days) && days > 0 ? String(days) : '5'

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: CLI,
      description: 'Accounts: switch, account, list, rename, names, install',
      argumentHint: 'switch <name> | account | list | rename <name> <new> | names | install',
    })
    // Save the plugin's settings for the terminal CLI, and keep the copy on PATH current.
    void relevo($, ['_sync'], warnDays).catch(() => undefined)
    return next(e)
  })

  on('command.run', { command: CLI }, async ($, e) => {
    const args = e.args.trim().split(/\s+/).filter(Boolean)
    const sub = args[0] ?? 'help'
    if (sub === 'switch') {
      return { text: await switchTo($, args.slice(1), warnDays), isTextDisplayOnly: true }
    }
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
