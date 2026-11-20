import type { Hook } from 'claude-code'

type Api = Parameters<Hook<'classic.Stop'>>[0]

// The review of a turn at its end, in two halves. The first, at every turn end
// of a canvas session: the rules of the Canvas style that a command can check,
// run over the lines the agent's commits of this turn added to the canvas and
// its sibling files. The second, only with `gi open --review` (GI_REVIEW): the
// reviewer below.
// Why the checks with no flag: `--review` was on in 1 of 64 `gi open` launches
// (round 2 of the canvas usage review, 2026-11-17), so the caps they check went
// unchecked, while the flag exists for the reviewer, a model call with no
// timeout that "must not stretch a turn without end"; the checks are a git log
// and regexes.
// Why: a rule in prose is loaded and still not followed, and a check that the
// agent has to remember to run is one more such rule.
// Why only the lines of this turn: a finding the agent answered must not come
// back at every later turn end, and `check-links` also lists a syntax example.
// Why advice and never a failure: a check cannot read the context, so a finding
// may be wrong; every finding says "check", and an error here is silence —
// unlike the floor, whose failure blocks.

// The caps of "Save his reading budget" in the style: change both together.
// MAX_TOTAL_QUESTIONS has no line there: it is a check of this file alone.
const MAX_AA_SENTENCES = 3
const MAX_OPEN_QUESTIONS = 3
// The open `???` of the canvas family that one reading of his may hold.
// Why: past it he stops deciding ("друг, это overflow для меня. Никаких решений
// принимать не буду" over 42 open `???`, 2026-10-31), and the cap per turn does
// not see a backlog that grows over many turns.
const MAX_TOTAL_QUESTIONS = 5
const MAX_LINE_WIDTH = 100

