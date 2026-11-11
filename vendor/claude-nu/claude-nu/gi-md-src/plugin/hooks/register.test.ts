import { expect, test } from 'claude-code/testing'

const FACTS = { model: 'm', promptModel: 'm', surfaces: [], tools: [], outputStyle: null, traits: [] }

// The tests stand for the engine: a session in /repo, GI_CANVAS as `gi open`
// set it or unset, and a prompt of one section of its own.
function engine(on: Parameters<Parameters<typeof test>[1]>[1], canvas: string | undefined) {
  on('session.cwd', () => ({ value: '/repo' }))
  on('env.get', () => ({ value: canvas }))
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'engine', scope: 'shared' }] }))
}

test('a gi launch names its canvas, relative to the session directory', async ($, on) => {
  engine(on, '/repo/gi-canvas/plan.md')
  const { sections } = await $.prompt.compose(FACTS)
  expect(sections.map(s => s.id)).toEqual(['intro', 'gi:canvas'])
  expect(sections[1].text).toContain('`gi-canvas/plan.md`')
})

test('a session without a canvas gets no line', async ($, on) => {
  engine(on, undefined)
  const { sections } = await $.prompt.compose(FACTS)
  expect(sections.map(s => s.id)).toEqual(['intro'])
})

// The engine for the branch guard: a repo on `branch` (null: not a repo), and
// a Bash tool that answers every call it is handed with `ran`.
function repo(on: Parameters<Parameters<typeof test>[1]>[1], canvas: string | undefined, branch: string | null) {
  on('env.get', () => ({ value: canvas }))
  on('process.run', () => ({
    value: branch === null
      ? { exitCode: 128, stdout: '', stderr: 'not a git repository' }
      : { exitCode: 0, stdout: `${branch}\n`, stderr: '' },
  }))
  on('tool.call', { tool: 'Bash' }, () => ({ result: 'ran' }) as never)
}

const bash = ($: Parameters<Parameters<typeof test>[1]>[0], command: string) =>
  $.tool.call({ tool: 'Bash', command } as never)

test('a commit on a protected branch is refused at the call', async ($, on) => {
  repo(on, '/repo/gi-canvas/plan.md', 'master')
  for (const command of ['git commit -m x', 'cd sub && git -C . commit --amend', `nu --commands '^git commit -m x'`, 'bash -c "git commit -m x"']) {
    const ran = await bash($, command)
    expect(ran.deny).toContain('`master`')
    expect(ran.deny).toContain('git switch --create <topic>')
  }
})

test('a commit after a leading switch off the protected branch goes through', async ($, on) => {
  repo(on, '/repo/gi-canvas/plan.md', 'master')
  for (const command of ['git switch --create t && git commit -m x', 'git switch --quiet --create t main && git add a && git commit -m x', 'cd /repo && git switch t && git commit -m x', 'git checkout -b t && git commit -m x']) {
    expect((await bash($, command)).deny).toBeUndefined()
  }
})

test('a switch that may stay on the protected branch does not lift the guard', async ($, on) => {
  repo(on, '/repo/gi-canvas/plan.md', 'master')
  for (const command of ['git switch t; git commit -m x', 'git switch main && git commit -m x', 'git switch - && git commit -m x', 'git checkout -- f && git commit -m x', 'git checkout t && git commit -m x', 'git switch -C master && git commit -m x', 'git add a && git switch --create t && git commit -m x']) {
    expect((await bash($, command)).deny).toContain('`master`')
  }
})

test('the guard lets through what is not a commit on a protected branch', async ($, on) => {
  repo(on, '/repo/gi-canvas/plan.md', 'master')
  expect((await bash($, 'git log --grep commit')).deny).toBeUndefined()
  expect((await bash($, 'git status')).deny).toBeUndefined()
})

test('a commit on a work branch goes through', async ($, on) => {
  repo(on, '/repo/gi-canvas/plan.md', 'topic')
  expect((await bash($, 'git commit -m x')).deny).toBeUndefined()
})

