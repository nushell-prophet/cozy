import type { Hook, Register } from 'claude-code'
import { familyFiles, headOf, OPEN_MARKER, reviewReason } from './review'
import { lastSeen, remember, rewrittenReason, standsOn } from './rewrite'

type Api = Parameters<Hook<'classic.Stop'>>[0]
type StopEvent = Parameters<Hook<'classic.Stop'>>[1]

// Mirrors GI_PROTECTED_BRANCHES in gi.nu: `gi open` warns about the same list.
const PROTECTED_BRANCHES = ['main', 'master']

// The chat budget of the Stop rule: at most this many line breaks, and
// GI_HOOK_MAX_LEN (default 480) UTF-8 bytes, so a Cyrillic answer gets about
// half the letters of a Latin one. Size is the whole floor: a real answer exceeds it.
// Why two lines plus: a status note and a pointer are two, and a floor that
// forbids the second is not measuring the thing it cares about.
// Not a link signal (backtick, `→`, filename) because: it made a path the price
// of every chat line, and demanding a path where there is none teaches the
// agent to invent one.
const MAX_BREAKS = 3
const DEFAULT_MAX_LEN = 480

// The marker that takes one exchange off the canvas, typed by the user at the
// start of their message: `chat: what does this flag do?`.
const CHAT_MARKER = 'chat:'

// A chat message that is `go` alone, or opens with it (`go ahead`): the agent
// goes on by the defaults and the decisions taken so far, and judges from the
// context where the answer goes; the floor only stops forcing it into the canvas.
// Why every `go`, not only one after an aside: the user wants the floor off
// whenever he says go in chat; when he wants the answers in the canvas, he
// writes `go` in the canvas, or the context puts them there.
// Why `го` too: the user has typed it for `go`; neither one carries a language.
// Not `\b` because: JavaScript reads it as an ASCII word edge even with the `u`
// flag, so `го ` would not match and `год` would.
// Why `пщ`: it is `go` typed on the Russian layout, and he sends it as `go`
// (de28c1fe, 2026-11-14).
const GO = /^(go|го|пщ)(?![\p{L}\p{N}_])/u

// A typed prompt of one line up to this many characters is a short chat question
// ("ты все?", "have advisor checked?"), and its answer may stay in the chat.
// Why: the floor blocked such answers and moved them where he did not ask for
// them (round 2 of the canvas usage review, 2026-11-17).
// Not a `!` command because: the `\ l` send and a typed `git log -p` hand over
// canvas work, which the floor holds to the canvas.
const SHORT_PROMPT = 60

// The heading of a skill whose replies to the chat the skill itself formats
// (the `40-cozy-output-formatting` convention): `/40-land-branch` shows its plan
// and its report there. A reference skill (`nushell-style`) has no such section.
const REPLIES = /^## Replies\s*$/m

// The prompt sources that are the user's own words. Why the user's alone: a
// marker the agent or another session could write would lift the floor that
// exists to hold the agent.
const USER_ORIGINS = ['composer', 'bridge', 'sdk']

