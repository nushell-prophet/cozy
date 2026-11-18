# Helpers behind the Helix `+` keybindings (config.toml [keys.normal."+"]).
# Loaded by hx-nu via nu-hx-config.nu, so `nu-hx <cmd>` is available in every
# Helix shell call, including nested `hx-nu --commands` evaluations.
#
# Why a module: the bindings used to inline this code in config.toml, pasting the
# selection into the command text through r###########'%{selection}'########### raw
# strings — which breaks on unlucky content (e.g. a stray '#). Here the selection
# arrives on STDIN instead (Helix pipes it for :pipe/:pipe-to — but NOT for
# :append-output/:insert-output, so bindings must use the pipe family), and needs
# no escaping. Only %{buffer_name} and line numbers are still substituted. As a
# .nu file the logic also gets highlighting, `nu --ide-check`, and topiary.
#
# Named nu-hx (not hx) because: `hx annotate` reads as a call to the editor binary.

const HX_BLOCK = path self | path dirname | path join hx-block

# Evaluate the selection and return it with its output appended as `# => ` comment
# lines (the `+ a` / `+ A` bindings). For :pipe, which replaces the selection, so
# the selection itself is echoed back first.
export def annotate [
    --abbreviate # keep the first 7 output lines and note how many were dropped
]: string -> string {
    let sel = $in
    let out = hx-nu --commands $sel o+e>| lines
    let len = $out | length

    $out
    | if $abbreviate and $len > 7 {
        first 7 | append $"... and ($len - 7) more lines"
    } else { }
    | each { $"# => ($in)" }
    # selection ends mid-line -> start the comments on a fresh line
    | if ($sel ends-with "\n") { } else { prepend '' }
    | to text
    | $sel + $in
}

# Strip the `# => ` lines produced by `annotate` (the `+ x` binding).
export def clear-annotations []: string -> string {
    lines | where $it !~ '^# =>' | to text
}

# Settle the CriticMarkup substitutions in the piped text: `--reject` keeps the old
# text, otherwise the new text stays. Any other text comes back unchanged.
# `\ \ a` and `\ \ r` pipe the tag under the cursor here.
export def critic-resolve [--reject]: string -> string {
    let kept = if $reject { '$1' } else { '$2' }

    $in | str replace --all --regex '(?s)\{~~(.*?)~>(.*?)~~\}' $kept
}

# Remove the CriticMarkup comment right after the substitution that starts the piped
# text. `\ \ a` and `\ \ r` pipe from the tag to the end of its line here.
# Why the lookahead: the text goes on to the end of the line, and a lazy match would
# run past this tag to the comment of the next one.
export def critic-drop-comment []: string -> string {
    $in | str replace --regex '(?s)^(\{~~(?:(?!~~\}).)*~~\})\{>>.*?<<\}' '$1'
}

# Evaluate the selection and flatten the result to one NUON line (the `+ f` binding).
# `to nuon` is appended INSIDE the eval: applied outside it would serialize the
# rendered table text, not the data. On its own line so a trailing comment in the
# selection can't swallow it; the selection is right-trimmed so no blank line lands
# between the pipeline and the continuation.
export def flatten []: string -> string {
    let cmd = $in | str trim --right | $in + "\n| to nuon"

    hx-nu --commands $cmd o+e>| str trim --right
}

# Evaluate the selection and write the result as a rectangle on the line(s) below
# it, via hx-block (the `+ b` binding). Edits the file on disk, so the binding
# wraps it in :update / :reload. `run` (0.114) executes hx-block in-process:
# pipeline input reaches its main directly, no extra nu spawn per press.
export def block-below [
    file: string # buffer path (Helix %{buffer_name})
    line: int # anchor line (Helix %{selection_line_end})
]: string -> nothing {
    hx-nu --commands $in | run $HX_BLOCK --below $file $line
}

# Re-align a selected markdown table so its columns line up (the `+ p` binding).
# Only the padding inside the cells changes; cell text is left as written.
# Not pandoc because: it needs an external binary and rewrites the WHOLE selection
# (escapes, list markers, wrapping), not just the table.
export def align-table []: string -> string {
    let src = $in | lines
    let rows = $src | each { str trim }

    let stray = $rows | enumerate | where not ($it.item starts-with '|')

    if ($stray | is-not-empty) {
        error make {msg: $"line ($stray.0.index + 1) is not a table row: ($stray.0.item)"}
    }
    if ($rows | length) < 2 {
        error make {msg: 'a markdown table needs a header row and a separator row'}
    }

    # a table indented under a list item keeps that indent
    let indent = $src | first | parse --regex '^(?<i>\s*)' | get 0.i
    let cells = $rows | each { split-cells }
    let seps = $cells | get 1

    if not ($seps | all { $in =~ '^:?-+:?$' }) {
        error make {msg: $"line 2 is not a separator row: ($rows | get 1)"}
    }

    # a ragged row is padded out, not rejected: markdown renderers accept it too
    let n = $cells | each { length } | math max
    let table = $cells | each {|row| $row | append (($row | length)..<$n | each { '' }) }
    let marks = 0..<$n | each {|i|
        let s = $seps | get --optional $i | default '-'

        {left: ($s starts-with ':') right: ($s ends-with ':')}
    }
    # `str length` counts graphemes, not display columns, so a CJK or emoji cell
    # still lands short — every ASCII table lines up
    let widths = 0..<$n | each {|i|
        $table | reject 1 | each {|row| $row | get $i | str length --grapheme-clusters } | append 3 | math max
    }

    $table
    | enumerate
    | each {|row|
        $marks
        | zip $widths
        | enumerate
        | each {|col|
            let mark = $col.item.0
            let width = $col.item.1

            if $row.index == 1 {
                '' | fill --character '-' --width $width
                | if $mark.left { ':' + ($in | str substring 1..) } else { }
                | if $mark.right { ($in | str substring ..<(-1)) + ':' } else { }
            } else {
                let align = match [$mark.left $mark.right] {
                    [false true] => 'r'
                    [true true] => 'c'
                    _ => 'l'
                }

                $row.item | get $col.index | fill --width $width --alignment $align
            }
        }
        | str join ' | '
        | $"($indent)| ($in) |"
    }
    | to text
}

# Split one markdown table row into trimmed cells. The lookbehind keeps an escaped
# `\|` inside a cell from being read as a column break.
def split-cells []: string -> list<string> {
    str replace --regex '^\|' ''
    | str replace --regex '(?<!\\)\|$' ''
    | split row --regex '(?<!\\)\|'
    | each { str trim }
}

# Copy the selection to the clipboard as an XML <selected-text> tag with file+line
# coordinates (the `+ s` / `+ S` bindings). The path is REPO-RELATIVE (git
# show-prefix + basename); outside a git repo it falls back to the ABSOLUTE path,
# not a bare basename. --absolute skips git entirely.
export def copy-tag [
    file: string # buffer path (Helix %{buffer_name})
    start: int # first selected line (Helix %{selection_line_start})
    end: int # last selected line (Helix %{selection_line_end})
    --absolute # use the absolute path even inside a git repo
]: string -> nothing {
    let sel = $in
    # `path expand` + `git -C` so the lookup hits the file's real dir, not Helix's cwd
    let abs = $file | path expand
    let path = if $absolute { $abs } else {
        let res = ^git -C ($abs | path dirname) rev-parse --show-prefix | complete

        if $res.exit_code == 0 { $"($res.stdout | str trim)($abs | path basename)" } else { $abs }
    }

    $'<selected-text file="($path)" lines="($start)-($end)">($sel)</selected-text>' | pbcopy
}

# Copy the selection as a <selected-text> tag addressed by a change-id link (the `+ t` binding):
# `<selected-text link="<repo>@<change-id>:<path>" lines="a-b">`. The link names the commit
# that last touched the file, so the tag still resolves after a rebase, where a path plus line
# numbers drifts. The link arrives as an argument, made by `cozy git link` in the binding itself:
# a call from this file would be a parse-time dependency on the cozy module, absent on a
# bare-dotfiles host, and one unknown command here kills every Helix<->nushell call.
export def copy-link-tag [
    link: string # from `cozy git link %{buffer_name}`
    start: int # first selected line (Helix %{selection_line_start})
    end: int # last selected line (Helix %{selection_line_end})
]: string -> nothing {
    $'<selected-text link="($link)" lines="($start)-($end)">($in)</selected-text>' | pbcopy
}

