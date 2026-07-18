---
name: jj-commit
description: >
  Create a jj (Jujutsu) commit. Use only when the user explicitly asks for a
  jj commit — git is the default workflow. Trigger on "jj commit",
  "commit with jj", "/jj-commit".
version: 0.1.0
allowed-tools: Bash(jj status:*), Bash(jj commit:*), Bash(jj diff:*), Bash(jj describe:*), Bash(jj squash:*), Bash(jj new:*), Bash(jj log:*), Bash(jj file list:*), Bash(jj file track:*), Bash(jj file untrack:*), Bash(jj metaedit:*)
---

# jj commit

## Context

Gather context first:

- Current jj status: `jj status`
- Change summary: `jj diff --stat`
- Recent commits: `jj log --limit 5`

## Task

Commit only files created, edited, or deleted in this session. Skip pre-existing changes in `jj status`.

Group unrelated changes into separate commits. For unrelated changes within a single file, use the jj-split-file-for-commit skill on that file.

Commit pattern — always use:
```bash
jj commit <files> -m 'message' && jj metaedit @- --update-author
```

Never use interactive commands (`jj split`, `jj squash -i`). Always specify `-m` flag.

Use conventional commits format: feat | fix | change | remove | refactor | docs | test | chore
Breaking changes: add '!' after type (e.g., `feat!: change API format`)