// `git commit` as the subcommand, after any global options (`git -C dir -c k=v
// commit`); `git log --grep commit` is not one. A quote or `^` may open it:
// agents here run nu one-shots from Bash (`nu --commands '^git commit'`).
const GIT_COMMIT = /(^|[\s;&|('"`^])git(\s+(-[Cc]\s+\S+|--?[\w-]+(=\S+)?))*\s+commit\b/

// A command that opens with a branch switch joined by `&&`, after any leading
// `cd <dir> &&`: the switch and its words before the `&&`.
// Why `&&` alone: a failed switch then stops the commit, where `;` would run it
// on the trunk.
const LEADING_SWITCH = /^\s*(?:cd\s+\S+\s*&&\s*)*git\s+(switch|checkout)((?:\s+[^\s;&|]+)*?)\s*&&/
const SWITCH_FLAGS = ['-q', '--quiet']
const CREATE_FLAGS = { switch: ['-c', '--create', '-C', '--force-create'], checkout: ['-b', '-B'] }

// The title prefix of a helix pane whose canvas has an answer to read. `nu-hx
// done-mark-clear` (dotfiles, the `C-r` binding) repeats it: change both together.
// Why a mark of its own: a counter of waiting replies may use `💬 ` on this
// title and clear it at zero, which would take this mark away.
const DONE_MARK = '✅ '
// The title prefix while the agent works a turn: the user goes on editing while
// the first edits of the turn have already arrived, or keeps the canvas pane
// fullscreen and does not see the Claude pane at all.
// Why `done-mark-clear` does not know it: `\ l` runs that command too, and a
// `\ l` during a turn would take the mark away while the work goes on.
const WORK_MARK = '⏳ '
// The title prefix of a turn that an API error or a refusal ended: without it
// the work mark would stay and claim the agent still works. `nu-hx
// done-mark-clear` repeats it, as for DONE_MARK.
const ERROR_MARK = '⚠ '

export const register: Register = on => {
  // Whether the current turn is an aside: its prompt is a `chat:` message, a
  // `go`, a short typed question or a slash command the user ran, or the agent
  // ran a skill with its own replies (`skill.prompt` below). Every prompt sets it
  // anew, a task notification to the value of the user's last prompt, a peer
  // message to false; the end of a turn clears it, so an aside is spent once
  // answered.
  // Why a slash command: a skill the user runs carries its own instructions for
  // the chat (`/40-land-branch` shows its plan there and waits), and the floor
  // pushed that answer into the canvas.
  // Why the turn end clears it: the types do not promise `prompt.submit` for a
  // `!` command, the `\ l` send, so a short question before it must not leave
  // the floor down for the turns of the key.
  // Why state here and not the transcript at Stop: `prompt.submit` hands over
  // the text as typed, so nothing parses the session file at every turn end.
  // A reload of the mod clears it: the floor is then up for one turn, and the
  // block's own escape hatch covers that.
  let aside = false
  // Whether that aside is off the canvas: a `chat:` message or a slash command,
  // not a `go`. Such a turn leaves the user's unsent canvas commits for the next
  // one: a `chat:` answer writes nothing to the canvas, and a skill that shows a
  // plan and waits must not be pushed on into other work.
  let offCanvas = false
  // The two flags as the user's last prompt set them, for a task notification.
  let lastUser = { aside: false, offCanvas: false }
  // The commit the repo stood on when the turn started: the review at the turn
  // end reads the commits made since. Unset with `gi open --no-hook`.
  let turnBase: string | undefined
  // The status line entry last set, so the timer below sets it only on a change.
  const shown: Shown = { text: undefined }

  // The queue of unsent files in the status line of Claude: `unsent: plan.md 2,
  // nu-hx.nu 1`, the commits of each file that `\ k` and `+ g` made in helix and
  // the agent was not sent yet.
  // Why a timer: the user commits in helix while the session is idle, and no
  // event of the session follows a commit; he reads the line before his `\ l`.
  // Why a file read and no process: `nu-hx` (dotfiles, `queue-add`) writes one
  // line per commit for this, so a look costs no git and no nu.
  on('session.start', async ($, e, next) => {
    if (await $.env.get('GI_CANVAS')) {
      $.clock.every(STATUS_PERIOD, () => showUnsent($, shown))
    }
    return next(e)
  })

  // The agent reads a file that has commits of the user it was not sent: they
  // go to it with the result of the read, and the file leaves the queue, so a
  // later `\ l` or turn end does not send them again.
  // Why the commits and not only a mark that the file is read: the Read tool
  // gives the text as it is now, and an instruction is in what changed.
  // Why the main loop alone: a subagent that reads the canvas would take the
  // commits with it, and the agent that owns the canvas would never see them.
  // Why after the read: a read that is refused or fails must not spend them.
  // Why not in an off-canvas aside: as at the turn end, a `chat:` answer or a
  // skill's own flow that reads the canvas must not be pushed on into them.
  on('tool.call', { tool: 'Read' }, async ($, e, next) => {
    const result = await next(e)
    if (offCanvas || e.agentId !== undefined || result.deny !== undefined || result.isError) {
      return result
    }
    const commits = await unsentCommits($, e.file_path).catch(() => undefined)
    await showUnsent($, shown)
    return commits
      ? { ...result, context: [...(result.context ?? []), `The user committed to this file, and these commits were never sent to you; they now count as sent. Read them as his instructions, oldest first: a later commit wins over an earlier one, as in a long message. What the Read above shows is the text after them.\n\n${commits}`] }
      : result
  })

  // A write of the agent to a file that has commits of the user it was not sent
  // is refused, and the refusal carries them, as a Read would.
  // Why: the agent wrote a block from the text it read before his commit and
  // put back the line he had replaced (omxzvrxr, 2026-11-17), and
  // the turn end told it of his commit only after the overwrite.
  // Why Bash too: that write was a `python3` heredoc, which the Edit and Write
  // tools never see. A command that names a queued file asks; a command that
  // names it and does not write it pays one refused call and gets his commits,
  // which it had to read anyway.
  // Why only a queued file for Bash: `\ k` and `+ g` queue the canvas too, and
  // `nu-hx unsent` costs about 0.4 s on a canvas of the mono (2026-11-17), which
  // every commit and `git show` of the agent that names the canvas would pay.
  // A limit: `\ l` marks its commits as sent at the keypress, and its line can
  // wait in the queue of Claude while a turn runs; a stale write passes then.
  // Why fail open: the guard is advice about a race, and a broken one must not
  // stop every write of the session; the turn end still hands the commits over.
  on('tool.call', { tool: ['Edit', 'Write'] }, async ($, e, next) => {
    const deny = offCanvas || e.agentId !== undefined ? undefined : await staleWrite($, [e.file_path]).catch(() => undefined)
    if (deny) {
      await showUnsent($, shown)
    }
    return deny ? { deny } : next(e)
  })
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const deny = offCanvas || e.agentId !== undefined ? undefined : await staleWrite($, await named($, e.command)).catch(() => undefined)
    if (deny) {
      await showUnsent($, shown)
    }
    return deny ? { deny } : next(e)
  })

  // A skill with its own chat replies, run by the agent: the floor stays down
  // for its replies. He orders a landing in words ("заленди"), the agent calls
  // the landing skill through the Skill tool, and the floor blocked each of its
  // replies (2026-11-17).
  // Not off the canvas, as his slash command is, because: the agent may run such
  // a skill in the middle of canvas work (one that records a mistake he marks in
  // a canvas line), and that turn keeps the review and the hand-over of his
  // commits. The cost: a commit he makes during a landing is handed over at its stop.
  // Why not a gi skill: the style says its pointer is the rows of its replies,
  // within the floor.
  on('skill.prompt', async ($, e, next) => {
    if (e.pluginName !== 'gi' && REPLIES.test(e.text)) {
      aside = true
    }
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    // An absent origin is the user's own prompt, as the engine's types define it.
    const user = !e.isMeta && (!e.origin || USER_ORIGINS.includes(e.origin.kind))
    const text = e.text.trim().toLowerCase()
    // A task notification (a background agent finished) goes on the work the
    // user's last prompt started, so it takes that prompt's aside.
    // Why: in the round-2 review, 19 floor blocks followed a notification
    // (counted by the review agent, 2026-11-17).
    if (e.origin?.kind === 'task-notification') {
      ;({ aside, offCanvas } = lastUser)
    } else {
      offCanvas = user && (!!e.command || text.startsWith(CHAT_MARKER))
      const short = !text.includes('\n') && !text.startsWith('!') && text.length <= SHORT_PROMPT
      aside = offCanvas || (user && (GO.test(text) || short))
      if (user) {
        lastUser = { aside, offCanvas }
      }
    }
    // Why here too, and not only at the turn end: the agent then reads the
    // rewrite before it works the prompt, not after.
    // Why try: the signal is news, and a prompt must not be lost over it.
    // Why not with an off-canvas aside: the text orders a report in the canvas,
    // and such a turn writes nothing there; it waits for the next canvas turn.
    const news = await lookAtHistory($, !offCanvas).catch(() => undefined)
    return next(news ? { ...e, context: [...(e.context ?? []), news] } : e)
  })

  // Why the turn and not `prompt.submit`: the user mostly starts a turn with a
  // `!` command from helix, and the types do not promise that event for it; the
  // work mark must show whatever started the work.
  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) {
      await showUnsent($, shown)
      await setMark($, WORK_MARK)
      await seedBase($)
      turnBase = await reviewBase($)
      await lookAtHistory($, false).catch(() => undefined)
    }
    return next(e)
  })

  // Why a system-prompt section and not `claude --append-system-prompt`: given
  // two of that flag, `claude` keeps only the last, so gi would have to refuse the
  // user's own. A section has its own id and sits beside anyone else's text.
  // Why the line at all: an environment variable is not in the model's context —
  // pointed at $env.GI_CANVAS, the agent guessed its name wrong and went hunting
  // the repo for a canvas.
  on('prompt.compose', async ($, e, next) => {
    const composed = await next(e)
    const canvas = await $.env.get('GI_CANVAS')
    if (!canvas) {
      return composed
    }
    // Relative to the session's directory, as gi prints it and the Stop hook
    // quotes it: the agent stands there, and the absolute form is noise.
    const doc = shortPath(canvas, await $.session.cwd())
    const text = `This session's canvas is \`${doc}\` — the one file the Canvas output style is about. Read it before your first answer; do not search for it.`
    const sections = [...composed.sections, { id: 'gi:canvas', text, scope: 'session' as const }]
    // `gi open --manager`: GI_MANAGER is the path of manager.md, the rules of
    // the manager mode. Why a section: the style file ships whole and has no
    // conditions. A subagent gets no section, so the rules bind the manager alone.
    const manager = await $.env.get('GI_MANAGER')
    if (manager) {
      sections.push({ id: 'gi:manager', text: ((await $.fs.read(manager)) as string).trim(), scope: 'session' })
    }
    return { ...composed, sections }
  })

  // Why at the call: a guard that reads the branch when the turn ends finds the
  // commits already made, and they have to be moved.
  // Why the session's directory and not the repo the command names: it is the
  // repo gi opened the canvas in.
  // Why Bash alone: agents here barely use the nushell MCP tool — 4 calls
  // machine-wide in the four weeks before 2026-10-14 (`claude-nu tool-calls`).
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    if (!GIT_COMMIT.test(e.command) || !(await $.env.get('GI_CANVAS'))) {
      return next(e)
    }
    const branch = await protectedBranch($)
    if (!branch || leavesProtected(e.command)) {
      return next(e)
    }
    return {
      deny: `You are on \`${branch}\` — gi commits are internal working history and must not land here. First switch to a branch of its own — \`git switch --create <topic>\`, alone or opening the command with \`&&\` — then commit; the branch gets squash-merged into \`${branch}\` after finalization.`,
    }
  }).catch(($, e, next) =>
    // Why deny on a broken guard: a guard that fails open is the one failure
    // nobody sees, as the Stop hook below turns its own errors into a block.
    next.called ? next(e) : { deny: `gi: the branch guard failed (${next.error?.message ?? next.error?.kind}); check the branch before committing.` },
  )

  // A turn that ends with no Stop: an interrupt or an API error. Where the
  // answer ends it, the Stop hook below has set the mark, or a blocked Stop
  // has kept the work mark, and the turn went on.
  // Why the interrupt takes the mark away: the user stopped the turn himself.
  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) {
      aside = false
      offCanvas = false
      if (e.reason !== 'answer') {
        await (e.reason === 'aborted' ? clearMark($, [WORK_MARK]) : setMark($, ERROR_MARK))
      }
    }
    return next(e)
  })

  // Why: a session quit in the middle of a turn would leave the work mark until
  // the next `gi open`.
  on('session.end', async ($, e, next) => {
    await clearMark($, [WORK_MARK])
    return next(e)
  })

  // The floor under the Canvas style: the style rests on prose and the agent
  // drifts back to long chat answers, so a turn may end only on a short chat
  // line. And a turn may not end over the user's canvas commits that the agent
  // was never sent (`unsentReason`).
  // Not a branch rule at the turn end because: the guard above refuses the
  // commit at the call, and the merge it cannot see is mostly the sanctioned
  // landing onto the trunk — such a rule would fire after every landing and
  // only flag a stray merge once it is made.
  // Why GI_NO_HOOK: `gi open --no-hook` opens a canvas with the style alone, and
  // the mod loads with every launch, so the launch has to say so.
  on('classic.Stop', async ($, e, next) => {
    // Already continuing from a prior block: let the turn end, or a block the
    // agent cannot clear loops forever.
    if (e.stop_hook_active) {
      await markDone($)
      return next(e)
    }
    const canvas = await $.env.get('GI_CANVAS')
    const reasons: (string | undefined)[] = []
    if (canvas && !(await $.env.get('GI_NO_HOOK'))) {
      // Why not on an off-canvas aside: a `chat:` answer and a skill's own flow
      // are not canvas work, as for the unsent commits below.
      // Why before them: the reviewer takes seconds, and `unsentReason` marks the
      // commits as sent; an interrupt during the wait would lose them.
      const review = offCanvas ? undefined : await reviewReason($, canvas, turnBase, e.last_assistant_message, !!(await $.env.get('GI_REVIEW')))
      reasons.push(offCanvas ? undefined : await unsentReason($, e, canvas))
      reasons.push(aside ? undefined : await stopReason($, e, canvas))
      reasons.push(review)
      // Why not on an off-canvas aside: as for the unsent commits; the news
      // waits for the next canvas turn.
      // Why after the rules above: one that throws must not take the news with it.
      // Why try: the signal is news, and a turn must not fail to end over it.
      if (!offCanvas) {
        reasons.unshift(await lookAtHistory($, true).catch(() => undefined))
      }
    }
    await showUnsent($, shown)
    const reason = reasons.filter(r => r !== undefined).join('\n\n') || undefined
    if (!reason) {
      await markDone($)
    }
    const below = await next(e)
    return reason ? { ...below, block: below.block ? `${below.block}\n\n${reason}` : reason } : below
  }).catch(($, e, next) =>
    // Why block on a broken rule (a typo in GI_HOOK_MAX_LEN): a
    // failed hook is skipped, and a floor that vanishes is the one failure
    // nobody sees. The loop guard still lets the turn end on the retry.
    e.stop_hook_active || next.called ? next(e) : { block: `gi: the Stop rule failed internally — fix this before continuing: ${next.error?.message ?? next.error?.kind}` },
  )
}