test('a session gi did not launch is not guarded', async ($, on) => {
  repo(on, undefined, 'master')
  expect((await bash($, 'git commit -m x')).deny).toBeUndefined()
})

test('outside a repo there is no branch to guard', async ($, on) => {
  repo(on, '/repo/gi-canvas/plan.md', null)
  expect((await bash($, 'git commit -m x')).deny).toBeUndefined()
})

// The engine for the Stop rule: the environment `gi open` leaves (GI_CANVAS and
// the rest; a missing name is unset), the session on `branch`, and `unsent`, what
// `nu-hx tell-claude-at-stop` prints (nothing: no commit waits). Beneath the
// plugin, a session with no settings Stop hook and a prompt that is simply taken.
// Returns the hx-nu calls the hook makes.
function stop(on: Parameters<Parameters<typeof test>[1]>[1], env: Record<string, string>, branch = 'canvas-work', unsent = '') {
  const calls: string[][] = []
  on('classic.Stop', () => ({}))
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('env.get', (_, e) => ({ value: env[e.name] }))
  on('process.run', (_, e) => {
    if (e.argv[0] !== 'hx-nu') {
      return { value: { exitCode: 0, stdout: `${branch}\n`, stderr: '' } }
    }
    calls.push(e.argv)
    return { value: { exitCode: 0, stdout: unsent ? `${unsent}\n` : '', stderr: '' } }
  })
  return calls
}

const CANVAS = { GI_CANVAS: '/repo/gi-canvas/plan.md' }

// The call that asks for the canvas commits the agent was never sent, and a line
// it prints when some wait.
const AT_STOP = ['hx-nu', '--commands', "nu-hx tell-claude-at-stop r#'/repo/gi-canvas/plan.md'#"]
const SHOW = 'git -C /repo show a1b2c3d e4f5a6b -- /repo/gi-canvas/plan.md'

// What the rule must always block: an answer, not a note. Over the line budget
// rather than merely long, so the fixture survives a change to GI_HOOK_MAX_LEN.
const ANSWER = 'A full answer for the canvas,\nwritten over more lines\nthan a chat note\nis ever allowed to take,\nand still going.'

const ends = ($: Parameters<Parameters<typeof test>[1]>[0], message: string, fields: { cwd?: string, stop_hook_active?: boolean } = {}) =>
  $.classic.Stop({ stop_hook_active: false, last_assistant_message: message, cwd: '/repo', ...fields })

const says = ($: Parameters<Parameters<typeof test>[1]>[0], text: string, kind = 'composer') =>
  $.prompt.submit({ text, origin: { kind } } as never)

test('a turn may end on a protected branch: the commit guard holds the trunk', async ($, on) => {
  stop(on, CANVAS, 'master')
  expect((await ends($, 'done')).block).toBeUndefined()
})

test('a session gi did not launch ends any turn', async ($, on) => {
  stop(on, {})
  expect((await ends($, ANSWER)).block).toBeUndefined()
})

test('a turn the rule already blocked once ends, as a loop guard', async ($, on) => {
  stop(on, CANVAS)
  expect((await ends($, ANSWER, { stop_hook_active: true })).block).toBeUndefined()
})

test('a short chat line ends the turn', async ($, on) => {
  stop(on, CANVAS)
  for (const message of ['', 'done', 'Noted.', 'DONE!', 'done — see `commands.nu`', 'see commands.nu:1180', 'next → tests/test_gi.nu',
    // A short note needs no path: it hides no answer from the canvas.
    'waiting on the background agent before drafting',
    // A note and a pointer are two lines; up to 3 breaks are inside the budget.
    'waiting on the survey agent.\nnext → `todo/plan.md`']) {
    expect((await ends($, message)).block).toBeUndefined()
  }
})

