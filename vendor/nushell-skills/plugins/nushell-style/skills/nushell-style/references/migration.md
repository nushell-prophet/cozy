# Nushell Migration Guide (0.100 → 0.117)

When updating Nushell scripts, consult this reference for breaking changes, renamed commands, and new idioms.
Versions noted as `(v0.NNN)`.

---

## Renamed & Removed Commands

- `range` → `slice` — removed 0.103
- `into bits` → `format bits` — removed 0.103
- `fmt` → `format number` — removed 0.103
- `split-by` → `group-by` (multiple groupers) — removed 0.102
- `date to-record` → `into record` — removed 0.102
- `date to-table` → `into record | transpose | transpose --header-row` — removed 0.102
- `utouch` → `touch` — removed 0.102
- `into value` (type inference) → `detect type` — 0.108
- `into value --columns` → `detect type --columns` — removed 0.112
- `random dice` (built-in) → `use std/random; random dice` — removed 0.112
- `filter` → `where` (accepts stored closures) — removed 0.117 (deprecated 0.105).
  A leftover `filter` now runs an external command of that name: ``Command `filter` not found``
- `date format` → `format date` — the removal hint is gone in 0.117; `date now | date format '%Y'` is now `Extra positional argument`
- `do -s` / `do -p` (short for `--ignore-shell-errors` / `--ignore-program-errors`) → `do --ignore-errors (-i)` — removed 0.104
- `do --ignore-shell-errors` → `do --ignore-errors (-i)` — deprecated 0.101
- `do --ignore-program-errors` → `do --ignore-errors (-i)` — deprecated 0.101
- `job tag` → `job describe` — 0.112
- `polars fetch` → (removed, no replacement) — 0.108
- `str upcase` → `str uppercase` — deprecated 0.114
- `str downcase` → `str lowercase` — deprecated 0.114
- `std/clip` `copy` / `paste` → `clip copy52` / `paste52` (OSC 52), or `clip copy` / `paste` under the `native-clip` experimental option — removed 0.114
- `idx import` / `idx export` → `idx init` (in-memory only; `--no-watch` turns watching off) — removed 0.115
- `nu --testbin <name>` → plain Nushell, or `nu -n -c "..."` — removed 0.115

### Renamed Flags

- `get`/`select`/`reject`: `--ignore-errors (-i)` → `--optional (-o)` — removed 0.117 (deprecated 0.106); `get -i b` is now `nu::parser::unknown_flag`
- `get --sensitive (-s)` → drop it (cell paths are case-sensitive by default; `!` after a member makes it case-insensitive) — removed 0.117
- `update cells --columns (-c) [a b] { ... }` → `update cells { ... } a b` (column names after the closure) — deprecated 0.117
- `du`: `--all (-a)` → `--long (-l)` — 0.101
- `watch`: `--debounce-ms` → `--debounce` (duration) — removed 0.112
- `metadata set`: `--merge` → closure form — removed 0.112
- `metadata set`: `--datasource-ls` → `--path-columns [name]` — removed 0.113 (deprecated 0.111)
- `kill`: `-0` / `-9` shorthand → `--signal 0` / `--signal 9` — removed 0.113
- `watch`: closure argument → bare `watch path` stream + `for`/`each` — deprecated 0.113
- `grid`: a single record as input → a list or table — removed 0.114 (deprecated 0.113); the implicit `name` column stays (`ls | grid`), despite the 0.114 release note
- `from xlsx` / `from ods`: `--header-row` → `--noheaders` / `--first-row` — removed 0.114 (added 0.113)
- `std/iter scan`: positional init + `--noinit` → `--fold` (omit for no initial value) — 0.114
- `to yaml`: `--compact-list-indent` → drop it (compact is the default) — removed 0.116.
  The new `--list-indent indented` gives the other style
- `tui label`: `--title` → `--titlebar` — deprecated 0.116.1, removed 0.118.
  `--title` now names the border of a bordered widget
- experimental option `background-completions` → `@interactive` on the completer command — added 0.115.1, removed 0.116 (see *Unified custom completers* below)

---

## Arithmetic & Operators

### Integer division returns float (v0.100)

```nushell
# before: 2 / 2 => int
# after:  2 / 2 => float (2.0)
# use // for integer floor division
```

### Floor division promotes to float (v0.100)

```nushell
1 // 1.0 | describe  # => float (was int)
```

### `mod` is now floored, not truncated (v0.100)

```nushell
8 mod -3   # => -1 (was 2)
```

### Float display always includes decimal (v0.106)

```nushell
4 / 2  # => 2.0 (was 2). Affects to csv, to json, to md round-trips
```

### Compound assignment type checking (v0.106)

```nushell
mut x = 1
# $x /= 2  # error: int / int = float, can't assign float to int
```

### New operators

- `like` / `not-like` — aliases for `=~` / `!~` (0.100)
- `has` / `not-has` — reverse-operand `in` / `not-in` (0.102)
- `not-starts-with` — negated starts-with (0.108)
- `not-ends-with` — negated ends-with (0.108)
- `older-than` / `newer-than` — datetime age against a duration (`$d older-than 2wk`) or a datetime (0.117); see `enhancements.md`

```nushell
# has — useful in where clauses
$table | where children has 'e'   # instead of: where ("e" in $it.children)
```

---

## Syntax Changes

### `++` is concatenation only (v0.101)

```nushell
# before: [1 2 3] ++ 4 => [1 2 3 4]
# after:  [1 2 3] ++ [4]  or  [1 2 3] | append 4
```

### `timeit` requires a closure (v0.101)

```nushell
timeit { ls }   # ok
# timeit (ls)   # error
```

### Closure params must be terminated by `|` (v0.100)

```nushell
{|a| $a } # ok
# { |a $a }  # parse error
```

### Stricter command signatures (v0.101)

```nushell
# before: def foo [] -> string { '' }  (silent failure)
# after:  def foo []: any -> string { '' }  (input type required)
```

### `let` at end of pipeline (v0.110)

```nushell
ls | get name | let files    # equivalent to: let files = ls | get name
```

### `let` mid-pipeline pass-through (v0.111)

```nushell
'hello' | let msg | str length  # => 5; $msg = "hello"
```

### `%` sigil for built-in commands (v0.112)

```nushell
def ls [] { echo duck }
ls     # => duck
%ls    # => real ls output
```

### Flags in a dynamic `%$cmd` / `%($cmd)` call reach the builtin (v0.117)

Before, a dynamic call dropped a flag or passed it on as a string.
Now an unquoted flag-like word is a flag, so a flag the builtin does not have is an error; quote the word to pass a string.
`--` is no longer passed on, and a list spread into a command with no rest parameter is an error (0.116 dropped it).
The same holds for `run-external` called this way: `%$cmd echo -la` is now an unknown flag of `run-external`.

```nushell
let cmd = 'sort'
[1 3 2] | %$cmd --reverse        # => [3, 2, 1]   (0.116: [1, 2, 3], the flag was ignored)
let cmd = 'echo'
# %$cmd --foo                    # 0.117: nu::parser::unknown_flag   (0.116: "--foo")
%$cmd '--foo'                    # => --foo
%$cmd -- --foo                   # => --foo   (0.116: [--, --foo])
let cmd = 'first'
# [1 2 3] | %($cmd) ...[2]       # 0.117: Cannot spread a list into this command   (0.116: 1)
```

### `$nu` paths renamed (v0.110)