// Look where the repo stands and give the rewrite since the commit the agent
// last stood on (`rewrite.ts`). The commit is remembered anew when there is no
// rewrite, and when the rewrite is told now (`tell`); a rewrite that cannot be
// told — at a turn start, with a `chat:` aside — stays for the next look, which
// finds it again from the same commit.
// Why nothing is remembered on a detached HEAD: a rebase that the user paused
// to split a commit stands there, and the look after it needs the old commit.
// Why GI_NO_HOOK: `gi open --no-hook` asks for the style alone.
async function lookAtHistory($: Api, tell: boolean) {
  const canvas = await $.env.get('GI_CANVAS')
  if (!canvas || (await $.env.get('GI_NO_HOOK'))) {
    return undefined
  }
  const now = await standsOn($, canvas)
  if (!now) {
    return undefined
  }
  const reason = await rewrittenReason($, canvas, await lastSeen($, canvas, now), now, PROTECTED_BRANCHES)
  if (!reason || tell) {
    await remember($, canvas, now)
  }
  return tell ? reason : undefined
}

// Show in the zellij title of the helix pane what the agent does: `mark` is
// DONE_MARK, WORK_MARK or ERROR_MARK. helix does not watch the file, and the user should see that
// the agent works, or that the answer arrived, without leaving the editor.
// Why try: the title is a hint, and a turn must not stop or fail over it; a
// failure shows as a title that does not change.
async function setMark($: Api, mark: string, facts: (canvas: string) => Promise<string> = async () => '') {
  try {
    const canvas = await $.env.get('GI_CANVAS')
    const pane = canvas && (await helixPane($))
    if (pane) {
      await $.process.run(['zellij', 'action', 'rename-pane', '--pane-id', `terminal_${pane}`, `${mark}${canvas.split('/').pop()}${await facts(canvas)}`])
    }
  } catch {}
}

