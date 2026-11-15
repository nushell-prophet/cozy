# Render structured data so a human and an agent can both read it.
#
# Nushell's own table is built for a terminal of known width: it pads columns
# with box-drawing rules, collapses a nested value to `[list 3 items]`, and
# drops whole columns into a bare `...` when the width runs out. A human sitting
# at a wide terminal loses nothing. Anything reading the output as text — an
# agent, a log, a pipe — loses the data and cannot tell that it did.
#
# Three rules, in order of importance:
#   1. Never lose data silently. Every elision names what it hid and prints the
#      cell path that fetches it.
#   2. Never truncate by terminal width. Long lines run; the reader soft-wraps.
#      A row budget is a different thing and is allowed: the terminal's width is
#      not a property of the data, but the size of the output is, and stopping
#      at a row boundary with a runnable `skip N` loses nothing under rule 1.
#   3. Spend characters on alignment (the human half), not on borders (nobody).
#
# The layout follows R's tibble print method — dimensions line, a type row under
# the column names, no borders, quantities right-aligned, and `--glimpse` for a
# table too wide to read across — and adds the one thing a dataframe never needs:
# nushell cells hold lists, records and whole tables, so an elided cell prints
# the path that brings it back.
#
# Why the name: "tibble" is R's `tbl` read aloud; `nibble` swaps the t for the
# n of nu, and a nibble is a small bite — what the character budget takes from
# a large table.

# Why to nuon and not `to text` for scalars: nuon keeps a filesize as `4096b`
# and a datetime as ISO 8601. `to text` renders them as `4.0 kB` and
# "a day ago", which are shorter to read but ambiguous to act on.
def render-cell [path: string max: int]: any -> string {
    let v = $in
    let d = ($v | describe)

    if $d == "nothing" {
        "null"
    } else if $d == "datetime" {
        # Why seconds: a filesystem mtime carries nanoseconds that are noise to
        # both readers and cost ~10 characters a row. The type row says
        # `datetime`, so the reader knows this is a rendering; `to nuon` keeps
        # the full precision when it matters.
        $v | format date "%Y-%m-%dT%H:%M:%S%:z"
    } else if $d == "duration" {
        # nuon gives `19314000000000ns`; nobody reads that. `into string` gives
        # `5hr 21min 54sec`, just as unambiguous and far shorter.
        $v | into string
    } else if $d == "string" {
        # A bare string needs no quotes, but one holding a newline would split
        # the row in two. Not `to nuon` because: nuon keeps the newline
        # literal, so the row still breaks. JSON escapes it to `\n`.
        if ($v | str contains "\n") { $v | to json --raw } else { $v }
    } else if ($d | str starts-with "list") or ($d | str starts-with "table") or ($d | str starts-with "record") {
        let inline = ($v | to nuon)
        if ($inline | width) <= $max { $inline } else { $"<($d) ⇒ get ($path)>" }
    } else {
        $v | to nuon
    }
}

# The type of a column across every value, not just the first — a column that
# mixes types is a fact worth showing, not smoothing over.
def column-type []: list -> string {
    let types = ($in | each {|v| $v | describe } | uniq)
    match ($types | length) {
        1 => ($types | first)
        _ => ($types | str join "|")
    }
}

# Quantities right-align, everything else left-aligns — tibble's rule. Lining up
# the ones place is what lets a reader compare magnitudes down a column without
# reading a single digit. A null does not break the run: it is a missing
# quantity, not a value of another kind.
const QUANTITIES = [int float filesize duration]

def column-aligns-right []: list -> bool {
    let types = ($in | each {|v| $v | describe } | uniq)
    ($types | any {|t| $t in $QUANTITIES }) and ($types | all {|t| ($t in $QUANTITIES) or ($t == "nothing") })
}

# How many terminal columns a string occupies. Not `str length` because: it
# counts UTF-8 bytes by default, so "русский" measures 14 and every Cyrillic
# cell pads wrong. Graphemes give the character count; CJK and emoji then need
# one extra column each, since they render double-width.
const WIDE = "[\u{1100}-\u{115F}\u{2E80}-\u{A4CF}\u{AC00}-\u{D7A3}\u{F900}-\u{FAFF}\u{FE30}-\u{FE6F}\u{FF00}-\u{FF60}\u{FFE0}-\u{FFE6}\u{1F300}-\u{1FAFF}]"

def width []: string -> int {
    let s = $in
    let graphemes = ($s | str length --grapheme-clusters)
    # Fast path, and not a nicety: the scan below runs a regex against every
    # character, and `width` is called two or three times per cell, so a flat
    # 2000×4 table spent 1.2 of its 1.6 seconds here. A string whose byte count
    # equals its grapheme count is pure ASCII — nothing in it is wide and
    # nothing is a multi-byte cluster — so that count is already the width.
    # Almost every cell qualifies; the ones that do not still pay full price.
    if ($s | str length --utf-8-bytes) == $graphemes {
        return $graphemes
    }
    $graphemes + ($s | split chars | where $it =~ $WIDE | length)
}

