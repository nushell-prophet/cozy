---
name: jj-improve-history
description: >
  Improve jj (Jujutsu) commit messages while preserving original authorship.
  Use only when the user explicitly asks — git is the default workflow.
  Trigger on "improve jj history", "rewrite jj messages", "/jj-improve-history".
  Optional argument: base revision to compare against (default: main).
version: 0.1.0
allowed-tools: Bash(jj:*), Read, Edit
---

# jj improve history

## Arguments

- `base-revision` (optional): Base revision to compare against (default: main). Referred to as `<base>` below.

## Context

Gather context first:

- Current revision: `jj log -r @ --no-graph --template 'change_id.short() ++ " " ++ description.first_line()'`
- Working copy clean or not: `jj diff --stat`

## Task

Review and improve commit messages in range `<base>..@-`.

List commits with their current messages:
```bash
jj log -r "<base>..@-" --template '
change_id.short() ++ " by " ++ author.name() ++ "\n" ++
"  " ++ description.first_line() ++ "\n"
'
```

For each commit needing improvement, read its diff to understand the change, then:
```bash
jj describe <change_id> -m "type: improved message"
```

`jj describe` preserves original authorship automatically.

Use conventional commits format: feat | fix | change | remove | refactor | docs | test | chore
Focus on capturing WHY the change was made, not just what changed.
