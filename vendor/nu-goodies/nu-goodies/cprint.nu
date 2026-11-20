# Print a string colorfully with bells and whistles
@category strings
export def main [
    text?: string # Text to format, if omitted stdin will be used
    --color (-c): string@'completions-colors' = 'default' # Color to use for the cprint text
    --highlight-color (-H): string@'completions-colors' = 'green_bold' # Color to use for highlighting text enclosed in asterisks
    --frame-color (-r): string@'completions-colors' = 'dark_gray' # Color to use for frame
    --frame (-f): string = '' # Symbol (or a string) to frame a text
    --lines-before (-b): int = 0 # Number of new lines before a text
    --lines-after (-a): int = 1 # Number of new lines after a text
    --echo (-e) # Echo text string instead of printing
    --keep-single-breaks # Don't remove single line breaks
    --width (-w): int = 80 # The total width of text to wrap it
    --indent (-i): int = 0 # Indent output by number of spaces
    --align: string@[left center right] = 'left' # Alignment of text
]: [string -> nothing nothing -> nothing nothing -> string string -> string] {
    let text = if $text == null { } else { $text }

    let width_safe = width-safe $width $indent

    $text
    | wrapit $keep_single_breaks $width_safe $indent
    | colorit $highlight_color $color
    | alignit $align $width_safe
    | if $frame != '' {
        frameit $width_safe $frame $frame_color
    } else { }
    | indentit $indent
    | newlineit $lines_before $lines_after
    | if $echo { } else { print --no-newline $in }
}

# Calculate safe text width accounting for terminal size and indent
export def 'width-safe' [
    width: int
    indent: int
]: nothing -> int {
    term size
    | get columns
    | [$in $width] | math min
    | $in - $indent
    | [$in 1] | math max # term size gives 0 in tests
}

# Wrap text to specified width, optionally preserving line breaks
export def 'wrapit' [
    keep_single_breaks: bool
    width_safe: int
    indent: int
]: string -> string {
    str replace --all --regex --multiline '^[\t ]+' ''
    | if $keep_single_breaks { } else { remove-single-nls }
    | str replace --all --regex --multiline '[\t ]+$' ''
    | str replace --all --regex --multiline $"\(.{1,($width_safe)}\)\(\\s|$\)|\(.{1,($width_safe)}\)" "$1$3\n"
    | str replace --regex $'\s+$' '' # trailing new line
}

# Collapse single newlines into spaces, preserve double newlines as paragraphs
export def 'remove-single-nls' []: string -> string {
    str replace --regex --all '(\n[\t ]*){2,}' '⏎'
    | str replace --all --regex --multiline '(?<!⏎)\n' ' ' # remove single line breaks used for code formatting
    | str replace --all '⏎' "\n\n"
}

# Add newlines before and after text
export def 'newlineit' [
    before: int
    after: int
]: string -> string {
    $"('' | fill --character (char nl) --width $before)($in)('' | fill --character (char nl) --width $after)"
}

# Wrap text with decorative frame lines above and below
export def 'frameit' [
    width_safe: int
    frame: string
    frame_color: string
]: string -> string {
    let input = $in

    # Why the cut: a frame of several characters overshoots the width
    let line = 0..<$width_safe | each { $frame } | str join | str substring --grapheme-clusters 0..<$width_safe
    let line = $"(ansi $frame_color)($line)(ansi reset)"

    $"($line)\n($input)\n($line)"
}

# Apply color and highlight *emphasized* text
export def 'colorit' [
    highlight_color: string
    color: string
]: string -> string {
    str replace --regex --all '\*([^*]+?)\*' $'(ansi reset)(ansi $highlight_color)$1(ansi reset)(ansi $color)'
    | $"(ansi $color)($in)(ansi reset)"
}

# Align each line of text within specified width
export def 'alignit' [
    alignment: string
    width_safe: int
]: string -> string {
    lines
    | fill --alignment $alignment --width $width_safe
    | str join (char nl)
}

# Add leading spaces to each line
export def 'indentit' [
    indent: int
]: string -> string {
    str replace --all --regex --multiline '^' ('' | fill --width $indent)
}

export def 'completions-colors' []: nothing -> list<record<value: string, style: string>> {
    # Why: the menu shows each name in its own color; bg_ and attr_ names have no fg and stay plain
    ansi --list | take until {|it| $it.name == reset } | each { {value: $in.name style: $in.name} }
}