# Resolve a fragment link, `path:/fragment/`, to the `path:line:col` that `:open` takes (the `+ o`
# binding). The fragment is a fixed string of the target line, so the link holds no line number:
# an edit above the line moves nothing in it, and it breaks only when the quoted words change,
# which is when the discussion it sits in is stale too (vim's `+/pattern`, the Text Fragments of
# browsers). The first link in the text wins, so the selection may be the backticked span or the
# whole line. The fragment runs to the last `/` before a backtick, a space or the end, so a `/`
# inside the quoted words is fine. A relative path resolves against the directory of the open
# document, as `gf` does, then against the cwd, where `:open` looks: the canvas convention and the
# harness convention for references differ, and both are in use.
# Why zero or several matches is an error, not the first hit: a jump to a wrong line is silent,
# and the fix is a longer fragment, so the error names the lines.
export def resolve-link [
    text: string # the selection (Helix %{selection}); the first `path:/fragment/` in it is the link
    file: string # buffer path (Helix %{buffer_name}), the base of a relative link
]: nothing -> string {
    let link = $text
    | parse --regex r#'(?<path>[^\s`'"]+):/(?<frag>.+)/(?=`|\s|$)'#
    | get --optional 0
    if $link == null { error make --unspanned {msg: $"no `path:/fragment/` link in: ($text)"} }

    let by_doc = $file | path expand | path dirname | path join $link.path
    # Why `path expand`: `path exists` reads `~/` as the home, and `open` reads it as a directory name.
    let path = if ($by_doc | path exists) { $by_doc } else { $link.path | path expand }
    if not ($path | path exists) {
        error make --unspanned {msg: $"($link.path): no such file under ($by_doc | path dirname) or (pwd)"}
    }

    # Why a line that holds `:/fragment/` is skipped: it is a link, not the target, and a link into
    # its own document always holds the fragment it names.
    let hits = open --raw $path
    | lines
    | enumerate
    | where {|r| $r.item has $link.frag and not ($r.item has $":/($link.frag)/") }
    match ($hits | length) {
        1 => $"($path):($hits.0.index + 1):(($hits.0.item | str index-of $link.frag) + 1)"
        0 => (error make --unspanned {msg: $"($path): no line holds /($link.frag)/"})
        _ => {
            let lines = $hits.index | each { $in + 1 } | str join ', '
            error make --unspanned {msg: $"($path): /($link.frag)/ is on lines ($lines); lengthen the fragment"}
        }
    }
}

# The fragment links of a file that `+ o` cannot open: each backticked `path:/fragment/` whose
# fragment matches no line or several lines, with the error the jump would show. Empty when all
# links hold. For agents, to check a canvas before a commit:
# `nu --commands 'use ~/.config/helix/nu-hx.nu; nu-hx check-links <file> | to nuon'`.
# Not a checker that counts matches itself because: it can pass a link that the jump refuses.
export def check-links [
    file: path # the document whose links to check; its relative links resolve against its directory
]: nothing -> table<line: int, link: string, error: string> {
    open --raw $file
    | lines
    | enumerate
    | each {|l|
        $l.item
        | parse --regex r#'`(?<link>[^\s`'"]+:/[^`]+/)`'#
        | each {|m|
            try { resolve-link $m.link $file | ignore } catch {|e|
                {line: ($l.index + 1) link: $m.link error: $e.msg}
            }
        }
    }
    # Why `%`: this module exports its own `flatten`, for the selection text.
    | %flatten
}

# A block tag line: `<!-- Qm… -->` or `<!-- /Qm… -->`, after `# ` in a .nu file; the CID is
# short, 10 characters.
const BLOCK_TAG = '^\s*(# )?<!-- /?Qm[1-9A-HJ-NP-Za-km-z]{8} -->\s*$'
const OPEN_TAG = '<!-- (?<short>Qm[1-9A-HJ-NP-Za-km-z]{8}) -->'
const CLOSE_TAG = '<!-- /(?<short>Qm[1-9A-HJ-NP-Za-km-z]{8}) -->'
# A line marker: `<Qm…>` at the end of a line, after ` # ` in a .nu file.
const LINE_MARKER = '\s*(# )?<(?<short>Qm[1-9A-HJ-NP-Za-km-z]{8})>\s*$'
const SHORT_CID = 10

# The repo of a buffer, as the cybergraph commands need it: the file, the repo root, the signer
# name and the nu-cybergraph-git module of that repo.
# Why the module of the buffer's repo: a branch that changes nu-cybergraph-git runs its own code.
# Why the git name: the spec gives one signer name per participant, and `$env.USER` is
# `agent` inside the container.
def cybergraph-context [file: string]: nothing -> record {
    let abs = $file | path expand
    let dir = $abs | path dirname
    let root = ^git -C $dir rev-parse --show-toplevel | str trim
    let module = $root | path join nu-cybergraph nu-cybergraph-git
    if not ($module | path exists) { error make --unspanned {msg: $"no nu-cybergraph-git module in ($root)"} }
    # Why before any write: the commit of `\ p` adds `cybergraph`, and `git add` refuses a path
    # outside the sparse checkout; the store that the lookups read is not on disk there either.
    # Why `particles/` and not `cybergraph`: the cone keeps every file at the root, so the bare
    # name always matches.
    let sparse = ^git -C $root config --bool --default false core.sparseCheckout | str trim
    if $sparse == 'true' and ('cybergraph/particles/' | ^git -C $root sparse-checkout check-rules | is-empty) {
        error make --unspanned {
            msg: $"cybergraph/ is outside the sparse checkout of ($root): git -C ($root) sparse-checkout add cybergraph"
        }
    }

    {abs: $abs root: $root module: $module signer: (^git -C $dir config user.name | str trim)}
}

# Run nu-cybergraph-git lines in a `nu` subprocess with the module and its conventions loaded, and
# return what they printed, trimmed; their error becomes this command's error.
# Why a subprocess: `use` needs the module path at parse time, and the path depends on the
# repo of the buffer.
def cybergraph-run [ctx: record lines: list<string>]: nothing -> string {
    let script = [
        $"use ($ctx.module | to nuon)"
        $"use ($ctx.module | path join convention.nu | to nuon)"
        ...$lines
    ]
    let run = ^nu --no-config-file --commands ($script | str join "\n") | complete
    if $run.exit_code != 0 { error make --unspanned {msg: ($run.stderr | str trim)} }

    $run.stdout | str trim
}

# The text of a particle from the lines that carry it: without the tag lines, the line markers
# and the common indent, with a newline at the end.
# Why these stay out: a marker must not change the CID it names, and an indented copy of a text
# is the same text.
def cybergraph-text [lines: list<string>]: nothing -> string {
    let body = $lines | where $it !~ $BLOCK_TAG | each { str replace --regex $LINE_MARKER '' }
    let filled = $body | where $it !~ '^\s*$'
    if ($filled | is-empty) { error make --unspanned {msg: "no text to make a particle of"} }
    let indent = $filled | each { parse --regex '^(?<i>\s*)' | get 0.i | str length } | math min

    $body | each { str substring --grapheme-clusters $indent.. } | str join "\n" | $"($in)\n"
}

# The full CIDs of short CIDs, looked up in the store of the cybergraph: null for a short CID that
# names no particle there; several particles that start with one short CID are an error.
# Why `particle-expand` of the module: the store keeps each particle in the shard of its CID,
# and the module holds the one rule for the shard.
def cybergraph-expand [ctx: record shorts: list<string>]: nothing -> list<oneof<string, nothing>> {
    cybergraph-run $ctx [
        $"use ($ctx.module | path join _particle.nu | to nuon) particle-expand"
        $"($shorts | to nuon) | each {|s| particle-expand ($ctx.root | path join cybergraph | to nuon) $s --optional } | to nuon"
    ] | from nuon
}

# The full CID of a particle from its short form, looked up in the store of the cybergraph.
def cybergraph-full-cid [ctx: record short: string]: nothing -> string {
    let found = cybergraph-expand $ctx [$short] | first
    if $found == null { error make --unspanned {msg: $"no particle ($short) in the cybergraph of ($ctx.root)"} }

    $found
}

# Refuse a line marker inside a multi-line string of a .nu file: `# <Qm…>` there is text of the
# string, not a comment.
def cybergraph-refuse-in-string [lines: list<string> line: int]: nothing -> nothing {
    let offset = $lines | first $line | str join "\n" | into binary | bytes length
    let strings = ast --flatten ($lines | str join "\n")
    | where shape in [shape_string shape_string_interpolation shape_raw_string]
    | where span.start < $offset and span.end > $offset
    if ($strings | is-not-empty) {
        error make --unspanned {msg: $"line ($line) is inside a string: a marker there would change it"}
    }
}

# Commit the lines that carry the marker and what the cybergraph of the repo got, and nothing
# else: the other uncommitted edits of the file stay out, as `+ h` leaves them.
def cybergraph-commit [ctx: record start: int end: int message: string]: nothing -> nothing {
    let staged = ^git-stage-lines $ctx.abs $start $end | complete
    # Why stdout: git-stage-lines writes its errors there, for the `:echo` of `+ h`.
    if $staged.exit_code != 0 { error make --unspanned {msg: ($staged.stdout | str trim)} }
    ^git -C $ctx.root add -- cybergraph
    ^git -C $ctx.root commit --quiet --message $message
}

