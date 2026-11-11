import type { Hook, Register } from 'claude-code'
import { headOf, reviewReason } from './review'

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
const GO = /^(go|го)(?![\p{L}\p{N}_])/u

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

export const register: Register = on => {
  // Whether the prompt that opened the current turn is an aside: a `chat:`
  // message, a `go`, or a slash command the user ran. Every prompt resets it, so an
  // aside is spent once answered, and a notification or a peer message starting
  // a turn puts the floor back up.
  // Why a slash command: a skill the user runs carries its own instructions for
  // the chat (`/40-land-branch` shows its plan there and waits), and the floor
  // pushed that answer into the canvas. A skill the agent calls through the Skill
  // tool raises no `prompt.submit`, so it never lifts the floor.
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
  // The commit the repo stood on when the turn started: the review at the turn
  // end reads the commits made since. Unset without `gi open --review`.
  let turnBase: string | undefined

  on('prompt.submit', ($, e, next) => {
    // An absent origin is the user's own prompt, as the engine's types define it.
    const user = !e.isMeta && (!e.origin || USER_ORIGINS.includes(e.origin.kind))
    const text = e.text.trim().toLowerCase()
    offCanvas = user && (!!e.command || text.startsWith(CHAT_MARKER))
    aside = offCanvas || (user && GO.test(text))
    return next(e)
  })

  // Why the turn and not `prompt.submit`: the user mostly starts a turn with a
  // `!` command from helix, and the types do not promise that event for it; the
  // mark must go whatever started the work.
  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) {
      await clearDoneMark($)
      await seedBase($)
      turnBase = await reviewBase($)
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
    return { ...composed, sections: [...composed.sections, { id: 'gi:canvas', text, scope: 'session' }] }
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
      await setDoneMark($)
      return next(e)
    }
    const canvas = await $.env.get('GI_CANVAS')
    const reasons: (string | undefined)[] = []
    if (canvas && !(await $.env.get('GI_NO_HOOK'))) {
      // Why not on an off-canvas aside: a `chat:` answer and a skill's own flow
      // are not canvas work, as for the unsent commits below.
      // Why before them: the reviewer takes seconds, and `unsentReason` marks the
      // commits as sent; an interrupt during the wait would lose them.
      const review = offCanvas || !(await $.env.get('GI_REVIEW')) ? undefined : await reviewReason($, canvas, turnBase, e.last_assistant_message)
      reasons.push(offCanvas ? undefined : await unsentReason($, e, canvas))
      reasons.push(aside ? undefined : await stopReason($, e, canvas))
      reasons.push(review)
    }
    const reason = reasons.filter(r => r !== undefined).join('\n\n') || undefined
    if (!reason) {
      await setDoneMark($)
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

// Show in the zellij title of the helix pane that the agent has finished its turn:
// helix does not watch the file, and the user should see the answer arrived
// without leaving the editor. At every turn end, a chat answer too.
// Why try: the title is a hint, and a turn must not stop or fail over it; a
// failure shows as a title that does not change.
async function setDoneMark($: Api) {
  try {
    const canvas = await $.env.get('GI_CANVAS')
    const pane = canvas && (await helixPane($))
    if (pane) {
      await $.process.run(['zellij', 'action', 'rename-pane', '--pane-id', `terminal_${pane}`, `${DONE_MARK}${canvas.split('/').pop()}`])
    }
  } catch {}
}

// Why only a title with the mark: a name the user gave the pane stays.
async function clearDoneMark($: Api) {
  try {
    const pane = (await $.env.get('GI_CANVAS')) && (await helixPane($))
    if (!pane) {
      return
    }
    const { stdout } = await $.process.run(['zellij', 'action', 'list-panes', '--json'])
    const panes = JSON.parse(stdout) as { id: number; is_plugin: boolean; title?: string }[]
    if (panes.find(p => !p.is_plugin && String(p.id) === pane)?.title?.startsWith(DONE_MARK)) {
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
    return canvas && (await $.env.get('GI_REVIEW')) ? await headOf($, canvas) : undefined
  } catch {
    return undefined
  }
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
    ? `The user committed to \`${shortPath(canvas, e.cwd)}\`, and these commits were never sent to you: run \`${show}\`. Read them all, oldest first, before you act: a later commit wins over an earlier one, as in a long message. The list can repeat what you already read — a \`git log -p\` the user typed by hand, or a fixup of a sent commit — so skip what you already did; where the intent of a commit is unclear, ask with a \`???\` in the canvas. Work the rest in the canvas as usual.`
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