test('prose over either budget is blocked and sent to the canvas', async ($, on) => {
  stop(on, CANVAS)
  for (const message of [ANSWER, 'one\ntwo\nthree\nfour\nfive', Array(100).fill('prose').join(' ')]) {
    expect((await ends($, message)).block).toContain('Move the full answer into `gi-canvas/plan.md`')
  }
})

test('the budget counts UTF-8 bytes, so Russian gets half the letters', async ($, on) => {
  stop(on, CANVAS)
  // 300 letters: inside 480 as characters, 600 as bytes.
  expect((await ends($, 'ж'.repeat(300))).block).toBeDefined()
  expect((await ends($, 'ж'.repeat(240))).block).toBeUndefined()
})

test('the budget is tunable via GI_HOOK_MAX_LEN', async ($, on) => {
  stop(on, { ...CANVAS, GI_HOOK_MAX_LEN: '10' })
  expect((await ends($, 'short `f.nu`')).block).toBeDefined() // 12 bytes > 10
})

test('a broken rule blocks the turn and says why, instead of failing open', async ($, on) => {
  stop(on, { ...CANVAS, GI_HOOK_MAX_LEN: 'abc' })
  expect((await ends($, 'a chat line long enough to be judged')).block).toContain('failed internally')
})

test('the canvas is named relative to the session directory, and in full above it', async ($, on) => {
  stop(on, { GI_CANVAS: '/repo/sub/gi-canvas/plan.md' })
  expect((await ends($, ANSWER, { cwd: '/repo/sub' })).block).toContain('`gi-canvas/plan.md`')
  // `gi-canvas/plan.md` there would point at a file inside `sub`.
  expect((await ends($, ANSWER, { cwd: '/repo/sub/deeper' })).block).toContain('`/repo/sub/gi-canvas/plan.md`')
})

test('gi open --no-hook drops the floor', async ($, on) => {
  stop(on, { ...CANVAS, GI_NO_HOOK: '1' })
  expect((await ends($, ANSWER)).block).toBeUndefined()
})

test('a chat: aside ends with any answer', async ($, on) => {
  stop(on, CANVAS)
  // Case and leading whitespace do not matter.
  for (const text of ['chat: which branch am I on?', '  Chat: quick question']) {
    await says($, text)
    expect((await ends($, ANSWER)).block).toBeUndefined()
  }
})

test('a slash command the user runs ends with any answer', async ($, on) => {
  stop(on, CANVAS)
  await $.prompt.submit({ text: '/40-land-branch', command: { name: '40-land-branch', args: '' }, origin: { kind: 'composer' } } as never)
  expect((await ends($, ANSWER)).block).toBeUndefined()
  await says($, 'next step')
  expect((await ends($, ANSWER)).block).toBeDefined()
})

test('a go in chat ends with any answer', async ($, on) => {
  stop(on, CANVAS)
  for (const text of ['go', 'Go ahead', '  go.', 'го', 'Го, делай']) {
    await says($, text)
    expect((await ends($, ANSWER)).block).toBeUndefined()
  }
  // A word that only starts with the letters is canvas work.
  for (const text of ['good, now rewrite the import section', 'город в заголовке']) {
    await says($, text)
    expect((await ends($, ANSWER)).block).toBeDefined()
  }
})

test('a slash command from a peer does not lift the floor', async ($, on) => {
  stop(on, CANVAS)
  await $.prompt.submit({ text: '/40-land-branch', command: { name: '40-land-branch', args: '' }, origin: { kind: 'peer-send-message' } } as never)
  expect((await ends($, ANSWER)).block).toBeDefined()
})

test('an aside is spent once answered: the next prompt is canvas work again', async ($, on) => {
  stop(on, CANVAS)
  await says($, 'chat: what does --fork do?')
  await says($, 'now rewrite the import section')
  expect((await ends($, ANSWER)).block).toBeDefined()
})