# Make the selected lines a particle of the cybergraph (the `\ p` binding, p for particle):
# `nu-cybergraph-git particle add` stores their text in `<repo root>/cybergraph/particles`, the file
# gets the marker — one line: `<Qm…>` at its end; several lines: `<!-- Qm… -->` and
# `<!-- /Qm… -->` around them; after `# ` in a .nu file — and the marked lines go into one
# commit with the particle, as `+ h` would stage them. The binding reloads the buffer after.
# A marked text whose CID still matches writes nothing. A marked text that changed gets a new
# particle, an `update-particle` link from the old one, and the new marker in place of the old.
# Why the lines come from the disk, not from the selection: the binding saves and waits first,
# so the file holds the buffer, and the command writes it back with the marker.
# Why the file has to be tracked and the index clean: the commit takes the whole index, so a
# change staged before `\ p` would land in it; `git-stage-lines` refuses an untracked file.
export def cybergraph-block [
    file: string # buffer path (Helix %{buffer_name}), saved before the call
    start: int # first selected line (Helix %{selection_line_start})
    end: int # last selected line (Helix %{selection_line_end})
]: any -> nothing {
    let ctx = cybergraph-context $file
    if (^git -C $ctx.root ls-files --error-unmatch -- $ctx.abs | complete | get exit_code) != 0 {
        error make --unspanned {msg: $"($file) is not tracked: commit it first"}
    }
    if (^git -C $ctx.root diff --cached --quiet | complete | get exit_code) != 0 {
        error make --unspanned {msg: "the index holds staged changes: commit or unstage them first"}
    }
    let all = open --raw $ctx.abs | decode utf-8 | lines
    let s = [$start $end] | math min
    let e = [$start $end] | math max
    if $e > ($all | length) { error make --unspanned {msg: $"line ($e) is past the end of ($file)"} }
    let sel = $all | slice ($s - 1)..($e - 1)
    let is_nu = $ctx.abs | str ends-with '.nu'
    let mark = if $is_nu { '# ' } else { '' }
    let line_form = $s == $e
    # The marker the selection carries already: of the one line, or the pair of tags around it.
    let found = if $line_form {
        $sel.0 | parse --regex $LINE_MARKER | get --optional 0.short
    } else {
        let open = $sel | first | parse --regex $OPEN_TAG | get --optional 0.short
        let close = $sel | last | parse --regex $CLOSE_TAG | get --optional 0.short
        if $open != null and $open == $close { $open } else { null }
    }
    if $line_form and $is_nu { cybergraph-refuse-in-string $all $s }

    let text_file = mktemp --tmpdir cybergraph-particle.XXXXXX
    cybergraph-text $sel | save --force $text_file
    let repo = $ctx.root | to nuon
    let cid = cybergraph-run $ctx [$"nu-cybergraph-git particle add ($text_file | to nuon) --dir ($repo)"]
    rm $text_file
    let short = $cid | str substring 0..<$SHORT_CID
    if $found == $short { return }

    let marked = if $line_form {
        [$"($sel.0 | str replace --regex $LINE_MARKER '' | str trim --right) ($mark)<($short)>"]
    } else if $found == null {
        let lead = $sel | where $it !~ $BLOCK_TAG and $it !~ '^\s*$' | first | parse --regex '^(?<i>\s*)' | get 0.i
        [$"($lead)($mark)<!-- ($short) -->" ...$sel $"($lead)($mark)<!-- /($short) -->"]
    } else {
        $sel | update 0 { str replace $found $short } | update (($sel | length) - 1) { str replace $found $short }
    }
    let last = $s + ($marked | length) - 1
    let where = $"($ctx.abs | path relative-to $ctx.root):($s)(if $last == $s { '' } else { $'-($last)' })"
    let message = if $found == null { $"cybergraph: particle ($short) of ($where)" } else {
        let old = cybergraph-full-cid $ctx $found
        cybergraph-run $ctx [$"convention update-particle ($old) ($cid) --keyless-signer ($ctx.signer | to nuon) --dir ($repo) | ignore"] | ignore
        $"cybergraph: particle ($short) replaces ($found) of ($where)"
    }
    ($all | first ($s - 1)) ++ $marked ++ ($all | skip $e) | to text | save --force $ctx.abs
    cybergraph-commit $ctx $s $last $message
}

# The markers of a file against the cybergraph (`nu-hx particles-check <file>`): one row per line
# marker and per block of tags, with the short CID, its lines, whether the text still hashes to
# it (`ok`, `changed`; `unclosed` for an opening tag with no closing one, `empty` for a block
# with no text), and whether the store holds the particle it names.
# Why a command and not a check in `\ p`: any edit makes a marker stale, and the one who asks
# is an agent that reads the file later; `particle cat` then shows the text the marker named.
export def particles-check [
    file: string # the file, as Helix names it or any path
]: nothing -> table<short: string, from: int, to: int, status: string, stored: bool> {
    let ctx = cybergraph-context $file
    let all = open --raw $ctx.abs | decode utf-8 | lines
    let rows = $all | enumerate | each {|l| {n: ($l.index + 1) line: $l.item} }
    let singles = $rows | where line =~ $LINE_MARKER | each {|r|
        {short: ($r.line | parse --regex $LINE_MARKER | get 0.short) from: $r.n to: $r.n text: (cybergraph-text [$r.line]) status: null}
    }
    let blocks = $rows | where line =~ $"^\\s*\(# \)?($OPEN_TAG)\\s*$" | each {|o|
        let short = $o.line | parse --regex $OPEN_TAG | get 0.short
        let close = $rows | where n > $o.n and line =~ $"<!-- /($short) -->" | get --optional 0.n
        match $close {
            null => {short: $short from: $o.n to: $o.n text: null status: unclosed}
            _ if $close - $o.n < 2 => {short: $short from: $o.n to: $close text: null status: empty}
            _ => {short: $short from: $o.n to: $close text: (cybergraph-text ($all | slice $o.n..($close - 2))) status: null}
        }
    }
    let items = $singles ++ $blocks | sort-by from
    let texts = $items | where text != null | get text
    let cids = if ($texts | is-empty) { [] } else {
        cybergraph-run $ctx [
            $"use ($ctx.module | path join _deps cid-v0.nu | to nuon) [cid-v0]"
            $"($texts | to nuon) | each { into binary | cid-v0 } | to nuon"
        ] | from nuon
    }
    let shorts = $items | get short | uniq
    let stored = if ($shorts | is-empty) { [] } else { $shorts | zip (cybergraph-expand $ctx $shorts) | where $it.1 != null | each { $in.0 } }
    let hashed = $items | where text != null | zip $cids | each {|p|
        $p.0 | update status (if ($p.1 | str starts-with $p.0.short) { 'ok' } else { 'changed' })
    }

    $hashed ++ ($items | where text == null)
    | sort-by from
    | each {|i| $i | reject text | insert stored ($i.short in $stored) }
}

# Commit in a Zellij pane that takes this pane's place until git exits (the `+ g` / `+ G`
# bindings); --add stages the whole file first. Returns only when the pane closes.
# Below the scissors line git's editor shows the staged diff word by word, or line by line
# with --line-diff (the `+ + g` / `+ + G` bindings).
# Why word by word: the user commits mostly markdown, where a line is a whole sentence and a
# line diff hides the one word that moved.
# Not `git commit --verbose` for it because: git has no option to make that diff a word diff.
# So the word diff goes into a --template after a scissors line of its own, and
# --cleanup=scissors drops it from the message.
# Why only a `# <path>` line per file and the changed text: the user needs only what changed;
# the blob hashes, the `@@` line numbers and git's status are noise there.
# Why the refusal: a Helix command list runs on after a failed command, so when the save
# fails, :buffer-close! fails with it and leaves the view on [scratch], whose expanded path
# lands in Helix's cwd, where git would commit whatever is staged in that repo.
# Why try, not a $env.LAST_EXIT_CODE check after git: nushell stops the script at the
# failing external, so that check never runs, and --close-on-exit hides the error at once.
# `null |` because catch passes the error record in as $in, and `input` rejects that input.
export def commit [
    file: string # buffer path (Helix %{buffer_name})
    --add # stage the whole file before committing
    --line-diff # show the diff line by line, as `git commit --verbose` does
]: any -> nothing {
    let file = $file | path expand

    if ($file | path type) != 'file' { error make {msg: $"not a file on disk: ($file)"} }
    let dir = $file | path dirname
    let before = head-of $dir

    if $add {
        refuse-ignored (^git -C $dir rev-parse --show-toplevel) $file
        ^git -C $dir add $file
    }

    let template = if $line_diff { null } else { mktemp --tmpdir commit-template.XXXXXX }
    if $template != null {
        let root = ^git -C $dir rev-parse --show-toplevel
        ^git -C $root diff --cached --name-only -z
        | split row (char nul)
        | compact --empty
        | each {|f|
            ^git -C $root diff --cached --word-diff --no-color -- $f
            | lines
            | skip until { $in starts-with '@@' }
            | each { if $in starts-with '@@' { '' } else { } }
            | prepend $"# ($f)"
            | str join (char newline)
        }
        | str join "\n\n"
        | $"\n# ------------------------ >8 ------------------------\n($in)\n"
        | save --force $template
    }
    let git_commit = if $line_diff { 'git commit --verbose' } else {
        $"git commit --no-status --cleanup=scissors --template r#'($template)'#"
    }

    ^zellij run --in-place --close-on-exit --block-until-exit --name commit --cwd $dir -- hx-nu --commands $"try { ($git_commit) } catch { null | input 'press Enter' }" | ignore
    if $template != null { rm $template }
    # Why only when HEAD moved: the user may leave the editor with no commit.
    if (head-of $dir) != $before { queue-add $file $before }
}