// What the done mark adds after the name: `✅ plan.md ?2 ↑5`, the open `???`
// and `!!!` of the canvas and its `<stem>*.md` siblings, and the commits of the
// branch that the trunk does not hold; each is left out at zero.
// Why: he asked in chat "мы залендили ветку?", "ты все?", "в canvas чего
// осталось?" (42 state questions in round 2 of the canvas usage review), and
// the title of the helix pane is where his eye is.
// After a landing that fast-forwards the trunk to the branch, `↑` is gone; a
// squash merge that leaves the branch behind keeps the count.
// A count that fails, or a repo with no protected branch, also leaves `↑` out.
// Why each fact fails alone: a title with one fact is still a hint.
async function doneFacts($: Api, canvas: string) {
  const open = await openMarkers($, canvas).catch(() => 0)
  const ahead = await aheadOfTrunk($, canvas).catch(() => 0)
  const facts = [open ? `?${open}` : '', ahead ? `↑${ahead}` : ''].filter(f => f)
  return facts.length ? ` ${facts.join(' ')}` : ''
}

// The marker lines of the agent that wait for the user (`OPEN_MARKER`), wider
// than the `rg` of the style, which reads column 0 only.
async function openMarkers($: Api, canvas: string) {
  let count = 0
  for (const path of await familyFiles($, canvas)) {
    count += ((await $.fs.read(path)) as string).split('\n').filter(l => OPEN_MARKER.test(l)).length
  }
  return count
}