```nushell
# before: $nu.temp-path / $nu.home-path
# after:  $nu.temp-dir  / $nu.home-dir
```

### `$ans` is a reserved variable name (v0.115)

`$ans` is now a builtin variable, like `$in`, `$nu` and `$env`.
In the REPL it holds a record about the last line (`exit_code`, `duration`, `command`, and `last` for the value when `$env.config.max_last_result_size` is above its `0b` default).
In a script it is `null`.
Any script binding that name breaks at parse time — rename the variable.

```nushell
# before: let ans = 5
# after:  let answer = 5
# error:  nu::parser::name_is_builtin_var — `ans` already a builtin variable
```

### Parser keywords cannot be shadowed (v0.115; `type` since v0.117)

Defining a command whose name is a *parser keyword* (`def`, `let`, `if`, `where`, `use`, `export def`, …) is now `nu::parser::name_is_keyword`.
This covers module exports and `use *` too.
Ordinary built-in commands are still shadowable — that is what the `%` sigil is for.
In 0.117 `type` became a keyword (it declares a type alias, see `enhancements.md`), so a command, alias or extern named `type` now fails the same way; rename it.
On macOS a bare `type ls` no longer runs `/usr/bin/type`; write `^type ls` or `which ls` (release notes only).

```nushell
# def def [] {}                 # error: 'def' is a parser keyword
# def type [] { 'mine' }        # 0.117: Can't use parser keyword `type` as command name   (0.116: defined it)
```

Related: a module named after a keyword may no longer export `main`, because the parser intercepts the call before the module can be reached (`nu::parser::keyword_shadow_module_main`).
Rename the module, or drop `export def main` and import the rest with `use if.nu *`.

### External arguments starting with `{` are parsed as Nushell values (v0.116)

An argument to an external command that begins with `{` is now parsed as a record or a closure, not as a string.
Nushell then fails at run time, because a record or a closure cannot become a string argument.
The common victims are `find -exec ... {}`, `xargs -I {}` and `fd --exec ... {}`.
Quote the braces.
An argument where `{` is not the first character (`--format={a}`, `x{a}`) is unchanged.

```nushell
# before: ^find . -name 'f1.txt' -exec echo found {} ';'
#   0.116: nu::shell::cant_convert — can't convert record to string
^find . -name 'f1.txt' -exec echo found '{}' ';'   # => found ./f1.txt
^echo '{"a":1}'                                      # quote JSON too
```

### `;` is rejected in list literals and `match` list patterns (v0.116)

Before, a `;` inside a list silently cut it: `[1; 2]` gave `[1]`.
Now it is `nu::parser::error` ("Unexpected semicolon in list"), and the same in a `match` list pattern.
The table form `[[a b]; [1 2]]` is unchanged, but a header with no rows, `[[a b];]`, is now a parse error (it used to give the list `[[a, b]]`).

```nushell
# [1; 2]                            # error (0.115: silently [1])
# match $x { [$a; $b] => ... }      # error — use [$a, $b] or [$a $b]
[[a b]; [1 2]]                      # still a table
```

### `take while` / `take until`: a flag after the closure is a parse error (v0.116)

`take while`, `take until`, `skip while`, `skip until` and `chunk-by` now accept a row condition as well as a closure.
The row condition reads everything after it as part of the condition, so a flag written after the closure — or after a `$closure` variable — fails with `Parse mismatch: expected operator`.
Of these commands only `take while` and `take until` have a flag (`--include`); put it before the condition.
A closure or `$closure` variable with nothing after it works as before.

```nushell
# [1 2 3 4 5] | take while {|x| $x < 3 } --include 1   # 0.116: parse error (0.115: [1, 2, 3])
# [1 2 3 4 5] | take while $pred --include 1           # same error
[1 2 3 4 5] | take while --include 1 {|x| $x < 3 }     # => [1, 2, 3]
```

### `not` takes the precedence `help operators` lists (v0.117)

`not` binds looser than a comparison and tighter than `and`/`or`, so `not $a == $b` is `not ($a == $b)`.
Before, `not` took only the next value, and most such lines were a type error.
For two bools the result is the same either way.
It is different, with no error, when a bool is compared with a value of another type.

```nushell
[[name]; [abc] [xyz]] | where not name =~ b   # => [[name]; [xyz]]   (0.116: parse error)
let flag = true
not $flag == 'yes'                            # => true   (0.116: false, read as (not $flag) == 'yes')
not true and false                            # => false  (unchanged)
```

### `-$x` and `-(expr)` negate the value (v0.117)

Before, `-$x` was the string `"-$x"` and `-(2 + 3)` the string `"-5"`, with no error.
This also holds for a flag's value and for an argument after `--`.
Arguments to external commands are unchanged.

```nushell
let x = 5
[-$x] | to nuon         # => [-5]   (0.116: ["-$x"])
[-(2 + 3)] | to nuon    # => [-5]   (0.116: ["-5"])
^echo -$x               # => -$x    (unchanged)
```

### Literals: new parse errors and new values (v0.117)

These are now parse errors; the 0.116 result is in parentheses:

- An int literal above the 64-bit range, `9223372036854775808` (a float); add `.0` to write a float
- A filesize or duration literal that does not fit, `99999999999999999999kb` or `99999999999999999999ns` (the small units `b`, `kb`, `kib`, `ns`, `us` saturated to the maximum; the larger units were already a compile error)
- A word in date form that is not a valid date, `2023-02-29` (ran as an external command)
- `[1 2]]` (`[1, "2]"]`)
- A record or table literal that names a field twice, `{a: 1, a: 2}` (a run-time error, so a branch that never ran passed)
- In `def`: a repeated parameter or flag name, a repeated short flag, a positional parameter after `...rest`, and a `--help` flag (`def --wrapped` may still declare one)
- An assignment to a `mut` variable inside a `where` closure, now `Capture of mutable variable` (the assignment never took effect)
- `$C` after `unlet $C` on a constant: `unlet` hides `$C` for the rest of the block, so a later `$C` is `Variable not found` (`unlet` did nothing)

These now give a different value:

- `INF`, `Nan` and `Infinity` are strings (floats); write `inf`, `nan` or `NaN`
- `-0x10` is `-16` (the string `"-0x10"`), and `+5sec` is a duration (ran as an external command)
- `{true: 1}` is `{"true": 1}` (a parse error)
- `[voilà#tag]` is `["voilà#tag"]`: inside brackets `#` starts a comment only after whitespace (`Unclosed delimiter`)
- `1 in [1.0]` is `true` (a parse error), `2.0 in 1.0..2.0` is `true` (`false`), `[1.0 inf] | math max` is `inf` (`1.0`)

### `alias` cannot hold a pipe or a redirection (v0.117)

`alias q = ls | length` is now `nu::parser::cant_alias_expression`.
Before, Nushell passed `|` and `length` to `ls` as arguments.
Use `def` for a pipeline.

```nushell
# alias q = ls | length      # 0.117: Can't create alias to expression
def q [] { ls | length }
```

### `hide` is block-scoped (v0.117)

`hide` inside `do { }`, `if` or a command body now hides the name only in that block.
Before, the name stayed hidden after the block ended.
This is about custom commands: in a script, `hide` of a builtin hides nothing, on 0.116 and 0.117 alike (`do { hide length; [1 2] | length }` → `2`).