# The base of the three-way merge in `merge-save`: the text of the file as Helix read it
# last, under `~/.cache/gi/base/<hash of the absolute path>`. Written by every gi key after
# its write (`:reload` then loads that text), by `C-r`, and by the gi plugin at a turn
# start when none is there (claude-nu `register.ts`, `seedBase`: the same path).
# Why a cache file, not a ref: mid-turn the disk holds an uncommitted write of the agent
# that no commit names, and `C-r` makes it the base.
def base-path [file: path]: nothing -> path {
    $nu.home-dir | path join .cache gi base ($file | path expand | hash sha256 | str substring 0..15)
}

# Remember the file on disk as the base of the next `merge-save` (the `C-r` binding, and
# every gi key after its write). Not a file on disk: nothing to remember.
export def base-note [file: path]: any -> nothing {
    let file = $file | path expand
    if ($file | path type) != 'file' { return }
    mkdir (base-path $file | path dirname)
    cp $file (base-path $file)
}

# `base-note` only when no base is there yet: the gi plugin runs it at every turn start,
# before the agent's first write, when the disk still holds what Helix read.
# Why not always: a base that is there is Helix's last read, and the agent's own writes of
# the previous turn must not replace it.
export def base-seed [file: path]: any -> nothing {
    if not (base-path $file | path exists) { base-note $file }
}

# The base of `merge-save` when `base-note` never ran for the file: the committed text,
# which a fresh Helix buffer and a first write of the agent both start from; outside git,
# or before the first commit, the disk.
def base-text [file: path disk: string]: nothing -> string {
    if (base-path $file | path exists) { return (open --raw (base-path $file)) }
    let head = ^git -C ($file | path dirname) show $"HEAD:./($file | path basename)" | complete
    if $head.exit_code == 0 { $head.stdout } else { $disk }
}

# The `C-r` binding, run by `:echo %sh{…}` just before `:reload`: remember the file on disk as
# the base, take the `✅ ` or `⚠ ` off the pane title, and print what changed on disk since the last
# gi key or `C-r`, the base of `merge-save` (`base-text`):
# `reloaded: +2 -2 lines, the first change at line 10`.
# Not a file on disk: an empty line, and the error of `:reload` takes the status line.
# Why a git failure goes to stdout: `%sh{}` sends stderr only to the Helix log.
export def reload-note [file: path]: nothing -> string {
    let file = $file | path expand
    let note = if ($file | path type) != 'file' { '' } else {
        let before = base-text $file (open --raw $file)
        base-note $file
        let diff = $before | ^git diff --no-index --unified=0 - $file | complete
        let body = $diff.stdout | lines | skip until { $in starts-with '@@' }

        if $diff.exit_code > 1 {
            $"reload-note: ($diff.stderr | str trim)"
        } else if ($body | is-empty) {
            'reloaded: no change on disk'
        } else {
            let added = $body | where $it starts-with '+' | length
            let removed = $body | where $it starts-with '-' | length
            let first = $body.0 | parse --regex '\+(?<line>\d+)' | get 0.line | into int
            $"reloaded: +($added) -($removed) lines, the first change at line ([$first 1] | math max)"
        }
    }
    done-mark-clear
    $note
}

# Write the Helix buffer (stdin, the whole text) to its file, merged with what someone else
# wrote there meanwhile: the agent of a gi canvas, or git with the same text and a new mtime.
# `git merge-file` over three versions: ours the buffer, theirs the disk, base the text Helix
# read last (`base-note`, else `base-text`).
# Why: Helix refuses `:w` once the mtime moved, whatever the content, and `:w!` throws the
# agent's write away. Here nothing is lost: a line both sides changed stays in the file as a
# `<<<<<<<` block, the error counts them, and `commit-file` refuses the file until they are
# resolved (`\ m` finds them).
# Why --diff3: the base inside the block shows what each side changed.
# Why a hint after each label: the user resolves the block by hand and has to see which side
# is which. The names stay: `base` is the term of every git merge tool, and `disk` is not
# always the agent's write, a git switch or rebase writes it too.
# Why refuse an empty buffer: the key has to `select_all` first, and an empty selection
# would write an empty file.
# The text it writes is formatted as on `:w` (`format-as-on-save`).
export def merge-save [file: path]: string -> nothing {
    let ours = $in
    let file = $file | path expand

    if ($file | path type) != 'file' { error make {msg: $"not a file on disk: ($file)"} }
    if ($ours | is-empty) { error make {msg: 'merge-save got an empty buffer: the key has to select_all first'} }
    let disk = open --raw $file
    let base = base-text $file $disk

    if $disk == $base {
        $ours | format-as-on-save ($file | path parse | get extension) | save --force --raw $file
    } else {
        let tmp = mktemp --directory --tmpdir merge-save.XXXXXX
        $ours | save --raw ($tmp | path join helix)
        $base | save --raw ($tmp | path join base)
        # Exits with the number of conflicts, 255 when the merge itself failed.
        let merged = ^git merge-file --diff3 --stdout -L 'helix: your buffer' -L 'base: what helix read last' -L 'disk: the file now, usually the agent' ($tmp | path join helix) ($tmp | path join base) $file
            | complete
        rm --recursive $tmp

        if $merged.exit_code == 255 { error make {msg: $"merge failed for ($file | path basename): ($merged.stderr)"} }
        $merged.stdout | format-as-on-save ($file | path parse | get extension) | save --force --raw $file
        if $merged.exit_code > 0 {
            base-note $file
            error make {msg: $"($merged.exit_code) conflicts in ($file | path basename): resolve the <<<<<<< blocks, then `\\ k`"}
        }
    }
    base-note $file
}

const TRAILING_SPACES = '(?m)[ \t]+$'

# Format the text as `:w` does (`:w` and the gi keys share this command): the formatters of
# markdown and nu in languages.toml call it, and `merge-save` calls it for `\ k` and `\ l`,
# which write the file past Helix. A nu file goes through topiary, then a markdown or nu file
# loses its trailing spaces, also in comments and strings, where topiary keeps them.
# Why all of them: the user wants every trailing space gone; dotnu finds its `# =>` output
# lines with the space optional, so a stripped empty output line does not double.
# Why a regex, not `lines | to text`: it keeps the file byte-exact otherwise, and `to text`
# would rewrite the final newline.
# Why the merged text, not the buffer before the merge: every line the formatter changes is a
# change of ours, and where the agent changed the same line, the merge makes a conflict
# that `:w` never makes. The agent's lines are formatted too, as on `:w`.
# Why a topiary failure keeps the text: a file mid-edit, or a merge with `<<<<<<<` blocks,
# does not parse, and its trailing spaces still go. A machine without topiary (it comes with
# cozy) saves the text unformatted too: `try` catches the missing command, which `complete` does not.
# Why add a final newline where it is missing: `:w` adds one (`insert-final-newline`);
# `\ k` and `\ l` write past Helix, where that setting does not reach.
export def format-as-on-save [
    extension: string # of the file: `md` and `nu` are formatted, any other passes as it is
]: string -> string {
    let text = $in

    match $extension {
        md => $text
        nu => {
            let formatted = try { $text | ^topiary format --language nu | complete }

            if $formatted.exit_code? == 0 { $formatted.stdout } else { $text }
        }
        _ => { return $text }
    }
    | str replace --all --regex $TRAILING_SPACES ''
    | if ($in | is-empty) or ($in | str ends-with "\n") { } else { $in + "\n" }
}

# Where `key` leaves the error of a gi key for `report`: `~/.cache/gi/report/<hash of the
# absolute path>`, keyed as the base is.
def report-path [file: path]: nothing -> path {
    $nu.home-dir | path join .cache gi report ($file | path expand | hash sha256 | str substring 0..15)
}

