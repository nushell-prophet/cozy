# Troubleshooting and Error Handling

## Common Error Categories

### 1. Immutable Commit Errors

```bash
# Error: "Commit X is immutable"
# Solution: Use --ignore-immutable or work with descendants

# Check if commit is immutable
jj log -r 'immutable() & <revision>'

# Work around
jj rebase -d <new_dest> -s <source> --ignore-immutable
jj duplicate <immutable_commit> -d <new_dest>  # Create copy instead
```

### 2. Divergent Change Errors

```bash
# Error: "Change X has diverged"
# Solution: Resolve divergence explicitly

# Find divergent changes
jj log -r 'divergent()'

# Resolve by abandoning one
jj abandon <unwanted_commit_id>

# Or merge divergent changes
jj new <divergent_commit1> <divergent_commit2>
```

### 3. Empty Commit Handling

```bash
# jj allows empty commits by default

# Find empty commits
jj log -r 'empty()'

# Remove empty commits
jj abandon 'empty() & mine()'

# Check if creating empty commit
check_empty() {
  jj log -r '@' --template='empty' | grep -q 'true' && echo "Warning: Empty commit"
}
```

### 4. Bookmark Conflicts

```bash
# Error: "Bookmark X is conflicted"
# Solution: Resolve manually

# Find conflicted bookmarks
jj bookmark list | grep -E '\?\?\?'

# Resolve by choosing one side
jj bookmark move <name> --to <chosen_commit>

# Or create new and delete conflicted
jj bookmark create <new_name> -r <commit>
jj bookmark delete <conflicted_name>
```

### 5. Large Repository Issues

```bash
# Error: "Revset evaluation too expensive"
# Solution: Use more specific revsets

# Instead of
jj log -r 'all()'

# Use
jj log -r '::@ | @::'  # Ancestors and descendants only
jj log -r 'mine() & author_date(after:"1 week ago")'
jj log -r 'all()' --limit 100
```

### 6. Push/Pull Errors

```bash
# Error: "No such remote bookmark"
# Solution: Check remote configuration

jj git remote list
jj bookmark track <bookmark>@<remote>
jj git fetch --all-remotes  # Test connectivity
```

## Debugging Environment

```bash
debug_environment() {
  echo "=== Environment Check ==="
  echo "jj version: $(jj --version)"
  echo "Git version: $(git --version 2>/dev/null || echo 'Not installed')"
  echo "Working directory: $(pwd)"
  echo "Repository root: $(jj workspace root 2>/dev/null || echo 'Not in repo')"
  echo "User: $(jj config get user.name 2>/dev/null || echo 'Not configured')"
  echo "Email: $(jj config get user.email 2>/dev/null || echo 'Not configured')"
}
```

## Repository Health Check

```bash
check_repo_health() {
  echo "=== Repository Health Check ==="
  local issues=0

  # Conflicts
  local conflicts=$(jj log -r 'conflicts()' --template='commit_id' | wc -l)
  [ "$conflicts" -gt 0 ] && {
    echo "WARNING: $conflicts commits have conflicts"
    ((issues++))
  }

  # Divergent changes
  local divergent=$(jj log -r 'divergent()' --template='commit_id' | wc -l)
  [ "$divergent" -gt 0 ] && {
    echo "WARNING: $divergent divergent changes"
    ((issues++))
  }

  # Empty commits
  local empty=$(jj log -r 'empty() & mine()' --template='commit_id' | wc -l)
  [ "$empty" -gt 0 ] && echo "INFO: $empty empty commits"

  # Working copy warnings
  jj st 2>&1 | grep -q "Warning:" && {
    echo "WARNING: Working copy has warnings"
    jj st 2>&1 | grep "Warning:"
    ((issues++))
  }

  echo "=== Health Check Complete: $issues issues ==="
  return $issues
}
```

## Operation Log Debugging

```bash
audit_operations() {
  echo "=== Recent Operations ==="

  jj op log --limit 10 --template='
  operation.id ++ " " ++
  operation.user ++ " " ++
  operation.description'
}

# See state at specific operation
jj log --at-op=<operation_id>
jj status --at-op=<operation_id>
jj bookmark list --at-op=<operation_id>
```

## Recovery Strategies

### Reverting Commits vs Operations

**IMPORTANT:** jj has TWO different revert commands:

1. **`jj revert`** - Reverts a COMMIT (like `git revert`)
2. **`jj op revert`** - Reverts an OPERATION (unique to jj)

```bash
# Revert a COMMIT (create reverse changes)
jj revert -r <commit> --insert-before @    # Most common: revert commit, place before @
jj revert -r <commit> --insert-after @     # Place after current working copy
jj revert -r <commit> --onto main          # Place on top of main

# NOTE: jj revert REQUIRES a destination flag!
# This will ERROR: jj revert -r abc123
# This works:      jj revert -r abc123 -B @
```

### Operation Recovery: undo vs op revert vs op restore

```bash
# undo: Undoes last operation (creates new operation)
jj undo

# op revert: Creates inverse of specific operation (preserves history)
jj op revert <operation_id>

# op restore: Resets to exact state at operation (loses subsequent changes)
jj op restore <operation_id>

# Selective recovery
jj op restore <id> --what=repo          # Only repository state
jj op restore <id> --what=working-copy  # Only working copy
```

### Full Recovery

```bash
full_recovery() {
  echo "=== Starting Full Recovery ==="

  # Create backup
  local backup="/tmp/jj_backup_$(date +%s)"
  cp -r .jj "$backup"
  echo "Backup: $backup"

  # Find last good operation
  local good_op=$(jj op log --limit 20 --template='
  if(operation.type == "error", "", operation.id)
  ' | grep -v "^$" | head -1)

  if [ -n "$good_op" ]; then
    echo "Restoring to: $good_op"
    jj op restore "$good_op"
  else
    echo "No good operation found"
    return 1
  fi
}
```

### Selective Recovery

```bash
selective_recovery() {
  local component="$1"  # bookmarks, working-copy, commits

  case "$component" in
    bookmarks)
      jj bookmark list --all
      jj git fetch --all-remotes
      ;;
    working-copy)
      jj workspace update-stale
      jj new @
      ;;
    commits)
      jj log -r 'all()' --limit 20
      ;;
  esac
}
```

## Error Recovery Patterns

```bash
recover_from_error() {
  local error_type="$1"

  case "$error_type" in
    "immutable")
      jj rebase --ignore-immutable "${@:2}"
      ;;
    "divergent")
      jj abandon "$(jj log -r 'divergent()' --template='commit_id' | head -1)"
      ;;
    "conflicts")
      # Apply automated resolution
      ;;
    *)
      echo "Unknown error: $error_type"
      return 1
      ;;
  esac
}
```

## Performance Optimization

```bash
optimize_performance() {
  # Enable filesystem monitoring
  jj config set core.fsmonitor true

  # Enable watchman if available
  command -v watchman >/dev/null && jj config set core.watchman true

  # Disable colors for automation
  jj config set ui.color never

  # Disable pager
  jj config set ui.paginate never
}

# Revset optimization tips
# Good:
jj log -r '::@' --limit 50
jj log -r 'mine() & author_date(after:"1 week ago")'
jj log -r 'bookmarks()'

# Avoid:
jj log -r 'all()'  # without limit
jj log -r 'ancestors(all())'
```

## Working Copy Issues

```bash
# Stale working copy
jj workspace update-stale

# Create new working copy commit
jj new @

# Check working copy status
jj debug working-copy
jj file list
```

## Checkpoint Pattern

```bash
create_checkpoint() {
  local id=$(jj op log --limit 1 --template='operation.id')
  echo "$id" > .jj_checkpoint
  echo "Checkpoint: $id"
}

restore_checkpoint() {
  local id=$(cat .jj_checkpoint 2>/dev/null)
  [ -n "$id" ] && jj op restore "$id"
}
```

## Common Gotchas

1. **Bookmarks don't move** - Must manually update after commits
2. **Empty commits allowed** - Working copy can be empty
3. **No detached HEAD** - Always on a commit
4. **Automatic file tracking** - New files tracked automatically
5. **Root commit exists** - Virtual commit at `root()`
6. **Interactive commands fail** - Hang in automation
7. **Conflict markers differ** - Not Git's `<<<<<<<` format
8. **`jj revert` needs destination** - MUST use `--insert-before`, `--insert-after`, or `--onto`
9. **Two kinds of revert** - `jj revert` (commits) vs `jj op revert` (operations)
