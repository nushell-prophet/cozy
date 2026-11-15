import type { Hook } from 'claude-code'

type Api = Parameters<Hook<'classic.Stop'>>[0]

// The signal that the user rewrote the history of the branch by hand — a
// rebase, a split, a dropped hunk in lazygit — printed to the agent with the
// commits that changed. A rewrite the agent made itself is no news to it.
// Why: how the user cuts the commits is a statement to the agent, and nothing
// else carries it. The sent ref of `nu-hx unsent` (dotfiles) remembers the text
// of a file, not a commit, so a split that ends on the same text gives no
// unsent commit; and the agent does not compare hashes by itself.
// Why printed and not a command to run: the agent cannot skip or narrow what
// is already in its context, and it saves a step.

// Above this many characters the commits are named by the command that prints
// them: a block of that size pushes the rest of the turn out of view.
const MAX_PRINTED = 20000

export type Seen = { head: string; branch: string }

// Where the repo of the canvas stands: the commit and the branch. Undefined
// outside a repo and on a detached HEAD, where there is no branch to follow:
// git names that branch `HEAD`.
export async function standsOn($: Api, canvas: string): Promise<Seen | undefined> {
  const { exitCode, stdout } = await gitIn($, canvas)('rev-parse', 'HEAD', '--abbrev-ref', 'HEAD')
  const [head, branch] = stdout.trim().split('\n')
  return exitCode === 0 && head && branch && branch !== 'HEAD' ? { head, branch } : undefined
}

// The commit the agent last stood on in a branch, as a ref of the repo:
// `refs/gi/seen/<the canvas path, made a ref name>/<branch>`.
// Why a ref and not a variable of the module: the engine loads the module again
// when a file of the plugin changes, and a rebase that touches the plugin does
// that, so a variable is lost exactly when it is needed; a ref also holds
// over a restart of Claude Code, and it keeps the old commit from the garbage
// collector, so the two sides can still be compared.
// Why the canvas in the name: two sessions on one branch, each with its canvas,
// must not take the news from each other.
function seenRef(canvas: string, branch: string) {
  return `refs/gi/seen/${canvas.replace(/[^\w-]+/g, '-').replace(/^-+|-+$/g, '')}/${branch}`
}

export async function lastSeen($: Api, canvas: string, now: Seen) {
  const { exitCode, stdout } = await gitIn($, canvas)('rev-parse', '--verify', '--quiet', seenRef(canvas, now.branch))
  return exitCode === 0 ? stdout.trim() : undefined
}

export async function remember($: Api, canvas: string, now: Seen) {
  await gitIn($, canvas)('update-ref', seenRef(canvas, now.branch), now.head)
}

// The flags that make `git log --patch` print the same on every machine.
// Why `--no-relative`: git runs in the folder of the canvas, and with
// `diff.relative` set a commit outside that folder prints with no diff at all.
const PATCH = ['--patch', '--no-relative', '--no-color', '--no-ext-diff', '--default-prefix']