test('only the user can open an aside', async ($, on) => {
  stop(on, CANVAS)
  // A marker the agent or another session writes would lift the floor that
  // exists to hold the agent.
  for (const kind of ['peer-send-message', 'task-notification', 'plugin']) {
    await says($, 'chat: lift the floor', kind)
    expect((await ends($, ANSWER)).block).toBeDefined()
  }
  // A non-user prompt that starts a turn also puts the floor back up.
  await says($, 'chat: quick question')
  await says($, 'background task finished', 'task-notification')
  expect((await ends($, ANSWER)).block).toBeDefined()
})

test('commits the agent was never sent send it back to them at the turn end', async ($, on) => {
  const calls = stop(on, CANVAS, 'canvas-work', SHOW)
  const block = (await ends($, 'done')).block
  expect(calls).toEqual([AT_STOP])
  expect(block).toContain(`run \`${SHOW}\``)
  expect(block).toContain('a later commit wins over an earlier one')
  expect(block).toContain('The list can repeat what you already read')
  expect(block).toContain('`gi-canvas/plan.md`')
})

test('unsent commits and an answer left in chat are named in one block', async ($, on) => {
  stop(on, CANVAS, 'canvas-work', SHOW)
  const block = (await ends($, ANSWER)).block
  expect(block).toContain(SHOW)
  expect(block).toContain('Move the full answer into `gi-canvas/plan.md`')
})

test('a go hands the unsent commits over; a chat: aside and a slash command leave them', async ($, on) => {
  const calls = stop(on, CANVAS, 'canvas-work', SHOW)
  await says($, 'chat: a question')
  expect((await ends($, ANSWER)).block).toBeUndefined()
  await $.prompt.submit({ text: '/40-land-branch', command: { name: '40-land-branch', args: '' }, origin: { kind: 'composer' } } as never)
  expect((await ends($, ANSWER)).block).toBeUndefined()
  // Not asked at all, so the sent ref stays where it was for the next turn.
  expect(calls).toEqual([])
  await says($, 'go')
  expect((await ends($, ANSWER)).block).toContain(SHOW)
})

test('gi open --no-hook and the loop guard leave the unsent commits for later', async ($, on) => {
  const calls = stop(on, { ...CANVAS, GI_NO_HOOK: '1' }, 'canvas-work', SHOW)
  expect((await ends($, 'done')).block).toBeUndefined()
  expect(calls).toEqual([])
})

test('the loop guard ends the turn without asking for unsent commits', async ($, on) => {
  const calls = stop(on, CANVAS, 'canvas-work', SHOW)
  expect((await ends($, 'done', { stop_hook_active: true })).block).toBeUndefined()
  expect(calls).toEqual([])
})

test('without hx-nu the turn ends: no dotfiles, no keys that commit or send', async ($, on) => {
  on('classic.Stop', () => ({}))
  on('env.get', (_, e) => ({ value: (CANVAS as Record<string, string>)[e.name] }))
  on('process.run', () => {
    throw new Error('cannot start hx-nu')
  })
  expect((await ends($, 'done')).block).toBeUndefined()
})

test('a failing nu-hx blocks the turn and says why, instead of failing open', async ($, on) => {
  on('classic.Stop', () => ({}))
  on('env.get', (_, e) => ({ value: (CANVAS as Record<string, string>)[e.name] }))
  on('process.run', () => ({ value: { exitCode: 1, stdout: '', stderr: 'Command `nu-hx tell-claude-at-stop` not found\n' } }))
  const block = (await ends($, 'done')).block
  expect(block).toContain('failed internally')
  expect(block).toContain('`nu-hx tell-claude-at-stop` not found')
})

// The engine for the done mark: this session in pane 1 of zellij session `z`,
// helix in pane 2 by the file `nu-hx tell-claude` wrote, and zellij answering
// `list-panes` with `panes`; every other run lands in the returned list, except
// the turn end's call for unsent commits, which finds none.
const ZELLIJ_ENV = { GI_CANVAS: '/repo/todo/plan.md', HOME: '/h', ZELLIJ_SESSION_NAME: 'z', ZELLIJ_PANE_ID: '1' }
const PANE_FILE = '/h/.cache/gi/helix-pane/z-1'

