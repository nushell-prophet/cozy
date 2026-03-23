# Configuration Reference

## Essential AI Agent Configuration

Create or update `~/.jjconfig.toml`:

```toml
[user]
name = "AI Agent"
email = "ai-agent@company.com"

[ui]
# Disable interactive features
paginate = "never"                  # No pager interruption
color = "never"                     # Easier output parsing
diff-editor = ":builtin"            # Avoid external editors
merge-editor = ":builtin"           # Avoid external editors
default-command = "log"             # Safe default command

# Conflict handling
conflict-marker-style = "diff"      # AI-recommended: shows changes as diffs
# conflict-marker-style = "snapshot"  # Alternative: shows full snapshots
# conflict-marker-style = "git"      # Git-compatible (2-sided only)

# Log formatting
log-word-wrap = true                # Better log formatting
show-cryptographic-signatures = true # Show signature status

# Sorting options
bookmark-list-sort-keys = ["name"]  # Sort bookmarks alphabetically
tag-list-sort-keys = ["name"]       # Sort tags alphabetically

[snapshot]
# Control automatic tracking (uses fileset expressions)
auto-track = 'all()'                # Track all files (default)
# auto-track = 'none()'             # Disable auto-tracking
# auto-track = '~glob:"*.tmp" & ~glob:"node_modules/**"'
auto-update-stale = true            # Auto-update stale working copies

[template-aliases]
'format_short_id(id)' = 'id.shortest()'
'format_timestamp(ts)' = 'ts.format("%Y-%m-%d %H:%M")'
'format_short_signature(sig)' = 'sig.name()'

[revset-aliases]
'work' = 'mine() & author_date(after:"1 week ago")'
'recent' = 'author_date(after:"yesterday")'
'problems' = 'conflicts() | divergent()'
'stale' = 'empty() & mine() & ~conflicts()'
'unsigned' = 'mine() & ~signed()'

[git]
private-commits = 'description(glob:"*WIP*") | description(glob:"*tmp*")'
sign-on-push = false                # Sign commits on push
auto-local-bookmark = false         # Don't create local bookmarks automatically

[remotes.origin]
auto-track-bookmarks = "glob:main"  # Only track main automatically
# auto-track-bookmarks = "*"        # Track all bookmarks

[merge]
hunk-level = "line"                 # "line" or "word" level merging
same-change = "keep"                # "keep" or "accept" identical changes

[working-copy]
eol-conversion = "input"            # "none", "input", "input-output"

[core]
fsmonitor = "watchman"              # "none", "watchman", or path to binary
```

## Commit Signing Configuration

```toml
[signing]
# Choose signing backend
backend = "gpg"                     # "gpg", "gpgsm", or "ssh"
# backend = "ssh"                   # For SSH signing
behavior = "own"                    # When to sign: "drop", "keep", "own", "force"
                                    # - drop: Never sign
                                    # - keep: Preserve existing signatures
                                    # - own: Sign commits you author
                                    # - force: Always sign all commits

# GPG signing
[signing.backends.gpg]
program = "gpg"                     # Path to GPG binary
allow-expired-keys = false          # Reject expired keys

# SSH signing
[signing.backends.ssh]
program = "ssh-keygen"              # Path to ssh-keygen
key = "~/.ssh/id_ed25519"           # Key file path or "ssh-agent"
allowed-signers = "~/.ssh/allowed_signers"  # For verification
```

## Environment Variables

```bash
export JJ_CONFIG=/path/to/automation.toml
export JJ_USER="AI Agent"
export JJ_EMAIL="ai-agent@company.com"
export NO_COLOR=1                   # Disable colors globally
export PAGER=""                     # Disable pager
export JJ_EDITOR="cat"              # Non-interactive editor
```

## Repository-Specific Configuration

Create `.jj/config.toml` in your repository:

```toml
[ui]
default-revset = "trunk()..@"       # Show work branch by default
log-word-wrap = true

[snapshot]
auto-track = '~glob:"*.pyc" & ~glob:"__pycache__/**" & ~glob:"node_modules/**"'

[template-aliases]
'pr-format' = 'description ++ "\n\nCommit: " ++ commit_id'
'changelog' = 'description.first_line() ++ " (" ++ author.name() ++ ")"'
```

## Code Formatting Tool Configuration

```toml
[fix.tools.rustfmt]
command = ["rustfmt", "--emit", "stdout"]
patterns = ['glob:"**/*.rs"']
enabled = true

[fix.tools.black]
command = ["black", "-"]
patterns = ['glob:"**/*.py"']
enabled = true

[fix.tools.prettier]
command = ["prettier", "--stdin-filepath", "$path"]
patterns = ['glob:"**/*.{js,ts,jsx,tsx,json,md}"']
enabled = true

[fix.tools.gofmt]
command = ["gofmt"]
patterns = ['glob:"**/*.go"']
enabled = true

[fix.tools.clang-format]
command = ["clang-format"]
patterns = ['glob:"**/*.{c,cpp,h,hpp}"']
enabled = true

# Tool execution order (priority)
[fix.tools.isort]
command = ["isort", "-"]
patterns = ['glob:"**/*.py"']
priority = 1                    # Runs first

[fix.tools.black]
command = ["black", "-"]
patterns = ['glob:"**/*.py"']
priority = 2                    # Runs second
```

## Conditional Configuration (Scoped Settings)

Configure different settings based on context:

```toml
# Work repositories get different email
[[--scope]]
--when.repositories = ["~/work", "~/projects/work-*"]
[--scope.user]
email = "work@company.com"

# Different editor for specific commands
[[--scope]]
--when.commands = ["describe", "commit"]
[--scope.ui]
editor = "vim"

# Platform-specific settings
[[--scope]]
--when.platforms = ["macos"]
[--scope.core]
fsmonitor = "watchman"

# Hostname-specific settings
[[--scope]]
--when.hostnames = ["work-laptop"]
[--scope.signing]
backend = "ssh"
```

## Config Commands

```bash
# View config
jj config list                      # All config
jj config list --user               # User config only
jj config list --repo               # Repo config only
jj config get user.email            # Specific value

# Set config
jj config set --user ui.color never
jj config set --repo ui.default-revset 'trunk()..@'

# Edit config
jj config edit --user               # Edit user config file
jj config edit --repo               # Edit repo config file
```