// The commits of HEAD that the first protected branch the repo has does not hold.
async function aheadOfTrunk($: Api, canvas: string) {
  const dir = canvas.slice(0, canvas.lastIndexOf('/'))
  for (const trunk of PROTECTED_BRANCHES) {
    const run = await $.process.run(['git', '-C', dir, 'rev-list', '--count', `${trunk}..HEAD`])
    if (run.exitCode === 0) {
      return Number(run.stdout.trim()) || 0
    }
  }
  return 0
}

// The answer arrived: the done mark, and a bell through the user's own
// notification channel (`preferredNotifChannel`; cozy sets `terminal_bell`).
// Why a bell of its own: Claude Code rings on its `idle_prompt`, about 60
// seconds after the answer, and the user waits for the answer in the helix pane.
// Why with no helix pane too: the bell says that the turn ended, and the
// mark is only one place that shows it.
// GI_NO_BELL: `gi open --no-bell` keeps the mark and drops the sound.
// Why try: as for the mark, a turn must not fail to end over a sound.
async function markDone($: Api) {
  await setMark($, DONE_MARK, canvas => doneFacts($, canvas))
  try {
    if ((await $.env.get('GI_CANVAS')) && !(await $.env.get('GI_NO_BELL'))) {
      await $.ui.notify('the answer is in the canvas', { title: 'gi' })
    }
  } catch {}
}

