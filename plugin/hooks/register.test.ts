import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'

// Nothing sits beneath the plugin: each `on` here stands for the engine.
const ENV = {
  CLAUDE_PLUGIN_ROOT: '/plugin',
  CLAUDE_CODE_SESSION_ID: '0a1b2c3d-1111-4222-8333-444455556666',
  CLAUDE_PID: '4242',
}

type Ran = { argv: readonly string[]; env: Record<string, string> }


function engine(on: On, exitCode: number, stdout: string) {
  const ran: Ran[] = []
  const exits: string[] = []
  const timers: number[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('process.hookEnv', () => ({ value: ENV }))
  on('process.run', (_, e) => {
    ran.push({ argv: e.argv, env: (e.init?.env ?? {}) as Record<string, string> })
    return { value: { exitCode, stdout, stderr: '' } }
  })
  on('clock.after', (_, e) => {
    timers.push(e.ms)
    return { value: undefined }
  })
  on('command.run', { command: 'exit' }, () => {
    exits.push('exit')
    return { text: '' }
  })
  return { ran, exits, timers }
}

test('/switch asks the CLI, shows its answer without a model turn, then closes the session', async ($, on) => {
  const seen = engine(on, 0, 'Switching to bob: this session closes and reopens as bob.\n')
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  const out = await $.command.run({ command: 'switch', args: ' bob ' })

  expect(out.text).toBe('Switching to bob: this session closes and reopens as bob.')
  expect(out.isTextDisplayOnly).toBe(true)
  const call = seen.ran.find(r => r.argv[1] === '_switch')
  expect(call?.argv).toEqual(['/plugin/bin/relevo', '_switch', 'bob'])
  expect(call?.env.CLAUDE_CODE_SESSION_ID).toBe(ENV.CLAUDE_CODE_SESSION_ID)
  expect(call?.env.CLAUDE_PID).toBe('4242')
  expect(seen.timers).toEqual([300])
  for (let i = 0; i < 100 && seen.exits.length === 0; i++) await new Promise(r => setTimeout(r, 5))
  expect(seen.exits).toEqual(['exit'])
})

test('/switch that the CLI refuses keeps the session open', async ($, on) => {
  const seen = engine(on, 3, 'No account named nobody (relevo list shows them).\n')
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  const out = await $.command.run({ command: 'switch', args: 'nobody' })

  expect(out.text).toBe('No account named nobody (relevo list shows them).')
  expect(seen.timers).toEqual([])
  expect(seen.exits).toEqual([])
})

test('/relevo runs only the subcommands that are safe inside a session', async ($, on) => {
  const seen = engine(on, 0, 'me (main) signed in\n')
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  for (const args of ['jane', 'run jane', 'add x@y.example', '_switch bob', '_sync']) {
    const out = await $.command.run({ command: 'relevo', args })
    expect(out.text).toContain('does not run inside a session')
  }
  expect(seen.ran.filter(r => r.argv[1] !== '_sync')).toEqual([])

  const listed = await $.command.run({ command: 'relevo', args: 'list' })
  expect(listed.text).toBe('me (main) signed in')
  expect(seen.ran.at(-1)?.argv).toEqual(['/plugin/bin/relevo', 'list'])
})

test('the login warning setting reaches the CLI', { options: { warn_days: 9 } }, async ($, on) => {
  const seen = engine(on, 0, 'ok\n')
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  await $.command.run({ command: 'relevo', args: 'list' })

  expect(seen.ran.at(-1)?.env.RELEVO_WARN_DAYS).toBe('9')
})