def pad [w: int --right]: string -> string {
    let s = $in
    let gap = ("" | fill --width ([($w - ($s | width)) 0] | math max))
    if $right { $gap + $s } else { $s + $gap }
}

# Line the decimal points up under each other — the second half of tibble's
# numeric pillar. Right-aligning alone puts `3.14159` and `1358.0` on a common
# right edge, which is where their last digits happen to fall, not where their
# ones place is; the eye then reads no magnitude from position at all.
#
# Not pillar's rounding to a shared significant-digit count, which is how tibble
# gets a rectangular column: it would print a number the data does not hold,
# and rule 1 here is never lose data silently. So the fraction is padded, not
# cut, and a long one widens the column instead of shortening its neighbours.
def align-decimal []: list<string> -> list<string> {
    let cells = $in
    # A cell that does not open with a digit is not a number to align — `null`,
    # `inf`, `NaN`. It keeps the plain right alignment of the whole column.
    let parts = (
        $cells | each {|s|
            if ($s =~ '^-?[0-9]') {
                let split = ($s | split row --number 2 ".")
                {int: ($split | first) frac: ($split | get --optional 1)}
            } else {
                {int: null frac: null}
            }
        }
    )

    let fracs = ($parts | get frac | compact)
    if ($fracs | is-empty) { return $cells }

    let fw = ($fracs | each {|f| $f | width } | math max)
    let iw = ($parts | each {|p| if $p.int == null { 0 } else { $p.int | width } } | math max)

    $cells | enumerate | each {|c|
        let p = ($parts | get $c.index)
        match $p {
            {int: null} => ($c.item | pad ($iw + 1 + $fw) --right)
            # An integer among floats has no dot to sit on, so it stops where
            # the dot would be — its ones place still lines up with theirs.
            {frac: null} => (($p.int | pad $iw --right) + ("" | fill --width ($fw + 1)))
            _ => (($p.int | pad $iw --right) + "." + ($p.frac | pad $fw))
        }
    }
}

def dim [--on]: string -> string {
    if $on { $"(ansi dark_gray)($in)(ansi reset)" } else { $in }
}

def render-record [v: record --max-cell: int --color]: nothing -> string {
    let pairs = ($v | items {|k val| {key: $k ty: ($val | describe) val: ($val | render-cell $k $max_cell)} })
    let kw = ($pairs | get key | each {|k| $k | width } | math max)
    let tw = ($pairs | get ty | each {|t| $t | width } | math max)
    let title = ($"# record ($pairs | length) fields" | dim --on=$color)
    let lines = (
        $pairs | each {|p|
            $"(($p.key | pad $kw))  (($p.ty | pad $tw) | dim --on=$color)  ($p.val)" | str trim --right
        }
    )
    [$title] ++ $lines | str join "\n"
}

# tibble's `glimpse()`: one line per column instead of one line per row, for a
# table too wide to read across. Nothing is dropped in the turn — every value a
# row would have shown is still on its column's line, so the transposition costs
# nothing but the alignment between rows.
def render-glimpse [cols: list<string> types: list<string> cells: list --no-types --color]: nothing -> list<string> {
    let cw = ($cols | each {|c| $c | width } | math max)
    let tw = ($types | each {|t| $t | width } | math max)
    $cols | enumerate | each {|c|
        let vals = ($cells | get $c.index | str join ", ")
        let ty = (if $no_types { "" } else { $"(($types | get $c.index) | pad $tw | dim --on=$color)  " })
        $"(($c.item | pad $cw))  ($ty)($vals)" | str trim --right
    }
}

# How many rows fit the character budget, decided before a single cell is
# rendered — measuring the finished output would mean doing the work the budget
# exists to avoid. A row's nuon length tracks its rendered length closely
# enough: the padding adds a little, the quotes and commas give a little back.
# Twenty rows is enough of a sample, and costs microseconds where rendering the
# same rows costs milliseconds.
def rows-for-budget [max_chars: int]: list -> int {
    let v = $in
    if ($v | is-empty) { return 0 }
    let sample = ($v | first 20)
    let per_row = (($sample | to nuon | str length) / ($sample | length))
    [1 (($max_chars / $per_row) | math round | into int)] | math max
}