// Why only a title with one of `marks`: a name the user gave the pane stays.
async function clearMark($: Api, marks: string[]) {
  try {
    const pane = (await $.env.get('GI_CANVAS')) && (await helixPane($))
    if (!pane) {
      return
    }
    const { stdout } = await $.process.run(['zellij', 'action', 'list-panes', '--json'])
    const panes = JSON.parse(stdout) as { id: number; is_plugin: boolean; title?: string }[]
    const title = panes.find(p => !p.is_plugin && String(p.id) === pane)?.title ?? ''
    if (marks.some(m => title.startsWith(m))) {
      await $.process.run(['zellij', 'action', 'undo-rename-pane', '--pane-id', `terminal_${pane}`])
    }
  } catch {}
}

// Remember the canvas as it is on disk as the base of the three-way merge that
// `nu-hx merge-save` (dotfiles, the `\ k` and `\ l` bindings) runs when the
// user's helix buffer and the agent's writes diverge — only when no base is
// there yet, so a turn's own writes never replace what helix read last.
// Why at the turn start: before the agent's first write the disk still holds
// the text helix read, and helix has no hook on opening a file.
// Why through hx-nu: the base's path and hash live in nu-hx.nu, and a second
// copy here would drift.
// Why try: without dotfiles there is no hx-nu, and the keys are not there either.
async function seedBase($: Api) {
  try {
    const canvas = await $.env.get('GI_CANVAS')
    if (canvas) {
      await $.process.run(['hx-nu', '--commands', `nu-hx base-seed r#'${canvas}'#`])
    }
  } catch {}
}

// Why try: the review is advice, and a turn must not fail to start over it.
async function reviewBase($: Api) {
  try {
    const canvas = await $.env.get('GI_CANVAS')
    return canvas && !(await $.env.get('GI_NO_HOOK')) ? await headOf($, canvas) : undefined
  } catch {
    return undefined
  }
}

type Shown = { text: string | undefined }

// How often the status line looks at the queue, in milliseconds.
const STATUS_PERIOD = 3000

// The queue of this session's pane as `nu-hx queue-add` (dotfiles) writes it:
// the absolute path of a file, once per commit. Change that path and this one
// together. Empty outside zellij and when no commit waits.
async function queued($: Api) {
  const home = await $.env.get('HOME')
  const session = await $.env.get('ZELLIJ_SESSION_NAME')
  const me = await $.env.get('ZELLIJ_PANE_ID')
  if (!home || !session || !me) {
    return []
  }
  const text = await $.fs.read(`${home}/.cache/gi/unsent/${session}-${me}`).catch(() => '')
  return (text as string).split('\n').filter(line => line !== '')
}