```nushell
def foo [] { 'foo' }
do { hide foo }
foo    # => foo   (0.116: Command `foo` not found)
```

### A module directory with a dot keeps its whole name (v0.117)

For a directory `a.b/` that holds `mod.nu`, `use a.b` now makes the module `a.b`, so its commands are `a.b foo`; before, the module was `a` (`a foo`).
Per the release notes, `overlay use a.b` gives the overlay `a.b`, and a directory `foo.nu/` is the module `foo.nu` (release notes only).

```nushell
use a.b
a.b foo   # 0.116: a foo
```

---

## Type System & Strictness

### Run-time pipeline input type checking (v0.102)

Previously parse-time only.
Now also enforced at run-time through `any`-typed intermediaries.

### `string` ↔ `glob` implicit casting (v0.108)

Strings and globs are subtypes of each other — no more `cant_convert` when passing string to glob param.

### `oneof<...>` type for parameters (v0.105; literals v0.117)

```nushell
def foo [param: oneof<binary, string>] { .. }
```

Since 0.117, `string`, `path`, `directory`, `glob`, `cell-path`, `external_arg` and `any` get a literal only when no other listed type matches it, whatever the order.
So a number goes to `int`, a bracket list to `list<...>`, and the original text is lost: `007` arrives as `7`.
Quote a literal to keep its text.
This also holds for defaults, for `list<oneof<...>>` elements and for `extern` parameters, which pass the converted value to the external.

```nushell
def f [x: oneof<string, int>] { $x | to nuon }
f 5            # => 5     (0.116: "5", a string)
f 007          # => 7     (0.116: "007")
f '007'        # => "007"
def g [x: oneof<string, list<string>>] { $x | describe }
g [foo bar]    # => list<string>   (0.116: string)
```

### `describe` reports `datetime` (v0.104)

```nushell
date now | describe  # => "datetime" (was "date")
```

### `each` passes through `null` (v0.107)

```nushell
# before: null | each { "something" } => "something"
# after:  null | each { "something" } => null
```

### Collecting streams with errors raises immediately (v0.108)

```nushell
# before: errors collected into list<error>
# after:  first error thrown immediately
```

### `length`, `columns`, `is-empty`, `is-not-empty` raise stream errors (v0.116)

Before, these commands ignored an error inside a stream and returned a wrong answer.
Now they raise the error.
A check like `if ($rows | is-empty)` that "worked" may now fail — the error was always there.

```nushell
[[name size]; [a 100b] [b 200b]] | where size <= 150 | length
# before: 2
# after:  nu::shell::operator_incompatible_types (filesize vs int)
```

### `each while` raises errors (v0.116)

Before, an error in the closure stopped `each while` silently, and the partial result looked like a normal early stop.
Now the error is raised.

```nushell
[1 2 3] | each while {|x| if $x == 2 { error make {msg: boom} } else { $x } }
# before: [1]
# after:  error: boom
```

### Semver comparisons type as `bool` (v0.115.1)

`('0.9.0' | into semver) < ('1.0.0' | into semver)` is typed `bool`, so it works with `or`/`and`, in `let` and as a `bool` argument.
Per the 0.115.1 release notes, 0.115.0 rejected these at parse time; drop any workaround written for it.

### Immediate error return on error values (v0.102)

Error values passed as pipeline input or arguments now cause immediate return.

### `pipefail` on by default (v0.111)

`$env.LAST_EXIT_CODE` reflects rightmost non-zero exit in a pipeline.

### Experimental `enforce-runtime-annotations` (v0.108)

Catches type annotation violations at runtime when enabled.

### `enforce-runtime-annotations` on by default (v0.114)

Runtime type checking of `let` annotations is now opt-out.
Scripts whose annotations only "passed" because the value was never checked will start erroring.
Disable if needed:

```nushell
nu --experimental-options '[enforce-runtime-annotations=false]' script.nu   # the flag goes before the script
```

The environment variable `NU_EXPERIMENTAL_OPTIONS="enforce-runtime-annotations=false"` works for an interactive `nu` (source-checked).
A script reads it only together with `--config` or `--env-config`;
`nu --commands` reads it only together with `--config`, `--env-config` or `--login`.
`--no-config-file` turns it off in every mode (`should_disable_experimental_options` in `src/experimental_options.rs`).

### Much stricter parse-time type checking (v0.114)

Several inference improvements move errors from runtime to parse time.
Annotations that previously "seemed fine" may now be rejected — usually they were wrong all along.

- Command output types are inferred from pipeline input type (`"foo" | str uppercase | let x` → `$x` is `string`, not `any`)
- `$in` is typed from the surrounding pipeline (`2 | $in + "foo"` is now a parse error)
- `let` bindings mid-/end-pipeline get the pipeline input type
- Optional params and typed flags *without a default* are now `oneof<T, nothing>`, not `T` — code that assumed `T` may need a `default` value or a null check; a switch (`--verbose` with no type) stays `bool`, `false` when absent
- Inside a `def`, the body is checked against the declared input/output signature (`def foo []: string -> any { accepts-int }` is a parse error)
- `if`/`match` expression output types are unions of branch types; without a fallback branch, `nothing` is included

### Submodules are no longer implicitly imported (v0.114)

`use foo` no longer brings `foo`'s exported sub-modules into scope.
Re-export them explicitly:

```nushell
export module foo {
    export module sub {
        export def baz [] { }
    }
    export use sub    # required in 0.114 to keep `foo sub baz` working
}
```

Note: the explicit `export use` does *not* run the submodule's `export-env` block — same as the old implicit behavior.

### Catch error record: `json` field replaced by `details` (v0.114)

The error record in `catch` blocks no longer has a `json` field.
The new `details` field holds the same data as a structured record — no `from json` step.
Labels additionally carry a `location` record (file name + file-relative `start`/`end` offsets).

```nushell
# before: try { fail } catch {|e| $e.json | from json }
# after:  try { fail } catch {|e| $e.details }
```

### `each`, `par-each` and `items` raise the closure's own error (v0.117)

When the closure fails, `catch` now gets the closure's error, not the wrapper `Eval block failed with pipeline input`.
So `$e.msg` is the closure's message, and `$e.details.code` is its code instead of `nu::shell::eval_block_with_input`.
A `catch` that matched the wrapper no longer matches.

```nushell
try { [1 2] | each {|x| $x / 0 } } catch {|e| $e.msg }            # => Division by zero.   (0.116: Eval block failed with pipeline input)
try { [1 2] | each {|x| $x / 0 } } catch {|e| $e.details.code }   # => nu::shell::division_by_zero
```

### `std/iter scan` signature now matches `reduce` (v0.114)

Initial value moves from positional to `--fold`; `--noinit` is gone — omitting `--fold` seeds with the first element (which stays in the output).

```nushell
# before: [1 2 3] | iter scan 0 {|x, acc| $x + $acc}            # [0 1 3 6]
# after:  [1 2 3] | iter scan --fold 0 {|x, acc| $x + $acc}     # [0 1 3 6]

# before: [1 2 3] | iter scan 0 --noinit {|x, acc| $x + $acc}   # [1 3 6]
# after:  [1 2 3] | iter scan --fold 0 {|x, acc| $x + $acc} | skip 1
# (plain `iter scan {|x, acc| ...}` seeds with the first element instead)
```

### `std/iter find-index` returns `null` on no match (v0.114)

Was `-1`.
Update sentinel checks: `if $idx == -1` → `if $idx == null`.