# Write the buffer (stdin) to its file through `merge-save`, run the action of a gi key, and
# keep the error of either for `report`.
# Why the one reader of stdin is here: a Helix that still runs the old key list (no
# `:config-reload` yet) pipes only the primary selection, and `quick-commit` or `tell-claude`
# must not take that for the buffer.
# Why `report`: under `:pipe-to`, Helix 25.07 takes the stderr of a failed command as its
# output and ignores it, so an error of the key never reached the screen. The key ends with
# `:sh nu-hx report`, which shows the kept error in a popup.
# Why raise it again: the exit code and stderr stay right for a shell that runs the key by hand.
export def key [file: path action: closure]: string -> nothing {
    let buffer = $in
    keep $file { $buffer | merge-save $file; do $action }
}

# Run the action of a key and keep its error for `report` (the `:pipe-to` step of a key whose
# stdin is a selection, not the buffer: nothing is saved here).
export def keep [file: path action: closure]: any -> nothing {
    let report = report-path $file
    let failed = try { do $action; null } catch {|e| $e.msg }

    mkdir ($report | path dirname)
    if $failed == null { rm --force $report } else {
        $failed | save --force --raw $report
        error make {msg: $failed}
    }
}

# Print the error `key` kept for the file, once (the `:sh` step of a gi key): Helix shows a
# non-empty output of `:sh` in a popup, and an empty one as "Command run".
export def report [file: path]: nothing -> string {
    let report = report-path $file
    if not ($report | path exists) { return '' }
    let message = open --raw $report
    rm $report
    $message
}

# The message `quick-commit` writes: the user's markers (2-char `!!` `??` `%%` at a line
# start) and CriticMarkup comments (`{>>`) that the diff adds, and the CriticMarkup
# substitutions it settles (`critic-settled`), e.g. `gi: !! 2, {>> 1, {~~ approved 1`.
# Why counts and not words: in a canvas the instructions live in the text, so the message
# only indexes the batch for Claude and for the log.
# Why 2-char only: `!!!` `???` `%%%` are the agent's, which the user does not add.
export def quick-commit-message []: string -> string {
    let diff = $in | lines
    let added = $diff | where $it =~ '^\+(?!\+\+)'
    let removed = $diff | where $it =~ '^-(?!--)'
    let counts = [
        [tag pattern];
        ['!!' '^\+\s*!!(?!!)'] ['??' '^\+\s*\?\?(?!\?)'] ['%%' '^\+\s*%%(?!%)']
    ]
        | each {|t| {tag: $t.tag n: ($added | where $it =~ $t.pattern | length)} }
        | append {tag: '{>>' n: ($added | str join (char newline) | split row '{>>' | length | $in - 1)}
        | append (
            critic-settled ($removed | str substring 1..) ($added | str substring 1..)
            | uniq --count
            | each { {tag: $"{~~ ($in.value)" n: $in.count} }
        )
        | where n > 0

    if ($counts | is-empty) { 'gi: edit' } else {
        $counts | each { $"($in.tag) ($in.n)" } | str join ', ' | $"gi: ($in)"
    }
}

# The CriticMarkup substitutions that a diff settles, one `approved` or `rejected` per tag:
# a removed line holds `{~~old~>new~~}`, and an added line is that same line with the new
# text (approved) or the old text (rejected) in the place of the tag and its comment, as
# `\ \ a` and `\ \ r` leave it.
# Why the whole line, not a search for the new text: a short substitution (`{~~is~>are~~}`)
# finds its words anywhere in the line.
# A tag over several lines, or a line with other edits too, is not counted here.
def critic-settled [removed: list<string> added: list<string>]: nothing -> list<string> {
    $removed
    | each {|line|
        $line
        | parse --regex '(?<tag>\{~~(?<old>(?:(?!~~\}).)*?)~>(?<new>.*?)~~\}(?:\{>>.*?<<\})?)'
        | insert line $line
    }
    | %flatten
    | each {|t|
        if ($t.line | str replace $t.tag $t.new) in $added {
            'approved'
        } else if ($t.line | str replace $t.tag $t.old) in $added {
            'rejected'
        }
    }
    | compact
}

# Refuse a file that git ignores, before the `git add` of `\ k` or `+ g`.
# Why: `git add` refuses it with only an exit code, and the user must see that the file is
# saved and not committed, and which rule hides it.
# `check-ignore` exits 0 only for an untracked file that a rule ignores; a tracked file passes.
def refuse-ignored [root: path file: path]: nothing -> nothing {
    let ignored = ^git -C $root check-ignore --verbose -- $file | complete
    if $ignored.exit_code == 0 {
        let rule = $ignored.stdout | split row (char tab) | first
        error make {msg: $"($file | path relative-to $root) is saved, not committed: git ignores it \(($rule)\)"}
    }
}

# Commit only this file, as it is on disk, with the `quick-commit-message` (the `\ k`
# binding, after `nu-hx key` wrote the buffer): the step that hands a batch of canvas
# instructions to `\ l`, without a message to write.
# Why the pathspec on commit: it commits this file alone, never what else is staged.
# Why refuse `<<<<<<<`: a `merge-save` conflict is not a text to commit, or to send.
export def quick-commit [file: path]: any -> nothing {
    let file = $file | path expand

    if ($file | path type) != 'file' { error make {msg: $"not a file on disk: ($file)"} }
    let root = ^git -C ($file | path dirname) rev-parse --show-toplevel

    if (open --raw $file | lines | any { $in starts-with '<<<<<<< ' }) {
        error make {msg: $"($file | path basename) still has <<<<<<< blocks: resolve them, then `\\ k`"}
    }
    refuse-ignored $root $file
    ^git -C $root add -- $file
    let diff = ^git -C $root diff --cached -- $file

    if ($diff | is-empty) { error make {msg: $"nothing to commit in ($file | path basename)"} }
    let before = head-of $root
    ^git -C $root commit --quiet --message ($diff | quick-commit-message) -- $file
    queue-add $file $before
}

# The queue of a Claude pane: the files the user committed in its tab and Claude was not sent
# yet, under `~/.cache/gi/unsent/<zellij session>-<pane id of Claude>`, one line with the
# absolute path per commit. `\ k` and `+ g` add to it, `\ l` and the gi Stop hook send all of
# it and remove it, and a `Read` of the agent takes its file out (`tell-claude-on-read`).
# Why a queue per Claude pane, not per file: the user edits several files for one agent, and
# one `\ l` in any of the buffers has to deliver them all.
# Why a line per commit: the gi plugin (claude-nu `register.ts`) shows the count of each file
# in the status line of Claude, and it reads this file with no git and no nu.
# The path repeats `helix-pane` of `tell-claude`: the plugin finds both by the pane of Claude.
def queue-path [claude: any]: nothing -> path {
    $nu.home-dir | path join .cache gi unsent $"($env.ZELLIJ_SESSION_NAME)-($claude)"
}

# The files of a queue, each once, in the order of their first commit; a file that is gone
# from the disk is left out.
def queue-files [queue: path]: nothing -> list<path> {
    if not ($queue | path exists) { return [] }
    open --raw $queue | lines | uniq | where ($it | path type) == 'file'
}

# Add the file to the queue of the Claude pane of this tab, after a commit of the user on top
# of the commit `before` (empty: the first commit of the repo).
# Outside zellij, and in a tab with no Claude pane, there is nobody to tell: nothing is kept.
# Why an error with several Claude panes and none launched for this file: the commit is
# made, and the user has to know that no pane will be sent it.
# A file that was never sent gets its text at `before` as the sent one: without it `unsent`
# starts at the last commit of Claude to the file, or at the first commit of the file, and
# the first `\ l` would send years of the user's commits to a file Claude never wrote.
def queue-add [file: path before: string]: nothing -> nothing {
    if ($env.ZELLIJ_PANE_ID? | is-empty) { return }

    let claudes = ^zellij action list-panes --json --command
        | from json
        | claude-panes $file ($env.ZELLIJ_PANE_ID | into int)

    if ($claudes | is-empty) { return }
    if ($claudes | length) > 1 {
        error make {msg: $"($file | path basename) is committed, not queued for Claude: ($claudes | length) Claude panes in this tab"}
    }
    let file = $file | path expand
    let root = ^git -C ($file | path dirname) rev-parse --show-toplevel
    let ref = sent-ref $file

    if $before != '' and (^git -C $root rev-parse --quiet --verify $ref | complete).exit_code != 0 {
        let text = ^git -C $root rev-parse --quiet --verify $"($before):($file | path relative-to $root)" | complete
        if $text.exit_code == 0 { ^git -C $root update-ref $ref ($text.stdout | str trim) }
    }
    let queue = queue-path $claudes.0.id
    mkdir ($queue | path dirname)
    $"($file)\n" | save --append $queue
}

# The commit a repo stands on; empty in a repo with no commit yet, where git exits non-zero.
def head-of [dir: path]: nothing -> string {
    ^git -C $dir rev-parse --quiet --verify HEAD | complete | get stdout | str trim
}

