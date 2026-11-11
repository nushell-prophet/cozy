import type { Hook } from 'claude-code'

type Api = Parameters<Hook<'classic.Stop'>>[0]

// The review of a turn at its end, on with `gi open --review` (GI_REVIEW), in
// two halves. The first: the rules of the Canvas style that a command can
// check, run over the lines the agent's commits of this turn added to the
// canvas and its sibling files. The second is the reviewer below.
// Why: a rule in prose is loaded and still not followed, and a check that the
// agent has to remember to run is one more such rule.
// Why only the lines of this turn: a finding the agent answered must not come
// back at every later turn end, and `check-links` also lists a syntax example.
// Why advice and never a failure: a check cannot read the context, so a finding
// may be wrong; every finding says "check", and an error here is silence —
// unlike the floor, whose failure blocks.

// The caps of "Save his reading budget" in the style: change both together.
const MAX_AA_LINES = 3
const MAX_OPEN_QUESTIONS = 3

const LIST_ITEM = /^\s*([-*]|\d+\.) /
const MARKER = /^\s*(AA:|\?\?\?|!!!|%%%)/

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
place: did the agent append an answer where an \`AA:\` entry had to be rewritten in place, or put a remark away from the words it is about?
carry: did the user type canvas work in the chat — not a \`chat:\` aside, a slash command, a \`go\` or a \`!\` command — that the agent did not carry into the canvas in his words?

If every answer is no, reply with the two letters OK and nothing else. Otherwise write one line per finding, at most five lines: \`<question>: <what is wrong, and where — the file and the words>\`. Report only what you can point at in this conversation; when you are not sure, leave it out. Leave out a finding that was raised earlier in this conversation and answered.`

// The findings of the checks and of the reviewer as one block of advice;
// undefined when the turn made no commit, when nothing is found, and on any failure.
export async function reviewReason($: Api, canvas: string, base: string | undefined, answer: string | undefined) {
  try {
    const email = base && (await agentCommitted($, canvas, base))
    if (!base || !email) {
      return undefined
    }
    // Each half fails alone: a reviewer the API refused leaves the checks standing.
    const [checks, reviewer] = await Promise.all([
      checkFindings($, canvas, base, email).catch(() => [] as string[]),
      reviewerFindings($, answer).catch(() => undefined),
    ])
    const parts = [checks.length ? `checks:\n${checks.map(f => `- ${f}`).join('\n')}` : undefined, reviewer ? `reviewer:\n${reviewer}` : undefined].filter(p => p !== undefined)
    return parts.length
      ? `gi review — advice on this turn, not an order: the checks read only the lines the turn added, and the reviewer has no tools. Check each line: fix what is right, in the canvas as usual; where a finding is wrong, change nothing and say so in your one chat line.\n\n${parts.join('\n\n')}`
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
  const findings = family.flatMap(a => [...unlinkedItems(a), ...longEntries(a)])
  const questions = family.flatMap(a => a.lines).filter(l => /^\s*\?\?\?/.test(l)).length
  if (questions > MAX_OPEN_QUESTIONS) {
    findings.push(`${questions} new \`???\` in one turn; the cap is ${MAX_OPEN_QUESTIONS}, the rest wait`)
  }
  for (const a of family) {
    findings.push(...(await refusedLinks($, `${dir}/${a.file}`, a)))
  }
  const text = (await $.fs.read(canvas)) as string
  for (const a of added) {
    if (a.isNew && a.file !== name && !text.includes(a.file)) {
      findings.push(`${a.file}: a new file beside the canvas that the canvas does not name in \`related_files\``)
    }
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

// "Save his reading budget": an `AA:` entry is one to three lines; its list
// lines do not count.
export function longEntries(a: Added) {
  const findings: string[] = []
  let first: string | undefined
  let count = 0
  const close = () => {
    if (first !== undefined && count > MAX_AA_LINES) {
      findings.push(`${a.file}: an \`AA:\` entry of ${count} lines, the cap is ${MAX_AA_LINES}: "${cut(first)}"`)
    }
    first = undefined
  }
  for (const line of a.lines) {
    if (/^\s*AA:/.test(line)) {
      close()
      first = line
      count = 1
    } else if (!line.trim() || MARKER.test(line)) {
      close()
    } else if (first !== undefined && !LIST_ITEM.test(line)) {
      count += 1
    }
  }
  close()
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
