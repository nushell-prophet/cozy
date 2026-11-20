use cprint.nu [ completions-colors ]
use history.nu [ get-last-commands-from-sql ]
use str.nu [ "str c" "str to-md-fence" "str to-raw-string" ]

# Open table in Less
@category viewers
export def 'L' [
    --abbreviated (-a): int = 1000
    --bat (-b) # Use bat instead of less
]: any -> nothing {
    table --expand --abbreviated $abbreviated | into string | if $bat { bat } else { less --RAW-CONTROL-CHARS }
}

# use std repeat

# Construct bars based on a given percentage from a given width (5 is default)
#
# https://github.com/nushell/nu_scripts/blob/bar/sourced/progress_bar/bar.nu
# > bar 0.2
# █
#
# > bar 0.71
# ███▌
@category chart
export def 'bar' [
    percentage: float
    --background (-b): string = 'default'
    --foreground (-f): string = 'default'
    --progress (-p) # Output the result using 'print -n'
    --width (-w): int = 5
]: nothing -> string {
    let blocks = [null "▏" "▎" "▍" "▌" "▋" "▊" "▉" "█"]
    let full_bar = $blocks | last
    let whole_part = '' | fill --character $full_bar --width (($percentage * $width) // 1 | into int)

    let fraction = $blocks
        | get (
            ($percentage * $width) mod 1
            | $in * ($blocks | length | $in - 1)
            | math round
            | into int # Why: 0.114 parse-time typing — `get` rejects `number` as cell-path
        )

    let result = $"($whole_part)($fraction)"
        | fill --character ' ' --width $width
        | if ($foreground == 'default') and ($background == 'default') { } else {
            $"(ansi --escape {fg: ($foreground) bg: ($background)})($in)(ansi reset)"
        }

    if $progress {
        print --no-newline $"($result)\r"
    } else {
        $result
    }
}

# Check crates.io for newer versions of your `cargo install`-ed binaries.
#
# A pure-nushell stand-in for `cargo install-update -a` (from the `cargo-update` crate) —
# it needs no extra tooling, just `cargo` and network access. Each installed crate is
# compared against its latest stable version on crates.io. Crates installed from git or a
# local path carry a `source` and can't be compared, so they are listed but not checked.
#
# > cargo-updates
# > cargo-updates --outdated   # only the ones with a newer stable version
@category development
export def 'cargo-updates' [
    --outdated (-o) # Show only crates that have a newer stable version
]: nothing -> table {
    let installed = cargo install --list
        | lines
        | parse --regex '(?m)^(?<name>\S+) v(?<version>[^ :]+)(?: \((?<source>[^)]+)\))?:$'

    let checked = $installed | par-each {|c|
        if $c.source != null {
            # Not from crates.io (git/path install) — nothing to compare against.
            {name: $c.name, installed: $c.version, latest: null, updatable: false, source: $c.source}
        } else {
            let latest = try {
                let cr = http get --headers [User-Agent "nu-goodies cargo-updates"] $"https://crates.io/api/v1/crates/($c.name)"
                    | get crate

                # Why: prefer the latest *stable* release; fall back to newest only for
                # crates that have never cut a stable version.
                $cr.max_stable_version | default $cr.newest_version
            } catch { null }

            {
                name: $c.name
                installed: $c.version
                latest: $latest
                updatable: ($latest != null and (semver-lt $c.version $latest))
                source: null
            }
        }
    }

    $checked
    | if $outdated { where $it.updatable } else { $in }
    | sort-by name
    | sort-by updatable --reverse # stable sort: updatable crates float to the top, names stay ordered
}

# True if version string $a is older than $b, compared by numeric release parts.
# Pre-release (`-rc.1`) and build (`+sha`) metadata are dropped before comparing.
export def semver-lt [a: string, b: string]: nothing -> bool {
    let pa = $a | split row '+' | first | split row '-' | first | split row '.' | into int
    let pb = $b | split row '+' | first | split row '-' | first | split row '.' | into int
    let n = [($pa | length) ($pb | length)] | math max
    let pa = $pa | append (0..<$n | each { 0 }) | first $n # right-pad with zeros so 1.2 vs 1.2.0 compare equal
    let pb = $pb | append (0..<$n | each { 0 }) | first $n

    for i in 0..<$n {
        let x = $pa | get $i
        let y = $pb | get $i

        if $x != $y { return ($x < $y) }
    }
    false
}

# output a command from a pipe where `example` is used, and truncate the output table
#
# > ls nu-goodies | first 3 | reject modified | example
# ╭───────────name───────────┬─type─┬──size──╮
# │ nu-goodies/str.nu        │ file │ 1.4 KB │
# │ nu-goodies/abbreviate.nu │ file │  898 B │
# ╰───────────name───────────┴─type─┴──size──╯
@category development
export def 'example' [
    --no-copy # Don't copy the output into clipboard
    --no-comment (-C) # Don't comment the result
    --abbreviated: int = 10
    --bare # Don't wrap in `nu -c`, output the raw nushell command
    --cwd # Include CWD into first line comment
    --md # Wrap the result in a ```nu markdown block
]: any -> string {
    let input = table --abbreviated $abbreviated
        | if $no_comment { } else { into string | ansi strip }

    let command = get-last-commands-from-sql 1
        | str replace --regex '\| example.*' ''
        | str trim
        | if $no_comment {
            nu-highlight # for making screnshots
        } else { }
        | if $bare { } else {
            if "'" not-in $in {
                # no single quotes — single-quote wrap (both shells)
                $"nu -c '($in)'"
            } else if ($in !~ '["$`\\]') {
                # only single quotes — double-quote wrap (both shells)
                $'nu -c "($in)"'
            } else {
                # both quote types (or bash-unsafe chars) — raw string, no escaping (nushell)
                $"nu -c ($in | str to-raw-string)"
            }
        }
        | str c $in (char nl)

    $input
    | if $no_comment { } else {
        lines
        | each { str c '# => ' $in }
    }
    | prepend $command
    | str join (char nl)
    | if $cwd { $"# (pwd)\n($in)" } else { }
    | if $md { str to-md-fence } else { }
    | if $no_copy { } else {
        tee { pbcopy }
    }
}

# Format `debug profile` output as a tree of source fragments with duration bars
#
# The `source` column holds only the first line of a block;
# pass `--spans` to `debug profile` for the whole block.
#
# > debug profile {pin-text cyber} --max-depth 7 | format profile
@category development
export def 'format profile' []: table -> table {
    let rows = $in | skip
    let max_duration = $rows.duration_ms | math max

    $rows
    | insert duration_ms_norm {|row| bar ($row.duration_ms / $max_duration) --width 16 }
    | insert hier {|row|
        let depth = $row.depth - 1
        let source = if 'span' in ($row | columns) { view span $row.span.start $row.span.end } else { $row.source }
            | str replace --all --regex '(^|\n)\s+' ''
            | str substring 0..((term size).columns - 40 - $depth * 2)

        (0..<$depth | each { '│ ' } | str join) + '├─' + $source
    }
    | sort-by id
    | reject --optional span source parent_id id depth
}

# Show git commit dates for files, excluding bulk-change commits
#
# A more general solution is in active development: `gitnu`, a Nushell module that gives git as tables.
@category filesystem
export def ls-git-modified-date [
    path?: path
    --max-files-in-commit: int = 5 # skip commits with more than this number of files. Useful for excluding automatic changes such as those by prettier or ruff
]: nothing -> table {
    let path = $path | default { pwd }

    # Why `--no-relative`: under `diff.relative = true` in the git config, `git log` gives the names
    # from the cwd, `git ls-files --full-name` gives them from the root, and the join matches nothing.
    let gitlog = git log --no-relative --all --format="===%ai" --name-only --diff-filter=ACMRT -- $path
        | $"\n($in)"
        | split row "\n==="
        | skip # skip the first empty group
        | each {|i|
            let lines = $i | lines

            let ts = $lines | first | into datetime

            let files = $lines | skip 2

            $files | each {|file| {name: $file commit-ts: $ts bulk: (($files | length) > $max_files_in_commit)} }
        }
        | flatten
        # Why: a file touched only by bulk commits must still be listed. `sort-by` is stable, so
        # within each group the newest commit stays first; `uniq-by` then prefers a non-bulk date
        # and falls back to a bulk one instead of dropping the file from the output entirely.
        | sort-by bulk
        | uniq-by name
        | reject bulk

    let path_candidate = git ls-files --full-name -- $path
        | lines
        | wrap name
        | join $gitlog name --inner

    let root = find-root
    let cwd = pwd

    $path_candidate
    | update name { [$root $in] | path join }
    # Why: names are cwd-relative only when `$path` sits under cwd; otherwise they stay absolute.
    # The trailing slash keeps `/a/bc` from passing as "under" `/a/b`. `--no-symlink` keeps the
    # logical path, the same one `pwd` and `find-root` report, so a symlinked cwd still matches.
    | if ($path | path expand --no-symlink | path join '' | str starts-with ($cwd | path join '')) { update name { path relative-to $cwd } } else { }
    | sort-by commit-ts --reverse
}

#dotnu-vars-end

# def main [ $n_last_commands: int = 2 --regex: string --lines_before_top_of_term: int --min_term_width: int ] {
#     ^wezterm cli get-text --escapes --start-line ($lines_before_top_of_term * -1)
#     | str replace -ra '(\r|\n)+$' ''
#     | lines
#     | skip until {|i| ($i | ansi strip) =~ $regex}
#     | split list --regex $regex
#     | drop
#     | last $n_last_commands
#     | flatten
#     | if $min_term_width == 0 { } else {
#         prepend (seq 1 $min_term_width | each {' '} | str join)
#     }
#     | str join (char nl)
# }

# Open Midnight Commander and cd to its exit directory
@category filesystem
export def --env mc [
    path1?: path
    path2?: path
]: nothing -> nothing {
    let path = ($nu.temp-dir | path join (random chars))
    let dirs = [$path1 $path2] | compact

    ^mc --nosubshell ...$dirs --printwd $path
    if ($path | path exists) {
        cd (open --raw $path)
        rm $path
    }
}

# Create directory and cd into it
@category filesystem
export def --env md [
    target_dir: string
    -d # Use standard directory
    --dest-dir: path = '~/temp'
]: nothing -> nothing {
    let dir = (
        if $d or ($dest_dir != '~/temp') {
            $dest_dir | path join ($target_dir | str replace --all ' ' '_')
        } else { $target_dir }
        | path expand
    )

    mkdir $dir
    if $env.ZELLIJ? != null {
        ^zellij action rename-tab ($target_dir | path basename)
    }
    cd $dir
}

# use number-format.nu

# Format number column in a table using number-format
#
# > [[a]; [123456.678] [2345.8900]] | number-col-format a --denom wt --decimals 2 --significant-digits 3
# ╭──────a───────╮
# │ 123_000.00wt │
# │   2_350.00wt │
# ╰──────────────╯
@category conversions
export def 'number-col-format' [
    column_name: string # A column name to format
    --thousands-delim (-t): string = '_' # Thousands delimiter: number-format 1000 -t ': 1'000
    --decimals (-d): int = 0 # Number of digits after decimal delimiter: number-format 1000.1234 -d 2: 1000.12
    --denom (-D): string = '' # Denom `--denom "Wt": number-format 1000 --denom 'Wt': 1000Wt
    --significant-digits: int = 0 # Round to this number of significant digits; 0 keeps the number as is
]: table -> table {
    let input = $in

    if $column_name not-in ($input | columns) {
        error make {
            msg: 'no such column in the input table'
            label: {text: $'the table has ($input | columns | str join ", ")', span: (metadata $column_name).span}
            help: 'pass one of the column names listed above'
        }
    }

    let formatted = $input
        | get $column_name
        | each {
            (
                number-format --denom $denom --decimals $decimals
                --thousands-delim $thousands_delim --significant-digits $significant_digits
            )
        }

    # Why the header: a table left-aligns strings, so a cell narrower than the header breaks the right edge
    let width = $formatted
        | ansi strip
        | append $column_name
        | str length --grapheme-clusters
        | math max

    # Not `fill --alignment right` because: fill counts the empty color pair of an empty `--denom` as one column
    let padded = $formatted | each {|cell|
        ('' | fill --width ($width - ($cell | ansi strip | str length --grapheme-clusters))) + $cell
    }

    $input | merge ($padded | wrap $column_name)
}

# use significant-digits.nu

# Format big numbers nicely
@example thousands-delimiter { number-format 1000 --thousands-delim "'" | ansi strip } --result "1'000"
@example padding { number-format 123 --integers 6 | ansi strip } --result '   123'
@example decimals { number-format 1000.1234 --decimals 2 | ansi strip } --result '1_000.12'
@example denomination { number-format 1000 --denom 'Wt' | ansi strip } --result '1_000Wt'
@category conversions
export def 'number-format' [
    num?: number # Number to format
    --thousands-delim (-t): string = '_' # Thousands delimiter
    --integers (-i): int = 0 # Length of padding whole-part digits
    --significant-digits: int = 0 # Round to this number of significant digits; 0 keeps the number as is
    --decimals (-d): int = 0 # Number of digits after decimal delimiter
    --denom (-D): string = '' # Denom
    --color: string@completions-colors = 'green'
]: [int -> string float -> string nothing -> string] {
    let in_num = $in

    let parts = $num
        | default $in_num
        | if $significant_digits == 0 { } else {
            significant-digits $significant_digits
        }
        | into string --decimals $decimals
        | split row '.'

    let whole_part = $parts.0
        | str replace --all --regex --no-expand '\B(?=(\d{3})+$)' $thousands_delim
        | fill --width $integers --alignment right

    let number = [$whole_part ...($parts | skip 1)] | str join '.'

    $"(ansi $color)($number)(ansi reset)(ansi green_bold)($denom)(ansi reset)"
}

# Generate 14 lines of spaces (placeholder grid)
@category terminal
export def 'orbita' []: nothing -> list<string> {
    1..14 | each { line ' ' }
}

export def line [
    symbol: string
]: nothing -> string {
    1..61 | each { $symbol } | str join
}

# https://discord.com/channels/601130461678272522/615253963645911060/1182672999921504336
# by @melmass at discord

# Interactively select columns from a table
@category viewers
export def 'select-i' []: table -> nothing {
    let tgt = $in
    let choices = $tgt
        | columns
        | input list --multi "Pick columns to get: "
        | str join " "

    get-last-commands-from-sql 1
    | str replace 'select-i' $'select ($choices)'
    | commandline edit --replace $in
}

# Round a number to n significant digits
#
# > 0.0000012346789 | significant-digits 2
# 0.0000012
#
# > 1.2346789 | significant-digits 3
# 1.23
#
# > 123456789.89 | significant-digits 5
# 123460000
#
# > 1sec / 3 | significant-digits
# 333ms
export def 'significant-digits' [
    n: int = 3 # a number of significant digits
]: [int -> int float -> float duration -> duration] {
    let input = $in
    let type = $input | describe
    let num = if $type == 'duration' { $input | into int } else { $input }

    # Why the guard: `math log` of 0 fails
    let precision = if $num == 0 { 0 } else {
        $n - 1 - ($num | math abs | math log 10 | math floor)
    }

    # Not `math round --precision` for a negative precision because: it scales by a float and
    # leaves noise, `3456789 | math round --precision -5` gives 3499999.9999999995 (0.116.2).
    # An integer factor keeps the result exact.
    let res = if $precision >= 0 {
        $num | math round --precision $precision
    } else {
        let factor = 10 ** (0 - $precision)

        ($num / $factor | math round) * $factor
    }

    match $type {
        'duration' => { $res | into duration }
        'int' => { $res | into int }
        _ => { $res | into float }
    }
}

# Quick tar archiver: pack paths into a timestamped .tar.gz backup
#
# > tarq notes.md pics
# notes.md_20260712_101010.tar.gz
@category filesystem
export def 'tarq' [
    ...paths: path # files or directories to include
    --name: string # archive base name (default: basename of the first path)
    --no-timestamp # name the archive exactly $base.tar.gz
    --ignore: list<string> = [] # paths or patterns to exclude (tar --exclude)
]: nothing -> string {
    if ($paths | is-empty) {
        error make {msg: 'provide at least one path to archive'}
    }

    # Why: timestamp is appended even with --name — a backup command that
    # silently overwrites the previous archive on re-run defeats its purpose
    let base = $name | default ($paths.0 | path expand | path basename)
    let archive = $base
        | if $no_timestamp { } else {
            $'($in)_(date now | format date "%Y%m%d_%H%M%S")'
        }
        | $in + '.tar.gz'

    # Why: excludes go before the file list — bsdtar (macOS) only applies
    # --exclude to paths that come after it; GNU tar doesn't care
    let excludes = $ignore | each { $'--exclude=($in)' }

    tar --create --gzip --file $archive ...$excludes -- ...$paths

    $archive
}

# checks for toolkit.nu file in the dir, and puts into commandline `overlay use as tk`
@category development
export def --env 'tt' []: nothing -> oneof<table, nothing> {
    if ('toolkit.nu' | path exists) {
        commandline edit "overlay use 'toolkit.nu' --prefix as tk; commandline edit 'tk'"
    } else {
        print 'No toolkit.nu in the current folder. Here are the first 3 files:'
        ls | first 3
    }
}

# riggrep to output table to capture paths via "[^\\s│]+:\\d+:\\d+" in wezterm
@category development
export def --wrapped 'rgv' [...rest]: any -> table {
    rg --vimgrep ...$rest
    | lines
    | each {
        split row ':' --number 4
        | {path: ($in | first 3 | str join ':') content: ($in | last)}
    }
}

# Find files matching the glob that contain the fixed string
export def 'files-containing' [
    find: string
    glob_pattern: string
    no_rg: bool = false
]: nothing -> list<string> {
    if (which rg | is-empty) or $no_rg {
        glob --no-dir $glob_pattern
        | where {|i| open --raw $i | str contains $find }
        | path relative-to (pwd)
    } else {
        # explicit `.` — without a path rg reads stdin when stdin is not a tty
        rg $find --fixed-strings --files-with-matches --glob $glob_pattern .
        | complete
        # rg exits 1 on "no matches" — not an error here
        | if $in.exit_code > 1 { error make --unspanned {msg: $in.stderr} } else { $in.stdout }
        | lines
        | str replace --regex '^\./' ''
    }
}

# Replace a fixed string in the given files; return the changed lines
# as a table with rgv-style `path:line:col` links
export def 'replace-in-files' [
    find: string
    replace: string
    files: list<string>
]: nothing -> table {
    $files
    | each {|file|
        let old = open --raw $file

        $old
        | str replace --all $find $replace
        | str replace --regex '\n*$' (char nl)
        | save --force $file

        $old
        | lines
        | enumerate
        | where {|l| $l.item | str contains $find }
        | each {|l| {
            path: ([$file ($l.index + 1) (($l.item | str index-of $find) + 1)] | str join ':')
            before: $l.item
            after: ($l.item | str replace --all $find $replace)
        }}
    }
    | flatten
}

# Find and replace text across multiple files by extension
@category filesystem
export def 'replace-in-all-files' [
    find: string # Text to search for
    replace: string # Replacement text
    --quiet # Suppress the changed-lines table and stats
    --no-git-check # Skip uncommitted changes check
    --no-rg # Use Nushell instead of ripgrep
    --extensions: list<string> = [nu md py] # File extensions to process
]: nothing -> oneof<table, nothing> {
    let glob = $extensions
        | str join ','
        | str c '**/*.{' $in '}'

    let files_found = files-containing $find $glob $no_rg

    # check all files before writing any, so a dirty file aborts the whole run
    if not $no_git_check { $files_found | each {|i| git-check-file-clean $i } }

    let changes = replace-in-files $find $replace $files_found

    if not $quiet {
        let field_name = $'total .($extensions) files'

        # I use record here just for decoration
        print {
            $field_name: (glob --no-dir $glob | length)
            'updated': ($files_found | length)
        }

        $changes
    }
}

# Move/rename a file and update references to it in markdown and code
#
# Replaces occurrences of the old path as given, then — if the basename
# changed — occurrences of the bare basename, which catches relative
# links like `../old.md` written from other directories.
@category filesystem
export def 'mv-update-links' [
    from: path # Current path of the file
    to: path # New path of the file
    --quiet # Suppress the changed-lines table
    --no-git-check # Skip uncommitted changes check
    --extensions: list<string> = [nu md py] # File extensions to scan for references
]: nothing -> oneof<table, nothing> {
    if not ($from | path exists) {
        error make {
            msg: 'file to move not found'
            label: {text: 'no such file', span: (metadata $from).span}
            help: 'pass the current path of the file'
        }
    }
    if ($to | path exists) {
        error make {
            msg: 'destination already exists'
            label: {text: 'this path is taken', span: (metadata $to).span}
            help: 'pick a free path, or move the existing file away first'
        }
    }
    let glob = $extensions
        | str join ','
        | str c '**/*.{' $in '}'

    let pairs = [
        [find replace];
        [($from | into string) ($to | into string)]
        [($from | path basename) ($to | path basename)]
    ]
    | uniq
    | where find != replace

    # check every file the whole run will touch before doing anything —
    # the move and the path pass dirty files the later passes see, so
    # checks made mid-run would abort with the work half-applied
    if not $no_git_check {
        git-check-file-clean $from

        $pairs
        | each {|pair| files-containing $pair.find $glob }
        | flatten
        | uniq
        | each {|i| git-check-file-clean $i }
    }

    mv $from $to

    let changes = $pairs
        | each {|pair|
            let files = files-containing $pair.find $glob

            replace-in-files $pair.find $pair.replace $files
        }
        | flatten

    if not $quiet { $changes }
}

# Error if file has uncommitted git changes
export def git-check-file-clean [
    file: path
]: nothing -> nothing {
    let git_status = git status --porcelain -- $file

    if ($git_status | is-not-empty) {
        error make --unspanned {
            msg: (str c 'file has uncommitted changes' (char nl) $git_status)
            help: 'commit or stash them, or pass --no-git-check'
            code: 'nu_goodies::git::file_not_clean'
        }
    }
}

# Insert new lines before the pipe symbol and let/mut
export def 'insert-new-lines' []: string -> string {
    let cmd = $in

    ast --flatten $cmd
    | where {|it| $it.shape == shape_pipe or ($it.shape == 'shape_internalcall' and $it.content in [let mut]) }
    | insert new_lines {|i| if $i.shape == shape_pipe { "\n" } else { "\n\n" } }
    | update span { get start }
    | select span new_lines
    | reverse
    | reduce --fold (
        $cmd
        | split chars
    ) {|i| insert $i.span $i.new_lines }
    | str join
}

# Format Nushell code using Topiary formatter
@category development
export def 'nu-format' [
    --no-new-lines (-n) # Skip automatic line breaks before pipes
]: [nothing -> nothing string -> string] {
    let input = $in

    let cmd = if $input == null {
        get-last-commands-from-sql 2 | first
    } else { $input }

    $cmd
    | if $no_new_lines { } else {
        insert-new-lines
    }
    | topiary format --language nu
    | if $input == null {
        commandline edit --replace $in
        return
    } else { }
}

# Resolve a path to one relative to cwd: as typed when it exists there, else from the repo root
export def 'path from-root' []: string -> string {
    let typed = $in

    if ($typed | path exists) and not ($typed starts-with '/') { return $typed }

    let root = find-root
    let target = if ($typed | path exists) { $typed } else if $root != null and ($root | path join $typed | path exists) {
        $root | path join $typed
    } else {
        error make {msg: $'no file `($typed)` from cwd or from the repo root'}
    }
    | path expand --no-symlink

    # Why: an absolute path outside the repo reads better as is than as a chain of `..`
    if $root == null or not ($target | path join '' | str starts-with ($root | path join '')) { return $target }

    let from = pwd | path split
    let to = $target | path split
    let common = $from | zip $to | take while {|pair| $pair.0 == $pair.1 } | length

    $from | skip $common | each { '..' } | append ($to | skip $common)
    | if ($in | is-empty) { '.' } else { path join }
}

export def 'completions-files-modified' [token: record]: nothing -> record {
    let typed = $token.text
    let resolved = if $typed == '' { $typed } else { try { $typed | path from-root } catch { $typed } }
    # Why: nushell filters suggestions by the typed text, which a path rewritten from the repo root never matches
    let filter = $resolved == $typed

    $resolved
    | if ($in | path type) == 'dir' and $in != '' {
        path join '*' | into glob | ls $in
    } else if not $filter { ls $in } else { ls }
    | sort-by modified --reverse
    | select name modified
    | update name { if $in has ' ' { $'`($in)`' } else { } }
    | update modified { date humanize }
    | rename value description
    | {
        options: {
            case_sensitive: false
            completion_algorithm: fuzzy
            sort: false
            filter: $filter
        }
        completions: $in
    }
}

# Resolve symlinks and return target paths, sorted by modification time
# A path written from the repo root becomes relative to cwd; a path found nowhere is an error
@category filesystem
export def 'fs' [...files: path@completions-files-modified]: nothing -> any {
    $files
    | each { path from-root }
    | uniq
    | each {|i|
        $i
        | if ($in | path type) == symlink {
            ls $i --long
            | update target {|i|
                $i.target
                | if $in starts-with '..' {
                    $i.name
                    | path dirname
                    | path join $i.target
                    | path expand
                    | path relative-to (pwd)
                } else { }
            }
            | get target.0
        } else { }
    }
    | if ($in | length) == 1 {
        first
    } else { }
}

# Pipe files into fzf with bat preview in the right pane. Returns the selected path.
# Lines like `file:line` or `file:line:col` (e.g. from `rgv`) highlight that line.
# Binary files show `file --brief` info instead of bat output.
# With --content the preview shows the cell value itself (for long texts),
# and the selection returns the whole row as a record.
@category filesystem
export def 'fzf-preview' [
    --column: string # column to take values from (table input); defaults to `name`, `path`, or the first column
    --content # preview cell values themselves instead of files; return the selected row as a record
]: [list<string> -> path list<path> -> path table -> path table -> record nothing -> path] {
    let input = $in | default { ls }

    let values = $input
        | if ($in | describe | str starts-with 'list') { } else {
            if $column != null {
                get $column
            } else if 'name' in ($in | columns) {
                get name
            } else if 'path' in ($in | columns) {
                get path
            } else {
                get ($in | columns | first)
            }
        }

    if $content {
        # Why --read0: NUL-separated items keep their newlines, so {} carries
        # the full value to the preview while --no-multi-line flattens the list
        # display; {n} (input index) maps the selection back to the row.
        # Not a temp json file + jq because: leaks files and adds a dependency.
        let idx = $values
            | each { into string }
            | str join (char --integer 0)
            | fzf --read0 --no-multi-line --preview 'printf %s {}' --preview-window 'right:70%:wrap' --bind 'enter:become(echo {n})'
            | into int

        return ($input | get $idx)
    }

    let preview = 'f={}
l=0
if ! [ -r "$f" ]; then
  rest=$(printf %s "$f" | grep --only-matching --extended-regexp ":[0-9]+(:[0-9]+)?$")
  if [ -n "$rest" ]; then
    base=${f%$rest}
    if [ -r "$base" ]; then
      f=$base
      l=$(printf %s "$rest" | grep --only-matching --extended-regexp "[0-9]+" | head -1)
    fi
  fi
fi
start=1
if [ "$l" -gt 0 ]; then
  start=$((l - ${FZF_PREVIEW_LINES:-40} / 2))
  [ "$start" -lt 1 ] && start=1
fi
# Why: plain prefix strip, not realpath --relative-to, which macOS realpath lacks;
# a path outside the cwd stays absolute.
rel=${f#"$PWD/"}
case $(file --brief --mime -- "$f") in
  *binary*) file -- "$rel" ;;
  *) bat --wrap=auto --terminal-width=${FZF_PREVIEW_COLUMNS:-80} --color=always --pager=never --style=header-filename,numbers --file-name="$rel" --line-range=$start: --highlight-line=$l -- "$f" ;;
esac'

    $values
    | to text
    | fzf --preview $preview --preview-window 'right:70%'
    | str trim
}