// Why try: the line is a hint, and no turn or timer may fail over it.
async function showUnsent($: Api, shown: Shown) {
  try {
    const counts = new Map<string, number>()
    for (const path of await queued($)) {
      const name = path.slice(path.lastIndexOf('/') + 1)
      counts.set(name, (counts.get(name) ?? 0) + 1)
    }
    const text = counts.size ? `unsent: ${[...counts].map(([name, n]) => `${name} ${n}`).join(', ')}` : undefined
    if (text !== shown.text) {
      shown.text = text
      await $.ui.status(text)
    }
  } catch {}
}

// The user's commits to `path` that the agent was never sent, with their
// diffs, when the file is the canvas or waits in the queue; `nu-hx
// tell-claude-on-read` (dotfiles) prints them, remembers them as sent and
// takes the file out of the queue.
// Why the check here first: every Read and write of the session comes through,
// and a nu process for each would slow all of them.
async function unsentCommits($: Api, path: string) {
  const canvas = await $.env.get('GI_CANVAS')
  if (!canvas || (await $.env.get('GI_NO_HOOK')) || (path !== canvas && !(await queued($)).includes(path))) {
    return undefined
  }
  const run = await $.process.run(['hx-nu', '--commands', `nu-hx tell-claude-on-read r#'${path}'# --canvas r#'${canvas}'#`])
  return (run.exitCode === 0 ? run.stdout.trim() : '') || undefined
}

// The queued files whose name a Bash command holds. A file is named by its
// base name, which a relative path and an absolute one both end in.
async function named($: Api, command: string) {
  const files = [...new Set(await queued($))]
  return files.filter(f => command.includes(f.slice(f.lastIndexOf('/') + 1)))
}

// The refusal of a write to `paths`, with the user's commits it was never
// sent; undefined when none waits.
async function staleWrite($: Api, paths: string[]) {
  for (const path of paths) {
    const commits = await unsentCommits($, path)
    if (commits) {
      return `The user committed to \`${path}\` since you last read it, and these commits were never sent to you; they now count as sent. Your call did not run. Read them as his instructions, oldest first: a later commit wins over an earlier one. Then read the file again and redo the call on its text as it is now, which holds them.\n\n${commits}`
    }
  }
  return undefined
}

// The helix pane that last sent this session a prompt, as `nu-hx tell-claude`
// (dotfiles, the `\ l` binding) wrote it: change that path and this one together.
// Why from the sender: it knows its own pane and the pane of Claude, so nothing
// has to search; a session before its first `\ l` has no file, and the read
// rejects into the caller's try, so it gets no mark.
async function helixPane($: Api) {
  const home = await $.env.get('HOME')
  const session = await $.env.get('ZELLIJ_SESSION_NAME')
  const me = await $.env.get('ZELLIJ_PANE_ID')
  if (!home || !session || !me) {
    return undefined
  }
  return ((await $.fs.read(`${home}/.cache/gi/helix-pane/${session}-${me}`)) as string).trim()
}

// The user's commits to the canvas that the agent was never sent — made with
// `\ k` while it worked, with no `\ l` after — handed over at the turn end as a
// `\ l` would hand them, so the turn goes on over them.
// Why: the user commits while the agent works, and a `\ l` for each batch is one
// action too many.
// Not the Claude Code note that a read file changed on disk because: it came for
// one such commit and not for another in one session (5efd3d53, 2026-11-05), and
// it carries the current text, not the order of the commits.
// Why at the turn end, not at the next tool call: the agent finishes the step it
// is in, and the batch is read whole, the later commit winning, as a long message is.
// Why through hx-nu: the range and the sent ref live in nu-hx.nu (`unsent`), and
// a second copy here would drift; it moves the ref too, so the next `\ l` does
// not send the same commits again.
// Why the line on repeats: after a `\ l` the user may stop the agent, fix the
// sent commit with a fixup, and type `git log -p -1` in chat by hand, which moves
// no ref; so the list can hold a commit the agent already read.
// Why a command that cannot start is no error: without dotfiles there is no
// hx-nu, and no `\ k` or `\ l` either. A nu-hx that fails is one: it throws into
// the rule's catch, which blocks the turn and says why.
async function unsentReason($: Api, e: StopEvent, canvas: string) {
  const run = await $.process.run(['hx-nu', '--commands', `nu-hx tell-claude-at-stop r#'${canvas}'#`]).catch(() => undefined)
  if (!run) {
    return undefined
  }
  if (run.exitCode !== 0) {
    throw new Error(`nu-hx tell-claude-at-stop: ${run.stderr.trim()}`)
  }
  const show = run.stdout.trim()
  return show
    ? `The user committed to \`${shortPath(canvas, e.cwd)}\` or to other files he edits beside it, and these commits were never sent to you: run \`${show}\`. Read them all, oldest first, before you act: a later commit wins over an earlier one, as in a long message. The list can repeat what you already read — a \`git log -p\` the user typed by hand, or a fixup of a sent commit — so skip what you already did; where the intent of a commit is unclear, ask with a \`???\` in the canvas. Work the rest in the canvas as usual.`
    : undefined
}

