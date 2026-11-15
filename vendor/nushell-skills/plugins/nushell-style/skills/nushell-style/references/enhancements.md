# New Nushell Features for Better Scripts (0.100 → 0.117)

Modern idioms and new capabilities to improve existing Nushell code.
Version noted as `(v0.NNN)`.

---

## Pipeline Flow

### `let` at end of pipeline (v0.110)

```nushell
# before
let files = ls | get name
# after
ls | get name | let files
```

### `let` mid-pipeline — capture without breaking flow (v0.111)

```nushell
http get $url | let data | get items | length
# $data holds the full response
```

### `each --flatten` — stream through without collecting (v0.108)

```nushell
# before: collects each closure output, then flattens
0..5..<25 | each {|e| slow-source ($e)..<($e + 5) } | flatten

# after: streams directly
0..5..<25 | each --flatten {|e| slow-source ($e)..<($e + 5) }
```

### `for` loops accept streams (v0.108)

No longer collects the source.
Works with unbounded streams.

```nushell
for event in (watch . --glob=**/*.rs) { cargo test }
```

### `generate` with pipeline input — stateful `each` (v0.102)

```nushell
[1 2 3 4] | generate {|item acc| {out: ($item + $acc) next: ($item + $acc)} } 0
```

### `watch` streams events as a table (v0.107)

```nushell
# before: required a closure
watch . {|op path| if $op == Write { lint $path } }

# after: pipe into normal commands
watch . | where operation == Write and path like '*.md' | each { md-lint $in.path }
```

### `par-each` streams results as they complete (v0.112)

Unordered `par-each` no longer blocks until all items finish.

### `peek` — inspect a stream without collecting (v0.113)

Captures the first `n` elements into the pipeline metadata while letting the stream continue flowing.
Useful for logging or debugging without forcing `collect`.

```nushell
ls **/*.rs
| peek 3                     # first 3 entries stashed in metadata
| where size > 10kb
| metadata access {|m| print $m.peek; $in }
```

### `run` — scripts as pipeline stages (v0.114, checked arguments v0.117)

A `.nu` script can now sit in the middle of a pipeline.
The script body is the transform (implicit `$in` as usual), or a `def main` entry point if defined.
The path resolves at parse time, like `source`: against the directory of the calling script (the cwd for `nu --commands` and the REPL), then `NU_LIB_DIRS`, never `PATH`.

```nushell
# shout.nu contains just:  str uppercase
'Hello Nushell!' | run shout.nu | str camel-case   # => helloNushell

# re-running a file that changes on disk: use --full-reparse
watch . --glob=*.nu | each { run --full-reparse ./test.nu }
```

Since 0.117 `run` checks the arguments against `main` the way a direct call does, and keeps the script's definitions inside it.

- An unknown flag, an extra positional argument and a value of the wrong type are errors.
  0.116 dropped them silently.
- `--flag=value` works; 0.116 dropped it.
- There is no conversion to the parameter type, unlike `nu script.nu`: quote a number for a `string` parameter.
- `run`'s own flags go before the path; after the path, `-f` and `--help` go to `main`.
- A list spread never carries flags: a `main` with a rest parameter gets `--foo` as a plain value, and a `main` without one rejects the spread (`Cannot spread a list into this command`).
  Spread a record to pass flags.
- The script's commands and constants, `main` included, stay inside it.
  On 0.116 they stayed defined in the caller (a `let` leaked only its name: reading it failed at run time), and a `main` from `run` ran a second time when the calling script ended.

```nushell
# greet.nu:  def main [--name: string, --count: int = 1] { $"($name) x($count)" }
run greet.nu --name=ana                          # => ana x1   (0.116: " x1")
run greet.nu ...{name: ana, count: 3}            # => ana x3
try { run greet.nu --count abc } catch {|e| $e.msg }   # => Can't convert to int.  (0.116: " xabc")
try { run greet.nu --name 23 } catch {|e| $e.msg }     # => Can't convert to string.
```

---

## Error Handling

### `try`/`catch`/`finally` (v0.111, fixed v0.116)

Since 0.116 `finally` runs however the `try` is left: success, error, `catch`, `return`, `break`, `continue`.

```nushell
def process [] {
    let tmp = mktemp
    try { do-work $tmp } finally { rm $tmp }
}
```

When an outer `catch` handles an error, every `finally` on the way out runs first, innermost first.
A `return` inside `try` runs `finally` and then leaves the command; the statements after the `try` do not run.

`finally` gets one value, as `$in` and as its optional parameter:

- success — the value of `try` (or of `catch`, when it ran)
- an error with no `catch` — the error record
- `return`, `exit`, `break` or `continue` — `nothing`

```nushell
try { 111 } finally {|v| print $v }                        # prints 111
try { error make 'x' } catch { 'caught' } finally { print $in }   # prints caught
try { error make 'boom' } finally {|e| print $e.msg }       # prints boom, then the error propagates
```

Before 0.116 this was not reliable: after `return` the statements after `try` still ran, `break` and `continue` skipped `finally`, and an inner `finally` was skipped when an outer `catch` handled the error.
Scripts that must run on 0.115 or older cannot rely on `finally` for cleanup in those cases.

### `try` with external commands (v0.117)

Since 0.117 an external inside `try` streams to the next command as it does outside `try`.

- A `try` with no `catch` and no `finally` does not wait for the external and ignores its exit code.
  So `complete` after it gets the exit code, and `try { ^cmd | lines } | first 3` stays lazy (0.116 hung on an endless producer).
- With `catch`, the commands after a failing external inside `try` process its output before `catch` runs.
  Put `collect` right after the external to check its exit code first.
- `try … finally` passes the output of an external that succeeds on: `complete`, `save --stderr` and `tee --stderr` after it see stdout, stderr and the exit code.
  A failing external is not caught without `catch`: after `finally` it fails the pipeline, and `complete` never runs.
  `finally {|v| … }` gets stdout as a string.

```nushell
try { ^sh -c 'echo hi; exit 3' } | lines           # => [hi]   (0.116: null)
try { ^sh -c 'exit 3' } | complete                 # => {stdout: "", stderr: "", exit_code: 3}
                                                   #    (0.116: Complete only works with external commands)
try { ^sh -c 'echo a; exit 3' | lines | each {|x| print $'side ($x)'; $x } } catch { 'caught' }
# => side a, then caught   (0.116: caught only)
try { ^sh -c 'echo a; exit 3' | collect | lines | each {|x| print $'side ($x)'; $x } } catch { 'caught' }
# => caught   (collect checks the exit code first)
try { ^sh -c 'echo out; echo err >&2' } finally { } | complete
# => {stdout: "out\n", stderr: "err\n", exit_code: 0}   (0.116: internal error: stderr should not exist)
```

When `catch` handles a failed external, its stderr is now printed, also after `| ignore`; 0.116 dropped it.
On 0.116, `try { ^cmd } catch { … } | ignore` also ran `catch` when a successful external wrote to stderr.

### Simplified `error make` (v0.110)

```nushell
error make 'something went wrong'   # string shorthand
error make                          # bare error with source span
{msg: 'oops'} | error make          # piped input becomes an `inner` error; msg is "originates from here"
```

### Automatic error chaining in catch (v0.110)

```nushell
try { error make 'inner' } catch { error make 'outer' }
# "outer" automatically wraps "inner"
```

### External file spans in errors (v0.110)

```nushell
error make {
    msg: 'parse error'
    src: {path: '/tmp/config.yaml'}
    labels: [{text: 'bad value' span: {start: 10 end: 15}}]
}
```

### `first --strict` / `last --strict` (v0.109)

Error on empty input instead of returning nothing.
Since 0.117 the error is `nu::shell::access_empty_content` ("Cannot access empty content."), also for a stream or binary; before it was `access_beyond_end` ("Row number too large (empty content).").

```nushell
try { [] | first --strict } catch {|e| $e.details.code }   # => nu::shell::access_empty_content
```

### Catch error record: structured access (v0.100, reworked v0.114)

```nushell
try { fail } catch {|e| $e.details }   # 0.114+: structured record, no deserialization
try { fail } catch {|e| $e.rendered }  # pre-formatted string
# pre-0.114: $e.json | from json  ($e.json removed in 0.114)
```