# Helper function initially from nupm/utils/dirs.nu
#
# Try to find the repository root directory by looking for .git in parent
# directories.
@category filesystem
export def find-root [dir?: path]: [nothing -> path nothing -> nothing] {
    let dir2 = $dir | default { pwd }

    let root_candidate = 1..($dir2 | path split | length)
        | reduce --fold $dir2 {|_ acc|
            if ($acc | path join '.git' | path exists) {
                $acc
            } else {
                $acc | path dirname
            }
        }

    # We need to do the last check in case the reduce loop ran to the end
    # without finding .git
    if ($root_candidate | path join '.git' | path exists) {
        $root_candidate
    } else {
        null
    }
}

# Change directory to git repository root
@category filesystem
export def --env cd-root [dir?: path]: [nothing -> nothing] {
    cd (find-root $dir)
}

# Rename Zellij tab, auto-incrementing duplicates
@category terminal
export def rename-tab [name: string = '']: nothing -> nothing {
    let name = if $name == '' { pwd | path basename | str replace --regex '^-+' '' } else { $name }

    let name_with_index = zellij action query-tab-names
        | lines
        | where $it =~ $"^($name)\(·|\$)"
        | [($in | length) ($in | parse --regex '(\d+)$' | get --optional capture0 | default [0] | into int)]
        | flatten
        | math max
        | if $in > 0 { $'($name)·($in + 1)' } else { $name }

    ^zellij action rename-tab $name_with_index
}