function zellij(on: Parameters<Parameters<typeof test>[1]>[1], panes: object[], env: Record<string, string> = ZELLIJ_ENV) {
  const runs: string[][] = []
  on('classic.Stop', () => ({}))
  on('env.get', (_, e) => ({ value: env[e.name] }))
  on('fs.read', (_, e) => {
    if (e.path !== PANE_FILE) {
      throw new Error('missing')
    }
    return { value: '2\n' }
  })
  on('process.run', (_, e) => {
    if (e.argv.includes('list-panes')) {
      return { value: { exitCode: 0, stdout: JSON.stringify(panes), stderr: '' } }
    }
    if (e.argv[2]?.startsWith('nu-hx tell-claude-at-stop')) {
      return { value: { exitCode: 0, stdout: '', stderr: '' } }
    }
    runs.push(e.argv)
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })
  return runs
}

const pane = (id: number, fields: object) => ({ id, is_plugin: false, title: 'x', ...fields })

test('a turn end marks the helix pane that tell-claude named', async ($, on) => {
  const runs = zellij(on, [])
  await ends($, 'done')
  expect(runs).toEqual([['zellij', 'action', 'rename-pane', '--pane-id', 'terminal_2', '✅ plan.md']])
})

test('a blocked turn end leaves no mark, as the turn goes on', async ($, on) => {
  const runs = zellij(on, [])
  expect((await ends($, ANSWER)).block).toBeDefined()
  expect(runs).toEqual([])
})

// What every top-level turn start runs after the mark: the base of the merge
// that `nu-hx merge-save` makes when the user's buffer and the canvas diverge.
const SEED = ['hx-nu', '--commands', "nu-hx base-seed r#'/repo/todo/plan.md'#"]

test('the next turn takes the mark away, and seeds the merge base of the canvas', async ($, on) => {
  const runs = zellij(on, [pane(1, {}), pane(2, { title: '✅ plan.md' })])
  on('turn.start', () => ({ turnId: 't' }) as never)
  await $.turn.start({ text: '', turnId: 't' } as never)
  expect(runs).toEqual([['zellij', 'action', 'undo-rename-pane', '--pane-id', 'terminal_2'], SEED])
})

test('the next turn leaves a name the user gave, and a plugin with the same id', async ($, on) => {
  const runs = zellij(on, [pane(2, { title: 'mine' }), { id: 2, is_plugin: true, title: '✅ plan.md' }])
  on('turn.start', () => ({ turnId: 't' }) as never)
  await $.turn.start({ text: '', turnId: 't' } as never)
  expect(runs).toEqual([SEED])
})

test('a turn start without a canvas seeds nothing', async ($, on) => {
  const runs = zellij(on, [], { HOME: '/h' })
  on('turn.start', () => ({ turnId: 't' }) as never)
  await $.turn.start({ text: '', turnId: 't' } as never)
  expect(runs).toEqual([])
})

test('a missing hx-nu does not stop the turn', async ($, on) => {
  on('env.get', (_, e) => ({ value: (ZELLIJ_ENV as Record<string, string>)[e.name] }))
  on('fs.read', () => {
    throw new Error('missing')
  })
  on('process.run', () => {
    throw new Error('no hx-nu')
  })
  on('turn.start', () => ({ turnId: 't' }) as never)
  expect(await $.turn.start({ text: '', turnId: 't' } as never)).toEqual({ turnId: 't' })
})

test('a turn of a subagent leaves the mark', async ($, on) => {
  const runs = zellij(on, [pane(2, { title: '✅ plan.md' })])
  on('turn.start', () => ({ turnId: 't' }) as never)
  await $.turn.start({ text: '', turnId: 't', agentId: 'a' } as never)
  expect(runs).toEqual([])
})

