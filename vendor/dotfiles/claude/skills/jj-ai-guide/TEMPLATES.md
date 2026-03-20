# Template System Reference

## Template Types

| Type | Available In | Key Properties |
|------|--------------|----------------|
| `Commit` | `jj log`, `jj show` | `commit_id`, `change_id`, `author`, `description`, `parents`, `bookmarks`, `tags` |
| `Operation` | `jj op log` | `id`, `description`, `tags`, `time`, `user`, `current_operation`, `root` |
| `AnnotationLine` | `jj annotate` | `commit`, `line`, `first_line_in_hunk` |
| `TreeDiff` | Diff outputs | Iterator of `TreeDiffEntry` |
| `TreeDiffEntry` | Diff outputs | `path`, `source`, `target` |
| `CryptographicSignature` | Signed commits | `status`, `key`, `display`, `backend` |
| `Trailer` | Commit trailers | `key`, `value` |

## Built-in Templates

```bash
jj log -T 'builtin_log_oneline'           # Compact one-line
jj log -T 'builtin_log_compact'           # Default format
jj log -T 'builtin_log_comfortable'       # Expanded format
jj log -T 'builtin_log_compact_full_description'  # Full description
jj log -T 'builtin_log_node_ascii'        # ASCII graph nodes
```

## Structured Output Examples

### JSON Format
```bash
jj log --template='{
  "commit": commit_id,
  "change": change_id,
  "author": author.email(),
  "date": author_date.format("%Y-%m-%dT%H:%M:%S%z"),
  "message": description,
  "bookmarks": separate(", ", local_bookmarks, remote_bookmarks)
}' -r '@::trunk()'
```

### CSV Format
```bash
jj log --template='commit_id.short() ++ "," ++ description.first_line() ++ "," ++ author.email() ++ "," ++ author_date.format("%Y-%m-%d")'
```

### Tab-Separated
```bash
jj log --template='commit_id.short() ++ "\t" ++ change_id.short() ++ "\t" ++ description.first_line()'
```

## String Methods

```bash
# Extraction
description.first_line()           # First line
description.lines()                # Iterator of lines

# Case
description.upper()                # Uppercase
description.lower()                # Lowercase

# Checks
description.starts_with("feat:")   # Prefix check
description.ends_with("!")         # Suffix check
description.contains("bug")        # Substring check

# Modification
description.remove_prefix("fix: ") # Remove prefix if present
description.remove_suffix(".")     # Remove suffix if present
description.substr(0, 50)          # Substring extraction
description.replace("foo", "bar")  # Replace first occurrence
description.replace("foo", "bar", 0)  # Replace all

# Pattern matching
description.match(glob:"fix*")     # Check if matches

# Splitting
author.email().split("@").first()  # Split and get first
```

## Conditional Templates

### Basic If
```bash
jj log --template='
if(conflicts,
  "CONFLICT: " ++ description.first_line(),
  "OK: " ++ description.first_line()
)'
```

### Signature Status
```bash
jj log --template='
if(signature,
  if(signature.status() == "good", "✓ ", "⚠ "),
  "  "
) ++ description.first_line()'
```

### Empty Detection
```bash
jj log --template='
if(empty,
  "[EMPTY] ",
  ""
) ++ description.first_line() ++ " (" ++ commit_id.short() ++ ")"'
```

### Coalesce (Fallback Values)
```bash
jj log --template='
coalesce(
  if(local_bookmarks, local_bookmarks.join(", ")),
  if(remote_bookmarks, remote_bookmarks.join(", ")),
  change_id.short()
)'
```

## Advanced Template Example

```bash
jj log --template='{
  "id": commit_id.short(),
  "change": change_id.short(),
  "parents": parents.map(|p| p.commit_id().short()).join(", "),
  "author": {
    "name": author.name(),
    "email": author.email(),
    "date": author_date.format("%Y-%m-%dT%H:%M:%S")
  },
  "committer": {
    "name": committer.name(),
    "email": committer.email(),
    "date": committer_date.format("%Y-%m-%dT%H:%M:%S")
  },
  "message": {
    "summary": description.first_line(),
    "body": description.lines().skip(1).join("\n")
  },
  "signature": if(signature, signature.status(), "none"),
  "contained_in": contained_in("trunk()..").join(", "),
  "stats": {
    "empty": empty,
    "conflicts": conflicts,
    "divergent": divergent,
    "hidden": hidden
  }
}'
```

## Trailers
```bash
jj log --template='
trailers.map(|t|
  t.key() ++ ": " ++ t.value()
).join("\n")' -r '@'
```

## Hyperlinks (Terminal OSC8)
```bash
jj log --template='
hyperlink("https://github.com/repo/commit/" ++ commit_id, commit_id.short())'
```

## Config Access
```bash
jj log --template='"Repo: " ++ config("user.email").value()'
```

## Global Functions

```bash
fill(80, content)                  # Word-wrap at 80 columns
indent("  ", content)              # Indent all lines
label("tag", content)              # Apply styling label
raw_escape_sequence("\x1b[1m")     # Raw terminal escape
surround("(", ")", content)        # Wrap with prefix/suffix
pad_start(8, content)              # Pad to width (right-align)
pad_end(8, content)                # Pad to width (left-align)
truncate_start(50, content)        # Truncate from start
truncate_end(50, content)          # Truncate from end
hash(content)                      # SHA-1 hash as hex string
```

## Template Aliases in Config

```toml
[template-aliases]
'format_short_id(id)' = 'id.shortest()'
'format_timestamp(ts)' = 'ts.format("%Y-%m-%d %H:%M")'
'format_short_signature(sig)' = 'sig.name()'
'my_format' = 'commit_id.short() ++ " " ++ description.first_line()'
'pr-format' = 'description ++ "\n\nCommit: " ++ commit_id'
'changelog' = 'description.first_line() ++ " (" ++ author.name() ++ ")"'
```

Usage:
```bash
jj log -T 'my_format' -r 'work'
```