### `--` ends flag parsing (v0.114)

POSIX-style end-of-options for built-in and custom commands: everything after `--` is positional, even if it starts with `-`.
The `--` itself is consumed — to pass a literal `--` as a value, write it twice (`cmd -- --`).
For `def --wrapped` and `extern` commands, `--` is still passed through unchanged.

```nushell
def greet [--upper name] { if $upper { $name | str uppercase } else { $name } }
greet -- -Alice   # "-Alice" is a positional value, not an unknown flag
```

### Closure calls count toward `recursion_limit` (v0.117)

`do`, `each`, `where` and other closure calls (per the release notes, hooks too) now count toward `$env.config.recursion_limit` (default `50`), like command calls.
A command that calls itself from inside a closure uses two levels per call, so with the default it stops at depth 25.
Endless closure recursion is now `nu::shell::recursion_limit_reached`; 0.116 crashed with a stack overflow.

```nushell
def r [n: int] { if $n == 0 { 'ok' } else { do { r ($n - 1) } } }
r 24   # => ok
r 25   # error: nu::shell::recursion_limit_reached   (0.116: ok)
$env.config.recursion_limit = 200   # raise it for deeper recursion
```

### `save` checks the input type of a custom `to <ext>` command (v0.117)

When the input type of a custom `to <ext>` command does not cover the data, `save` now fails with `Input type not supported`.
Before, `save` ran the converter anyway.
Per the release notes, built-in `to` commands reject the same input as before, now with `Input type not supported` as the message (release notes only).

```nushell
def 'to foo' []: int -> string { 'x' }
# {a: 1} | save out.foo   # 0.117: Input type not supported   (0.116: wrote "x")
```

---

## Command Behavior Changes

### `find` is case-sensitive by default (v0.107)

```nushell
[Foo bar] | find foo                  # no match
[Foo bar] | find --ignore-case foo    # matches "Foo"
```

### Cell-paths are case-sensitive by default (v0.105)

```nushell
$record | get Content-Type     # exact match required
$record | get Content-Type!    # case-insensitive (! suffix)
# $env remains always case-insensitive
```

### `split list` keeps empty sublists (v0.103)

```nushell
[1 0 0 3] | split list 0  # => [[1] [] [3]]  (was [[1] [3]])
```

### `match` no longer executes returned closures (v0.103)

```nushell
match 1 { _ => {|| print hi } } # returns closure (was: executed it)
```

### `split column` uses 0-indexed names (v0.109)

```nushell
'a b c' | split column ' '  # columns: column0, column1, column2 (was 1-indexed)
```

### `url parse` params is a table (v0.100)

```nushell
# before: params was a record {a: 1, b: 2}
# after:  params is a table [[key, value]; [a, "1"], [b, "2"]]  (values stay strings)
```

### `overlay list` returns table (v0.107)

```nushell
# before: overlay list | last => "name"
# after:  overlay list | last | get name => "name"
```

### `http --max-time` takes duration (v0.100)

```nushell
http get --max-time 30sec $url   # was: --max-time 30
```

### `format filesize` is case-sensitive (v0.102)

```nushell
1000b | format filesize kB    # => 1 kB (metric)
1000b | format filesize KiB   # => 0.97 KiB (binary)
```

### `format bits` outputs big endian (v0.107)

```nushell
# Use --endian native to restore old (pre-0.107) behavior
258 | format bits --endian native
```

### `parse` unmatched groups return `null` (v0.106)

```nushell
# before: unmatched optional capture group => ""
# after:  => null
```

### `rm`/`mv`/`cp`/`du` dotfile handling (v0.110, v0.117)

Since 0.110, `*` in `mv`, `cp` and `du` does not match dotfiles, and 0.116 `rm *` skips them too; `--all` includes them.
Since 0.117 these four commands also skip files inside a hidden directory that a glob reaches: `rm **/*.txt` keeps `.hid/x.txt`, which 0.116 removed.
A pattern whose own component starts with `.` still matches it (`rm .*.txt`, `rm .hid/*.txt`).
`ls` and `glob` are unchanged: `glob **/*.txt` still lists `.hid/x.txt`.

```nushell
cp --all * /tmp            # include dotfiles
rm **/*.txt                # 0.117: skips .hid/x.txt   (0.116: removed it)
rm --all **/*.txt          # also inside hidden directories
```

With the experimental `dc-glob` option, 0.117 gives these commands the same rules: before, `rm *` removed dotfiles there.
Per the release notes, `dc-glob` also changes `**`, `{a,b}` and malformed patterns (release notes only).

### `open *.md` returns structured data (v0.112)

```nushell
# before: open file.md => raw string
# after:  open file.md => parsed AST (from md)
open --raw file.md   # for raw string
```

### `from md` default output is concise rows (v0.113)

```nushell
# before (0.112): open file.md => full AST (type, position, attrs, children)
# after  (0.113): open file.md => concise human-friendly rows
open file.md --raw | from md --verbose   # full AST as before
```

### `parse` no longer auto-splits streams (v0.113)

Byte/string streams — from an external process or from a file (`open app.log`) — are no longer implicitly split by lines before `parse`.
Pipe through `lines` first.

```nushell
# file.log holds "INFO one\nWARN two"
^cat file.log | parse '{level} {msg}'           # => one row, msg: "one\nWARN two"
^cat file.log | lines | parse '{level} {msg}'   # => [[level, msg]; [INFO, one], [WARN, two]]
```

### `kill -0` no longer accepted as shorthand (v0.113)

`kill -0` used to send signal 0 but now errors (was also a footgun — could terminate nushell itself).
Use the long form.

```nushell
# before: kill -0 1234
# after:  kill --signal 0 1234   # signal 0 = check if process exists
# same for: kill -9 pid => kill --signal 9 pid
```

### `mkdir --verbose` / `mv --verbose` / `rm --verbose` return tables (v0.113)

Verbose flags now return queryable structured tables instead of human text.
Scripts that parsed the text output need to consume the table columns.

One row per argument, with the absolute path.
Since 0.116, a directory that already existed reports `created: false` (it was `true`).

```nushell
mkdir --verbose a/b/c
# => [[path, created, error]; ["/abs/a/b/c", true, null]]

mv --verbose src dst   # columns: source, destination, message
rm --verbose old.txt   # columns: path, deleted, error
```

### `to yaml` quoting changed in 0.113.0 and 0.113.1 (superseded)

