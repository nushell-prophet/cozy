# Filesets Reference

Filesets select files by path patterns. Used with `jj squash`, `jj split`, `jj file`, `jj diff`, etc.

## Pattern Types

### Default (prefix-glob)
```bash
jj squash "src/"              # All files under src/
jj squash "*.py"              # Python files in current dir
jj squash "**/*.py"           # Python files recursively
```

### Explicit Pattern Types

```bash
# Glob patterns
jj squash 'glob:"test_*.py"'           # Standard glob
jj squash 'cwd-glob:"local/*.txt"'     # Relative to current directory
jj squash 'root-glob:"src/**/*.rs"'    # Relative to repo root

# Exact file matching (no wildcards)
jj squash 'file:"README.md"'           # Exact file in current dir
jj squash 'cwd-file:"./config.toml"'   # Explicit cwd-relative
jj squash 'root-file:"Cargo.toml"'     # Repo root-relative

# Regex matching
jj squash 'regex:".*test.*\.py"'       # Regex pattern
jj squash 'cwd-regex:".*\.test\.*"'    # Cwd-relative regex
jj squash 'root-regex:"src/.*\.rs"'    # Root-relative regex

# Case-insensitive (append -i)
jj squash 'glob-i:"*.TXT"'             # Matches .txt, .TXT, .Txt
jj squash 'file-i:"readme.md"'         # Case-insensitive file match
```

## Path Prefixes

```bash
# cwd: relative to current working directory (default)
jj squash 'cwd:"./local/"'

# root: relative to repository root
jj squash 'root:"src/lib/"'

# Default is cwd-prefix-glob
jj squash "src/"              # Same as cwd-prefix-glob:"src/"
```

## Operators

```bash
# Union: OR
jj squash "src/ | tests/"             # Files in src OR tests

# Intersection: AND
jj squash 'src/ & glob:"*.py"'        # Python files in src

# Difference: EXCEPT
jj squash 'src/ ~ glob:"*test*"'      # src files except tests

# Negation: NOT
jj squash '~glob:"*.tmp"'             # Everything except .tmp files

# Grouping
jj squash '(src/ | lib/) & ~glob:"*test*"'
```

## Functions

```bash
jj squash 'all()'                     # All tracked files
jj squash 'none()'                    # No files
```

## Complex Patterns

```bash
# Combine operators
jj squash 'glob:"*.{py,js,ts}" & ~glob:"node_modules/**"'
jj squash '(root:"src/" | root:"lib/") & glob:"*.rs" & ~glob:"*test*"'

# Multiple extensions
jj squash 'glob:"*.{py,pyi,pyx}"'     # All Python-related files

# Recursive patterns
jj squash 'glob:"**/test_*.py"'       # All test files recursively
jj squash 'root-glob:"docs/**/*.md"'  # All markdown in docs/
```

## AI-Specific Patterns

```bash
# Code categories
CODE_FILES="glob:*.{py,js,ts,java,cpp,c,h,hpp,rs,go}"
TEST_FILES="glob:*{test,spec}*.{py,js,ts} | glob:test_*"
CONFIG_FILES="glob:*.{json,yaml,yml,toml,ini,cfg,conf}"
DOC_FILES="glob:*.{md,rst,txt}"
BUILD_ARTIFACTS="glob:*.{o,pyc,pyo,class,jar,exe,dll,so,dylib}"

# Usage
jj squash "$CODE_FILES & src/"     # Code files in src
jj split "$TEST_FILES"             # Split out test files
jj file untrack "$BUILD_ARTIFACTS" # Untrack build artifacts
```

## Repository Structure Patterns

```bash
# Monorepo
FRONTEND="packages/frontend/ | apps/web/"
BACKEND="packages/backend/ | apps/api/"
SHARED="packages/shared/ | lib/"

# Microservices
SERVICE_A="services/auth/ | services/user/"
SERVICE_B="services/payment/ | services/order/"

# By responsibility
FEATURES="src/features/ | components/"
UTILS="src/utils/ | src/helpers/"
TESTS="src/**/*test* | tests/ | __tests__/"

# Usage
jj squash "$FRONTEND & glob:*.ts"    # Frontend TypeScript
```

## Working with File States

```bash
# List files
jj file list                  # All tracked files
jj file list --revision @-    # Files in parent commit
jj file list "src/"          # Files in directory

# Changed files
jj diff --name-only "src/"    # Changed files in src
jj diff --name-only "glob:*.py" # Changed Python files

# Selective operations
jj squash "$(jj diff --name-only 'glob:*.py')"  # Squash Python changes
```

## Bulk Operations

```bash
bulk_squash() {
  local patterns=("$@")
  for pattern in "${patterns[@]}"; do
    if jj diff --name-only "$pattern" | grep -q .; then
      jj squash "$pattern" -m "Update $(basename "$pattern")"
    fi
  done
}

# Usage
bulk_squash "src/*.py" "tests/*.py" "docs/*.md"
```

## Configuration-Based Filesets

```toml
# .jj/config.toml
[template-aliases]
code = 'files(glob:"*.{py,js,ts,java,cpp,c,h,hpp,rs,go}")'
tests = 'files(glob:"*{test,spec}*.{py,js,ts}") | files(glob:"test_*")'
docs = 'files(glob:"*.{md,rst,txt}")'
```

Usage in commands:
```bash
jj log --template=code       # Show commits touching code
jj squash 'files(glob:"*.py") & ~files(glob:"*test*")'
```
