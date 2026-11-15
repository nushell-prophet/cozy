---
name: 40-change-id
description: >
  Reference for names of commits and files that survive a history rewrite: the
  `Change-Id` and `Session` trailers that a `commit-msg` hook stamps, change-id
  links to a file in another repo, and git notes that correct an old commit
  message. Use this skill before a commit is named in a note, a report or a
  commit body; before the message of a commit is corrected; when the user asks
  "which session made this commit", "which branch was that", "when was this
  change made", "fix the message of an old commit", "link this file from the
  other repo", "какая сессия сделала этот коммит", "поправь сообщение старого
  коммита", "дай ссылку на файл в другом репо"; or when a reference by sha no
  longer resolves.
version: 0.1.0
---

# Names that survive a rewrite: `Change-Id`, `Session`, links, notes

A repo that rewrites history often — amend, rebase, squash — loses a sha with each rewrite.
This is the reference for the names that hold through a rewrite, and for the two ways to correct a commit message.
The hooks and the `cozy git` commands come from [cozy](https://github.com/nushell-prophet/cozy), which loads the commands in every interactive nu.
In a repo without the hooks, a commit has no trailers, and its name is its sha.

## A commit is named by its `Change-Id` where it has one, by sha otherwise

A sha dies with each rewrite, while the `Change-Id: <32 reverse-hex letters>` trailer travels inside the message.
So a reference to a commit, in a note or a report, is the first 8 letters of the trailer when the commit carries one.
`git log -1 --format='%(trailers:key=Change-Id,valueonly)'` reads it, and `git log --all --grep='^Change-Id: <id>'` finds it again.

The last 8 letters are the unix time the id was minted, in the same alphabet, so an id also dates a change even after a rebase moved the commit's own date.
`printf '%s' <id> | cut --characters 25-32 | tr 'zyxwvutsrqponmlk' '0123456789abcdef'` gives the hex seconds.

The trailer is stamped by a `commit-msg` hook, and only repos that have it carry ids.
`cozy git install-change-id-hook <repo>` installs it once per clone, into the common `.git/hooks`, so worktrees share it.
It installs two more hooks with it: an `applypatch-msg` hook that stamps commits applied by `git am`, and a `prepare-commit-msg` hook that names a reverted change by its id in `git revert`.
Repos that cannot have it (an upstream clone such as Nushell) stay on shas — so the fallback is the sha, not a guess.
Nothing warns about a missing hook; `ls "$(git rev-parse --git-common-dir)/hooks/commit-msg"` is the check.

## A commit names the session that wrote it in a `Session:` trailer

The same `commit-msg` hook stamps it from `CLAUDE_CODE_SESSION_ID`, so a commit made outside Claude Code has none.
An amend or a rebase that keeps the message keeps the session, and a new message names the new one.

- `git log -1 --format='%(trailers:key=Session,valueonly)' <sha>` names the session of a commit.
- `git log --all --grep='^Session: <uuid>'` lists the commits of a session.
- `git branch --contains <sha>` gives their branches.

Ask git this before you mine transcripts for which session or which branch did something.
Why: a search for "the branch we made skills in, from this work" took minutes over branch graphs, and a `Session:` trailer that two branches shared answered it in seconds.

## A file in another repo is named by a change-id link

The form is `<repo>@<change-id>:<path in repo>`: git's own `<rev>:<path>` with the repo in front, so the reader knows where to run git and what to show.
When work spans repos, the commit body and the note name the files on the other side this way.

- `cozy git link <file>` writes one.
  It names the commit that last touched the file, so the link survives the rewrites that move a sha.
  It refuses a file with uncommitted changes, since a link names committed content.
- `cozy git resolve <link>` prints the file at that commit; a prefix of the id works.
- A commit without an id gets its sha in the same slot: hex is a sha, letters `k`-`z` are an id.
- In the helix config of cozy, `+ t` copies the selection as `<selected-text link="…" lines="a-b">`; `+ s` stays for a path inside the same repo.

So a reference in a todo or a commit body is a change-id link, or a path plus a quote — never a bare sha, which the next rebase orphans.
Why: repos that change together but do not share a history make a plain path name a file that has already moved on; the link names the state the writer saw and still resolves after.

## An old commit message is corrected with a git note, never by rewriting history

`git notes edit <sha>` writes it; `git log` shows it indented under the message, and `git log -p refs/notes/commits` shows every correction as a diff.
A custom `--format` hides notes unless it has `%N`, so read a commit you are about to act on without one.
Notes stay local: `git push` does not send `refs/notes/*`, and none is set up to, so a fresh clone and the remote never see a correction.
Don't push them.
Why: the user wants to fix the messages of old commits and see the diff of each fix, with default git functionality instead of a tool of our own.

"Old" means something depends on the sha: the commit is pushed, or a trailer, a note or a file names it.
A commit that is only on a local branch, with nothing naming its sha, is rewritten instead — `commit --amend`, or a `rebase` fixup when later commits sit on it; its `Change-Id` survives.
Why: a note on such a commit keeps a false sentence in the history for no reader who relies on it.
The maintainer: "if the commit was recent and nothing relies on this sha, we can amend, if that is better."

### Reword a commit without an editor, and keep its id

```bash
git commit --allow-empty --message 'amend! <sha>' --message '<new message>'
GIT_SEQUENCE_EDITOR=true git rebase --interactive --autosquash <sha>~1
```

`--fixup=reword:` refuses `--message` and opens an editor.
Name the target by its sha, not its subject: the `commit-msg` hook copies the `Change-Id` only from a commit named by sha, and `amend! <subject>` gets a fresh id that the rebase puts on the target.