# The ref that remembers the text of a file as Claude was last sent it (`unsent`).
def sent-ref [file: path]: nothing -> string {
    $"refs/gi/sent/($file | path expand | hash sha256 | str substring 0..15)"
}

# The user's commits to a file that Claude has not been sent, oldest first, and the text of the
# file at the tip that the ref remembers once they are sent: what `\ l` sends, and what the gi
# Stop hook hands over at a turn end (`tell-claude-at-stop`).
# The start is the newest commit whose file is the text of the last send, a blob kept in
# `refs/gi/sent/<hash of the absolute path>`; else the last Claude commit on the file, else the
# file's whole history.
# Why a sent ref, not only the last Claude commit: a user commit made while Claude is
# mid-turn and sent later sits before Claude's next commit, so that range drops it.
# Why the text, not the commit of the send: an amend or a rebase gives the commit a new sha
# and keeps the text, and a ref to a blob keeps no old commit alive.
# A squash after Claude's answer leaves no commit with the sent text, so the start falls back
# to the last Claude commit: the squash itself when an agent made it. An unsent commit of the
# user that the squash folds in is then not sent.
# Why the absolute path in the hash: worktrees share refs, and one canvas path can be
# checked out in several of them.
# Why only the user's commits: Claude's own are no news to Claude; and by author, not by the
# Co-Authored-By trailer, because early agent commits carry the author only.
# Why skip an author address with `+claude@`: that is a chat prompt of the user that Claude
# carried into the canvas under his name (the Canvas style of the gi plugin in claude-nu), so
# it is Claude's own commit too.
# Why the text at the tip, not at HEAD: the range is fixed at the keypress, so the remembered
# text matches what was sent even when the line waits in Claude's queue.
export def unsent [file: path]: nothing -> record<root: string, base: string, shas: list<string>, ref: string, text: string> {
    let file = $file | path expand
    let root = ^git -C ($file | path dirname) rev-parse --show-toplevel
    let ref = sent-ref $file
    let tip = ^git -C $root rev-parse --short=12 HEAD
    let rel = $file | path relative-to $root
    # `complete`, because a missing ref is a normal case and git exits 1 for it, and so is a
    # commit that deleted the file.
    let blob_at = {|rev| ^git -C $root rev-parse --quiet --verify $"($rev):($rel)" | complete | get stdout | str trim }
    let sent = ^git -C $root rev-parse --quiet --verify $"($ref)^{blob}" | complete | get stdout | str trim
    # Why the filter after `--find-object`: it also lists the commit that changed the text away.
    let seen_at = if ($sent | is-empty) { null } else {
        ^git -C $root log --format=%h $"--find-object=($sent)" HEAD -- $file
        | lines
        | where { (do $blob_at $in) == $sent }
        | get --optional 0
    }
    let base = if $seen_at != null { $seen_at } else {
        ^git -C $root log --max-count=1 --format=%h --author='^Claude' -- $file
    }
    let range = if ($base | is-empty) { $tip } else { $"($base)..($tip)" }
    let shas = ^git -C $root log --reverse --format=%h --perl-regexp '--author=^(?!Claude|.*\+claude@)' $range -- $file
        | lines

    {root: $root base: $base shas: $shas ref: $ref text: (do $blob_at $tip)}
}

# The `unsent` records of the files that have commits to send, each with its `file`.
def unsent-of [files: list<path>]: nothing -> table {
    $files
    | each {|file| unsent $file | insert file ($file | path expand) }
    | where ($it.shas | is-not-empty)
}

# The `git show` line for the `unsent-of` records: one command per repo, joined with `;`.
# Why `git show <shas>`, not `git log <range>` with the author filter: the filter needs a `!` in
# the line, and the line runs in Claude's bash mode.
# Why the commits of all the files in one command, by commit time: the user edits the files
# in one order, and a later commit wins over an earlier one, whatever file it is in.
# Why a format of its own: `format.pretty` is made for a human in lazygit, and the user saw an
# agent cut its needless tokens with a `--format`. The commits are the user's, made a moment
# ago, so the date and the author tell Claude nothing; the subject of a `gi:` commit is the
# instruction, so it goes on the line of the sha. `%+N` keeps the notes a custom format hides.
# Not `--- %h`, as in that agent command, because: the diff under it has a `--- a/<file>` line.
# Not a bare format string because: it means `tformat:`, which adds a second blank line before
# each diff.
def show-line [unsents: table]: nothing -> string {
    $unsents
    | group-by root --to-table
    | each {|repo|
        let shas = ^git -C $repo.root show --no-patch --format=%ct%x09%h ...($repo.items.shas | %flatten | uniq)
            | lines
            | parse "{time}\t{sha}"
            | sort-by { $in.time | into int }
            | get sha

        $"git -C ($repo.root) show '--format=format:%h %s%n%b%+N' ($shas | str join ' ') -- ($repo.items.file | str join ' ')"
    }
    | str join '; '
}

# Remember the `unsent-of` records as sent: each ref takes the text of its file at the tip.
def mark-sent [unsents: table]: nothing -> nothing {
    $unsents | each {|u| ^git -C $u.root update-ref $u.ref $u.text } | ignore
}

# The queue of the Claude pane that this process runs in, for the commands that the gi
# plugin calls; null outside zellij.
def own-queue []: nothing -> any {
    if ($env.ZELLIJ_PANE_ID? | is-empty) or ($env.ZELLIJ_SESSION_NAME? | is-empty) { return null }
    queue-path $env.ZELLIJ_PANE_ID
}

# The `\ l` of a turn end, for the Stop hook of the gi plugin (claude-nu `register.ts`): print
# the `git show` line of the `unsent` commits of the canvas and of the queued files, without
# the `!`, and remember them as sent; print nothing when there are none.
# Why: the user commits with `\ k` while Claude works, and a `\ l` for each batch is one action
# too many; the hook hands them over when the turn ends.
# Why no refusal of a dirty file: at a turn end the uncommitted part is the user's draft or
# the agent's answer to it, and the hook hands over commits only.
# Why remember at once, as `tell-claude` does: the range is fixed when it is handed over, so
# the next `\ l` does not send the same commits again.
export def tell-claude-at-stop [file: path]: nothing -> string {
    let queue = own-queue
    let files = if $queue == null { [] } else { queue-files $queue }
    let unsents = unsent-of ([($file | path expand)] | append $files | uniq)

    if $queue != null { rm --force $queue }
    if ($unsents | is-empty) { return '' }
    mark-sent $unsents
    show-line $unsents
}

# For the gi plugin, after the agent read `file` with its Read tool: when the file is the
# canvas or is in the queue, and has `unsent` commits, print them with their diffs, remember
# them as sent and take the file out of the queue; else print nothing.
# Why the diffs and not only a mark that the file is read: the Read tool gives the text as it
# is now, and an instruction is in what changed — a line the user deleted, or one new `!!`
# among hundreds of lines.
# Why printed, not a command to run: the agent cannot skip what is already in its context.
# Why `--no-relative`: with `diff.relative` set, a diff in another folder prints empty.
export def tell-claude-on-read [file: path --canvas: path]: nothing -> string {
    let file = $file | path expand
    let queue = own-queue
    let queued = if $queue == null { [] } else { queue-files $queue }

    if $file not-in ($queued | append ($canvas | default [] | path expand)) { return '' }
    let unsents = unsent-of [$file]

    if $queue != null and $file in $queued {
        let rest = open --raw $queue | lines | where $it != $file
        if ($rest | is-empty) { rm --force $queue } else { $rest | str join (char newline) | $"($in)\n" | save --force $queue }
    }
    if ($unsents | is-empty) { return '' }
    mark-sent $unsents
    ^git -C $unsents.0.root show --no-relative --no-color --no-ext-diff '--format=format:%h %s%n%b%+N' ...$unsents.0.shas -- $file
}

# Take the `✅ ` of the gi Stop hook, or the `⚠ ` of a turn that an API error ended, from the
# title of this pane (the `C-r` binding): the user has read the answer. `DONE_MARK` and
# `ERROR_MARK` in the gi plugin (claude-nu `register.ts`) repeat the prefixes.
# Why only a title with a mark: a name the user gave the pane stays.
# Why not the `⏳ ` of a turn in work: `\ l` runs this too, and the agent still works then.
export def done-mark-clear []: any -> nothing {
    let id = $env.ZELLIJ_PANE_ID? | default '' | into string
    if ($id | is-empty) { return }

    let title = ^zellij action list-panes --json
    | from json
    | where { (not $in.is_plugin) and ($in.id | into string) == $id }
    | get --optional 0.title
    | default ''

    if (['✅ ' '⚠ '] | any {|mark| $title | str starts-with $mark }) {
        ^zellij action undo-rename-pane --pane-id $"terminal_($id)"
    }
}