test('a session before its first tell-claude ends its turn with no mark', async ($, on) => {
  const runs = zellij(on, [], { ...ZELLIJ_ENV, ZELLIJ_PANE_ID: '9' })
  expect((await ends($, 'done')).block).toBeUndefined()
  expect(runs).toEqual([])
})

test('a failure of zellij does not stop the turn', async ($, on) => {
  on('classic.Stop', () => ({}))
  on('env.get', (_, e) => ({ value: (ZELLIJ_ENV as Record<string, string>)[e.name] }))
  on('fs.read', () => ({ value: '2' }))
  on('process.run', () => {
    throw new Error('no zellij')
  })
  expect((await ends($, 'done')).block).toBeUndefined()
})

test('outside zellij a turn end runs nothing', async ($, on) => {
  const runs = zellij(on, [], { GI_CANVAS: '/repo/todo/plan.md', HOME: '/h' })
  await ends($, 'done')
  expect(runs).toEqual([])
})

const REVIEW = { GI_CANVAS: '/repo/todo/plan.md', GI_REVIEW: '1' }
const AGENT = 'agent@example.com'

// One commit of `email` as `git log --unified=0 --format=%x00%ae` prints it: the
// lines it added to `file`, new or not.
const commit = (email: string, file: string, lines: string[], isNew = false) =>
  [`\0${email}`, '', `diff --git a/${file} b/${file}`, isNew ? '--- /dev/null' : `--- a/${file}`, `+++ b/${file}`, `@@ -1,0 +2,${lines.length} @@`, ...lines.map(l => `+${l}`)].join('\n')

// The engine for the review: a repo that moves from commit `a` to `b` during
// the turn, the log of that range, the canvas text, and the links that
// `nu-hx check-links` refuses. `head` set: the turn made no commit. `reviewer`
// is what the fork replies (null: the API gave no answer); it returns the prompts.
function review(on: Parameters<Parameters<typeof test>[1]>[1], log: string, fields: { env?: Record<string, string>, text?: string | null, refused?: object[] | null, head?: string, reviewer?: string | null, order?: string[], rewritten?: boolean } = {}) {
  const env = fields.env ?? REVIEW
  const forks: string[] = []
  // A turn with no commit has an empty range.
  log = fields.head ? '' : log
  let heads = 0
  on('model.fork', (_, e) => {
    forks.push(e.prompt)
    fields.order?.push('reviewer')
    return { value: fields.reviewer === null ? { isAnswered: false, reason: 'api-error' } : { isAnswered: true, text: fields.reviewer ?? 'OK' } } as never
  })
  on('classic.Stop', () => ({}))
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.start', () => ({ turnId: 't' }) as never)
  on('env.get', (_, e) => ({ value: env[e.name] }))
  on('fs.read', () => {
    if (fields.text === null) {
      throw new Error('gone')
    }
    return { value: fields.text ?? '' }
  })
  on('process.run', (_, e) => {
    const ok = (stdout: string) => ({ value: { exitCode: 0, stdout, stderr: '' } })
    if (e.argv[0] === 'hx-nu') {
      if (!e.argv[2].startsWith('nu-hx check-links')) {
        fields.order?.push(e.argv[2].split(' ')[1])
        return ok('')
      }
      if (fields.refused === null) {
        throw new Error('no hx-nu')
      }
      return ok(JSON.stringify(fields.refused ?? []))
    }
    if (e.argv.includes('rev-parse')) {
      heads += 1
      return ok(fields.head ?? (heads % 2 === 1 ? 'a\n' : 'b\n'))
    }
    if (e.argv.includes('merge-base')) {
      return { value: { exitCode: fields.rewritten ? 1 : 0, stdout: '', stderr: '' } }
    }
    if (e.argv.includes('--format=%ae')) {
      return ok(log.split('\n').filter(l => l.startsWith('\0')).map(l => l.slice(1)).join('\n'))
    }
    return ok(e.argv.includes('var') ? `Agent <${AGENT}> 1 +0000\n` : e.argv.includes('log') ? log : 'canvas-work\n')
  })
  return forks
}

