---
name: jj-ai-guide
description: Guide for working with Jujutsu (jj) version control system. Use when the user is working in a jj repository, asks about jj commands, or needs help with version control operations in a jj-based project. Covers commands, revsets, filesets, templates, conflicts, and AI-safe workflows.
allowed-tools: Bash, Read, Grep, Glob
---

# Jujutsu (jj) Guide for AI Agents

## Critical Warnings

### Author Attribution

In jj, the working copy is always a commit. When a user works in their shell, jj creates the working copy with **their** identity. By the time an AI agent runs `jj commit`, the author is already set to the user.

**Solution:** After committing, run `jj metaedit @- --update-author` to update the author to the configured user (from `JJ_CONFIG` env var).

```bash
# Pattern: commit, then fix author on the just-committed change (@-)
jj commit <files> -m 'message' && jj metaedit @- --update-author
```

Why this approach:
- Author is managed in config, not hardcoded in commands
- `--update-author` reads from `user.name`/`user.email` in config
- Avoids deprecated `jj commit --author` flag

### File Untracking

**DO NOT USE `jj abandon` TO REMOVE FILES FROM VERSION CONTROL!**
- `jj abandon` DELETES THE ENTIRE COMMIT
- Use `jj file untrack <file>` to remove files from tracking (keeps them on disk)

**Correct workflow:**
```bash
echo "secrets.env" >> .gitignore    # First, prevent re-tracking
jj file untrack secrets.env          # Then remove from version control
jj commit -m "Remove secrets.env from tracking" && jj metaedit @- --update-author
```

### Interactive Commands (WILL FAIL in automation)

**AVOID these commands:**
- `jj split` (without specific files)
- `jj squash -i`
- `jj diffedit`
- `jj rebase -i`
- `jj resolve`

**Use these AI-safe alternatives:**
- `jj split <files>` - Split specific files into new commit
- `jj squash` or `jj squash <files>` - Move changes without interaction
- `jj edit <commit>` then modify and `jj squash`
- `jj rebase -s <source> -d <dest>` - Specific revisions
- Edit conflict markers in files directly

## Core Conceptual Differences from Git

| Concept | Git | jj |
|---------|-----|-----|
| Working copy | Separate from commits | Always a commit (auto-committed) |
| Staging | Three-tree (working, index, HEAD) | Two-tree (working copy, repository) |
| Identity | Commit IDs only | Both Change IDs (stable) and Commit IDs |
| Authorship | `--amend` changes committer | Rewrite operations preserve original author |
| Branches | Current branch moves with commits | Bookmarks don't move automatically |
| Conflicts | Block operations | Can be committed and resolved later |
| Rebasing | Manual for dependents | Automatic for all descendants |

## Essential Commands

```bash
# Repository
jj git init [--colocate]      # Initialize
jj git clone <url>            # Clone
jj st                         # Status
jj diff                       # Show changes
jj log                        # History graph

# Working with changes
jj commit -m "msg" && jj metaedit @- --update-author  # Create commit (AI agents)
jj describe -m "msg"          # Update description (preserves author)
jj new <rev>                  # Create new commit on revision
jj edit <rev>                 # Edit existing commit
jj squash                     # Move changes to parent
jj squash <files>             # Move specific files to parent
jj abandon                    # Delete current commit

# Navigation
jj next                       # Move to child commit
jj prev                       # Move to parent commit

# Bookmarks (branches)
jj bookmark create <name>     # Create at current revision
jj bookmark move <name> --to <rev>  # Move bookmark
jj bookmark track <name> --remote=<remote>  # Track remote

# Remote operations
jj git fetch                  # Fetch from remotes
jj git push                   # Push to remote

# Recovery
jj undo                       # Undo last operation
jj op log                     # View operation history
jj op restore <id>            # Restore to operation state

# Reverting commits (like git revert)
jj revert -r <rev> --insert-after @  # Create reverse commit after current
jj revert -r <rev> --insert-before @ # Create reverse commit before current
jj revert -r <rev> --onto <dest>     # Create reverse commit at destination

# Restoring paths
jj restore <paths>            # Restore paths from parent (undo changes)
jj restore --from <rev>       # Restore paths from specific revision
jj restore --from <rev> --into <dest>  # Restore into specific revision

# History inspection
jj evolog                     # Show how current change evolved
jj file annotate <path>       # Blame: show who changed each line

# Smart change distribution
jj absorb                     # Auto-move changes to appropriate ancestors
```