async function stopReason($: Api, e: StopEvent, canvas: string) {
  if (allowed(e.last_assistant_message ?? '', await $.env.get('GI_HOOK_MAX_LEN'))) {
    return undefined
  }
  // The escape hatch is safe by construction: the blocked message is already
  // on the user's screen, and the loop guard ends the turn on the follow-up
  // whatever it says — a misfire can redirect one reply, never trap the agent.
  return `Chat may carry only one short line — \`done\`, a status note, or a pointer to where the answer landed. Move the full answer into \`${shortPath(canvas, e.cwd)}\` and commit it; leave only that one line in chat. If this block looks like a misfire — wrong canvas, no gi work in this session — don't move anything: reply with one short line telling the user to read your previous message above in the chat and to check the session's canvas (\`claude-nu gi\`).`
}

// True when `message` may stand alone in chat: empty, or within both budgets.
function allowed(message: string, maxLen: string | undefined) {
  const text = message.trim()
  const max = maxLen ? Number(maxLen) : DEFAULT_MAX_LEN
  if (!Number.isInteger(max)) {
    throw new Error(`GI_HOOK_MAX_LEN is not an integer: ${maxLen}`)
  }
  return text.split(/\r?\n/).length <= MAX_BREAKS + 1 && new TextEncoder().encode(text).length <= max
}

// Whether the command leaves the protected branch before anything else runs:
// it opens with `git switch <branch>`, `git switch --create <branch>` or
// `git checkout -b <branch>`, and the branch is not a protected one.
// Why it is allowed: agents open with the switch and commit in the same call
// (24 Bash calls in 23 sessions this rule lets through, 2026-04-03 to
// 2026-10-13; counted on 2026-10-14 by running this rule over
// `claude-nu projects | claude-nu tool-calls --tool Bash 'git commit'`),
// and the branch is read before the call runs, so the guard saw the trunk.
// Not a plain `git checkout <name>` because: `git checkout -- file` and
// `git checkout file` have the same shape and stay on the trunk.
function leavesProtected(command: string) {
  const match = LEADING_SWITCH.exec(command)
  if (!match) {
    return false
  }
  const verb = match[1] as 'switch' | 'checkout'
  const words = match[2].trim().split(/\s+/).filter(w => !SWITCH_FLAGS.includes(w))
  const create = words.length > 0 && CREATE_FLAGS[verb].includes(words[0])
  const names = create ? words.slice(1) : words
  // A start point may follow a new branch name; a plain switch takes one name.
  const fits = create ? names.length === 1 || names.length === 2 : verb === 'switch' && names.length === 1
  const name = names[0]
  return fits && !name.startsWith('-') && !PROTECTED_BRANCHES.includes(name)
}

// The session's branch when it is a protected one; undefined outside a repo, on
// a detached HEAD, or on any other.
async function protectedBranch($: Api) {
  const { exitCode, stdout } = await $.process.run(['git', 'branch', '--show-current'])
  const branch = stdout.trim()
  return exitCode === 0 && PROTECTED_BRANCHES.includes(branch) ? branch : undefined
}

// The canvas relative to `dir` when it lies under it, as gi prints it: the
// agent stands there, and the absolute form is noise. A canvas above has no
// short form that resolves, so it is named in full.
function shortPath(canvas: string, dir: string) {
  return canvas.startsWith(`${dir}/`) ? canvas.slice(dir.length + 1) : canvas
}
