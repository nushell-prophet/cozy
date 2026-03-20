# AI Agent Workflows

Automation scripts and patterns for AI agents working with jj.

## Author Attribution

**Important:** In jj, the working copy inherits the user's identity. AI agents must update the author after committing:

```bash
jj commit -m "message" && jj metaedit @- --update-author
```

The `--update-author` flag reads from `JJ_CONFIG` env var pointing to the agent's config file with `user.name` and `user.email`.

## Standard AI Workflow Pattern

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

## Automated Code Review

```bash
review_recent_changes() {
  local days="${1:-7}"
  local authors="${2:-all}"

  if [ "$authors" = "all" ]; then
    jj log -r "author_date(after:\"$days days ago\")" --template='{
      "commit": commit_id,
      "author": author.email(),
      "date": author_date,
      "message": description.first_line(),
      "changes": files.len()
    }'
  else
    jj log -r "author_date(after:\"$days days ago\") & author(glob:\"*$authors*\")" --template='json()'
  fi
}

find_potential_issues() {
  # Large commits
  jj log -r 'mine() & author_date(after:"1 week ago")' --template='
  if(files.len() > 10,
    "LARGE: " ++ description.first_line() ++ " (" ++ files.len() ++ " files)",
    ""
  )' | grep -v "^$"

  # Issue-related commits
  jj log -r 'description(regex:"(fix|bug|issue|problem|error)")' --template='
  "ISSUE: " ++ description.first_line() ++ " (" ++ commit_id.short() ++ ")"'
}
```

## Branch Management

```bash
cleanup_branches() {
  local cutoff_days="${1:-30}"

  jj bookmark list --template='{
    "name": name,
    "target": target,
    "last_commit_date": target.author_date()
  }' | jq -r '
  select(.last_commit_date < (now - ('$cutoff_days' * 24 * 60 * 60))) |
  .name
  ' | while read bookmark; do
    echo "Deleting stale bookmark: $bookmark"
    jj bookmark delete "$bookmark"
  done
}

sync_with_remote() {
  local remote="${1:-origin}"

  jj git fetch --remote "$remote"

  jj bookmark list --template='
  if(remote_targets.contains("'$remote'"),
    name,
    ""
  )' | grep -v "^$" | while read bookmark; do
    if jj bookmark list "$bookmark" | grep -q "ahead"; then
      echo "Bookmark $bookmark is ahead of remote"
    else
      jj bookmark move "$bookmark" --to "$bookmark@$remote"
    fi
  done
}
```

## Testing Integration

```bash
test_changes() {
  local base_commit="${1:-main}"

  local changed_files=$(jj diff --from "$base_commit" --name-only)

  for file in $changed_files; do
    case "$file" in
      src/*.py)
        echo "Running tests for $file"
        pytest "tests/$(basename "$file" .py)_test.py" 2>/dev/null || true
        ;;
      *.js|*.ts)
        echo "Running JS tests for $file"
        npm test -- --testPathPattern="$(basename "$file" .js)" 2>/dev/null || true
        ;;
    esac
  done
}

validate_commit() {
  local commit="${1:-@}"

  # Check commit message format
  local msg=$(jj log -r "$commit" --template='description.first_line()')
  if ! echo "$msg" | grep -qE '^(feat|fix|docs|style|refactor|test|chore)(\(.+\))?: .+'; then
    echo "ERROR: Commit message doesn't follow conventional format"
    return 1
  fi

  # Check for conflicts
  if jj log -r "$commit" --template='conflicts' | grep -q 'true'; then
    echo "ERROR: Commit has unresolved conflicts"
    return 1
  fi

  return 0
}
```

## Release Management

```bash
prepare_release() {
  local version="$1"
  local base_branch="${2:-main}"

  jj new "$base_branch" -m "Prepare release $version"
  jj bookmark create "release/$version"

  # Generate changelog
  jj log -r "$base_branch..@" --template='
  "- " ++ description.first_line() ++ " (" ++ change_id.short() ++ ")"
  ' > CHANGELOG_$version.md

  # Update version files
  find . -name "package.json" -o -name "pyproject.toml" | while read file; do
    case "$file" in
      */package.json)
        jq '.version = "'$version'"' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        ;;
      */pyproject.toml)
        sed -i 's/version = ".*"/version = "'$version'"/' "$file"
        ;;
    esac
  done

  jj commit -m "Bump version to $version"
}

tag_release() {
  local version="$1"
  local commit="${2:-@}"

  # Create tag (using git in co-located repo)
  git tag -a "v$version" -m "Release version $version" "$(jj log -r "$commit" --template='commit_id')"

  jj git push --bookmark "release/$version"
  git push origin "v$version"
}
```