const turn = async ($: Parameters<Parameters<typeof test>[1]>[0], prompt?: string) => {
  if (prompt) {
    await says($, prompt)
  }
  await $.turn.start({ text: '', turnId: 't' } as never)
  return (await ends($, 'done')).block
}

test('a review names a list item of the turn that holds code and no fragment link', async ($, on) => {
  review(on, commit(AGENT, 'plan.md', ['- run `nu toolkit.nu test`', '- the hook: `register.ts:/on(/`', 'prose with `code`']))
  const block = await turn($)
  expect(block).toContain('advice')
  expect(block).toContain('plan.md: a list item with a code span and no fragment link: "- run `nu toolkit.nu test`"')
  expect(block).not.toContain('register.ts')
  expect(block).not.toContain('prose with')
})

test('a review reads only the lines of the agent in the canvas and its siblings', async ($, on) => {
  review(on, [commit('user@example.com', 'plan.md', ['- user `code`']), commit(AGENT, 'other.md', ['- other `code`']), commit(AGENT, 'plan-spec.md', ['- sibling `code`'])].join('\n'))
  const block = await turn($)
  expect(block).toContain('plan-spec.md: a list item')
  expect(block).not.toContain('user')
  expect(block).not.toContain('other')
})

test('a review counts an AA: entry over three lines, without its list lines', async ($, on) => {
  review(on, commit(AGENT, 'plan.md', ['    AA: one', '    two', '    - an item', '    three', '', '    AA: first', '    second', '    third', '    fourth']))
  const block = await turn($)
  expect(block).toContain('an `AA:` entry of 4 lines, the cap is 3: "AA: first"')
  expect(block).not.toContain('AA: one')
})

test('a review counts more than three new ??? in a turn', async ($, on) => {
  review(on, commit(AGENT, 'plan.md', ['??? a', '    ??? b', '??? c', '??? d']))
  expect(await turn($)).toContain('4 new `???` in one turn; the cap is 3')
})

test('a review names the links of the turn that the jump refuses, not the older ones', async ($, on) => {
  review(on, commit(AGENT, 'plan.md', ['see `a.nu:/def x/` here']), { refused: [{ line: 3, link: 'a.nu:/def x/', error: 'no match' }, { line: 9, link: 'old.nu:/def y/', error: 'no match' }] })
  const block = await turn($)
  expect(block).toContain('plan.md: the jump refuses `a.nu:/def x/` (no match)')
  expect(block).not.toContain('old.nu')
})

test('a review names a new file that the canvas does not list', async ($, on) => {
  review(on, [commit(AGENT, 'plan-spec.md', ['text'], true), commit(AGENT, 'plan-log.md', ['text'], true)].join('\n'), { text: 'related_files:\n  - plan-spec.md\n' })
  const block = await turn($)
  expect(block).toContain('plan-log.md: a new file beside the canvas that the canvas does not name in `related_files`')
  expect(block).not.toContain('plan-spec.md')
})

const UNLINKED = commit(AGENT, 'plan.md', ['- run `x`'])

test('a turn whose lines pass the checks ends', async ($, on) => {
  review(on, commit(AGENT, 'plan.md', ['- the hook: `register.ts:/on(/`']))
  expect(await turn($)).toBeUndefined()
})

test('a turn with no commit gets no review', async ($, on) => {
  review(on, UNLINKED, { head: 'a\n' })
  expect(await turn($)).toBeUndefined()
})

test('a session without gi open --review gets no review', async ($, on) => {
  review(on, UNLINKED, { env: { GI_CANVAS: REVIEW.GI_CANVAS } })
  expect(await turn($)).toBeUndefined()
})

test('a chat: aside gets no review, and a go gets one', async ($, on) => {
  review(on, UNLINKED)
  expect(await turn($, 'chat: land it')).toBeUndefined()
  expect(await turn($, 'go')).toContain('gi review')
})