# The Claude panes in the tab of pane `me`, from `zellij action list-panes --json --command`.
# Among several, the ones launched for this file win (`gi open` puts the canvas path in the
# command line).
def claude-panes [file: path me: int]: list<record> -> list<record> {
    let panes = $in | where is_plugin == false
    let tab = $panes | where id == $me | get 0.tab_id
    let claudes = $panes
        | where tab_id == $tab and id != $me and ($it.pane_command? | default '' | str contains 'claude')
    let bound = $claudes | where pane_command =~ ($file | path basename)

    if ($bound | is-empty) { $claudes } else { $bound }
}

# The pane id of the one Claude session of `claude-panes`; errors when there are 0 or 2+.
export def tell-claude-pane [file: path me: int]: list<record> -> int {
    let pick = $in | claude-panes $file $me

    if ($pick | length) != 1 {
        error make {msg: $"want one Claude pane in this tab, found ($pick | length): ($pick | get title | str join ', ')"}
    }
    $pick.0.id
}

# Type the `!git show` line of the `unsent` commits and Enter into the Claude pane of this tab
# (the `\ l` binding), so Claude reads the new commits without a switch to its pane; then
# remember them as sent. The line holds the commits of this file and of every file in the
# queue of that pane, so one `\ l` in any buffer delivers all that `\ k` and `+ g` committed.
# A file with uncommitted changes (the buffer, written by `nu-hx key` just before) is
# committed first, as `\ k` does: one key per delivery.
# Why `--ignored`: plain `status` prints nothing for an ignored file, and `quick-commit`
# must run to refuse it.
# Why refuse a dirty file after that: the line shows commits only, so Claude would read an
# older text than the one on screen and nothing would say so. Only this file: the buffers of
# the other files are not in reach, and their commits are what the user chose to hand over.
# Why refuse an empty send: the line alone starts a Claude turn, here over nothing.
# Why -C and the absolute paths in the line: Claude's cwd need not be the one of Helix.
# Why typed into the open pane, not a second `claude --resume`: a second process on the
# session forks its transcript, and the open pane never sees the turn (tested with -p).
# Why write-chars, not `zellij action paste`: Claude folds a bracketed paste into a chip.
export def tell-claude [file: path]: any -> nothing {
    let file = $file | path expand
    let claude = ^zellij action list-panes --json --command
        | from json
        | tell-claude-pane $file ($env.ZELLIJ_PANE_ID | into int)
    let pane = $"terminal_($claude)"
    let root = ^git -C ($file | path dirname) rev-parse --show-toplevel

    if (^git -C $root status --porcelain --ignored -- $file | is-not-empty) { quick-commit $file }
    if (^git -C $root status --porcelain -- $file | is-not-empty) {
        error make {msg: $"($file | path basename) has uncommitted changes: commit them with `\\ k` first"}
    }
    let queue = queue-path $claude
    let files = [$file] | append (queue-files $queue) | uniq
    let unsents = unsent-of $files

    if ($unsents | is-empty) {
        rm --force $queue
        error make {msg: $"no new commits of yours to ($files | path basename | str join ', ')"}
    }

    # Why a file: the Stop hook of the gi plugin (claude-nu `register.ts`, `helixPane`, the same
    # path) has to know which pane to mark, and only this side knows both panes.
    let panes = $nu.home-dir | path join .cache gi helix-pane
    mkdir $panes
    $env.ZELLIJ_PANE_ID | into string | save --force ($panes | path join $"($env.ZELLIJ_SESSION_NAME)-($claude)")
    done-mark-clear

    ^zellij action write-chars --pane-id $pane $"!(show-line $unsents)"
    ^zellij action send-keys --pane-id $pane Enter
    mark-sent $unsents
    rm --force $queue
}

# The pane id of the one nu shell in the tab of pane `me`, from `zellij action list-panes
# --json --command`; errors when the tab has 0 or 2+ of them.
export def nu-pane [me: int]: list<record> -> int {
    let panes = $in | where is_plugin == false
    let tab = $panes | where id == $me | get 0.tab_id
    let shells = $panes
        | where tab_id == $tab and id != $me
        | where ($it.pane_command? | default '' | split row ' ' | first | path basename) == 'nu'

    if ($shells | length) != 1 {
        error make {msg: $"want one nu pane in this tab, found ($shells | length): ($shells | get title | str join ', ')"}
    }
    $shells.0.id
}

# Paste the file into the nu pane of this tab and press Enter there (the `+ r` binding).
# Why paste, not write-chars: a typed newline submits the line in nu, so a pipeline over
# several lines would run only its first line; a bracketed paste keeps it one entry.
export def send-to-nu [file: path]: any -> nothing {
    let pane = ^zellij action list-panes --json --command
        | from json
        | nu-pane ($env.ZELLIJ_PANE_ID | into int)
        | $"terminal_($in)"

    ^zellij action paste --pane-id $pane (open --raw $file | str trim --right)
    ^zellij action send-keys --pane-id $pane Enter
}