Up to 0.112 `to yaml` wrote `off` without quotes (release notes only).
0.113.0 (#18010) quoted every string;
0.113.1 (#18298, repeated in the 0.114 notes) quoted only strings YAML would read as something else, like `off`, and left `/dev/stdout` plain (release notes only).
The 0.115 rework (next entry) replaced both, so compare YAML text against 0.115+ output only.

### YAML reworked — `from yaml` defaults to YAML 1.2 (v0.115)

The old `serde_yaml` backend is gone.
Nushell no longer parses YAML as a mix of the 1.1 and 1.2 specs; `from yaml` is YAML 1.2 now.
Pass `--spec 1.1` to get the old scalar magic back.

```nushell
'yes'       | from yaml             # => "yes" (string; was true)
'yes'       | from yaml --spec 1.1  # => true
'0247'      | from yaml             # => 247 (leading zero is just a zero)
'0247'      | from yaml --spec 1.1  # => 167 (octal 0o247)
'190:20:30' | from yaml             # => "190:20:30" (string)
'190:20:30' | from yaml --spec 1.1  # => 685230 (sexagesimal)
```

Mapping keys are stricter: a plain key that resolves to a bool, number or null is rejected, because Nushell record keys are strings.
Pass `--key-resolution verbatim` to keep the original key text instead.

```nushell
# 'true: enabled' | from yaml                          # error: Found unsupported key
'true: enabled' | from yaml --key-resolution verbatim  # => {"true": enabled}
```

Tags are real now: an unknown tag errors instead of being silently dropped.
`--ignore-tags` restores the old "treat it as a plain scalar" behavior.

```nushell
# 'Key: !Sub ${AWS::StackName}' | from yaml               # error: Unknown tag
'Key: !Sub ${AWS::StackName}' | from yaml --ignore-tags   # => {Key: "${AWS::StackName}"}
```

`to yaml` errors on values that cannot round-trip (closures, etc.) instead of mangling them.
Choose the fallback explicitly: `--non-roundtrip null` writes `null`, `--serialize` writes a lossy string form.
Since 0.116 a bare `null` works as well as the string `"null"` (in 0.115 only the string did).
`--non-roundtrip lossy` is listed in the error text but rejected with `Incompatible parameters` in 0.115 and 0.116, unless `--serialize` is also given — and then it changes nothing, so use `--serialize`.

```nushell
# {|| $in } | to yaml                     # error: Found non-roundtrippable closure
{|| $in } | to yaml --non-roundtrip 'null'  # => null (a bare null works only since 0.116)
{|| $in } | to yaml --serialize          # => !closure "{|| $in }"
```

Emitted YAML also looks different — quoting follows 1.2 rules and Nushell types get local tags (`!filesize`, `!cell-path`).
Scripts that compare YAML text need rechecking.

```nushell
{b: 'off'} | to yaml             # => b: off      (bare; 0.113/0.114 quoted it)
{b: 'off'} | to yaml --spec 1.1  # => b: "off"
```

In 0.116 the list style flag changed: `--compact-list-indent` is gone (compact was already the default), and `--list-indent indented` gives the other style.

```nushell
{a: [1 2]} | to yaml                         # => "a:\n- 1\n- 2\n"
{a: [1 2]} | to yaml --list-indent indented  # => "a:\n  - 1\n  - 2\n"
```

Also new (not breaking): multi-document streams (`--multiple auto|list|single` on read, `--multiple` on write), working anchors/aliases/merge keys, and `--indent` / `--quote` / `--add-directives` for output shape.

### `from kdl` / `to kdl` default formats changed (v0.115)

`from kdl` now defaults to `--format nodes` — a table of `name`, `args`, `props`, `children` rows.
`to kdl` defaults to `--format jik` (JSON-in-KDL), emitting one top-level `-` node.
This replaces the old heuristic that flattened values under synthetic node names like `root`, so any script that read or wrote those names needs updating.

```nushell
{a: 1, b: true} | to kdl                # => - a=1 b=#true
'node one; node two' | from kdl | to nuon
# => [[name, args, props, children]; [node, [one], {}, []], [node, [two], {}, []]]
```

Both commands also take `--spec 1` or `--spec 2` (default `2`).
Parsing is strict per spec: v1 keywords (`true`/`false`/`null`) and v2 keywords (`#true`/`#false`/`#null`) cannot be mixed.

```nushell
{a: 1, b: true} | to kdl --spec 1   # => - a=1 b=true
```

### `from xlsx` / `from ods` reworked (v0.114)

- Signatures corrected: they return a *record* with one table per sheet (the old signature claimed `table`); `from ods` input is `binary`, not `string`
- 0.113's `--header-row` flag is removed.
  New flags: `--noheaders` (same as the csv/tsv flag) and `--first-row $n` (start reading at row *n*; `--first-row 0` keeps leading empty rows that are otherwise skipped)
- `datetime` import now works for ods too, and more datetime formats parse
- Values that can't be coerced now import as `string`/`float` instead of `null`
- New `--prefer-integers` imports whole-number floats as `int`

### Float ranges use fractional steps (v0.114)

`0.1..0.3` now yields `[0.1 0.2 0.3]` (was just `[0.1]` — step defaulted to 1).
Values are rounded to the step's precision, removing artifacts like `0.30000000000000004`.

### Empty `{}` row condition parses as closure (v0.114)

`1..3 | where {}` was "expected bool, found record" — now `{}` in row-condition position is an empty closure (returns nothing → empty result).

### `is-terminal` defaults to `--stdout` and detects redirection (v0.114)

`is-terminal | $in`, `let x = (is-terminal)`, and `is-terminal o> file` now correctly report `false` where they previously reported the terminal state.

### `to csv` / `to tsv` now stream and fail on schema drift (v0.113)

Rows are written as they arrive instead of buffered.
If a later row of a *stream* (for example the output of `each`) introduces a new column, the export errors mid-stream: "streamed csv schema changed".
A list that is already collected (a literal, a variable) still gets the union of columns.

```nushell
# fix 1: declare columns up front
$rows | to csv --columns [a b c]
# fix 2: collect first when the schema is variable
$rows | collect | to csv
```

### `ls` no longer sets `source` metadata (v0.113)

Paired with the `metadata set --datasource-ls` removal.
Code that inspected `$result | metadata | get source` and matched `"ls"` needs another signal.

### `into datetime` and relative dates (v0.104, v0.117)

0.104 moved human strings such as `next Friday` from `into datetime` to `date from-human`.
Since 0.117 `into datetime` reads them again.
`format date`, `date humanize` and `date to-timezone` read the same strings.
These commands also read `@<unix seconds>`, ISO week dates, ordinal dates, `+ N days` and IANA zone names.
0.116 rejected all of these with `Unable to parse datetime`.

```nushell
'@1745000000' | into datetime                              # => 2025-04-18T18:13:20+00:00
'2025-W16-5' | into datetime | format date '%F'            # => 2025-04-18
'2025-108' | into datetime | format date '%F'              # => 2025-04-18
'2025-04-18 + 2 days' | into datetime | format date '%F'   # => 2025-04-20
'2025-04-18 04:04:32 America/New_York' | into datetime     # => 2025-04-18T04:04:32-04:00
```

Relative words in `into datetime` follow GNU `date -d`, not `date from-human`:

- A weekday (`next friday`) is at midnight; `date from-human` keeps the current time of day
- A bare unit is one unit from now: `'week' | into datetime` works, while `'week' | date from-human` is `Incorrect value.`
- `in 2 days` reads only with `date from-human`

Some strings changed value or stopped parsing:

```nushell
'1/1/70' | into datetime | format date '%Y'   # => 1970   (0.116: 2070); two-digit years now map to 1969-2068
'-0500' | into datetime                       # => 1969-12-31T23:59:59.999999500+00:00, nanoseconds   (0.116: the year 500)
# '2025-02-30' | into datetime                # 0.117: error   (0.116: 2025-02-28)
# '3.14' | into datetime                      # 0.117: error   (0.116: a date in the year 3)
```

`detect type` reads none of the new forms: it calls the date parser only for strings that look like `Y-M-D`, `D-M-Y` or `M-D-Y` (source-checked), so `'@1745000000' | detect type` stays a string.

### `to md` formats lists as unordered (v0.110)

```nushell
[a b c] | to md             # => "* a\n* b\n* c"
[a b c] | to md --list none # old behavior
```

### `str join` datetime formatting (v0.104)

Datetime values now format as RFC2822/RFC3339.
Use `format date` first for custom format.

### `http post` sends pretty JSON (v0.107)

Body size increased.
Use `to json --raw` before piping if compact JSON needed.

### Where `mktemp` creates things (v0.111, v0.116)

- No template: in the temp dir (v0.111), for files and `--directory` alike
- A template: in the current directory — since 0.116 also with `--directory` (it went to the temp dir before)
- `--tmpdir` puts a templated file or directory in the temp dir

```nushell
mktemp --directory mydir.XXX            # => $env.PWD/mydir.OjL, an absolute path (0.115: /tmp/mydir.OjL)
mktemp --directory --tmpdir mydir.XXX   # => /tmp/mydir.Df1
```

### `default` column arguments are cell paths (v0.116)

A dotted argument now names a nested field, and missing records on the way are created.
Quote it to target a key that really contains a dot.

```nushell
{} | default 5 a.b              # => {a: {b: 5}}   (0.115: {"a.b": 5})
{a: {c: 1}} | default 5 a.b     # => {a: {c: 1, b: 5}}
{} | default 5 'a.b'            # => {"a.b": 5}
```

### `lines --skip-empty` works on strings and byte streams (v0.116)

Before, the flag only worked on list input; on a string or an external's output it did nothing.
Now it drops empty and whitespace-only lines for every input.

```nushell
"foo\n\n  \nbar" | lines --skip-empty   # => [foo, bar]   (0.115: [foo, "", "  ", bar])
```

### `format pattern` / `parse` reject an unclosed `{` (v0.116)

A pattern with a `{` that has no matching `}` used to succeed and drop the brace; now it is `nu::shell::delimiter_error`.
Write `{{` for a literal brace in `format pattern`.
A lone `}` in `parse` is still a literal character, and `parse --regex` is unchanged.

```nushell
# {} | format pattern 'x{'        # error (0.115: "x")
# "hello " | parse "hello {"      # error (0.115: one empty row)
{a: 1} | format pattern '{{a}} = {a}'   # => "{a} = 1"
```

### `flatten` keeps a nested field that clashes with a top-level column (v0.116)

When a top-level column came after a nested record field with the same name, `flatten` silently dropped the nested one.
Now the nested field is renamed to `<parent>_<field>`, the same as it already was for the other order.

```nushell
{a: {b: 1}, b: 2} | flatten   # => [[a_b, b]; [1, 2]]   (0.115: [[b]; [2]])
```

### `into float` reads a comma as the decimal separator (v0.116)

This used to be an error; now it converts.
A thousands separator is read as a decimal point, so `"1,500"` becomes `1.5` with no error — while `into int` still reads it as `1500`.
Strip separators before converting numbers written with them.

```nushell
'1,5'   | into float    # => 1.5   (0.115: error)
'1,500' | into float    # => 1.5   (!)
'1,500' | into int      # => 1500
'1,500' | str replace --all ',' '' | into float   # => 1500.0
```

### `print` fails after a failing external (v0.117)

When `^cmd` fails, `^cmd | print` now fails with the exit code of `^cmd`, as `^cmd | collect` already did.
A script stops there, and nothing is written to stderr.
Before, `print` hid the failure, and the script went on.
`do --ignore-errors { ^cmd } | print` fails too.

```nushell
^false | print; print after                   # prints nothing, exit code 1   (0.116: prints "after", exit code 0)
^sh -c 'exit 3' | print                       # exit code 3
try { ^false | print } catch {|e| $e.msg }    # => External command had a non-zero exit code   (0.116: no error)
^false | ignore; print after                  # prints "after": ignore still drops the failure
^sh -c 'echo hi; exit 3' | complete | get stdout | print   # prints "hi" whatever the exit code
```

### `group-by --to-table` keeps the type of the key (v0.117)

The group column now holds the original value with its type, not its display string.
Values that print the same are now separate groups (`1MB` and `1.001MB`, `true` and `"true"`).
A string compare against the key now matches nothing, with no error.
Plain `group-by`, which returns a record, is unchanged: its keys are strings.

```nushell
[{n: 1} {n: 2} {n: 1}] | group-by n --to-table | get n                      # => [1, 2]   (0.116: ["1", "2"])
[{n: 1} {n: 2} {n: 1}] | group-by n --to-table | where n == '1' | length    # => 0   (0.116: 1)
[[size]; [1MB] [1.001MB]] | group-by size --to-table | length               # => 2   (0.116: 1)
```

### `math <op> <column>` on a table reduces the column (v0.117)

`math sum`, `avg`, `product`, `max`, `min`, `median`, `mode`, `stddev` and `variance` with column arguments now reduce those columns over all rows and return one record, as `select <columns> | math <op>` does.
Before, the operation ran on each cell of the column alone and returned the table: a number came back as itself (`avg` gave `1.0`, `stddev` gave `0.0`), and a list was reduced.
That per-row form is now an error on a column of lists, so write `update <column> { math <op> }`.
Record input is unchanged.

```nushell
[[a b]; [1 10] [2 20]] | math sum a              # => {a: 3}   (0.116: the table unchanged)
[[a b]; [1 10] [2 20]] | math max a b            # => {a: 2, b: 20}
# [[a]; [[1 2]] [[3 4]]] | math sum a            # 0.117: Input type not supported   (0.116: [[a]; [3], [7]])
[[a]; [[1 2]] [[3 4]]] | update a { math sum }   # => [[a]; [3], [7]]
```

### `ps` has the same columns on every platform (v0.117)

- `ps`: `pid ppid name user status cpu cpu_time mem` — `user` and `cpu_time` are new here, and `virtual` moved to `ps --long`
- `ps --long` adds `virtual private command exe start_time user_id process_group_id session_id priority nice threads read written cwd environment`
- `process_threads` → `threads`; `working` and `paged` are gone (`private` is the memory that only the process uses)
- On Windows `user_sid` → `user_id` (release notes only)
- A value that the platform or the process does not give is `null`; macOS and Windows now list processes they used to leave out (release notes only)

The columns above were checked on Linux.
`=~` on a `null` is an error, so drop the nulls first:

```nushell
# ps --long | where cwd =~ tmp            # 0.117: The '=~' operator does not work on values of type 'nothing'
ps --long | compact cwd | where cwd =~ tmp
ps | compact cpu | sort-by cpu | last 3
```

### `load-env`, `with-env` and `FOO=bar cmd` apply `ENV_CONVERSIONS` (v0.117)

A string `PATH` set this way now becomes a list, as at startup.
`--no-convert` sets the values as given.
Per the release notes, these commands can now set `$env.config`, and they reject `PWD` in any letter case (release notes only).

```nushell
load-env {PATH: '/x:/y'}; $env.PATH | describe               # => list<string>   (0.116: string)
PATH='/x:/y' do { $env.PATH | describe }                      # => list<string>   (0.116: string)
load-env --no-convert {PATH: '/x:/y'}; $env.PATH | describe   # => string
```

### `open .env` parses the file as dotenv (v0.117)

`open` on `.env`, `.env.local` and names like `prod.env` now returns a record of the `KEY=value` lines; 0.116 returned the text.
Such a file that is not `KEY=value` lines, for example an autoenv shell script, now fails with `Error while parsing as dotenv`; read it with `open --raw`.
`open .env | load-env` loads the variables; `from dotenv` is in `enhancements.md`.
`save` now matches the extension in any letter case: `{a: 1} | save data.JSON` writes JSON (0.116: `Unsupported input`).

```nushell
# .env holds the lines FOO=bar and PATH=/a:/b
open .env                # => {FOO: bar, PATH: "/a:/b"}   (0.116: the text)
open --raw .env.local    # the text, whatever the file holds
```

### `join` errors when no row has the join column (v0.117)

`join` now fails with `column_not_found` when the input or the right table has rows but none of them has the join column.
Before, a misspelled column name gave an empty result.
Per the release notes, an empty table, or one where only some rows lack the column, behaves as before (release notes only).

```nushell
# [[a b]; [1 2] [3 4]] | join [[a c]; [1 3] [4 5]] d   # 0.117: Cannot find column 'd'   (0.116: [])
```

### `query db` reports SQLite errors (v0.117)

A failed statement, such as a `NOT NULL` or `UNIQUE` violation, is now an error; 0.116 returned an empty list.
Per the release notes, a query that fails partway is an error instead of partial rows, and so is a failing table when `open` reads a database (release notes only).

```nushell
stor open | query db 'CREATE TABLE u (a INTEGER NOT NULL)'
# stor open | query db 'INSERT INTO u (a) VALUES (NULL)'   # 0.117: Failed to query SQLite database   (0.116: [])
```

### `update cells` raises errors from its closure (v0.117)

Before, an error in the closure became the cell value, and nothing failed until a command read that cell.

```nushell
# [[a b]; [1 x]] | update cells { $in * 10 } | get 0.a               # 0.117: error, '*' on a string   (0.116: 10)
[[a b]; [1 x]] | update cells { try { $in * 10 } catch { null } }    # => [[a, b]; [10, null]]
```

### Duplicate column names and unknown alignments are errors (v0.117)

`split column` with a repeated name, and `rename` to a name that already exists, now fail with `column_defined_twice`.
Before, they made a table with two columns of one name.
`fill --alignment` with an unknown value is now `invalid_value`; before, it aligned left.

```nushell
# 'a b' | split column ' ' x x               # 0.117: column_defined_twice   (0.116: [{x: a, x: b}])
# [[a b]; [1 2]] | rename --column {a: b}    # 0.117: column_defined_twice   (0.116: [{b: 1, b: 2}])
```

### `detect type` leaves padded strings alone (v0.117)

```nushell
' 42' | detect type          # => " 42"   (0.116: Can't convert to int)
'+42' | detect type          # => 42      (0.116: "+42")
'2025-02-30' | detect type   # => "2025-02-30"   (0.116: 2025-02-28)
```

### `du` counts a hard-linked file once (v0.117)

`du a b c` on three hard links to one file returns one row, for the first link; 0.116 returned three.
Per the release notes, `ls --du` also counts such a file once in each listed directory (release notes only).

### `run` keeps a script's definitions inside it (v0.117)

After `run s.nu`, the commands and constants of `s.nu` are no longer defined in the caller (on 0.116 a `let` leaked only its name: reading it failed at run time).
`run` also rejects arguments that `main` does not accept; see the `run` section of `enhancements.md`.

```nushell
run s.nu; helper   # 0.117: Command `helper` not found   (0.116: ran helper from s.nu)
```

---

## New Commands & Idioms

### Replace old patterns

- `"next Friday" | into datetime` → `"next Friday" | date from-human` — 0.104 to 0.116 only; since 0.117 both read it, with different rules (see *`into datetime` and relative dates*)
- `"123" | into value` → `"123" | detect type` — 0.108
- `$table | into value` → `$table | update cells { detect type }` — 0.108
- `$data | filter $f` → `$data | where $f` — 0.105; `filter` is removed in 0.117
- `{ || } | to json` → `{ || } | to json --serialize` — 0.103
- `get --ignore-errors key` → `get --optional key` — 0.106; `--ignore-errors` is removed in 0.117
- manual external completer match → `@complete fish-completer; extern git []` — 0.108
- `def foo [x: string@completer_fn]` → `def foo [x: string@[a b c]]` (inline) — 0.108
- `find ... | result` → `find --no-highlight ...` (strip ANSI) — 0.102
- manual `http get --full | get headers` → `http get url | metadata | get http_response` — 0.108
- `^find . -exec cmd {} ';'` → `^find . -exec cmd '{}' ';'` (quote a leading `{` for externals) — 0.116
- `def comp [context: string, pos: int]` → `def comp [place: record]` (`$place.command`, `$place.cursor`) — 0.116
- `def comp [spans]` / external `{|spans| ...}` → `[place: record]` / `{|place| ...}` (`$place.command`) — 0.116
- `to yaml --compact-list-indent` → `to yaml` — 0.116
- `take while {|x| ...} --include 1` → `take while --include 1 {|x| ...}` (flag before the condition; same for `take until`) — 0.116
- `default 0 a.b` meant as a key with a dot → `default 0 "a.b"` (unquoted is now a nested path) — 0.116
- `update cells -c [a b] { ... }` → `update cells { ... } a b` — 0.117
- `alias q = ls | length` → `def q [] { ls | length }` — 0.117
- `$env.config.keybindings = [...]` (meant to add) → `$env.config.keybindings ++= [...]`; same for `menus` — 0.117
- `$t | math sum col` on a column of lists (per row) → `$t | update col { math sum }` — 0.117
- `^cmd | print` that must survive a failing `^cmd` → `^cmd | complete | get stdout | print` — 0.117
- `open .env` for the text of a non-dotenv file → `open --raw .env` — 0.117

### Background jobs (v0.103, experimental)

```nushell
job spawn { long-task }
job list
job kill $id
```

### Custom command attributes (v0.103+)

```nushell
@example 'double 2' { 2 | double } --result 4
@deprecated 'Use new-cmd' --since '0.105.0'
@search-terms math multiply
@category 'math'
@test
def 'test add' [] { assert equal (1 + 1) 2 }
```

### `parse` with `_` placeholder (v0.105)

```nushell
'hello world' | parse '{word} {_}'   # ignores second field
```

### `default --empty` (v0.103)

Returns default for empty strings/lists/records/binary, not just null.

### `try..catch..finally` (v0.111; semantics fixed v0.116; externals v0.117)

```nushell
try { risky } catch { handle } finally { cleanup }
```

Since 0.116, `finally` runs however the `try` is left, and the rest follows from that:

- An error with no `catch` runs `finally`, then propagates — the statements after the `try` no longer run (0.115 ran them)
- An error caught by an *outer* `try` runs every `finally` in between, innermost first (0.115 skipped them)
- `break` and `continue` run `finally` before the loop moves on (0.115 skipped it)
- An error raised inside `finally` replaces the original error
- `finally` receives a value as `$in` and as its optional parameter (`finally {|x| ... }`): the result of `try`/`catch` on success, the error record on an uncaught error, `nothing` after `return`, `exit`, `break` or `continue`
- The result of the whole expression is the `try`/`catch` value; the value of `finally` is dropped

```nushell
def g [] {
    try { error make {msg: boom} } finally { print 'cleanup' }
    print 'after'   # 0.115 printed this; 0.116 does not
}
try { g } catch {|e| $e.msg }           # prints "cleanup", => boom
try { 42 } finally {|x| print $x }      # prints 42, => 42
```

0.117 changes how `try` treats an external command; *`try` with external commands* in `enhancements.md` has the details:

- With no `catch` and no `finally`, `try` passes the external's output on and ignores its failure
- With `catch`, the commands after a failing external inside `try` process its output before `catch` runs; put `collect` right after the external to check its exit code first
- After `try ... finally`, the next command gets the stdout and stderr of an external that succeeds, so `complete` and `save --stderr` work (0.116: internal error); a failing external still fails the pipeline, since there is no `catch`

```nushell
try { ^sh -c 'exit 3' } | complete     # => {stdout: "", stderr: "", exit_code: 3}   (0.116: Complete only works with external commands)
try { ^sh -c 'echo notnum; exit 3' | lines | each { into int } } catch {|e| $e.msg }             # => Can't convert to int.   (0.116: External command had a non-zero exit code)
try { ^sh -c 'echo notnum; exit 3' | collect | lines | each { into int } } catch {|e| $e.msg }   # => External command had a non-zero exit code
```

### `timeit --output` (v0.110)

```nushell
timeit --output { 'text' }  # => {time: ..., output: text}
```

### `str escape-regex` (v0.112)

```nushell
'.*' | str escape-regex  # => "\.\*"
```

### `into duration` parses hh:mm:ss (v0.112)

```nushell
'16:59:58' | into duration  # => 16hr 59min 58sec
```

### Spread `null` as empty (v0.107)

```nushell
[1 2 ...(null)] == [1 2]   # true
{a: 1 ...(null)} == {a: 1} # true
```

### `source null` / `use null` for conditional sourcing (v0.102)

```nushell
const file = if ($file | path exists) { $file } else { null }
source $file
```

### `http` auto-detects verb (v0.106)

```nushell
http https://example.com             # GET (no body)
http https://example.com {data: 1}   # POST (has body)
```

### `http` auto-prepends scheme (v0.105)

```nushell
http get example.com    # => http://example.com
http get :8000          # => http://localhost:8000
```

---

## Configuration Changes

### Filesize config restructured (v0.102)

```nushell
# before:
$env.config.filesize.format = 'auto'
$env.config.filesize.metric = true

# after:
$env.config.filesize.unit = 'metric'   # or "binary", "kB", "KiB", etc.
$env.config.filesize.precision = 1     # decimal places, or null
```

### Startup config overhaul (v0.101)

- `default_env.nu` / `default_config.nu` always loaded before user files
- `$env.config` always exists at startup with defaults
- `const NU_LIB_DIRS` replaces `$env.NU_LIB_DIRS`
- `const NU_PLUGIN_DIRS` replaces `$env.NU_PLUGIN_DIRS`
- PATH conversion handled internally — remove `ENV_CONVERSIONS` for PATH
- Hooks fields are non-optional, default to `[]` or `{}`
- User autoload: `($nu.default-config-dir)/autoload/*.nu` sourced at startup (v0.102)

### Assigning `$env.config.keybindings` or `$env.config.menus` replaces the list (v0.117)

`$env.config.keybindings = [...]` and `$env.config.menus = [...]` now replace the whole list, the defaults included.
The defaults hold the menus and keys for Tab completion, the history menu (Ctrl+R) and F1 help, so a config that assigns either list loses them.
Before, Nushell merged the new list into the defaults.
Add with `++=`; `config default` (new in 0.117, so a config that calls it does not parse on 0.116) returns the default config, so `(config default).keybindings` starts the list again from the defaults.
Per the release notes, the same holds for `keybindings` or `menus` set inside `$env.config = {...}` (release notes only).

```nushell
$env.config.keybindings = [{name: my_binding, modifier: control, keycode: char_t, mode: emacs, event: {send: clearscreen}}]
$env.config.keybindings | length                          # => 1   (0.116: 9, the 8 defaults and the new one)
$env.config.keybindings = (config default).keybindings    # back to the 8 defaults
$env.config.keybindings ++= [{name: my_binding, modifier: control, keycode: char_t, mode: emacs, event: {send: clearscreen}}]
```

An entry that Nushell cannot read is now rejected when it is assigned (`Encountered 1 error(s) when updating config`), and the old list stays.
In `config.nu` the lines after the rejected assignment do not run, and `nu --config <file> --commands '...'` exits with code 1 without running the command.
Before, the entry was accepted and the rest of the file ran.

### `PROMPT_*` not inherited (v0.103)

`PROMPT_COMMAND` etc. from parent process are ignored.

### Unified custom completers (v0.116)

Every completer — a parameter completer, `@complete`, the external completer and a menu `source` — now gets its input by the *names* of its parameters: `token`, `place`, `buffer`, in any order.
The old positional forms of parameter and command completers still run for now, with a `nu::shell::deprecated` warning; the bridge will be removed.
Migrate:

- `def comp [context: string, pos: int]` → `def comp [place: record]`: the old `context` was the current command's text, which is `$place.command` (not `$buffer`, which is the line up to the cursor, including what stands before a `|`); `$place.command` is a list of words, not a string; `$place.cursor` replaces `pos`
- `def comp [spans]` and external `{|spans| ...}` → `[place: record]` / `{|place| ...}`; `$place.command` is the old `spans`
- menu `source: {|buffer, position| ...}` → `{|token| ...}`, `{|place| ...}` or `{|buffer| ...}`

The `background-completions` experimental option (added in 0.115.1) is gone: `nu --experimental-options '[background-completions=false]'` now fails at startup with "Invalid value".
A completer that needs the terminal (`fzf`, `input list`) gets `@interactive` on its `def` instead.
`'git checkout mai' | commandline complete --input` shows the record a completer would receive.
The full model — outputs, `fallback`, options — is in the `nushell-completions` skill.

### Completion config changes

- Custom completer `sort: true` uses `$env.config.completions.sort` (was alphabetical) — 0.101
- Missing `sort` field defaults to `true` (was `false`) — 0.101
- Custom completer `case_sensitive` inherits from config (was `true`) — 0.102
- External completers no longer used for internal commands — 0.103
- `positional: false` in a completer's `options` → `completion_algorithm: "substring"` — removed 0.117 (deprecated 0.104).
  A completer that still returns `positional: false` gets no warning and prefix matching, where 0.116 gave substring matching; with `$env.config.completions.algorithm` set, it gets that algorithm (source-checked)
- `$env.config.completions.algorithm = "substring"` option — 0.104
- External completer fallback requires `null` return (not any invalid value) — 0.102

### `display_output` hook (v0.101)

If set, solely responsible for formatting — `table` no longer runs on top.
Set to `null` for default `table` behavior.

### Hook execution order changed (v0.107)

`env_change` → `pre_prompt` → `PROMPT_COMMAND` (was: `pre_prompt` first).

### EditCommand renames (v0.108)

`cutinside` → `cutinsidepair`, `yankinside` → `copyinsidepair` in keybinding config.

### Env var names case-insensitive (v0.111)

All `$env` lookups are case-insensitive on all OSes.

### History config fields locked after REPL start (v0.113)

These fields are read once at startup by reedline; setting them from the REPL is now a hard error instead of silently ignored.
Set them in `config.nu` (or via `--config` / env vars) and restart.

```nushell
# locked: error if assigned from REPL
$env.config.history.path
$env.config.history.max_size
$env.config.history.file_format
$env.config.history.isolation

# still mutable from REPL — re-read every prompt
$env.config.history.sync_on_enter
$env.config.history.ignore_space_prefixed
```
