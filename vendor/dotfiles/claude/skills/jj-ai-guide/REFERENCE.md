# Command and Revset Reference

## Command Mapping: Git to jj

### Repository Operations
```bash
git init                     → jj git init [--colocate]
git clone <url>             → jj git clone <url>
git status                  → jj st
git diff                    → jj diff
git diff HEAD               → jj diff
git diff <rev>^ <rev>       → jj diff -r <rev>
git log --oneline --graph   → jj log
```

### Working with Changes
```bash
git add <file>              → (automatic in jj)
git commit -m "msg"         → jj commit -m "msg"
git commit --amend          → jj describe / jj squash
git checkout <commit>       → jj edit <commit>
git switch -c new main      → jj new main
git reset --hard            → jj abandon
git reset --soft HEAD~      → jj squash --from @-
```

### Advanced Operations
```bash
git add -p; git commit --amend → jj squash <files>
git rebase <branch>         → jj rebase -s <source> -d <dest>
git cherry-pick             → jj duplicate -d <dest>
git reflog; git reset       → jj op log; jj undo
git revert <rev>            → jj revert -r <rev> --insert-before @
git restore <path>          → jj restore <path>
git blame <file>            → jj file annotate <file>
```

## Content Movement Commands (AI-Safe)

```bash
jj split <files>            # Split specific files into new commit
jj squash                   # Move entire change to parent
jj squash <files>           # Move specific files to parent
jj squash --from <commit>   # Move changes from specific commit
jj squash --into <commit>   # Move changes to specific commit
```

## Complete Revset Reference

### Symbol Priority Resolution
When a symbol could match multiple types, jj resolves in order:
1. Tag name
2. Bookmark name
3. Git ref
4. Commit ID or change ID

Use explicit functions: `commit_id(abc)`, `bookmarks("main")`, `tags("v1.0")`

### Content-Based Queries
```bash
# Description patterns
description(glob:"*fix*")           # Contains "fix"
description(regex:"^(feat|fix):")   # Conventional commits
description(exact:"Initial commit") # Exact match
subject(glob:"fix:*")               # First line only

# Author/committer
author("bot@company.com")           # Specific author
author(glob:"*bot*")               # Pattern matching
mine()                             # Your commits
author_date(after:"2024-01-01")    # Date filtering
committer_date(before:"1 week ago") # Relative dates

# File changes
files("src/")                      # Touching src/ directory
files(glob:"*.py")                 # Python files
diff_contains("TODO")              # Content changes
diff_contains("TODO", "src/")      # In specific path

# Signatures
signed()                           # Cryptographically signed commits
```

### String Pattern Syntax
```bash
# Pattern types
exact:"string"                     # Exact match
glob:"pattern"                     # Unix shell wildcards (default)
regex:"pattern"                    # Regular expression
substring:"string"                 # Contains substring

# Case-insensitive (append -i)
glob-i:"fix*"                      # Case-insensitive glob
exact-i:"README"                   # Case-insensitive exact
regex-i:"error|warning"            # Case-insensitive regex

# Pattern operators
bookmarks(~glob:"ci/*")            # NOT matching
bookmarks(glob:"feat*" & ~glob:"*wip*")  # AND + NOT
description(glob:"fix*" | glob:"bug*")   # OR
```

### State-Based Queries
```bash
# Repository state
empty()                            # Empty commits
conflicts()                        # Commits with conflicts
immutable()                        # Immutable commits
mutable()                          # Mutable commits
divergent()                        # Divergent changes
present(@)                         # Check if exists (no error if missing)
visible()                          # All visible commits
hidden()                           # Hidden commits

# Bookmark-related
bookmarks()                        # All bookmarked commits
bookmarks("feat*")                 # Matching pattern
remote_bookmarks()                 # Remote bookmarks
remote_bookmarks("main", "origin") # Specific remote bookmark
tracked_remote_bookmarks()         # Tracked remotes
untracked_remote_bookmarks()       # Untracked remotes
tags()                             # All tag targets
tags("v1.*")                       # Matching pattern

# Working copies
working_copies()                   # All workspace working copies
```

### Navigation Functions
```bash
# Parent/child
parents(x)                         # Same as x-
parents(x, 3)                      # Same as x--- (3 levels)
children(x)                        # Same as x+
children(x, 2)                     # 2 levels down
ancestors(x, 5)                    # Limited depth ancestors
descendants(x, 3)                  # Limited depth descendants

# IMPORTANT: Range operator order matters!
@---::@                            # Correct: older::newer (last 4 commits)
@::@---                            # WRONG: produces empty result
jj log -n 5                        # Simpler: just use -n flag for recent commits

# First-parent traversal
first_parent(x)                    # First parent only
first_parent(x, 2)                 # First parent, 2 levels
first_ancestors(x)                 # Ancestors via first parent only

# Graph operations
connected(x)                       # Same as x::x
reachable(srcs, domain)            # All reachable within domain
fork_point(x)                      # Common ancestor heads
heads(x)                           # Not ancestors of others in x
roots(x)                           # Not descendants of others in x
latest(x, 5)                       # Latest 5 by timestamp
```

### Advanced Functions
```bash
merges()                           # Merge commits
exactly(x, 1)                      # Error if not exactly 1
coalesce(a, b, c)                  # First non-empty revset
bisect(x)                          # Midpoint for bisection
at_operation(@-, visible_heads())  # At previous operation
```