# List the keys of one normal-mode table of config.toml (`+`, `\`, `+ +`) with what each does:
# the `#…→` label a prompt binding shows, else the comment at the end of the key line,
# else the first sentence of the comment above the key, else the command itself.
# Why: Helix's own `+` popup shows a multi-command key only as "[Multiple commands]".
# Why one table: `?` of each table lists only that table's own keys.
# Parses the raw text, because a TOML parser drops the comments.
export def keys [
    table: string # the keys that open the table, space-separated: `+`, `\` or `+ +`
    config: path = (path self | path dirname | path join config.toml)
]: nothing -> table<key: string, does: string> {
    let header = $table
    | split row ' '
    | each { $'"($in | str replace --all '\' '\\')"' }
    | str join '.'
    | $"[keys.normal.($in)]"
    let label = {|line| $line | parse --regex ':[a-z-]+ #(?<l>.*)→$' | get --optional 0.l }

    open --raw $config
    | lines
    | skip until { $in == $header }
    | skip 1
    | take until { $in starts-with '[' }
    | reduce --fold {rows: [] comment: []} {|line acc|
        if ($line starts-with '#') {
            $acc | update comment { append ($line | str replace --regex '^#\s?' '') }
        } else if ($line =~ '^\S+ = ') {
            let kv = $line | parse --regex '^(?<key>\S+) = (?<value>.*)' | first
            let row = {
                key: ($kv.key | str trim --char "'")
                label: (do $label $line)
                trailing: ($kv.value | parse --regex r#'["'\[\]]\s+#\s(?<c>.*)$'# | get --optional 0.c)
                about: ($acc.comment | str join ' ' | split row --regex '(?<=\.)\s' | first)
                value: $kv.value
            }

            $acc | update rows { append $row } | update comment []
        } else {
            let l = do $label $line

            $acc
            | if $l != null and ($acc.rows | last | get label) == null {
                update rows { update ($in | length | $in - 1) { update label $l } }
            } else { }
            | if ($line | str trim | is-empty) { update comment [] } else { }
        }
    }
    | get rows
    | each {|r|
        let does = [$r.label $r.trailing $r.about $r.value] | where $it not-in [null '']

        {key: $r.key does: ($does | first)}
    }
}

# The blocks of a file by the commit that last touched each line, in the order of the commits
# (the `] h` / `[ h` bindings walk them). A block is a run of consecutive lines with one commit in
# `git blame`; the lines not committed yet form the newest blocks.
# Why blame on the current file, not `git log -p`: blame gives every present line its commit
# directly, while a diff per commit gives line numbers in old states of the file that every later
# commit shifts. The cost: a line touched twice counts for the later commit only.
# Why the order from `git rev-list`, not the commit dates: amend and rebase move the dates.
# Why rev-list without the path: blame follows a rename, `rev-list -- <path>` does not.
export def change-blocks [
    file: string # buffer path (Helix %{buffer_name})
]: nothing -> table<order: int, sha: string, subject: string, start: int, end: int> {
    let blamed = ^git blame --line-porcelain -- $file
    | parse --regex '(?m)^(?<sha>[0-9a-f]{40,64}) \d+ (?<line>\d+)(?: \d+)?\n(?:[^\t\n][^\n]*\n)*?summary (?<subject>[^\n]*)'
    | update line { into int }
    let shas = $blamed.sha | uniq
    let commits = ^git rev-list --reverse --topo-order HEAD | lines | where $it in $shas

    $blamed
    | sort-by line
    | chunk-by {|r| $r.sha }
    | each {|c|
        let committed = $c.0.sha in $commits
        {
            order: (if $committed { $commits | enumerate | where item == $c.0.sha | get 0.index } else { $commits | length })
            sha: $c.0.sha
            subject: (if $committed { $c.0.subject } else { 'not committed' })
            start: $c.0.line
            end: ($c | last | get line)
        }
    }
    | sort-by order start
}

# The line to go to for the change after the one at `line` (`--back`: before it): the first line
# of the next block of `change-blocks`. At the last block the line stays, so the key is a no-op there.
# `--newest` and `--oldest` ignore `line` and go to the ends of the walk: the user reads a canvas
# from the newest answer back, so `] H` then `[ h` is the usual walk.
export def next-change [
    file: string # buffer path (Helix %{buffer_name})
    line: int # the line of the cursor (Helix %{cursor_line})
    --back # the previous change instead
    --newest # the newest change of the file
    --oldest # the oldest change of the file
]: nothing -> int {
    let blocks = change-blocks $file
    if $newest { return ($blocks | last | get start) }
    if $oldest { return ($blocks | first | get start) }
    let at = $blocks | enumerate | where {|b| $line >= $b.item.start and $line <= $b.item.end } | get --optional 0.index
    if $at == null { error make --unspanned {msg: $"($file): line ($line) is not in the file on disk; save the buffer first"} }
    let target = if $back { $at - 1 } else { $at + 1 }
    if $target < 0 or $target >= ($blocks | length) { $line } else { $blocks | get $target | get start }
}

# The markers that `\ m` searches for, as one regex for a line: the agent's markers, its newest
# `AA*:` entries, CriticMarkup comments and substitutions, merge conflicts.
# The `m` macro in config.toml spells the same set in Helix keys: change the two together.
const MARKERS = '!!!|\?\?\?|%%%|\{>>|\{~~|AA\*:|^<{7}'

# The panes of this Zellij session, with the command, the cwd and the tab of each.
def zellij-panes []: nothing -> list<record> {
    if ($env.ZELLIJ? | is-empty) {
        error make --unspanned {msg: "not in a Zellij session: the open canvases are the files of its panes"}
    }
    ^zellij action list-panes --all --json | from json
}

# The files that a pane named when it started, resolved against its cwd: the file arguments of a
# Helix pane, and the canvas of a Claude pane that `gi open` started (its `--name`).
# Why the launch line: Helix tells no other process which buffers it holds. The cost: a file that
# Helix opened later, with `:open` or a picker, is not seen.
def pane-files [pane: record]: nothing -> table<file: path, helix: bool> {
    let words = $pane.pane_command? | default '' | split row ' ' | where $it != ''
    let bin = $words | get --optional 0 | default '' | path basename
    let names = match $bin {
        hx => ($words | skip 1 | where $it !~ '^[+-]')
        claude if ($pane.pane_command | str contains 'gi:Canvas') => ($pane.pane_command | parse --regex '--name (?<n>\S+)' | get n)
        _ => []
    }

    $names | each {|n| {file: ($pane.pane_cwd | path join $n) helix: ($bin == hx)} }
}

# Whether a file is a canvas bound to a session: a `session:` in its frontmatter, or in the
# `const gi` record that opens a `.nu` canvas.
def canvas-session [file: path]: nothing -> bool {
    let lines = open --raw $file | lines
    let first = $lines | get --optional 0 | default ''
    let head = if $first == '---' {
        $lines | skip 1 | take until { $in == '---' }
    } else if ($first | str starts-with 'const gi = {') {
        $lines | take until { $in == '}' }
    } else { [] }

    $head | any { $in =~ '^\s*session:' }
}

# The canvases open in this Zellij session, newest edit first; the input is `zellij-panes`.
# The canvas of a Claude pane counts as it is; a file that only Helix holds counts when
# `canvas-session` says it is a canvas. `tab` is the tab of the Claude pane when there is one, and
# `helix` lists the Helix panes that hold the file, those of that tab first.
export def open-canvases []: list<record> -> table<file: path, tab: string, claude: bool, helix: list<int>, modified: datetime> {
    $in
    | where is_plugin == false and ($it.pane_cwd? | is-not-empty)
    | each {|p| pane-files $p | insert pane $p.id | insert tab_id $p.tab_id | insert tab $p.tab_name }
    | %flatten
    | where ($it.file | path type) == file
    | update file { path expand }
    | group-by file --to-table
    | each {|g|
        let claude = $g.items | where not $it.helix
        let home = $claude | get --optional 0 | default ($g.items | first)
        let helix = $g.items | where $it.helix | sort-by {|h| $h.tab_id != $home.tab_id }

        {
            file: $g.file
            tab: $home.tab
            claude: ($claude | is-not-empty)
            helix: $helix.pane
            modified: (ls $g.file | get 0.modified)
        }
    }
    | where {|c| $c.claude or (canvas-session $c.file) }
    | sort-by modified --reverse
}

# The lines of a file that hold a marker of MARKERS: the 1-based number and the trimmed text of each.
# Code spans and fenced blocks do not count: a marker in backticks is a mention of it.
# Why trimmed: the text becomes the fragment of a link, and a fragment matches inside a line.
export def file-markers [file: path]: nothing -> table<line: int, text: string> {
    open --raw $file
    | lines
    | enumerate
    | reduce --fold {fence: false hits: []} {|r acc|
        if ($r.item | str trim --left | str starts-with '```') {
            $acc | update fence { not $in }
        } else if not $acc.fence and ($r.item | str replace --all --regex '`[^`]*`' '' | $in =~ $MARKERS) {
            $acc | update hits { append {line: ($r.index + 1) text: ($r.item | str trim)} }
        } else {
            $acc
        }
    }
    | get hits
}

# The text of the list that `\ M` opens: a heading per canvas with markers, and under it one fragment
# link per marker, the link that `\ o` and `+ o` follow; the canvases with no marker share the last line.
# The input is `open-canvases` with two more columns: `markers` from `file-markers`, and `edited`.
# Why the whole line as the fragment: the list shows what the marker says, and the link still finds
# the line after an edit above it.
# Why absolute paths: the canvases are in different worktrees, so a relative path is no shorter.
export def open-markers-text []: table -> string {
    let canvases = $in
    let clean = $canvases | where ($it.markers | is-empty)
    let body = $canvases
        | where ($it.markers | is-not-empty)
        | each {|c|
            let claude = if $c.claude { '' } else { ', no Claude pane' }

            ['' $"## ($c.file | path basename)" $"tab ($c.tab), edited ($c.edited)($claude)" '']
            | append ($c.markers | each { $"($c.file):/($in.text)/" })
        }
        | %flatten
    let tail = if ($canvases | is-empty) {
        ['' 'No canvas is open in this Zellij session.']
    } else if ($clean | is-not-empty) {
        let names = $clean | each { $"($in.file | path basename) in tab ($in.tab)" } | str join ', '

        ['' $"No open markers: ($names)."]
    } else { [] }

    ['# Open markers' '' '`\ o` on a line jumps to its marker, in the tab of its canvas.']
    | append $body
    | append $tail
    | str join (char newline)
    | $"($in)(char newline)"
}

# Write the list of the markers of every open canvas and return its path (the `\ M` binding opens it).
# Why a file and not a scratch buffer: the next `\ M` writes it again and `:reload` refreshes the
# one buffer, where a scratch buffer per press would pile up.
export def open-markers []: nothing -> path {
    let out = $nu.home-dir | path join .cache gi open-markers.md

    mkdir ($out | path dirname)
    zellij-panes
    | open-canvases
    | insert markers {|c| file-markers $c.file }
    | insert edited {|c| $c.modified | date humanize }
    | open-markers-text
    | save --force $out
    $out
}

# Open the fragment link in `text` in the Helix pane of its canvas, and switch to that tab (the
# `\ o` binding, which sends the line of the cursor). Then return `file`, so that the `:open` of
# the binding only reopens this buffer.
# Return the target for an `:open` here, as `+ o` does, when the link names no open canvas, when
# this pane holds the canvas, when no Helix pane does, and outside Zellij.
# Why the tab of the canvas: `\ l` hands the commits of a file to the Claude pane of its own tab,
# so a canvas answered in another tab would reach the wrong session.
# Why Esc first: in insert mode or in a prompt, that Helix would take `:open` as text.
export def open-link-in-tab [
    text: string # the selection (Helix %{selection}); the first `path:/fragment/` in it is the link
    file: string # buffer path (Helix %{buffer_name}), the base of a relative link
]: nothing -> string {
    let target = resolve-link $text $file
    if ($env.ZELLIJ? | is-empty) { return $target }

    let path = $target | str replace --regex ':\d+:\d+$' '' | path expand
    let helix = zellij-panes | open-canvases | where file == $path | get --optional 0.helix | default []
    let me = $env.ZELLIJ_PANE_ID | into int
    if ($helix | is-empty) or $me in $helix { return $target }

    let pane = $"terminal_($helix.0)"
    ^zellij action send-keys --pane-id $pane Esc
    ^zellij action write-chars --pane-id $pane $":open ($target)"
    ^zellij action send-keys --pane-id $pane Enter
    ^zellij action focus-pane-id $pane
    $file
}