## Revsets Quick Reference

Revsets query commits. See [REFERENCE.md](REFERENCE.md) for complete documentation.

```bash
# Basic symbols
@                             # Current working copy
@-                            # Parent of working copy
::@                           # All ancestors of @
@::                           # All descendants of @

# Common functions
mine()                        # Your commits
conflicts()                   # Commits with conflicts
empty()                       # Empty commits
bookmarks()                   # Commits with bookmarks
trunk()                       # Main branch head

# Content queries
description("text")           # Match description
author("email")               # Match author
files("path/")                # Commits touching files
diff_contains("text")         # Content changes

# Combining
conflicts() & mine()          # My commits with conflicts
heads() & ~bookmarks()        # Anonymous heads
```

## Filesets Quick Reference

Filesets select files. See [FILESETS.md](FILESETS.md) for complete documentation.

```bash
# Patterns
"src/"                        # All files under src/
"*.py"                        # Python files
'glob:"**/*.rs"'              # Recursive glob
'file:"exact.txt"'            # Exact file match
'regex:"test.*\.py"'          # Regex pattern

# Case-insensitive (append -i)
'glob-i:"*.TXT"'              # Matches .txt, .TXT, etc.

# Operators
"src/ | tests/"               # Union (OR)
'src/ & glob:"*.py"'          # Intersection (AND)
'src/ ~ glob:"*test*"'        # Difference (EXCEPT)
'~glob:"*.tmp"'               # Negation (NOT)
```

## Templates Quick Reference

Templates format output. See [TEMPLATES.md](TEMPLATES.md) for complete documentation.

```bash
# Structured output
jj log --template='commit_id.short() ++ " " ++ description.first_line()'

# JSON-like format
jj log --template='{
  "id": commit_id.short(),
  "message": description.first_line(),
  "author": author.email()
}'

# String methods
description.first_line()      # First line
description.upper()           # Uppercase
description.contains("fix")   # Substring check
```

## Conflict Resolution

jj stores conflicts in commits (never blocks operations). See [CONFLICTS.md](CONFLICTS.md) for details.

### Marker Format (diff style, default)
```
<<<<<<< conflict 1 of 1
%%%%%%% diff from: vpxusssl "merge base"
\\\\\\\        to: rtsqusxu "commit A"
 apple
-grape
+grapefruit
 orange
+++++++ ysrnknol "commit B"
APPLE
GRAPE
ORANGE
>>>>>>> conflict 1 of 1 ends
```

### Resolution workflow
```bash
jj new <conflicted_commit>    # Create working copy on conflict
# Edit files to resolve
jj squash                     # Merge resolution into conflicted commit
```

## AI Agent Workflow Pattern

```bash
jj st                         # 1. Check status first
jj new <base_commit>          # 2. Create new working commit
# Edit files directly          # 3. Make changes
jj describe -m "message"      # 4. Set description
jj squash <specific_files>    # 5. Move specific files if needed
jj metaedit --update-author   # 6. Fix author attribution
jj bookmark create <name>     # 7. Create bookmark if needed
jj log                        # 8. Verify results
```

## Key Principles

1. **Never use interactive commands** - They hang in automation
2. **Specify files explicitly** - Use `jj squash <files>` not `jj squash -i`
3. **Use change IDs** - They're stable across rewrites
4. **Leverage operation log** - `jj undo` and `jj op restore` for recovery
5. **Edit conflicts directly** - Parse markers programmatically
6. **Bookmarks don't auto-move** - Must update manually after commits

## Additional Resources

- [REFERENCE.md](REFERENCE.md) - Complete command and revset reference
- [TEMPLATES.md](TEMPLATES.md) - Template system details
- [FILESETS.md](FILESETS.md) - Fileset patterns and operators
- [CONFIGURATION.md](CONFIGURATION.md) - Full configuration reference
- [CONFLICTS.md](CONFLICTS.md) - Conflict resolution details
- [WORKFLOWS.md](WORKFLOWS.md) - AI agent automation scripts
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Error handling and recovery