const LIST_ITEM = /^\s*([-*]|\d+\.) /
// A marker line of the agent that waits for the user: `???` or `!!!` at any
// indent, also as a list item. The helix title of the gi hooks counts these too.
export const OPEN_MARKER = /^\s*(- )?(\?\?\?|!!!)/
const MARKER = /^\s*(AA:|\?\?\?|!!!|%%%)/
// A line that ends a sentence, also before a closing quote, bracket or mark.
// No backtick among them: a line that ends in the code span `???` ends no sentence.
const SENTENCE_END = /[.?!]["')*]*$/

export type Added = { file: string; isNew: boolean; lines: string[] }

// The commit the session's repo stands on, read in the directory of the canvas.
export async function headOf($: Api, canvas: string) {
  const { exitCode, stdout } = await $.process.run(['git', '-C', dirOf(canvas), 'rev-parse', 'HEAD'])
  return exitCode === 0 ? stdout.trim() : undefined
}

// The rules that need judgement, asked of the session's own model over the
// session's own transcript (`$.model.fork`): the reviewer knows what the user
// said, has no tools, and answers once.
// Why one call with five questions: the turn end waits for one request, and
// the fork has no timeout of its own — only the user's interrupt ends it.
// Why no `effort`: on a model without per-message effort another level writes
// the whole conversation to the prompt cache again; haste is asked in the
// prompt, which leaves the cached prefix as the main thread sent it.
// The first word of a finding is the question it answers, so the findings of
// each one can be counted in the transcripts: the block is a hidden user
// record there (`claude-nu messages --include-system 'gi review'`).
const REVIEW_PROMPT = `You are now the gi reviewer of this canvas session, not its agent. You have no tools: answer at once from what this conversation already shows, and do not think it over at length.

Review only the turn that is ending now, from the user's last prompt to the answer below, against the Canvas style and the user's instructions above. Answer five closed questions:

sync: did the turn change a fact — in the canvas, in a sibling file, or by an edit of the user — and leave an older copy of it in the canvas or its sibling files, as far as this conversation shows their text?
command: did the turn do something other than what the user's words asked — it acted on a question, edited on a "check" or a "review", wrote code on a "reprocess", went past what a "go" covered, or the reverse of one of these?
not-requested: did the agent fill a gap with a choice of its own and not name it in a \`Not requested:\` line?
place: did the agent append an answer where an \`AA:\` entry under the same point had to be rewritten in place, or put an answer or a remark away from the line or words it is about?
carry: did the user type canvas work in the chat — not a \`chat:\` aside, a slash command, a \`go\` or a \`!\` command — that the agent did not carry into the canvas in his words?

If every answer is no, reply with the two letters OK and nothing else. Otherwise write one line per finding, at most five lines: \`<question>: <what is wrong, and where — the file and the words>\`. Report only what you can point at in this conversation; when you are not sure, leave it out. Leave out a finding that was raised earlier in this conversation and answered.`

// The findings of the checks and of the reviewer as one block of advice;
// undefined when the turn made no commit, when nothing is found, and on any failure.
export async function reviewReason($: Api, canvas: string, base: string | undefined, answer: string | undefined, withReviewer: boolean) {
  try {
    const email = base && (await agentCommitted($, canvas, base))
    if (!base || !email) {
      return undefined
    }
    // Each half fails alone: a reviewer the API refused leaves the checks standing.
    const [checks, reviewer] = await Promise.all([
      checkFindings($, canvas, base, email).catch(() => [] as string[]),
      withReviewer ? reviewerFindings($, answer).catch(() => undefined) : undefined,
    ])
    const parts = [checks.length ? `checks:\n${checks.map(f => `- ${f}`).join('\n')}` : undefined, reviewer ? `reviewer:\n${reviewer}` : undefined].filter(p => p !== undefined)
    return parts.length
      ? `gi review — advice on this turn, not an order: the checks read the lines the turn added and the open markers of the canvas${withReviewer ? ', and the reviewer has no tools' : ''}. Check each line: fix what is right, in the canvas as usual; where a finding is wrong, change nothing and say so in your one chat line.\n\n${parts.join('\n\n')}`
      : undefined
  } catch {
    return undefined
  }
}

// The email of the agent when the turn holds a commit of the agent, else undefined.
// The agent's commits are the ones under the identity this process commits
// with; the user's `\\ k` commits and the carry commits (`+claude@`) hold his
// lines, and a turn that holds only those gets no review. Where the user and
// the agent commit under one email, his lines are read as the agent's.
// Why the ancestor test: after an amend or a rebase of the commit the turn
// started on, the range holds commits of earlier turns again, and their
// findings would come back.
async function agentCommitted($: Api, canvas: string, base: string) {
  const dir = dirOf(canvas)
  const git = (...args: string[]) => $.process.run(['git', '-C', dir, ...args])
  if ((await git('merge-base', '--is-ancestor', base, 'HEAD')).exitCode !== 0) {
    return undefined
  }
  const email = /<([^>]*)>/.exec((await git('var', 'GIT_AUTHOR_IDENT')).stdout)?.[1]
  const authors = await git('log', '--format=%ae', `${base}..HEAD`)
  return email && authors.exitCode === 0 && authors.stdout.split('\n').includes(email) ? email : undefined
}

// Why only the lines that open with the name of a question: a reply in prose
// ("No findings.") is no finding, and the name is what the count reads.
const FINDING = /^(sync|command|not-requested|place|carry):/

// Why the answer rides in the prompt: the fork repeats the main thread's last
// request, and the answer the turn ends on came back from that request.
async function reviewerFindings($: Api, answer: string | undefined) {
  const reply = await $.model.fork({ prompt: answer ? `${REVIEW_PROMPT}\n\nThe answer the turn is about to end on:\n\n${answer}` : REVIEW_PROMPT })
  // A reply may dress a line as a list item, code or bold: the dress goes.
  const findings = reply.isAnswered ? reply.text.split('\n').map(l => l.replace(/^[\s\-*`]+/, '').trim()).filter(l => FINDING.test(l)) : []
  return findings.length ? findings.join('\n') : undefined
}

async function checkFindings($: Api, canvas: string, base: string, email: string) {
  const dir = dirOf(canvas)
  const name = canvas.slice(dir.length + 1)
  const stem = name.replace(/\.[^.]+$/, '')
  // Why the pathspec `.`: the checks are about the canvas folder, so a new file
  // elsewhere, such as a source file, is not seen.
  const log = await $.process.run(['git', '-C', dir, '-c', 'core.quotePath=false', 'log', '--reverse', '--relative', '--default-prefix', '--no-color', '--no-ext-diff', '--unified=0', '--format=%x00%ae', `${base}..HEAD`, '--', '.'])
  if (log.exitCode !== 0) {
    return []
  }
  const added = addedLines(log.stdout, email)
  // The canvas and its siblings: every `<canvas stem>*.md` beside it.
  const family = added.filter(a => a.file.endsWith('.md') && a.file.startsWith(stem) && !a.file.includes('/'))
  const findings = family.flatMap(a => [...unlinkedItems(a), ...longEntries(a), ...wideLines(a)])
  const questions = family.flatMap(a => a.lines).filter(l => /^\s*\?\?\?/.test(l)).length
  if (questions > MAX_OPEN_QUESTIONS) {
    findings.push(`${questions} new \`???\` in one turn; the cap is ${MAX_OPEN_QUESTIONS}, the rest wait`)
  }
  for (const a of family) {
    findings.push(...(await refusedLinks($, `${dir}/${a.file}`, a)))
  }
  findings.push(...(await openFindings($, canvas, family).catch(() => [] as string[])))
  const text = (await $.fs.read(canvas)) as string
  for (const a of added) {
    if (a.isNew && a.file !== name && !text.includes(a.file)) {
      findings.push(`${a.file}: a new file beside the canvas that the canvas does not name in \`related_files\``)
    }
  }
  return findings
}

// The `<stem>*.md` files beside the canvas, the canvas among them, as paths.
export async function familyFiles($: Api, canvas: string) {
  const dir = dirOf(canvas)
  const stem = canvas.slice(dir.length + 1).replace(/\.[^.]+$/, '')
  return (await $.fs.list(dir)).filter(f => f.kind === 'file' && f.name.startsWith(stem) && f.name.endsWith('.md')).map(f => `${dir}/${f.name}`)
}

// The open markers of the canvas family as they stand now: too many open `???`
// in all, when the turn added one, and a `!!!` the turn added to a file that
// holds an open `???`.
// Why only a turn that added a `???`: the agent cannot close one that waits for
// him, so a finding at every turn end would only cost turns.
// Why the second: a `!!!` sign step stood beside two open `???` defaults, he
// signed it, a default was wrong, and it took a revert and a second signature
// (unvuwwxv, nsmnmwly, pssnmmnq).
async function openFindings($: Api, canvas: string, family: Added[]) {
  const findings: string[] = []
  const marker = (line: string) => OPEN_MARKER.exec(line)?.[2]
  let total = 0
  for (const path of await familyFiles($, canvas)) {
    const name = path.slice(path.lastIndexOf('/') + 1)
    const questions = ((await $.fs.read(path)) as string).split('\n').filter(l => marker(l) === '???').length
    total += questions
    if (questions && family.some(a => a.file === name && a.lines.some(l => marker(l) === '!!!'))) {
      findings.push(`${name}: a new \`!!!\` in a file with ${questions} open \`???\`: he may act on the step before the question is settled; settle the \`???\` first, or name in the step the default it takes`)
    }
  }
  if (total > MAX_TOTAL_QUESTIONS && family.some(a => a.lines.some(l => marker(l) === '???'))) {
    findings.push(`${total} open \`???\` in the canvas and its siblings, more than the ${MAX_TOTAL_QUESTIONS} he decides in one reading: settle or drop the ones you can before you add one`)
  }
  return findings
}

// The lines that the commits of `email` added, per file, from the output of
// `git log --unified=0 --format=%x00%ae`. An empty line stands between hunks, so
// a run of lines never joins two places of a file.
export function addedLines(log: string, email: string): Added[] {
  const files = new Map<string, Added>()
  let mine = false
  let inHunk = false
  let isNew = false
  let current: Added | undefined
  for (const line of log.split('\n')) {
    if (line.startsWith('\0')) {
      mine = line.slice(1) === email
      inHunk = false
      current = undefined
    } else if (line.startsWith('diff --git ')) {
      inHunk = false
      current = undefined
    } else if (!inHunk && line.startsWith('--- ')) {
      isNew = line === '--- /dev/null'
    } else if (!inHunk && line.startsWith('+++ b/')) {
      // git ends the name of a file that holds a space with a tab.
      const file = line.slice(6).replace(/\t$/, '')
      current = mine ? (files.get(file) ?? { file, isNew: false, lines: [] }) : undefined
      if (current) {
        current.isNew ||= isNew
        files.set(file, current)
      }
    } else if (line.startsWith('@@')) {
      inHunk = true
      current?.lines.push('')
    } else if (inHunk && line.startsWith('+')) {
      current?.lines.push(line.slice(1))
    }
  }
  return [...files.values()]
}

// "Two or more items are a list": an item that holds a code span and no
// fragment link is a missing link, or a code span that names no place.
export function unlinkedItems(a: Added) {
  return a.lines
    .filter(l => LIST_ITEM.test(l) && l.includes('`') && !l.includes(':/'))
    .map(l => `${a.file}: a list item with a code span and no fragment link: "${cut(l)}"`)
}

// "Save his reading budget": an `AA:` entry is one to three sentences; its
// list items do not count.
// Why sentences and not lines: the lines of an entry are semantic-feed lines,
// so a cap in lines is obeyed most cheaply with long lines.
// A sentence is counted where a line ends it; lines with no such end before the
// entry closes are one more sentence.
export function longEntries(a: Added) {
  const findings: string[] = []
  let first: string | undefined
  let count = 0
  let open = false
  const close = () => {
    const sentences = count + (open ? 1 : 0)
    if (first !== undefined && sentences > MAX_AA_SENTENCES) {
      findings.push(`${a.file}: an \`AA:\` entry of ${sentences} sentences, the cap is ${MAX_AA_SENTENCES}: "${cut(first)}"`)
    }
    first = undefined
  }
  const read = (line: string) => {
    open = !SENTENCE_END.test(line.trimEnd())
    count += open ? 0 : 1
  }
  for (const line of a.lines) {
    if (/^\s*AA:/.test(line)) {
      close()
      first = line
      count = 0
      read(line)
    } else if (!line.trim() || MARKER.test(line)) {
      close()
    } else if (first !== undefined && !LIST_ITEM.test(line)) {
      read(line)
    }
  }
  close()
  return findings
}

// "Save his reading budget": a line of an `AA:` entry is a semantic-feed line
// of at most 100 characters.
// Why beside the count of sentences: three long lines hold three sentences and
// pass that count.
export function wideLines(a: Added) {
  const findings: string[] = []
  let inEntry = false
  for (const line of a.lines) {
    inEntry = /^\s*AA:/.test(line) || (inEntry && !!line.trim() && !MARKER.test(line))
    if (inEntry && line.length > MAX_LINE_WIDTH) {
      findings.push(`${a.file}: a line of an \`AA:\` entry of ${line.length} characters, a feed line has at most ${MAX_LINE_WIDTH}: "${cut(line)}"`)
    }
  }
  return findings
}

// "A place you name is a fragment link": the links of the turn's own lines that
// the jump in helix refuses, as `nu-hx check-links` (dotfiles) lists them.
// Why through hx-nu: the resolver of a link lives in nu-hx.nu, and a second
// copy here would pass a link that the jump refuses.
// A command that cannot start is no finding: without dotfiles there is no jump.
async function refusedLinks($: Api, path: string, a: Added) {
  if (!a.lines.some(l => l.includes(':/'))) {
    return []
  }
  const run = await $.process.run(['hx-nu', '--commands', `nu-hx check-links r#'${path}'# | to json`]).catch(() => undefined)
  if (!run || run.exitCode !== 0) {
    return []
  }
  const rows = JSON.parse(run.stdout) as { link: string; error: string }[]
  return rows
    .filter(r => a.lines.some(l => l.includes(r.link)))
    .map(r => `${a.file}: the jump refuses \`${r.link}\` (${r.error})`)
}

function dirOf(path: string) {
  return path.slice(0, path.lastIndexOf('/'))
}

function cut(line: string) {
  const text = line.trim()
  return text.length > 80 ? `${text.slice(0, 80)}…` : text
}
