; A whole copy of helix's runtime/queries/markdown/injections.scm, with the
; indented code block pattern added at the end. This file replaces the built-in one, so a
; later upstream fix to markdown injections does not reach here: after a helix
; upgrade, copy the upstream file again and keep the added pattern.
; The copied part matched helix f7ab5ec4a on 2026-11-14.

; From nvim-treesitter/nvim-treesitter

(fenced_code_block
  (code_fence_content) @injection.shebang @injection.content
  (#set! injection.include-unnamed-children))

(fenced_code_block
  (info_string
    (language) @injection.language)
  (code_fence_content) @injection.content (#set! injection.include-unnamed-children))

((html_block) @injection.content
 (#set! injection.language "html")
 (#set! injection.include-unnamed-children)
 (#set! injection.combined))

((pipe_table_cell) @injection.content (#set! injection.language "markdown.inline") (#set! injection.include-unnamed-children))

((minus_metadata) @injection.content (#set! injection.language "yaml") (#set! injection.include-unnamed-children))
((plus_metadata) @injection.content (#set! injection.language "toml") (#set! injection.include-unnamed-children))

((inline) @injection.content (#set! injection.language "markdown.inline") (#set! injection.include-unnamed-children))

; Why: the user never writes code by indentation, only in fences, but a gi canvas
; indents each turn 4 spaces deeper than the text above it. After a blank line
; such a block is an indented code block, which runs on to the end of the ladder,
; and the markdown grammar does not parse inline text inside it.
; Not the upstream behaviour because: the cost, markdown colours in real indented
; code, does not occur in the files of the user.
((indented_code_block) @injection.content (#set! injection.language "markdown.inline") (#set! injection.include-unnamed-children))