Since 0.114 each label also carries a `location` record — file name plus file-relative `start`/`end` offsets — which makes external error-reporting tools feasible (the raw `span` offsets are into nushell's whole internal source buffer, not the file).

---

## Data Manipulation

### `record where` / `each` / `walk` / `apply` — fields without `transpose` (v0.117)

These replace the `transpose key value | … | transpose --header-row --as-record` round trip.
Each also takes a table and works on every row.

- `record where` keeps fields by a row condition on `key` and `value`, or by a closure `{|k v| … }`.
  With `--keys` or `--values` the condition gets only that part as `$it`; put the flag before the condition.
- `record each {|k v| … }` returns the new entry as `{newkey: value}` or `[newkey value]`, or `null` to drop the field.
- `record walk {|value path| … }` runs on every leaf of a nested record and gets its cell path.
  `--containers` also visits nested records and lists; `--no-lists` passes a list whole.
- `record apply {field: {closure}}` converts the named fields and leaves the rest; `--strict` errors on a field the input does not have.

```nushell
{a: 1, b: 2, c: 3} | record where value > 1                       # => {b: 2, c: 3}
{NU_LOG: debug, HOME: /home/me} | record where key starts-with NU_ # => {NU_LOG: debug}
{a: 1, b: 2} | record each {|k v| {($k | str uppercase): ($v * 10)} }   # => {A: 10, B: 20}

{db: {host: prod, password: hunter2}, api: {token: abc}}
| record walk {|v path| if ($path | to text) =~ 'password|token' { '***' } else { $v } }
# => {db: {host: prod, password: ***}, api: {token: ***}}

[{name: a, size: '1'} {name: b, size: '2'}] | record apply {size: {into int}}
# => [[name, size]; [a, 1], [b, 2]]
```

### `get ...$paths` — several paths from a list (v0.117)

`get` no longer needs a first cell path, so a list of paths spreads in (0.116: `missing_positional`).
Several literal paths, `get db.host name`, worked before too.
A spread always returns a list, one value per path.
A string in the list is one column name, so `'db.host'` looks for a column with a dot in its name.
Build nested paths as `$.db.host` literals, or with `split row . | into cell-path`.

```nushell
let cfg = {db: {host: h1, port: 5432}, name: app}
let paths = [$.db.host $.name]
$cfg | get ...$paths                                      # => ["h1", app]
$cfg | get ...(['db.port'] | each { split row . | into cell-path })   # => [5432]
$cfg | get ...[$.db.host $.nope?]                         # => ["h1", null]
```

`get` with no argument returns its input (on 0.116 a parse error), or errors with `Pipeline empty` when there is no input.

### `merge deep` — nested record merging (v0.101)

```nushell
{a: {x: 1}} | merge deep {a: {y: 2}}
# => {a: {x: 1, y: 2}}

{b: [1 2]} | merge deep --strategy=append {b: [3 4]}
# => {b: [1 2 3 4]}
```

### `union` / `intersect` / `difference` — built-in set operations (v0.114)

Deduplicated, order-preserving, work on scalars and records alike.

```nushell
[1 2 3 4] | union [3 4 5 6]        # => [1 2 3 4 5 6]
[1 2 3 4] | intersect [3 4 5 6]    # => [3 4]
[1 2 3 4] | difference [3 4 5 6]   # => [1 2]
[{a: 1} {a: 2}] | union [{a: 2} {a: 3}]   # records compare structurally
```

Replaces hand-rolled `append | uniq` (union), `where $it in $other` (intersect), `where $it not-in $other` (difference) — with dedup included.

### `combinations` / `permutations` (v0.114)

Lazily streamed.

```nushell
[1 2 3] | combinations 2   # => [[1 2] [1 3] [2 3]]
[1 2 3] | permutations     # => 6 orderings
```

### `append` takes multiple values (v0.114)

```nushell
[1] | append 2 3 4   # => [1 2 3 4]  (was: | append 2 | append 3 ...)
```

### `chunk-by` — group consecutive elements (v0.101, row conditions v0.116)

```nushell
[1 3 -2 -2 0 1 2] | chunk-by {|x| $x >= 0 }
# => [[1, 3], [-2, -2], [0, 1, 2]]

# 0.116: row-condition form, like `where`
[1 3 -2 -2 0 1 2] | chunk-by $it >= 0          # same result
[[n]; [1] [3] [-2] [0]] | chunk-by n >= 0      # a column name works too
```

### `compact` works on records (v0.108)

```nushell
# before
$record | transpose k v | where v != null | transpose --header-row

# after
{a: 1 b: null c: 3} | compact   # => {a: 1, c: 3}
```

### `default --empty` (v0.103)

Returns default for empty strings, lists, records, binary — not just null.

```nushell
'' | default --empty 'fallback'   # => "fallback"
```

### `default` with lazy closure (v0.105)

```nushell
ls | default { expensive_call } some_col
# closure only evaluated when needed, result cached
```

### `group-by` multiple groupers + `--to-table` (v0.101)

```nushell
$data | group-by color category --to-table
# => table with columns: color, category, items
```

Since 0.117 the `--to-table` key columns keep their type; before they were display strings.
Two filesizes that print alike (`1MB`, `1.001MB`) are now two groups, and `"true"` and `true` too.
The record form without `--to-table` still uses string keys.

```nushell
[{n: 1} {n: 2} {n: 1}] | group-by n --to-table   # => [[n, items]; [1, [[n]; [1], [1]]], [2, [[n]; [2]]]]   (0.116: n was "1", "2")
```

### `group-by --prune` (v0.112)

Remove the grouping column from results.

```nushell
$table | group-by category --prune
```

### `uniq-by --keep-last` (v0.111), `uniq --keep-last` (v0.117)

The last occurrence wins, in the position of the first.

```nushell
[[fruit count]; [apple 9] [pear 3] [apple 2]] | uniq-by fruit --keep-last
# => [[fruit, count]; [apple, 2], [pear, 3]]
```

`uniq --keep-last` (`-l`) shows a difference only where equal values can differ, as with `--ignore-case`:

```nushell
[Apple apple APPLE pear] | uniq --ignore-case               # => [Apple, pear]
[Apple apple APPLE pear] | uniq --ignore-case --keep-last   # => [APPLE, pear]
```

### `join --prefix` / `--suffix` (v0.111)

```nushell
$left | join $right key --suffix '_right'
```

### `join --anti` — rows with no match (v0.117)

Keeps the left rows whose join column has no match on the right — the same as `where col not-in $right.col`.

```nushell
let orders = [[id user]; [1 ana] [2 bob] [3 eve]]
$orders | join --anti [[user]; [bob]] user   # => [[id, user]; [1, ana], [3, eve]]
```

### `drop column --left` (v0.111)

```nushell
$table | drop column 2 --left
```

### `move --first` / `--last` (v0.102)

```nushell
$table | move name --first
$table | move id --last
```

### `drop nth` with spread (v0.106)

```nushell
ls | drop nth ...[1 2 3]
```

### `update` with optional cell paths (v0.109)

```nushell
{a: 1} | update b? 2  # => {a: 1} (no error when path absent)
```

### `update cells --recursive` (v0.116)

The closure runs on every leaf value inside nested records and lists, not on the whole cell.

```nushell
{a: {b: 1, c: [2 3]}, d: 4} | update cells --recursive { $in * 10 }
# => {a: {b: 10, c: [20, 30]}, d: 40}
```

Since 0.117 the columns to change follow the closure as plain names, like in `select`; `--columns [..]` still works, with a deprecation warning.

```nushell
[[name val1 val2]; [foo 1 4] [bar 8 3]] | update cells { $in * 2 } val1 val2
# => [[name, "val1", "val2"]; [foo, 2, 8], [bar, 16, 6]]
```

### `default` fills nested fields (v0.116)

A column argument is a cell path now, so `default` reaches into records and creates the missing parents.
Quote the name to target a key that contains a dot.

```nushell
{} | default 5 a.b                        # => {a: {b: 5}}
[{a: {}} {a: {b: 1}}] | default 0 a.b     # => [[a]; [{b: 0}] [{b: 1}]]
{} | default 5 'a.b'                      # => {"a.b": 5}
```

### Spread `null` as empty (v0.107)

Eliminates null-guard branches.

```nushell
let extra = if $cond { {key: val} } else { null }
{base: 1 ...$extra}   # null acts as empty record

[1 2 ...(null)]   # => [1 2]
```

### Table literal columns support variables (v0.108)

```nushell
let col = 'name'
[[$col age]; [Alice 30]]
```

### Built-in commands accept `null` for optional params (v0.112)

Enables transparent forwarding in wrappers.

```nushell
def wraps-first [rows?: int] { [1 2 3] | first $rows }
wraps-first      # => 1
wraps-first 2    # => [1, 2]
```

### Named flags given `null` (v0.116)

A named flag given `null` now follows its type:

- the type does not accept `nothing` (`--x: int`, `--preserve: list<string>`) — the flag counts as not passed, so its default applies
- the type accepts `nothing` (`--x: any`, `--x: oneof<int, nothing>`) — `null` is passed through

This makes a wrapper that forwards `--flag=$maybe_null` behave like the caller left the flag out.
It works for builtins too: `{a: 1} | to nuon --indent=$maybe` with `$maybe = null` gives `{a: 1}`.

```nushell
def f [--x: oneof<int, nothing> = 5] { $x }
f              # => 5
f --x=null     # => null

def g [--x: int = 5] { $x }
let maybe = null
g --x=$maybe   # => 5
g --x=(null)   # => 5
g --x=null     # parse error: expected int — a literal null is checked at parse time
```

### Record spread into named flags (v0.116)

`...{flag: value}` passes each field as a named flag, for custom and builtin commands alike.
A switch field set to `true` sets the switch; `false` or `null` leaves it out.
Other `null` fields follow the rule above.
An unknown field name is a runtime error (``Unknown flag `bogus` in spread record``), and a value of the wrong type is too.

```nushell
# a wrapper that shadows cp and forwards its flags as one record
def cp [--preserve: list<string>, --recursive, ...rest] {
    %cp ...{preserve: $preserve, recursive: $recursive} ...$rest
}
cp --recursive src dst     # preserve is null, so %cp never sees --preserve
```

### `any` / `all` accept row conditions (v0.115)

Same syntax as `where` — reference columns directly, or use `$it`.
Closures still work for anything longer.

```nushell
[9 8 7 6] | enumerate | any item == index * 2   # => true
[1sec 1min 1hr] | all ($it | describe) == 'duration'   # => true
```

### Row conditions: bare column names after `and` / `or` / `xor` (v0.117)

A bare name after a logical operator is a column now, in `where`, `any`, `all`, `take while` and the rest.
0.116 read it as a string.

```nushell
[{a: true, b: true} {a: true, b: false}] | where a and b   # => [[a, b]; [true, true]]
# 0.116: The 'and' operator does not work on values of type 'string'.
[{a: false, b: false}] | where not a and not b             # => [[a, b]; [false, false]]
# 0.116: Can't convert to boolean.
```

### `take while` / `take until --include` (v0.115, row conditions v0.116)

`--include (-i) $n` keeps `n` more items after the point where the stream would have stopped — the usual "and the row that ended it" case.

Since 0.116 `take while`, `take until`, `skip while` and `skip until` also accept a row condition, like `where`.
The condition takes everything after it, so **a flag must come before the condition** — also for a closure or a `$closure` variable.
`take while {|x| $x < 3 } --include 1` parsed on 0.115 and is a parse error (`expected operator`) on 0.116.

```nushell
[1 2 3 4 5] | take while --include 1 {|x| $x < 3 }     # => [1, 2, 3]
[1 2 3 4 5 6] | take until --include 2 {|x| $x > 3 }   # => [1, 2, 3, 4, 5]

# 0.116 row-condition form
[1 2 3 4 5] | take while $it < 3                       # => [1, 2]
[1 2 3 4 5] | take while --include 1 $it < 3           # => [1, 2, 3]
[1 2 3 4 5] | skip until $it > 3                       # => [4, 5]
[[n]; [1] [2] [5] [1]] | take while n < 3              # => [[n]; [1] [2]]
```

### `filesize` arguments on `chunks` / `first` / `last` / `take` / `skip` / `drop` (v0.115)

`drop` also works on `binary` input now.
Splitting a file by size no longer needs a byte count in a variable.

```nushell
let bytes = 0x[00 01 02 03 04 05 06 07]
$bytes | chunks 3b | length   # => 3
$bytes | first 2b             # => 2 bytes
$bytes | drop 3b              # => 5 bytes

# split a big file into 10MiB parts
open --raw file.7z | chunks 10MiB | enumerate | each {|c|
    $c.item | save $'file.7z.($c.index + 1)'
}
```

### Math commands on records with list columns (v0.115), on table columns (v0.117)

Reducing commands (`math avg/sum/product/max/min/median/mode/stddev/variance`) and element-wise ones (`math abs/cbrt/ceil/floor/sqrt/round/log`) handle a record whose columns are lists, including uneven lengths.
On a record, an optional cell path restricts the operation to named columns; the rest pass through untouched.

```nushell
{alice: [0.1 0.6 0.2] bob: [0.8 0.3 0.2 0.9]} | math avg
# => {alice: 0.3, bob: 0.55}

{alice: [1 2 3] bob: [4 5 6]} | math avg alice
# => {alice: 2.0, bob: [4, 5, 6]}
```

Since 0.117 a reducer with column names on a **table** reduces those columns across all rows and returns one record, like `select <cols> | math <op>`.
0.116 returned the table unchanged.
A table column that holds lists is now an error (`Input type not supported`); for the old row-by-row result use `update a { math sum }`.

```nushell
[[a b c]; [1 10 x] [2 20 y]] | math sum a b   # => {a: 3, b: 30}
```

---

## Strings & Parsing

### `str escape-regex` (v0.112)

```nushell
let safe = $user_input | str escape-regex
$data | where name like $'^($safe)$'
```

Escapes for the `fancy-regex` flavor Nushell uses everywhere — see `regex.md`.

### `str replace` with closure (v0.109)

The whole match arrives as `$in`; capture groups arrive as the closure's parameters, one per group.

```nushell
'foo123bar' | str replace --regex '\d+' { into int | $in * 2 | into string }   # => foo246bar
'a1b22' | str replace --all --regex '(\d)(\d)?' {|d1 d2| $'<($d1)($d2)>' }     # => a<1>b<22>
```

A closure that declares a parameter when the regex has no group fails with `Missing parameter`.

### `parse` with `_` placeholder (v0.105)

```nushell
'hello world' | parse '{word} {_}'   # discards second field
```

### `str length --chars` (v0.108)

```nushell
'hällo' | str length --chars  # => 5 (not byte count)
```

### `str expand` with zero-padded ranges (v0.103)

```nushell
'file{00..10}.txt' | str expand
```

### `into string --group-digits` (v0.103)

```nushell
1234567 | into string --group-digits  # => "1,234,567"
```

### `find --no-highlight` (v0.102)

```nushell
$data | find 'term' --no-highlight  # no ANSI in output
```

### `find --only-matching` — the matched text only, like `grep -o` (v0.117)

Each match is one item of a flat list, so a pattern that occurs twice in one string gives two items.

```nushell
'error 404, then 500' | find --only-matching --regex '\d{3}'   # => ["404", "500"]
[[n]; ['id 12'] ['id 7']] | find --only-matching --regex '\d+'  # => ["12", "7"]
['foo bar' 'Foo baz'] | find --only-matching --ignore-case foo  # => [foo, Foo]
```

### `path relative-to --walk-up` (v0.117)

Without the flag, a path that is not under the base is an error.

```nushell
'/a/b/c' | path relative-to '/a/d/e' --walk-up   # => ../../b/c
'/a/b/c' | path relative-to '/a/d/e'            # error: The argument path is not a parent of the input path.
```

### `detect type` reads durations (v0.117)

```nushell
'1hr 3min' | detect type   # => 1hr 3min (a duration; 0.116 kept the string)
'+42' | detect type        # => 42
' 5ns' | detect type       # => " 5ns" — padded strings stay strings
```

### `char eol` — platform line ending (v0.103)

```nushell
char eol  # "\r\n" on Windows, "\n" elsewhere
```

### `char` slashes, same on every OS (v0.116)

```nushell
char forward_slash   # => /   (also: slash, fslash)
char back_slash      # => \   (also: bslash)
```

`char path_sep` stays the one that follows the OS.

### `into float` accepts a comma decimal separator (v0.116)

```nushell
'1,5' | into float       # => 1.5
'1,000.5' | into float   # error: Ambiguity in conversion
'1,000' | into float     # => 1.0 — the comma is read as a decimal point, not a thousands separator
```

On 0.115 all three were errors.
Strip thousands separators yourself before converting (`str replace --all ',' ''`).

### `hash sha512` (v0.116)

```nushell
'abc' | hash sha512   # 128 hex characters; --binary for raw bytes
```

### `split row --right` / `split column --right` (v0.114)

`--number $n` splits from the left; add `--right` to keep the split points rightmost — the classic "separate the version suffix" case:

```nushell
'some-package-1.0' | split row '-' --number 2           # [some, package-1.0]
'some-package-1.0' | split row '-' --number 2 --right   # [some-package, 1.0]
```

### SemVer as a first-class value (v0.114, extended v0.115)

`into semver` parses; the value sorts correctly, decomposes with `into record`, rebuilds from a record, bumps without string surgery, and matches ranges.
Replaces `split row '.' | into int` sorting hacks.

```nushell
'1.2.3-alpha.1' | into semver | semver bump release      # => 1.2.3
'1.2.3' | semver bump minor                              # => 1.3.0
['2.0.0' '1.10.0' '1.2.0'] | each { into semver } | sort # correct numeric order
'1.2.3' | into semver | $in in ('>=1.0.0' | into semver-range)  # => true
'1.2.3-alpha.1+b.2' | into semver | into record  # major/minor/patch/pre/build
```

Since 0.115 the values also compare with `==`, `!=`, `<`, `<=`, `>`, `>=`, so version gates read like ordinary conditions.
A plain string on the right-hand side is accepted when it parses as a semver.

```nushell
('2.0.1' | into semver) > ('1.9.9' | into semver)   # => true
('2.0.1' | into semver) > '1.9.9'                   # => true
('1.0.0-alpha' | into semver) < ('1.0.0' | into semver)   # => true
```

Since 0.115.1 the parser also types the result as `bool`, so it works with `and`/`or`, in `let`, and as a `bool` argument:

```nushell
let outdated = ('0.9.0' | into semver) < ('1.0.0' | into semver)   # $outdated | describe => bool
(which crush | is-empty) or ((crush --version | into semver) < ('1.0.0' | into semver))
```

Also new in 0.115:

- `into semver` / `into semver-range` take `--loose` for `v`-style prefixes — `v1.2.3`, `v.1.2.3`, `v:1.2.3`, `v-1.2.3`, `v_1.2.3`.
  `into record` then carries the prefix in a `prefix` field.
- `into semver` accepts a list, and a cell path to convert in place: `$nu.os-info | into semver kernel_version`, `["1.2.0" "0.3.12"] | into semver`.
- A single semver no longer renders as a one-row table, and semver values print in `cyan_bold`.

Note: semver is a custom value, so `to nuon` on it fails — and `try` does not catch that error (0.115.1 to 0.117; run on 0.116.0 and on the 0.117 release commit).
A closure fails the same way, so the trap is `to nuon` on any value it cannot write, not semver alone.
When `to nuon` is not the last statement of the `try` body, no error shows at all.
Convert with `into string` or `into record` before serializing; `to json` already writes it as a string.
Since 0.116 `into string` on a semver is typed as `string`, so it also fits a typed position such as `path join` (0.115 rejected it at parse time).

---

## Dates & Time

### `date from-human` (v0.104)

The text comes as pipeline input; an argument is a parse error.
It ignores a 12-hour time such as `6pm` without an error and keeps the current time of day — write `18:00`.

```nushell
'friday 18:00' | date from-human        # => next Friday, 18:00
'next Friday at 6pm' | date from-human  # => next Friday, at the current time of day
```

Since 0.117 `into datetime` also reads relative dates such as `tomorrow 10am` and `3 days ago`, with GNU `date -d` rules that differ from `date from-human` in places; `migration.md` has the differences.

### `into datetime`: IANA zones, `--formats` (v0.117)

`--timezone` takes any zone from `date list-timezone` now (0.116: `Type mismatch`).
It applies to integer timestamps and to `--format` input; in a free-form string, write the zone into the string.

```nushell
1745000000000000000 | into datetime --timezone America/New_York   # => 2025-04-18T14:13:20-04:00
'2025-04-18 04:04:32 America/New_York' | into datetime            # => 2025-04-18T04:04:32-04:00
'@1745000000' | into datetime                                     # => 2025-04-18T18:13:20+00:00
```

Impossible dates are errors now, and February 29 of a leap year reads right:

```nushell
'2000-02-29' | into datetime   # => 2000-02-29T00:00:00+00:00   (0.116: 2000-02-28)
'2026-02-30' | into datetime   # error: Unable to parse datetime   (0.116: 2026-02-28, no error)
```

`into datetime --formats` lists every format read without `--format`, each with an example.
Its columns are `Recognized_Format`, `Format`, `Kind` and `Description`; `Kind` is one of `standard`, `date`, `datetime`, `time`, `zone`, `variant`, `relative`, `timestamp`.

```nushell
into datetime --formats | where Kind == relative | get Recognized_Format
```

### `older-than` / `newer-than` — filter by age (v0.117)

`ls | where modified older-than 2wk` replaces `where modified < ((date now) - 2wk)`.
With a datetime on the right they work like `<` and `>`.
Both are strict, and `null` on either side gives `null`.
A duration on the right reads the clock, so that form cannot run in a `const`; a datetime on the right can.

```nushell
let rows = [[name modified]; [old ((date now) - 30day)] [new ((date now) - 1day)]]
$rows | where modified older-than 2wk | get name   # => [old]
$rows | where modified newer-than 2wk | get name   # => [new]
2023-06-01 older-than 2024-01-01                   # => true
```

`(date now) < 2day` is still a parse error; since 0.117 its help suggests `older-than`.

### `into datetime` from record (v0.104)

```nushell
{year: 2025 month: 3 day: 30 hour: 12 minute: 15 second: 59 timezone: '+02:00'}
| into datetime
```

### `into duration` from record, float, or hh:mm:ss (v0.104, v0.112)

```nushell
{week: 10 day: 1 hour: 2} | into duration
1.5 | into duration --unit day
'16:59:58' | into duration    # => 16hr 59min 58sec
```

### `timeit --output` (v0.110)

```nushell
timeit --output { some-command }  # => {time: 14328, output: <result>}
```

### `%J` / `%Q` date format specifiers (v0.108)

```nushell
date now | format date '%J_%Q'   # => 20250918_131144
```

### `seq date` accepts any duration increment (v0.102)

```nushell
seq date --begin-date 2025-01-01 --end-date 2025-01-02 --increment 6hr
```

### `date list-timezone` shows the UTC offset (v0.116)

Each row is `{timezone, offset}`; `offset` is the current offset as a string, so it follows daylight saving time.

```nushell
date list-timezone | where timezone == Asia/Kolkata   # => [[timezone, offset]; [Asia/Kolkata, "+05:30"]]
```

---

## Type Safety & Command Metadata

### `oneof<...>` parameter type (v0.105)

```nushell
def foo [param: oneof<binary, string>] { .. }
```

Since 0.117 a literal goes to the non-string type it matches, whatever the order: with `oneof<string, int>`, `5` arrives as an int (0.116: a string).
`migration.md` covers what that changes for existing commands.

### Type aliases: `type Name = …` (v0.117)

A name for a type, usable wherever a type annotation goes: parameters, flags, rest and closure parameters, input/output types, `let`/`mut`/`const`.
A type alias can use another one.
Help, `scope commands` and errors show the expanded type.

```nushell
type Point = record<x: float, y: float>
type Polygon = list<Point>
def first-x [poly: Polygon]: nothing -> float { $poly.0.x }
first-x [{x: 1.5, y: 2.0}]   # => 1.5
```

The check is strict: a record literal with `int` fields does not fit `record<x: float, y: float>`, and the parser rejects it (`expected list<record<x: float, y: float>>, found list<record<x: int, y: int>>`).

- A type alias is visible from its definition to the end of its block; define it before use.
- A module exports one with `export type`.
  A bare `use geo` does not import it: write `use geo Point`, `use geo [Point]` or `use geo *`.
- `hide Point` hides it; `scope modules` lists a module's aliases in the `type_aliases` column.
- `type` is a parser keyword now, so a command, alias or extern named `type` is a parse error (`Can't use parser keyword`).

### Custom value types in signatures (v0.117)

A custom value type such as `semver` is a valid parameter and input/output type now (0.116: `unknown type`).
A string does not convert to it on the way in: convert with `into semver` before the call.
Plugin types such as `polars_dataframe` work the same way (release notes only).

```nushell
def bump [v: semver]: nothing -> semver { $v | semver bump minor }
bump ('1.2.3' | into semver) | into string   # => 1.3.0
```

### `@deprecated` attribute (v0.105)

```nushell
@deprecated 'Use new-cmd' --since '0.105.0' --remove '0.110.0'
def old-cmd [] { ... }
```

### `@example`, `@search-terms`, `@category` (v0.103)

```nushell
@example 'double 5' { 5 | double } --result 10
@search-terms multiply scale
@category math
def double []: [int -> int] { $in * 2 }
```

### `describe --detailed` (v0.104)

Returns a record that always has `type`, `detailed_type` and `rust_type`; the other fields depend on the value.
A list adds `length` and `value`, a record adds `columns` and has no `value`, a byte stream adds `origin` and `metadata`.

### `get` is const-evaluable (v0.102)

```nushell
const val = [a b c] | get 2  # works at parse time
```

### `first` / `last` in `const` (v0.117)

```nushell
const LEVELS = [debug info warn]
const DEFAULT = $LEVELS | first   # => debug
const TOP2 = $LEVELS | last 2     # => [info, warn]
```

On 0.116 both were `Not a const command`.
`1.. | last` is an error now (`Incorrect value.`, labelled `Range must be bounded`); 0.116 hung on it.

### `external_arg` parameter type (v0.115)

Takes an argument the way an external command would: no int/bool coercion, the raw text arrives typed as `glob`.
Useful for wrappers that forward arguments to another tool.

```nushell
# script.nu
def main [a: external_arg, ...rest: external_arg] {
    $'($a) ($a | describe) | ($rest | describe)'
}
```

```nushell
nu script.nu 0001 true 007
# => 0001 glob | list<glob>     ("0001" stays a string, not 1)

nu script.nu 0001 -- --verbose 'x y'
# => rest gets ["--verbose", "x y"]
```

A `glob` value expands when it reaches an external command.
So a wrapper forwards a quoted `'*.md'` from the shell as the matching file names, not as the pattern.
Convert with `into string` when the external must get the text as typed:

```nushell
# wrap.nu, run as: nu wrap.nu '*.md'
def main [a: external_arg] {
    ^echo $a                   # => a.md b.md
    ^echo ($a | into string)   # => *.md
}
```

### `scope` reports local scopes, `scope commands` reports deprecations (v0.115)

`scope variables` / `commands` / `aliases` / `modules` / `externs` now list what is defined in the current block as well as the global scope, so introspection inside `do`, `if`, `for`, or a custom command finally sees the local names.

```nushell
let a = 1
do { let b = 2; scope variables | where name in ["$a" "$b"] | get name }
# => [$a, $b]

do { def local-cmd [] { 1 }; scope commands | where name == 'local-cmd' | length }
# => 1  (0 again after the block ends)
```

`scope commands` also carries `deprecation_info` — deprecated commands and flags are now machine-readable:

```nushell
scope commands | where name == 'str downcase' | first | get deprecation_info.0.help
# => Use `str lowercase` instead.
```

### `view source --dependencies` (v0.116)

Appends the source of every custom command the target calls, transitively — module-private helpers included, which cannot be viewed any other way.
It also prepends every `const` those bodies read, with its current value.
Useful to hand one self-contained snippet to a reviewer or an agent.

```nushell
module m {
    const LIMIT = 42
    def helper [] { $LIMIT }
    export def bar [] { helper }
}
use m
view source 'm bar' --dependencies
# const LIMIT = 42
#
# def "m bar" [] { helper }
#
# def helper [] { $LIMIT }
```

---

## HTTP

### Auto verb detection (v0.106)

```nushell
http https://example.com            # GET (no body)
http https://example.com {data: 1}  # POST (body present)
```

### Auto scheme (v0.105)

```nushell
http get example.com   # prepends http://
http get :8000         # => http://localhost:8000
```

### Connection pooling (v0.110)

```nushell
http get --pool https://api.example.com/a
http get --pool https://api.example.com/b
```

### Response metadata — no `--full` needed (v0.108)

```nushell
http get --allow-errors $url
| metadata access {|m|
    if $m.http_response.status != 200 { error make 'failed' } else { }
}
| lines | each { from json }
```

### Redirect tracking (v0.107)

```nushell
http get --full $url | get urls   # redirect chain
```

### Unix domain sockets (v0.109)

```nushell
http get --unix-socket /var/run/docker.sock http://localhost/containers/json
```

### `url parse --base` (v0.112)

```nushell
'/path/page' | url parse --base 'https://example.com'
```

### `url split-query` (v0.100)

```nushell
'a=1&b=2' | url split-query  # => [[key, value]; [a, 1], [b, 2]]
```

### Error responses use the body as message (v0.114)

`http` error messages now carry the response body — usually the API's actual explanation — instead of just the status line.

### Custom `from <ext>` converters, IPv6 hosts (v0.117)

`http` converts a response with a custom `from <ext>` command, as `open` does.
For a `text/plain` response the extension comes from the URL; otherwise from the content type, `application/x-foo` → `from foo` (source-checked).
0.116 failed with `Internal error: can't run custom command with 'run'`.

```nushell
def "from kv" []: string -> record { lines | split column '=' k v | transpose --header-row --as-record }
http get http://localhost:8000/data.kv   # served as text/plain "a=1\nb=2" => {a: "1", b: "2"}
```

A URL with an IPv6 host, such as `http://[::1]:8000/`, works now (0.116: `DNS Error`).
Zone IDs such as `http://[fe80::1%eth0]/` are accepted too (release notes only).

---

## Completions

0.116 changed what a completer receives and may return; the `nushell-completions` skill has the current model.

### `@complete` attribute (v0.108)

Attach a completer to an entire command.

```nushell
@complete external
def --wrapped jc [...args] { ^jc ...$args | from json }

@complete my-completer
def go [direction] { ... }
```

### Inline list completions (v0.108)

```nushell
# before: separate completer function
def dirs [] { [left up right down] }
def go [dir: string@dirs] { }

# after: inline
def go [dir: string@[left up right down]] { }
```

### Substring algorithm (v0.104)

```nushell
$env.config.completions.algorithm = 'substring'
```

---

## Commands & Scripts

### `%` sigil for built-ins (v0.112)

Call the original even when shadowed.

```nushell
def ls [] { echo 'custom' }
%ls  # => real ls output
```

### Dynamic `%` sigil dispatch (v0.113, flags v0.117) — last resort

`%$cmd` and `%($cmd)` resolve the builtin to invoke at runtime, multi-word names included.
**Only builtins are eligible.**
A custom command, an alias and an external all fail with `Command not found` — verified for each.

Since 0.117 the call is checked like a direct call.
An unquoted `--flag` goes to the builtin as a flag, and a record spread passes computed flags.
An unknown flag, a missing value and an extra positional argument are errors.
`--` is no longer passed on, and a list spread into a command without a rest parameter is an error.
On 0.116 the flags were dropped or passed as plain values, with no error.

```nushell
let cmd = 'sort'
[1 3 2] | %$cmd --reverse             # => [3, 2, 1]   (0.116: [1, 2, 3])
[1 3 2] | %$cmd ...{reverse: true}    # => [3, 2, 1]
let sr = 'str replace'
'a-b-c' | %$sr --all '-' '_'          # => a_b_c       (0.116: error)
```

To pass a flag-like string as a value, quote it: `%$cmd '--foo'`.
`migration.md` lists the calls that break.

Because the command is unknown at parse time, a bare cell-path argument is read as a column name.
The fix is the `$.a.b` literal, which carries its own structure (see "Cell-Paths Are Values" in `patterns.md`):

```nushell
let g = 'get'
{a: {b: 7}} | %$g a.b      # => error: Cannot find column 'a.b'
{a: {b: 7}} | %$g $.a.b    # => 7
```

Prefer the static `%get` whenever the command set is known as you write — `SKILL.md` lists the costs under Don't.

### Fish-style abbreviations (v0.113)

Syntax-aware expansions triggered on space/enter, configured via `$env.config.abbreviations`.
Unlike aliases, the expanded text is visible and editable before submission.

```nushell
$env.config.abbreviations = {
    gco: 'git checkout'
    ll: 'ls -la'
}
# typing `gco<space>` expands to `git checkout `
```

### Command group aliasing (v0.111)

```nushell
alias pl = polars
ps | pl into-df | pl select [(pl col name)] | pl collect
```

### `path self` (v0.101)

```nushell
const this_file = path self
const this_dir = path self .
```

`path self` runs only at parse time, so its result has to land in a `const`.
Called inside a `def` body it fails with `this command can only run during parse-time`, and the help line — "try assigning this command's output to a const variable" — is the actual fix, not a hint.
Put it at the top of the file: `const SCRIPT_DIR = path self | path dirname`.
It also takes a path argument resolved against the script's own directory, which is how a script points at a neighbour without a hardcoded absolute path: `const SIBLING = path self ../CLAUDE.md`.
Both forms work in a `const`, neither works in a command body.
It needs a real file too, so `nu --commands 'path self'` fails — test it in a script, not with `-c`.

### Background jobs (v0.103, `--auto-kill` v0.117)

```nushell
job spawn { long-task | save result.txt }
job list
job kill $id
```

The background jobs of a script or of `nu --commands` end when it exits.
Only the job's own child process is stopped: a grandchild, such as the `sleep` in `job spawn { ^sh -c 'sleep 30; echo x' }`, keeps running after the script, on 0.116 and 0.117 alike.
A plain exit killed the job's external on 0.116 too (run on both); 0.117 also ends them after Ctrl-C (not run: needs an interactive Ctrl-C).

`job spawn --auto-kill` (`-k`) marks a job that `exit` in the REPL may kill without the "background jobs still running" warning (release notes only: the warning is REPL-only).
`job list` shows the mark in an `auto_kill` column:

```nushell
job spawn --auto-kill { sleep 10min }
job spawn { sleep 10min }
job list | sort-by id | select id auto_kill   # => [[id, auto_kill]; [1, true], [2, false]]
```

### Inter-job messaging (v0.104)

```nushell
'hello' | job send $target_id   # the message is the pipeline input; id 0 is the main thread
job recv                        # blocks until a message arrives
```

### `unlet` (v0.110, constants v0.117)

```nushell
let big = open huge.csv
# ... process ...
unlet $big
```

A later `$big` is a runtime error (`Variable not found`).

Since 0.117 `unlet` on a constant hides its name for the rest of the block, so a later `$C` is a parse error.
A command body that read the constant before keeps its value.
0.116 accepted `unlet $C` and changed nothing.

```nushell
const C = 5
def show [] { $C }
unlet $C
show   # => 5
# $C   # parse error: variable not found   (0.116: 5)
```

`unlet $in` is an error.

### `explore regex` — interactive regex TUI (v0.109)

```nushell
open file.txt | explore regex
```

### `--` end-of-options delimiter (v0.114)

Pass flag-looking values as positionals without quoting tricks:

```nushell
process -- --verbose -x foo   # rest param gets ["--verbose", "-x", "foo"]
```

### `ignore` stream and error controls (v0.114)

```nushell
noisy-cmd | ignore --stderr        # swallow stderr, keep stdout
noisy-cmd | ignore --stdout        # swallow stdout, keep stderr
ext-cmd | ignore --show-errors     # still surface errors + LAST_EXIT_CODE
```

### `commandline complete` — query nushell's own completions (v0.114)

Returns what Tab would suggest — usable inside custom completers or scripts:

```nushell
commandline complete                              # for current buffer
'./a' | commandline complete --type directory     # directory suggestions
'%ls -' | commandline complete --detailed         # flags with descriptions
```

0.116 added `--input` (the `{token, place, buffer}` record a completer would receive) and reworked how custom completers take input — see the `nushell-completions` skill.

### `random pass` — password generation (v0.114)

```nushell
random pass --chars 20 --require-each-type
# flags: --no-uppercase/--no-lowercase/--no-numbers/--no-symbols, ...
```

### `is-terminal` detects redirection (v0.114)

Now defaults to `--stdout` and reports `false` when output is piped, captured, or redirected — `if (is-terminal) { fancy } else { plain }` finally works in all four cases (`| $in`, `o> file`, subexpression capture, terminal).

### `$ans` — the last REPL result (v0.115)

A record describing the previous REPL entry.
**REPL only** — it is not populated in scripts or `nu -c`.
`ans` is now a reserved name, so `let ans = ...` in existing scripts has to be renamed.

```nushell
$ans.last        # the previous pipeline's value
$ans.exit_code   # int, like $env.LAST_EXIT_CODE
$ans.duration    # duration
$ans.command     # the line you typed, as a string
```

Storing the output is opt-in: `$env.config.max_last_result_size` is a filesize and defaults to `0b`, which omits the `last` key entirely — probe it with `$ans.last?`.
The rest of the record is always there.
Set the size to rescue an expensive pipeline you forgot to bind:

```nushell
$env.config.max_last_result_size = 10mb
slow-thing | complete    # ran for 15 minutes
let saved = $ans.last    # no re-run
```

Output over the limit is truncated, with a warning when you read it.

### Constant expressions in `match` arms (v0.115)

An arm pattern may now be a parenthesized const expression, so a path or prefix kept in a `const` can be matched without a chain of `if`s.

```nushell
match 'test' { ('t' + 'es' + 't') => { 'OK' } }   # => OK

const ROOT = '/srv/app'
match $dir {
    ($ROOT + '/logs') => { rotate }
    ($ROOT + '/cache') => { purge }
}
```

### `match` list patterns: `..` / `..$rest` at any position (v0.117)

Items before the rest pattern match the start of the list, items after it match the end.
0.116 ignored the items after `..` silently, so `[.., 'done']` matched `[build test]`.
Two rest patterns in one list pattern are a parse error.

```nushell
match [1 2 3 4] { [$first, ..$middle, $last] => $middle }   # => [2, 3]   (0.116: [2, 3, 4])
match [build test] { [.., 'done'] => 'finished', _ => 'running' }   # => running   (0.116: finished)
match [a] { [$x, ..$mid, $y] => 'two or more', _ => 'short' }      # => short
```

### `@structured` — an extern that returns data (v0.117)

`@structured [args] { decode }` on an `extern` adds the arguments and decodes the output whenever Nushell uses it: piped into an internal command or saved with `let`.
To the terminal, `print`, a file, `complete`, `ignore` or another external, the command runs as written.
`^git status` always runs as written.

```nushell
@structured [--porcelain] { lines | parse --regex '^(?<status>..) (?<file>.+)$' }
extern "git status" []

git status | where status =~ M | get file   # runs `git status --porcelain` => ["a.txt"]
let s = git status                          # => [[status, file]; [" M", "a.txt"], ["??", "b.txt"]]
git status                                  # git's own text
```

The arguments go before the user's own, so a format flag the user passes can break the decode; use `^` then.
The `nushell-completions` skill covers externs in full.

### `tui` — small terminal interfaces from a pipeline (v0.116)

A family of builder commands (`tui table`, `tui select`, `tui textbox`, `tui split`, `tui button`, …) that pipe into `tui run`.
`tui run` needs a terminal and returns one record, `{action, focused, selected, page, values, rows, live}`.
`tui debug` paints the same interface without a terminal and can replay keys — the way to test one in a script:

```nushell
[{name: a} {name: b}] | tui table | tui debug --keys [down enter] | select action selected
# => {action: submit, selected: {name: b}}
```

`tui.md` covers the family in full; `help tui debug` lists the key tokens.

### `nu --dap` — debugger for scripts (v0.116)

`nu --dap` starts a Debug Adapter Protocol server over stdio.
An editor with DAP support can then set breakpoints, step through pipelines and inspect variables in a `.nu` script.

### `nu --commands` takes script arguments after `--` (v0.115)

When the command string defines `main`, everything after `--` is passed to it.

```nushell
nu --commands 'def main [name: string, ...rest] { $"hi ($name) ($rest)" }' -- world a b
# => hi world [a, b]
```

---

## Serialization & Formats

### `to nuon --raw-strings` (v0.110)

```nushell
"path\\to\\file" | to nuon --raw-strings  # => r#'path\to\file'#
```

### `to nuon --list-of-records` (v0.112)

```nushell
ls | to nuon --list-of-records --indent 2
# => [{name: "foo", ...}, {name: "bar", ...}]
```

### `to nuon --no-commas` (v0.113)

Omit the optional commas — handy when generating NUON for diff-friendly inclusion in source files.

```nushell
{a: 1 b: 2} | to nuon --no-commas   # => {a: 1 b: 2}
```

Since 0.117 `--raw` together with `--no-commas` is an error (`Incompatible parameters`); 0.116 wrote the corrupt `{a:1b:2}`.

### `to nuon --pretty` and aligned table columns (v0.114)

`--pretty` (`-p`) is shorthand for `--indent 2`.
With any of `--indent` / `--tabs` / `--pretty`, table columns are now aligned:

```nushell
[[name age]; [Alice 30] [Bob 25]] | to nuon --pretty
# [
#   [name,  age];
#   [Alice, 30],
#   [Bob,   25]
# ]
```

### KDL format support (v0.114, reworked v0.115)

`from kdl` / `to kdl`.
Two data models, each the default on one side:

- `from kdl` defaults to `--format nodes` — a list of `{name, args, props, children}` rows, which is what a real config document looks like.
- `to kdl` defaults to `--format jik` ([JSON-in-KDL][jik]) — one top-level `-` node, so records and lists serialize predictably.
  This replaced the 0.114 heuristic that flattened values under synthetic node names like `root`.

`--spec 1` / `--spec 2` picks the KDL language version (default 2).
Parsing is strict: v1 keywords (`true`/`false`/`null`) and v2 keywords (`#true`/`#false`/`#null`) are not mixed.

```nushell
{a: 1 b: true} | to kdl              # => - a=1 b=#true
{a: 1 b: true} | to kdl --spec 1     # => - a=1 b=true
'node one; node two' | from kdl | to kdl   # round-trips as two nodes
```

Nu type annotations survive the round trip, the same way YAML tags do:

```nushell
'node (filesize)1024' | from kdl | get 0.args.0   # => 1.0 kB (a filesize)
{size: 1kb} | to kdl                              # => - size=(filesize)1000
```

[jik]: https://github.com/kdl-org/kdl/blob/main/JSON-IN-KDL.md

### `url encode` / `url decode` handle non-UTF-8 (v0.114)

```nushell
'£ rates' | encode iso-8859-1 | url encode              # binary input ok
'%A3%20rates' | url decode --binary | decode iso-8859-1 # binary output opt-in
```

### `save` preserves TOML comments and formatting (v0.113)

Round-tripping a TOML file no longer strips comments, blank lines, or inline-table layout.
`Cargo.toml` style files can now be programmatically edited without losing context.

```nushell
open Cargo.toml | update package.version '1.1.0' | save --force Cargo.toml
# comments above [package] and on untouched keys survive;
# the trailing comment on the key you changed is dropped
```

### `save --force` creates missing parent directories (v0.116)

A `mkdir ($path | path dirname)` before `save --force` is no longer needed.
Without `--force`, a missing parent is still an error (`Directory not found`).

```nushell
'hi' | save --force build/out/report.txt   # creates build/out/ first
```

### `from dotenv` / `to dotenv` — `.env` files (v0.117)

`open` reads `.env`, `.env.local` and `prod.env` as a record, and `save` writes a record to them as dotenv text.
The parser handles comments, `export`, quotes, multiline values and `${VAR}` expansion from earlier keys or the environment.
It runs no commands: `$(…)` and backticks stay text.
`to dotenv` joins a `PATH` list with the path separator and quotes values that need it.

```nushell
# .env:  export HOST=example.org / PORT=8080 / URL="http://${HOST}:${PORT}"
open .env | get URL                  # => http://example.org:8080   (0.116: open gave raw text)
open .env | load-env                 # loads the variables
{A: 'x y', PATH: ['/bin' '/usr/bin']} | to dotenv
# => A='x y'
# => PATH=/bin:/usr/bin
```

`load-env`, `with-env` and `FOO=bar cmd` now apply `$env.ENV_CONVERSIONS`, so a string `PATH` becomes a list.
A `.env` file that is not `KEY=value` lines now fails to open; read it with `open --raw`.
`migration.md` covers both breaks.

### `save` binds the flags of a custom `to <ext>` (v0.117)

`save file.<ext>` calls a custom `to <ext>` command with its flag defaults bound.
0.116 failed inside the converter with `Variable not found` for a flag with a default.

```nushell
def "to tsvx" [--sep: string = "\t"]: table -> string { each { values | str join $sep } | str join "\n" }
[[a b]; [1 2]] | save --force out.tsvx   # out.tsvx holds "1\t2"
```

### `to md --list` (v0.110)

```nushell
[a b c] | to md --list ordered   # numbered list
[a b c] | to md --list none      # plain text (old behavior)
```

### `to md` table cells: `|` escaped (v0.108), line breaks as `<br>`, row order kept (v0.117)

No more broken markdown tables from data containing `|`.
Since 0.117 a line break in a cell is written as `<br>`, and rows with different columns stay in input order, with empty cells for the missing columns.

```nushell
[{a: 1, b: 2} {a: 3} {b: 4} {a: 5}] | to md
# => | a | b |
# => | --- | --- |
# => | 1 | 2 |
# => | 3 |  |
# => |  | 4 |
# => | 5 |  |
# 0.116 moved the {a: 5} row before {b: 4}
```

### `from md` — structured markdown parsing (v0.112, refined v0.113)

```nushell
open README.md             # 0.113: concise human-friendly rows
open --raw README.md | from md --verbose  # full AST (type, position, attrs, children)
open --raw README.md       # raw string
```

### `to text --no-newline` (v0.100)

```nushell
[a b] | to text --no-newline  # no trailing newline
```

### `to txt` alias, `into binary` from duration (v0.115)

`to txt` is a second name for `to text`, following the `to yaml` / `to yml` pattern.
`into binary` now accepts durations.

```nushell
[a b c] | to txt   # same as: to text
1sec | into binary # => 8 bytes, little-endian nanoseconds
```

### `format number --no-prefix` (v0.106)

`format number` returns a record of every representation; `--no-prefix` drops `0x`, `0b`, `0o`.

```nushell
255 | format number --no-prefix | get lowerhex   # => "ff"
```

### `bytes split` — streaming binary split (v0.102)

```nushell
open --raw file | bytes split 0x[00] | each { decode }
```

### `source null` / `use null` — conditional sourcing (v0.102)

```nushell
const file = if ('local.nu' | path exists) { 'local.nu' } else { null }
source $file  # no-op when null
```

---

## Standard Library (`std`, `std-rfc`)

### `std/clip` — clipboard (v0.106, promoted from std-rfc)

```nushell
use std/clip
'data' | clip copy
clip paste
```

### `std-rfc/iter recurse` — recursive descent (v0.105)

Equivalent to jq `..`.
Flattens nested structures.

```nushell
use std-rfc/iter *
{a: {b: 1 c: [2 3]}} | recurse | where ($it.item | describe) == 'int'
```

### `std-rfc/iter only` — assert exactly one element (v0.106)

```nushell
use std-rfc/iter *
ls | where name == 'foo.txt' | only modified
```

### `std-rfc/random choice` (v0.107)

```nushell
use std-rfc/random
$list | random choice 3
```

### `std-rfc/str dedent` (v0.103)

`dedent` wants the text to start with a newline and removes the indent of the last line (it errors with `First line must be empty` otherwise).
For a string without that shape, `unindent` removes the smallest indent.

```nushell
use std-rfc/str *
"
  hello
    world
  " | dedent                         # => "hello\n  world"
"  hello\n  world" | unindent       # => "hello\nworld"
```

### `std-rfc/kv` — key-value store (v0.103)

SQLite-backed, supports named tables (v0.107).

```nushell
use std-rfc/kv *
'data' | kv set mykey
kv get mykey
kv set key val --table project_settings
```

### `std-rfc/conversions` (v0.103)

`into list`, `columns-into-table`, `name-values`, `record-into-columns`, `table-into-columns`.

### `log set-level` (v0.102)

It takes the numeric level: 10 DEBUG, 20 INFO, 30 WARNING, 40 ERROR, 50 CRITICAL (`log log-level` prints the table).

```nushell
use std/log
log set-level 10   # show debug messages
```

### `std/log --context` — structured fields on a log line (v0.116)

Every emitter (`log debug`, `log info`, …, `log custom`) takes `--context <record>`, printed as `key="value"` pairs after the message.
A custom format places it with `%CONTEXT%`.

```nushell
use std/log
log info 'request done' --context {user: Ana, ms: 42}
# 2026-09-27T02:53:38.888|INF|request done user="Ana" ms="42"
```

### `std-rfc/str lcp` — longest common prefix (v0.113)

```nushell
use std-rfc/str *
[foobar foobaz foo123] | lcp
# => {prefix: foo, rest: [bar, baz, "123"], success: true}
```

### `std-rfc/iter prod` — cartesian product (v0.113)

The argument is a record of named lists; the input list becomes the `in` column.

```nushell
use std-rfc/iter *
[a b] | prod {n: [1 2]}   # => [[in, n]; [a, 1], [a, 2], [b, 1], [b, 2]]
prod {size: [s l] color: [red blue]}   # no input: product of the record alone
```

### `std-rfc/iter recurse` multiple cell paths (v0.113)

Pass several cell paths to descend into multiple shapes in one call.

### `std-rfc/url` (v0.113)

Change one part of a URL without a round trip through `url parse` / `url join`: `url with-host`, `with-port`, `with-path`, `with-fragment`, `with-params`, or several at once with `url replace`.
Import the module without `*` — the commands are named `with-params` etc. inside it, and `use std-rfc/url` puts the `url` prefix in front.

```nushell
use std-rfc/url
'https://example.com/a?x=1' | url with-params {y: 2}                        # => https://example.com/a?y=2
'https://example.com/a?x=1' | url replace --host example.org --path b       # => https://example.org/b?x=1
```

### `std-rfc/pb` — terminal progress bars via OSC 9;4 (v0.113)

Sets the host terminal's taskbar/dock progress (where supported — iTerm, WezTerm, ConEmu, etc.).

```nushell
use std-rfc/pb
try {
    0..<10 | each {|x| sleep 200ms; pb set-idx $x 10 }
} catch { pb error } finally { pb clear }
```

### `std-rfc/date floor` / `date ceil` (v0.115)

Round a datetime down or up to a duration boundary — bucketing timestamps without arithmetic on the parts.

```nushell
use std-rfc/date *
2026-07-15T12:11:10-04:00 | date floor 1hr   # => 2026-07-15 12:00:00
2026-07-15T12:11:10-04:00 | date ceil 1hr    # => 2026-07-15 13:00:00
```

### More std commands stream (v0.114)

`std/iter intersperse` / `flat-map`, `std-rfc/conversions into list`, and `std-rfc/tables select/reject column-slices` no longer collect their input; `std-rfc/iter only` consumes at most 2 items.
Safe in long/unbounded pipelines now.

---

## Tables & Display

### `input list` overhaul — fuzzy, multi-select, per-column (v0.111)

```nushell
ls | input list --fuzzy --multi
ls | input list --fuzzy --per-column
```

### Table modes: `"single"` (v0.105), `"double"` (v0.106)

```nushell
$env.config.table.mode = 'single'   # thin lines, sharp corners
$env.config.table.mode = 'double'   # double-line box drawing
```

### `config use-colors` (v0.102)

```nushell
if (config use-colors) { $'(ansi green)ok(ansi reset)' } else { 'ok' }
```

### `random uuid` with version (v0.103)

```nushell
random uuid --version 7  # time-ordered UUID v7
```

### Structured verbose for `mkdir` / `mv` / `rm` (v0.113)

`--verbose` now returns queryable tables instead of human text — scripts can filter on the result.

```nushell
mkdir --verbose existing new | where created   # one row per argument; only `new` is kept
mv --verbose *.log archive/ | get message      # columns: source, destination, message
rm --verbose old/*                             # columns: path, deleted, error
```

Before 0.116 `mkdir --verbose` reported `created: true` for a directory that already existed.

### `mkdir --fail-if-exists` (v0.116)

Plain `mkdir` still succeeds silently on an existing directory.
With `--fail-if-exists` it errors (`File exists`) — a cheap lock or "run once" guard.

```nushell
try { mkdir --fail-if-exists .lock } catch { error make 'another run is active' }
```

### `idx` — in-memory filesystem index (v0.113)

Fast fuzzy file/path lookup and content search backed by an in-process index.
Persisted with `export`/`import`.

```nushell
idx init ~/repos                       # build index
idx find 'skill'                       # fuzzy match files and dirs
idx search --regex 'TODO\(\w+\)'       # content search across indexed files
idx dirs                               # which directories are indexed
idx status                             # memory / counts
idx drop                               # free memory
```

0.114 refinements: `idx init` content-indexes by default; hits print relative to cwd; `idx search` takes `[` / `?` literally (globs still filter *which files* to search: `idx search pattern */tests/*`); and `--context 2` / `--context -3..5` adds surrounding lines to matches.

0.115: `idx export` / `idx import` were removed — the index is in-memory only, so `idx init` is the single way to build it.
Watching stays on by default (`--no-watch` disables it), and the new `idx watch` streams change events as rows of `{kind, path}`:

```nushell
idx init . --wait
idx watch '**/*.rs' --ignore [target] | where kind == 'modified' | each {|e| lint $e.path }
idx watch --max-events 1 --timeout 5sec   # terminate cleanly
```

### `$env.NU_BACKTRACE = 1` (v0.103)

Enable nushell-level backtraces for debugging error chains.

### Metadata: pipeline span (v0.106), `--path-columns` (v0.111)

```nushell
# point errors at pipeline source
ls | metadata access {|m| error make {msg: 'bad' label: {text: 'here' span: $m.span}} }

# enable path rendering in custom tables
glob * | wrap path | metadata set --path-columns [path]
```

Since 0.117 `metadata <expr>` ignores pipeline input, so `[1] | each {|x| (metadata $x).span }` works; 0.116 failed with `Incompatible parameters`.

### Width-priority columns in `table` (v0.114)

Tag columns that must keep their width when the terminal is narrow — untagged wide columns get truncated first:

```nushell
ps --long | select name command pid | metadata set --table-width-priority-columns [pid]
```

Since 0.117 the priority also holds under `table --expand`.
One priority column keeps at least a third of the table width (or its natural width, when that is less); several priority columns share the room, so each can get less.
A priority column does not bring back a column hidden behind `...`.

### `metadata access` closure can mutate caller env (v0.113)

Previously the closure ran in an isolated scope.
Now it behaves like `do --env`, so `$env` assignments and `cd` inside the closure leak out.

```nushell
ls | metadata access {|m| $env.LAST_LISTED = $m.span.start }
# $env.LAST_LISTED is set in the caller after the pipeline
```

### `pre_prompt` / `env_change` hooks can edit the commandline (v0.113)

Hooks can rewrite the buffer the user is about to submit (e.g. inject a prefix, rewrite a deprecated command).
Previously they were read-only.

### `ansi gradient --fgnamed` / `--list` (v0.113)

Named gradients replace having to spell out start/end hex codes.

```nushell
'banner' | ansi gradient --fgnamed rainbow
ansi gradient --list   # show all named palettes
```

### `ansi opt` — shorter escape sequences (v0.117)

Rewrites ANSI escapes in a string, binary or byte stream to a shorter form with the same look — for colored output saved to a file or sent over a slow link.

```nushell
let s = $"(ansi red)(ansi reset)(ansi red)a(ansi reset)"
[($s | str length) ($s | ansi opt | str length)]   # => [19, 10]
```

---

## Other 0.115 Notes

### Performance worth knowing about

- `lines` on a string *value* returns a list stream instead of building the whole list first — it is lazy now, like it already was for byte streams.
- `str replace --regex` / `--multiline` is roughly 10x faster over lists, tables, and records with many string values.
- Built-in commands with `--regex` parameters share an LRU regex cache, so tight loops no longer recompile the pattern.
- Reading a small part of a big list or table (`$list.0`) no longer copies the whole value; large binary values are cheaper to slice and convert too.

### Fixes that change script behavior

- A nested `try/finally` no longer swallows the outer handler — an error after the inner block is caught by the outer `try`/`catch` as it should be.
  The remaining `finally` gaps (order, `return`, `break`, `continue`) were fixed in 0.116 — see "`try`/`catch`/`finally`" above.
- `group-by` treats `null` consistently: it is no longer folded into `""`, and record output omits it.
  Use `--to-table` to keep null groups.
- `math max` on an *empty stream* now errors like it already did on an empty list, instead of returning nothing.
- `"" | path type` returns `null`, not `"dir"`.
- Quotes inside a `(...)` subexpression of an interpolated string parse: `$"('" "')"` prints `" "`.
- `error make` rejects an invalid `label` (missing `span: {start, end}`) instead of silently using the record's own span.

### Interactive / REPL (little effect on scripts)

- Helix edit mode: `$env.config.edit_mode = helix`, with `helix_normal` / `helix_insert` / `helix_select` keybinding tables and `cursor_shape.helix_*`.
- `commandline set-prompt` updates a rendered prompt from a background job, so a slow segment (git branch, k8s context) can fill in asynchronously.
- `color_config.selection` / `selection_cursor` style the visual selection.
- Completion results are cached across prompts; cap with `$env.config.completions.cache_size` (default `100`).

### `matrix` custom value

0.115 adds a `matrix` custom value backed by ndarray, with a family of subcommands: constructors (`matrix zeros`, `matrix identity`, `into matrix`), access, arithmetic, linear algebra (`matrix multiply`, `matrix transpose`), reshaping, `matrix map`, reductions, and `matrix into-nu` to get a table back.
`each` / `par-each` / `reduce` on a matrix error and point at the matrix equivalent.
See the 0.115 release notes for the full list.

```nushell
[[1 2 3] [4 5 6]] | into matrix | matrix transpose | matrix into-nu | to nuon
# => [[1.0, 4.0], [2.0, 5.0], [3.0, 6.0]]
```