## Code Analysis

```bash
find_hotspots() {
  local days="${1:-90}"

  # Most frequently changed files
  jj log -r "author_date(after:\"$days days ago\")" --template='
  files.map(|f| f.path()).join("\n")
  ' | sort | uniq -c | sort -nr | head -20

  # Authors by activity
  jj log -r "author_date(after:\"$days days ago\")" --template='
  author.email()
  ' | sort | uniq -c | sort -nr
}

analyze_technical_debt() {
  # Find TODO/FIXME
  jj log -r 'diff_contains("TODO") | diff_contains("FIXME")' --template='
  "DEBT: " ++ description.first_line() ++ " (" ++ commit_id.short() ++ ")"
  '

  # Large files
  jj log -r 'files(glob:"*.py") | files(glob:"*.js")' --template='
  files.map(|f| f.path()).join("\n")
  ' | sort -u | while read file; do
    [ -f "$file" ] && [ $(wc -l < "$file") -gt 500 ] && echo "LARGE: $file"
  done
}
```

## Dependency Management

```bash
update_dependencies() {
  local commit_each="${1:-false}"

  if [ -f "package.json" ]; then
    npm update
    [ "$commit_each" = "true" ] && jj commit -m "Update npm dependencies" package.json package-lock.json
  fi

  if [ -f "requirements.txt" ]; then
    pip list --outdated --format=json | jq -r '.[] | .name' | xargs -I{} pip install --upgrade {}
    pip freeze > requirements.txt
    [ "$commit_each" = "true" ] && jj commit -m "Update Python dependencies" requirements.txt
  fi

  if [ -f "Cargo.toml" ]; then
    cargo update
    [ "$commit_each" = "true" ] && jj commit -m "Update Rust dependencies" Cargo.toml Cargo.lock
  fi
}

security_audit() {
  if [ -f "package.json" ]; then
    npm audit --json | jq -r '.vulnerabilities | keys[]' | while read vuln; do
      echo "NPM VULNERABILITY: $vuln"
    done
  fi

  # Check for secrets in recent commits
  jj log -r 'author_date(after:"1 week ago")' --template='
  files.map(|f| f.path()).join("\n")
  ' | sort -u | while read file; do
    [ -f "$file" ] && grep -qE '(password|secret|key|token).*=.*["\'][^"\']{8,}["\']' "$file" && echo "POTENTIAL SECRET: $file"
  done
}
```

## Safe Operation Wrappers

```bash
safe_rebase() {
  local source="$1"
  local dest="$2"

  local checkpoint=$(jj op log --limit 1 --template='operation.id')

  if ! jj rebase -s "$source" -d "$dest"; then
    echo "Rebase failed, restoring checkpoint"
    jj op restore "$checkpoint"
    return 1
  fi

  if jj log -r 'conflicts()' --template='commit_id' | grep -q '.'; then
    echo "Rebase created conflicts, restoring checkpoint"
    jj op restore "$checkpoint"
    return 1
  fi

  return 0
}

safe_commit() {
  local message="$1"
  shift
  local files=("$@")

  if jj st | grep -q 'No changes'; then
    echo "No changes to commit"
    return 1
  fi

  if [ ${#files[@]} -gt 0 ]; then
    jj commit -m "$message" "${files[@]}" && jj metaedit @- --update-author
  else
    jj commit -m "$message" && jj metaedit @- --update-author
  fi
}
```

## Pre-flight Checks

```bash
preflight_checks() {
  if jj log -r 'conflicts()' --template='commit_id' | grep -q '.'; then
    echo "Error: Repository has conflicts"
    return 1
  fi

  if jj log -r 'divergent()' --template='commit_id' | grep -q '.'; then
    echo "Error: Repository has divergent changes"
    return 1
  fi

  if jj st | grep -q 'Warning:'; then
    echo "Error: Working copy has warnings"
    return 1
  fi

  return 0
}

validate_repo_state() {
  local issues=0

  jj log -r 'conflicts()' --template='commit_id' | grep -q '.' && {
    echo "ISSUE: Repository has conflicts"
    ((issues++))
  }

  jj log -r 'divergent()' --template='commit_id' | grep -q '.' && {
    echo "ISSUE: Repository has divergent changes"
    ((issues++))
  }

  jj log -r 'empty() & mine()' --template='commit_id' | grep -q '.' && {
    echo "WARNING: You have empty commits"
  }

  return $issues
}
```
