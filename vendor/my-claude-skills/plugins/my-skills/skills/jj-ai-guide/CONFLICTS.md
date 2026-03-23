# Conflict Resolution Reference

jj stores conflicts in commits - operations never fail due to conflicts. This allows you to resolve conflicts whenever you're ready.

## Conflict Marker Styles

Controlled by `ui.conflict-marker-style` config option.

### 1. `diff` Style (Default, AI-recommended)

Shows changes as diffs to apply to a snapshot:

```
<<<<<<< conflict 1 of 1
%%%%%%% diff from: vpxusssl 38d49363 "merge base"
\\\\\\\        to: rtsqusxu 2768b0b9 "commit A"
 apple
-grape
+grapefruit
 orange
+++++++ ysrnknol 7a20f389 "commit B"
APPLE
GRAPE
ORANGE
>>>>>>> conflict 1 of 1 ends
```

Markers:
- `%%%%%%%` - Start of a diff to apply
- `\\\\\\\` - Continues label on new line
- `+++++++` - Start of a snapshot (base to apply diff to)

### 2. `snapshot` Style

Shows full content of each side:

```
<<<<<<< conflict 1 of 1
+++++++ rtsqusxu 2768b0b9 "commit A"
apple
grapefruit
orange
------- vpxusssl 38d49363 "merge base"
apple
grape
orange
+++++++ ysrnknol 7a20f389 "commit B"
APPLE
GRAPE
ORANGE
>>>>>>> conflict 1 of 1 ends
```

Markers:
- `+++++++` - Start of a snapshot
- `-------` - Base version

### 3. `git` Style

Familiar Git format (2-sided conflicts only):

```
<<<<<<< rtsqusxu 2768b0b9 "commit A"
apple
grapefruit
orange
||||||| vpxusssl 38d49363 "merge base"
apple
grape
orange
=======
APPLE
GRAPE
ORANGE
>>>>>>> ysrnknol 7a20f389 "commit B"
```

Falls back to `snapshot` for 3+ sided conflicts.

## Long Conflict Markers

When files contain text that could be confused for conflict markers, jj uses longer markers:

```
<<<<<<<<<<<<<<< conflict 1 of 1
%%%%%%%%%%%%%%% diff from: wqvuxsty cb9217d5 "merge base"
\\\\\\\\\\\\\\\        to: kwntsput 0e15b770 "commit A"
-Heading
+HEADING
 =======
+++++++++++++++ mpnwrytz 52020ed6 "commit B"
New Heading
===========
>>>>>>>>>>>>>>> conflict 1 of 1 ends
```

## Missing Terminating Newline

When a side has no trailing newline, jj adds a comment:

```
<<<<<<< conflict 1 of 1
+++++++ tlwwkqxk d121763d "commit A" (no terminating newline)
grapefruit
%%%%%%% diff from: qwpqssno fe561d93 "merge base" (no terminating newline)
\\\\\\\        to: poxkmrxy c735fe02 "commit B"
-grape
+grape
>>>>>>> conflict 1 of 1 ends
```

## Resolution Workflow

### Standard Resolution
```bash
jj new <conflicted_commit>    # Create working copy on conflict
# Edit files to resolve conflicts
jj squash                     # Merge resolution into conflicted commit
```

### Alternative: Edit Directly
```bash
jj edit <conflicted_commit>   # Edit the conflicted commit directly
# Edit files to resolve
# Harder to inspect resolutions with jj diff
```

## Programmatic Conflict Detection

```bash
# Find all commits with conflicts
jj log -r 'conflicts()'

# Find conflicts in specific paths
jj log -r 'conflicts() & files("src/")'

# Show conflict details
jj show -r 'conflicts()' --no-pager

# Check if current working copy has conflicts
jj st | grep -q "Warning: There are unresolved conflicts"
```

## Automated Resolution Strategies

### Take One Side
```bash
resolve_take_side() {
  local file="$1"
  local side="$2"  # 1 or 2
  # Parse conflict markers and keep specified side
}
```

### Parse Conflicts Programmatically
```bash
parse_conflict() {
  local file="$1"
  awk '/<<<<<<< Conflict/,/>>>>>>> Conflict.*ends/{
    if(/%%%%%%% Changes from base/) { in_diff=1; next }
    if(/\+\+\+\+\+\+\+ Contents/) { in_diff=0; in_snap=1; next }
    if(/>>>>>>> Conflict.*ends/) { in_diff=0; in_snap=0; next }
    if(in_diff) print "DIFF:", $0
    if(in_snap) print "SNAP:", $0
  }' "$file"
}
```

## Multi-way Conflicts

3+ way conflicts show multiple diff/snapshot sections:

```
<<<<<<< Conflict 1 of 1
%%%%%%% Changes from base to side #1
+side 1 changes
+++++++ Contents of side #2
side 2 content
+++++++ Contents of side #3
side 3 content
>>>>>>> Conflict 1 of 1 ends
```

### Parsing Multi-way
```bash
parse_multiway() {
  local file="$1"
  local current_side=""
  while IFS= read -r line; do
    case "$line" in
      "%%%%%%% Changes from base to side #"*)
        current_side="diff"
        ;;
      "+++++++ Contents of side #"*)
        current_side="side_$(echo "$line" | grep -o '#[0-9]*' | tr -d '#')"
        ;;
      ">>>>>>> Conflict"*"ends")
        current_side=""
        ;;
      *)
        [ -n "$current_side" ] && echo "$current_side: $line"
        ;;
    esac
  done < "$file"
}
```

## Batch Resolution

```bash
# Resolve multiple conflicts
for commit in $(jj log -r 'conflicts()' --no-graph --template='change_id'); do
  jj new "$commit"
  # Apply automated resolution
  jj squash -m "Auto-resolve conflicts in $commit"
done
```

## Using External Merge Tools

If configured in `ui.merge-editor`:
```bash
jj resolve                    # Opens merge tool (interactive - avoid in automation)
```

For AI agents, prefer editing conflict markers directly rather than using `jj resolve`.