# Render a table, record, or list as aligned plain text with a type row, losing
# nothing to the terminal width and naming every value it had to elide.
@example "a nested list survives, where the box table shows a list 2 items placeholder" {
    [{i: 1 files: [a b]}] | nibble
} --result "# table 1×2\n     i  files\n   int  list<string>\n0    1  [a, b]"
export def main [
    --max-cell: int = 60 # inline a nested value up to this width, then elide it
    --head: int # render only the first N rows and announce the rest
    --max-chars: int = 10_000 # stop near this much output and announce the rest
    --all # render every row, whatever it costs
    --no-types # drop the type row
    --glimpse # transpose: one line per column, for a table too wide to read across
]: [any -> string] {
    let v = $in
    let d = ($v | describe)
    # Colour only when a human is watching. `is-terminal --stdout` and not
    # `$nu.is-interactive` because: the latter reports REPL-ness, and it is true
    # for an agent driving the nushell MCP and false for any `nu script.nu`.
    let color = (is-terminal --stdout)

    if ($d | str starts-with "record") {
        return (render-record $v --max-cell $max_cell --color=$color)
    }
    if not (($d | str starts-with "table") or ($d | str starts-with "list")) {
        return ($v | render-cell "" $max_cell)
    }

    let total = ($v | length)
    let limit = (
        if $all { null } else if $head != null { $head } else { $v | rows-for-budget $max_chars }
    )
    let indexed = ($v | enumerate)
    let shown = (if $limit == null { $indexed } else { $indexed | first $limit })
    let rows = ($shown | get item)

    # A list of scalars has no columns of its own; give it one so the same
    # alignment code covers both shapes.
    let scalar_list = (($rows | all {|r| ($r | describe) !~ '^record' }) and ($rows | is-not-empty))
    let cols = (if $scalar_list { ["value"] } else { $rows | each {|r| $r | columns } | flatten | uniq })

    # Column-major first: the type row and the cells both need the same values,
    # and a list of scalars has no key to look them up by.
    # Why the {v: …} wrapper: `each` drops a closure that returns null, so a
    # missing key would shorten the column instead of leaving a hole in it.
    # Boxing the value and pulling the column back out preserves the nulls.
    let by_col = (
        $cols | each {|c|
            if $scalar_list { $rows } else { $rows | each {|r| {v: ($r | get --optional $c)} } | get v }
        }
    )

    let indices = ($shown | get index)
    let types = ($by_col | each {|vals| $vals | column-type })

    # Render every cell once, column-major: both layouts need the same strings,
    # and the path an elision prints names the row it came from either way.
    let cells = (
        $cols | enumerate | each {|c|
            $by_col | get $c.index | enumerate | each {|v|
                # A list of scalars has no column to address, so `get 0.value`
                # would not run where `get 0` does.
                let path = (
                    if $scalar_list { $indices | get $v.index | into string } else { $"(($indices | get $v.index)).($c.item)" }
                )
                $v.item | render-cell $path $max_cell
            }
        }
    )

    let lines = (
        if $glimpse {
            render-glimpse $cols $types $cells --no-types=$no_types --color=$color
        } else {
            # The row index is a quantity too, and the widths carry the whole
            # column — name, type and cells — so a number keeps its header.
            let aligns = ([true] ++ ($by_col | each {|vals| $vals | column-aligns-right }))

            # Only the row layout stacks its cells, so only it lines up the dots.
            # In a glimpse the values sit side by side on one line, where padding
            # inside a number would be noise.
            let stacked = (
                $cols | enumerate | each {|c|
                    let col = ($cells | get $c.index)
                    if ($aligns | get ($c.index + 1)) { $col | align-decimal } else { $col }
                }
            )

            let body = (
                $indices | enumerate | each {|s|
                    [($s.item | into string)] ++ ($cols | enumerate | each {|c| $stacked | get $c.index | get $s.index })
                }
            )
            let header = ([""] ++ $cols)
            let type_row = (if $no_types { [] } else { [([""] ++ $types)] })
            let matrix = ([$header] ++ $type_row ++ $body)

            # Why outliers are excluded: one 2000-character cell would otherwise pad
            # every other row in its column out to 2000, costing more whitespace than
            # the data. A column sized by its typical cells keeps them aligned and lets
            # the rare giant overflow its own row — misaligned, but never hidden.
            let widths = (
                0..($cols | length) | each {|i|
                    let lens = ($matrix | each {|row| $row | get $i | width })
                    let typical = ($lens | where $it <= $max_cell)
                    if ($typical | is-empty) { $max_cell } else { $typical | math max }
                }
            )

            $matrix | enumerate | each {|m|
                let text = (
                    $m.item | enumerate | each {|c|
                        $c.item | pad ($widths | get $c.index) --right=($aligns | get $c.index)
                    } | str join "  " | str trim --right
                )
                # The type row is scaffolding — dim it for a human, but leave the column
                # names at full strength, since those are what a reader scans for. In a
                # pipe nothing is dimmed at all, so an agent sees no escape codes.
                if (not $no_types) and $m.index == 1 { $text | dim --on=$color } else { $text }
            }
        }
    )

    let shape = (if $glimpse { "glimpse" } else { "table" })
    let title = ($"# ($shape) ($total)×($cols | length)" | dim --on=$color)
    let more = (
        if ($limit != null) and ($total > $limit) {
            [($"# ($total - $limit) more rows ⇒ skip ($limit)" | dim --on=$color)]
        } else { [] }
    )

    [$title] ++ $lines ++ $more | str join "\n"
}