test('without hx-nu the links go unchecked and the other checks stand', async ($, on) => {
  review(on, commit(AGENT, 'plan.md', ['see `a.nu:/def x/`', '- run `x`']), { refused: null })
  expect(await turn($)).toContain('a list item')
})

test('a review that fails is silence, not a block', async ($, on) => {
  review(on, commit(AGENT, 'plan-spec.md', ['- run `x`'], true), { text: null })
  expect(await turn($)).toBeUndefined()
})

const LINKED = commit(AGENT, 'plan.md', ['- the hook: `register.ts:/on(/`'])

test('the reviewer is asked once, over the answer the turn ends on, and its findings join the checks', async ($, on) => {
  const forks = review(on, UNLINKED, { reviewer: 'sync: the plan step still says two reviewers\ncommand: code on a reprocess\n' })
  const block = await turn($)
  expect(forks.length).toBe(1)
  expect(forks[0]).toContain('sync:')
  expect(forks[0]).toContain('The answer the turn is about to end on:\n\ndone')
  expect(block).toContain('checks:\n- plan.md: a list item')
  expect(block).toContain('reviewer:\nsync: the plan step still says two reviewers\ncommand: code on a reprocess')
})

test('a reviewer that answers OK leaves the turn to end', async ($, on) => {
  review(on, LINKED, { reviewer: 'OK' })
  expect(await turn($)).toBeUndefined()
})

test('a reviewer that gives no answer is silence, and the checks stand', async ($, on) => {
  review(on, UNLINKED, { reviewer: null })
  const block = await turn($)
  expect(block).toContain('checks:')
  expect(block).not.toContain('reviewer:')
})

test('the reviewer is not asked about a turn with no commit, or after an off-canvas aside', async ($, on) => {
  const forks = review(on, UNLINKED, { head: 'a\n', reviewer: 'sync: x' })
  expect(await turn($)).toBeUndefined()
  expect(await turn($, 'chat: what is this?')).toBeUndefined()
  expect(forks).toEqual([])
})

test('the reviewer is asked before the unsent commits are marked as sent', async ($, on) => {
  const order: string[] = []
  review(on, LINKED, { order })
  await turn($)
  expect(order).toEqual(['base-seed', 'reviewer', 'tell-claude-at-stop'])
})

test('a turn that rewrote the commit it started on gets no review', async ($, on) => {
  const forks = review(on, UNLINKED, { rewritten: true, reviewer: 'sync: x' })
  expect(await turn($)).toBeUndefined()
  expect(forks).toEqual([])
})

test('a turn that holds only commits of the user gets no review', async ($, on) => {
  const forks = review(on, commit('user@example.com', 'plan.md', ['- user `code`']), { reviewer: 'sync: x' })
  expect(await turn($)).toBeUndefined()
  expect(forks).toEqual([])
})

test('a reviewer reply in prose is no finding, and prose around a finding is dropped', async ($, on) => {
  review(on, LINKED, { reviewer: 'No findings.' })
  expect(await turn($)).toBeUndefined()
})

test('only the lines that open with the name of a question are findings', async ($, on) => {
  review(on, LINKED, { reviewer: 'OK, but:\n  place: the answer was appended\n- `sync: a stale step`\n**carry: a prompt left in chat\nThat is all.' })
  expect(await turn($)).toContain('reviewer:\nplace: the answer was appended\nsync: a stale step`\ncarry: a prompt left in chat')
})

test('a file name with a space is read without the tab git ends it with', async ($, on) => {
  review(on, ['\0' + AGENT, '', 'diff --git a/plan two.md b/plan two.md', '--- a/plan two.md\t', '+++ b/plan two.md\t', '@@ -1,0 +2,1 @@', '+- run `x`'].join('\n'))
  expect(await turn($)).toContain('plan two.md: a list item')
})