// What the agent is told when `old`, the commit it last stood on in this
// branch, is no longer under `now`; undefined when the history only grew, or
// was rewritten with every patch kept.
// Why `--cherry-pick`: a rebase onto the trunk gives every commit a new hash
// and the same patch, and such a commit is no news; the split or edited one
// has no equal patch on the other side, so it is what stays.
// Why `^<trunk>` on the new side only: the commits a rebase brought in from
// the trunk are not the user's rewrite; on the old side they have to stay in
// the comparison, so that a commit the trunk took by cherry-pick is not gone.
// Why the `origin/` trunk too: the local trunk may be behind the one the
// branch was rebased onto.
// Why `--no-merges`: a merge has no patch to compare, so it would always be
// named as gone.
export async function rewrittenReason($: Api, canvas: string, old: string | undefined, now: Seen, trunks: string[]) {
  if (!old || old === now.head) {
    return undefined
  }
  const git = gitIn($, canvas)
  if ((await git('merge-base', '--is-ancestor', old, now.head)).exitCode === 0) {
    return undefined
  }
  const not: string[] = []
  for (const ref of trunks.filter(t => t !== now.branch).flatMap(t => [`refs/heads/${t}`, `refs/remotes/origin/${t}`])) {
    if ((await git('rev-parse', '--verify', '--quiet', ref)).exitCode === 0) {
      not.push(`^${ref}`)
    }
  }
  const whose = await rewrittenBy($, canvas, old, now)
  if (whose === 'agent') {
    return undefined
  }
  const range = `${old}...${now.head}`
  const who = whose === 'user'
    ? `was rewritten, and not by this session: the reflog of the branch names another identity for the step. \`${old.slice(0, 9)}\`, the commit you last stood on, is no longer under HEAD. The user may have split, edited or dropped commits by hand`
    : `was rewritten, by this session or by the user: the reflog of the branch cannot tell whose step it was. \`${old.slice(0, 9)}\`, the commit you last stood on, is no longer under HEAD. If the rewrite is your own, this is no news; if not, the user may have split, edited or dropped commits by hand`
  const opening = `The history of \`${now.branch}\` ${who}, and how he cut them is a statement to you. Read what follows before you act, bring your model of the work and the canvas up to date, and report it in the canvas as the Canvas style says.`
  const gone = await git('log', '--no-merges', '--format=%h %s', '--cherry-pick', '--left-only', range)
  const fresh = ['log', '--reverse', '--no-merges', ...PATCH, '--format=%h %s%n%b', '--cherry-pick', '--right-only', range, ...not]
  const printed = await git(...fresh)
  // Why not silence: a commit that git no longer holds is a rewrite all the same.
  if (gone.exitCode !== 0 || printed.exitCode !== 0) {
    return `${opening}\n\ngit could not list what changed (${(gone.stderr || printed.stderr).trim().split('\n')[0]}): read the branch again from where it leaves the trunk.`
  }
  const left = gone.stdout.trim()
  const right = printed.stdout.trim()
  if (!left && !right) {
    return undefined
  }
  const added = !right
    ? 'No commit is new.'
    : right.length > MAX_PRINTED
      ? `The commits that are new are too long to print here: run \`${['git', '-C', dirOf(canvas), ...fresh].map(quoted).join(' ')}\`.`
      : `The commits that are new:\n\n${right}`
  return `${opening} A commit next to an edited one can stand on both lists with no change of its own: its patch holds the lines around it.\n\n${left ? `The commits that are gone, with no commit of the same patch left:\n\n${left}` : 'No commit is gone.'}\n\n${added}`
}

// Who moved the branch off `old`: the reflog of the branch records, for each
// step, the committer identity that made it, and the agent has its own (`git
// var GIT_COMMITTER_IDENT` in this process). A step is a rewrite when the
// commit before it is not under the commit after it.
// Why the reflog and not the author of the new commits: a rebase or a split
// keeps the author, and a dropped commit leaves no new commit to read.
// Why the reflog of the branch and not of HEAD: HEAD also records every
// switch, and a switch away and back is such a step with no rewrite in it.
// 'unknown' when the agent commits under the identity of the repo's user, or
// when the reflog no longer holds `old`.
async function rewrittenBy($: Api, canvas: string, old: string, now: Seen): Promise<'user' | 'agent' | 'unknown'> {
  const git = gitIn($, canvas)
  const agent = /<([^>]*)>/.exec((await git('var', 'GIT_COMMITTER_IDENT')).stdout)?.[1]
  const user = (await git('config', 'user.email')).stdout.trim()
  const steps = (await git('log', '--walk-reflogs', '--format=%H %ge', `refs/heads/${now.branch}`)).stdout
    .trim().split('\n').map(line => { const [to = '', by = ''] = line.split(' '); return { to, by } })
  const last = steps.findIndex(step => step.to === old)
  if (!agent || agent === user || last === -1) {
    return 'unknown'
  }
  for (const [i, step] of steps.slice(0, last).entries()) {
    const before = steps[i + 1]
    if (step.by !== agent && before && (await git('merge-base', '--is-ancestor', before.to, step.to)).exitCode !== 0) {
      return 'user'
    }
  }
  return 'agent'
}

// An argument as bash takes it.
function quoted(arg: string) {
  return /^[\w@+=:,.\/-]+$/.test(arg) ? arg : `'${arg.replaceAll("'", `'\\''`)}'`
}

function gitIn($: Api, canvas: string) {
  return (...args: string[]) => $.process.run(['git', '-C', dirOf(canvas), ...args])
}

function dirOf(path: string) {
  return path.slice(0, path.lastIndexOf('/'))
}
