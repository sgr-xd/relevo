// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The Relevo authors
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

test('/relevo switch asks the CLI, shows its answer without a model turn, then closes the session', async ($, on) => {
  const seen = engine(on, 0, 'Switching to bob: this session closes and reopens as bob.\n')
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  const out = await $.command.run({ command: 'relevo', args: ' switch  bob ' })

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

test('/relevo switch that the CLI refuses keeps the session open', async ($, on) => {
  const seen = engine(on, 3, 'No account named nobody (relevo list shows them).\n')
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  const out = await $.command.run({ command: 'relevo', args: 'switch nobody' })

  expect(out.text).toBe('No account named nobody (relevo list shows them).')
  expect(seen.timers).toEqual([])
  expect(seen.exits).toEqual([])
})

test('/relevo runs only the subcommands that are safe inside a session, and switch', async ($, on) => {
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

// An engine whose CLI answers per call, in order (the last answer repeats).
function scripted(on: On, answers: { code: number; out: string }[]) {
  const ran: Ran[] = []
  const exits: string[] = []
  const logs: string[] = []
  const notes: string[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => ({ value: { command: e.name } }))
  on('process.hookEnv', () => ({ value: ENV }))
  on('process.run', (_, e) => {
    if (e.argv[1] !== '_sync') ran.push({ argv: e.argv, env: (e.init?.env ?? {}) as Record<string, string> })
    const a = answers[Math.min(ran.length, answers.length) - 1] ?? { code: 0, out: '' }
    return { value: { exitCode: e.argv[1] === '_sync' ? 0 : a.code, stdout: e.argv[1] === '_sync' ? '' : a.out, stderr: '' } }
  })
  on('clock.after', () => ({ value: undefined }))
  on('command.run', { command: 'exit' }, () => (exits.push('exit'), { text: '' }))
  on('ui.log', (_, e) => (logs.push(e.text), { value: undefined }))
  on('ui.notify', (_, e) => (notes.push(e.text), { value: { isSent: true } as never }))
  on('classic.StopFailure', () => ({}) as never)
  return { ran, exits, logs, notes }
}
function answerAsk(on: On, label: string | null) {
  const asked: string[] = []
  on('tool.call', { tool: 'AskUserQuestion' }, (_, e: any) => {
    asked.push(e.questions[0].question)
    if (label === null) return { deny: 'dismissed' }
    return { result: { questions: e.questions, answers: { [e.questions[0].question]: label } } as never }
  })
  return asked
}
const settle = async (until: () => boolean) => {
  for (let i = 0; i < 100 && !until(); i++) await new Promise(r => setTimeout(r, 5))
}
const LIMIT = { code: 4, out: 'bob is at a usage limit: Current session: 100% used · resets 4pm\n' }
const SWITCHING = { code: 0, out: 'Switching to bob.\n' }

test('/relevo switch to an account at its limit asks first; "Switch anyway" switches', async ($, on) => {
  const seen = scripted(on, [LIMIT, SWITCHING])
  const asked = answerAsk(on, 'Switch anyway')
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  const out = await $.command.run({ command: 'relevo', args: 'switch bob' })

  expect(asked[0]).toBe('bob is at a usage limit: Current session: 100% used · resets 4pm Switch anyway?')
  expect(seen.ran.map(r => r.argv.slice(1))).toEqual([['_switch', 'bob'], ['_switch', 'bob', '--anyway']])
  expect(out.text).toBe('Switching to bob.')
  await settle(() => seen.exits.length > 0)
  expect(seen.exits).toEqual(['exit'])
})

for (const [name, label] of [['says "Stay"', 'Stay on this account'], ['closes the question', null]] as const) {
  test(`/relevo switch to an account at its limit stays when the person ${name}`, async ($, on) => {
    const seen = scripted(on, [LIMIT, SWITCHING])
    answerAsk(on, label)
    await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

    const out = await $.command.run({ command: 'relevo', args: 'switch bob' })

    expect(out.text).toContain('Staying on this account.')
    expect(seen.ran.length).toBe(1)
    await settle(() => false)
    expect(seen.exits).toEqual([])
  })
}

test('/relevo account shows the CLI account view without a model turn', async ($, on) => {
  const seen = scripted(on, [{ code: 0, out: '▶ jane (acc2) signed in\n' }])
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  const out = await $.command.run({ command: 'relevo', args: 'account' })

  expect(out.text).toBe('▶ jane (acc2) signed in')
  expect(out.isTextDisplayOnly).toBe(true)
  expect(seen.ran.map(r => r.argv[1])).toEqual(['account'])
})

test('a rate-limit stop posts where to continue, and never switches', async ($, on) => {
  const msg = 'Usage limit reached on jane. To continue this conversation on bob:  /relevo switch bob'
  const seen = scripted(on, [{ code: 0, out: `${msg}\n` }])
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  await $.classic.StopFailure({ error: 'rate_limit' })
  await settle(() => seen.notes.length > 0)

  expect(seen.ran.map(r => r.argv[1])).toEqual(['_limited'])
  expect(seen.logs).toEqual([msg])
  expect(seen.notes).toEqual([msg])
  expect(seen.exits).toEqual([])

  await $.classic.StopFailure({ error: 'server_error' })
  expect(seen.ran.length).toBe(1)
})

test('only /relevo is registered: no bare /switch or /account that a built-in could clash with', async ($, on) => {
  const names: string[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => (names.push(e.name), { value: { command: e.name } }))
  on('process.hookEnv', () => ({ value: ENV }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: '', stderr: '' } }))
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  expect(names).toEqual(['relevo'])
})

test('/relevo with no subcommand shows the help', async ($, on) => {
  const seen = scripted(on, [{ code: 0, out: 'Relevo: several Claude accounts, one Claude Code.\n' }])
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  const out = await $.command.run({ command: 'relevo', args: '' })

  expect(out.text).toBe('Relevo: several Claude accounts, one Claude Code.')
  expect(seen.ran.map(r => r.argv.slice(1))).toEqual([['help']])
})

for (const args of ['switch bob --anyway', 'switch --anyway bob', 'switch bob extra', 'switch', 'switch -x', 'switch Bob', 'switch ../bob']) {
  test(`/relevo ${args} is refused before the CLI: no --anyway, no close`, async ($, on) => {
    const seen = scripted(on, [SWITCHING])
    const asked = answerAsk(on, 'Switch anyway')
    await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

    const out = await $.command.run({ command: 'relevo', args })

    expect(out.text).toBe('usage: /relevo switch <name>   (relevo list shows the names)')
    expect(seen.ran.filter(r => r.argv[1] === '_switch')).toEqual([])
    expect(seen.ran.some(r => r.argv.includes('--anyway'))).toBe(false)
    expect(asked).toEqual([])
    await settle(() => false)
    expect(seen.exits).toEqual([])
  })
}

test('only the "Switch anyway" answer adds --anyway, and only after the plain check', async ($, on) => {
  const seen = scripted(on, [LIMIT, SWITCHING])
  answerAsk(on, 'Switch anyway')
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  await $.command.run({ command: 'relevo', args: 'switch bob' })

  expect(seen.ran.map(r => r.argv.slice(1))).toEqual([['_switch', 'bob'], ['_switch', 'bob', '--anyway']])
})

// --- the shell line: written only after the person's "Add the line" ---------------------------
const INSTALLED = { code: 0, out: 'Installed: ~/.local/bin/relevo\n' }
const ABSENT = { code: 0, out: 'absent ~/.zshrc\n' }
const ADDED = { code: 0, out: 'Added to ~/.zshrc: plain claude now opens your default account.\n' }
const NOT_STARTED = { code: 5, out: 'This session was not started with relevo, so it cannot reopen itself.\n' }

test('/relevo install offers the shell line; "Add the line" adds it', async ($, on) => {
  const seen = scripted(on, [INSTALLED, ABSENT, ADDED])
  const asked = answerAsk(on, 'Add the line')
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  const out = await $.command.run({ command: 'relevo', args: 'install' })

  expect(asked[0]).toContain('This adds one line to ~/.zshrc; relevo shell --remove takes it out.')
  expect(seen.ran.map(r => r.argv.slice(1))).toEqual([['install'], ['_shell'], ['shell', '--add']])
  expect(out.text).toBe('Installed: ~/.local/bin/relevo\nAdded to ~/.zshrc: plain claude now opens your default account.')
})

for (const [name, label] of [['says "Not now"', 'Not now'], ['closes the question', null]] as const) {
  test(`/relevo install writes no shell line when the person ${name}`, async ($, on) => {
    const seen = scripted(on, [INSTALLED, ABSENT, ADDED])
    answerAsk(on, label)
    await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

    const out = await $.command.run({ command: 'relevo', args: 'install' })

    expect(seen.ran.some(r => r.argv.includes('--add'))).toBe(false)
    expect(out.text).toBe('Installed: ~/.local/bin/relevo')
  })
}

for (const state of ['present ~/.zshrc', 'ours ~/.zshrc', 'conflict ~/.zshrc', 'unsupported ']) {
  test(`/relevo install asks nothing when the CLI says "${state.trim()}"`, async ($, on) => {
    const seen = scripted(on, [INSTALLED, { code: 0, out: `${state}\n` }, ADDED])
    const asked = answerAsk(on, 'Add the line')
    await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

    await $.command.run({ command: 'relevo', args: 'install' })

    expect(asked).toEqual([])
    expect(seen.ran.some(r => r.argv.includes('--add'))).toBe(false)
  })
}

test('a failed /relevo install asks nothing', async ($, on) => {
  const seen = scripted(on, [{ code: 1, out: 'relevo: could not create folders\n' }, ABSENT, ADDED])
  const asked = answerAsk(on, 'Add the line')
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  await $.command.run({ command: 'relevo', args: 'install' })

  expect(asked).toEqual([])
  expect(seen.ran.map(r => r.argv[1])).toEqual(['install'])
})

test('/relevo switch in a session relevo did not start offers the line, and keeps the session', async ($, on) => {
  const seen = scripted(on, [NOT_STARTED, ABSENT, ADDED])
  const asked = answerAsk(on, 'Add the line')
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  const out = await $.command.run({ command: 'relevo', args: 'switch bob' })

  expect(asked[0]).toContain('so /relevo switch reopens by itself next time?')
  expect(seen.ran.map(r => r.argv.slice(1))).toEqual([['_switch', 'bob'], ['_shell'], ['shell', '--add']])
  expect(out.text).toContain('Added to ~/.zshrc')
  await settle(() => false)
  expect(seen.exits).toEqual([])
})

test('/relevo switch in a session relevo did not start: "Not now" writes nothing', async ($, on) => {
  const seen = scripted(on, [NOT_STARTED, ABSENT, ADDED])
  answerAsk(on, 'Not now')
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

  const out = await $.command.run({ command: 'relevo', args: 'switch bob' })

  expect(seen.ran.some(r => r.argv.includes('--add'))).toBe(false)
  expect(out.text).toBe('This session was not started with relevo, so it cannot reopen itself.')
})