### Built-in Aliases
```bash
trunk()                            # Default remote branch head
immutable_heads()                  # Heads of immutable commits
immutable()                        # ::immutable_heads()
mutable()                          # ~immutable()
builtin_immutable_heads()          # trunk() | tags() | untracked_remote_bookmarks()
```

### Bulk Operations
```bash
jj rebase -d main -s 'all:feat/*'  # Rebase all feat branches
jj abandon 'all:empty() & mine()'   # Abandon my empty commits
jj describe 'all:@::' -m "Updated"  # Describe all descendants
```

### Common AI Patterns
```bash
mine() & empty()                   # My empty commits
conflicts() & @::                  # Conflicts in my branch
files("src/") & description("test") # Test changes in src/
author_date(after:"yesterday") & mine() # My recent work
bookmarks() & ~immutable()         # Mutable bookmarked commits
heads() & ~bookmarks()             # Anonymous heads
signed() & mine()                  # My signed commits
divergent() | conflicts()          # All problematic commits
```

## Bookmark Management

```bash
jj bookmark create <name>          # Create at current revision
jj bookmark create <name> -r <rev> # Create at specific revision
jj bookmark move <name> --to <rev> # Move to new target
jj bookmark track <name> --remote=<remote>    # Track remote
jj bookmark untrack <name> --remote=<remote>  # Stop tracking
jj bookmark list --tracked         # List tracked bookmarks
jj bookmark list --all             # Include untracked remotes
```

Bookmark conflicts shown with `??` suffix (e.g., `main??`)

## Workspaces

```bash
jj workspace add ../path           # Create new workspace
jj workspace add ../path --name ws # With custom name
jj workspace list                  # List workspaces
jj workspace root                  # Current workspace root
jj workspace forget <name>         # Remove workspace
jj workspace update-stale          # Update stale working copy
```

## Code Formatting (jj fix)

```bash
jj fix                             # Fix current commit
jj fix -r @-                       # Fix specific revision
jj fix -r 'trunk()..@'             # Fix range
jj fix -r @ 'glob:"*.py"'          # Fix specific files
jj fix -s feature-start            # Source and descendants
jj fix --dry-run                   # Preview changes
```

## Commit Signing

```bash
jj sign -r @                       # Sign current commit
jj sign -r 'mine() & ~signed()'    # Sign all unsigned
jj unsign -r @                     # Remove signature
```

Signature status: `good`, `bad`, `unknown`, `expired`

## Reverting Commits

Create a commit that undoes changes from another commit (like `git revert`):

```bash
# REQUIRED: Must specify where to place the revert commit
jj revert -r <rev> --insert-after @   # After current working copy
jj revert -r <rev> --insert-before @  # Before current working copy (most common)
jj revert -r <rev> --onto <dest>      # On top of specific revision

# Revert multiple commits
jj revert -r 'abc123 | def456' --insert-before @

# Short form: -B for --insert-before, -A for --insert-after
jj revert -r <rev> -B @               # Common usage
```

**Note:** Unlike git, `jj revert` REQUIRES a destination flag (`--onto`, `--insert-after`, or `--insert-before`).

## Restoring Paths

Restore file contents from another revision:

```bash
# Restore paths in working copy from parent (undo changes)
jj restore <paths>

# Restore from specific revision
jj restore --from <rev> <paths>

# Restore all paths (make working copy empty)
jj restore                            # Similar to jj abandon but keeps commit

# Restore into specific revision
jj restore --from <source> --into <dest> <paths>
```

## Change Distribution (jj absorb)

Automatically move changes to the appropriate ancestor commits:

```bash
# Absorb all changes in working copy
jj absorb

# Absorb specific files
jj absorb <paths>

# Absorb from specific revision
jj absorb --from <rev>

# Absorb into specific range
jj absorb --into 'trunk()..@'
```

`jj absorb` analyzes where each line was last modified and moves changes to those commits automatically.

## History Inspection

### Change Evolution (jj evolog)

Show how a change has evolved over time:

```bash
jj evolog                             # Current change history
jj evolog -r <rev>                    # Specific change history
jj evolog --limit 10                  # Limit entries
```

### File Annotation (jj file annotate)

Show who changed each line (like `git blame`):

```bash
jj file annotate <path>               # Annotate file
jj file annotate -r <rev> <path>      # At specific revision
```

### Interdiff

Compare the changes between two commits:

```bash
jj interdiff --from <rev1> --to <rev2>
```

## Bisection (jj bisect)

Find a bad revision by bisection:

```bash
# Run command to find first bad revision
jj bisect run --good <good_rev> --bad <bad_rev> <command>
```

## Additional Commands

### Tags
```bash
jj tag list                           # List tags
jj tag create <name> -r <rev>         # Create tag (requires git backend)
```

### Sparse Checkouts
```bash
jj sparse list                        # List sparse patterns
jj sparse set --add <path>            # Add to sparse set
jj sparse set --remove <path>         # Remove from sparse set
jj sparse reset                       # Reset to full checkout
```

### Parallelize
```bash
jj parallelize <revs>                 # Make revisions siblings
```

### Simplify Parents
```bash
jj simplify-parents -r <rev>          # Remove redundant parent edges
```
