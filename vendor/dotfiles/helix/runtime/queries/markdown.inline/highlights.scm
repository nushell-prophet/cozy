; A whole copy of helix's runtime/queries/markdown.inline/highlights.scm, with the
; strikethrough pattern changed for CriticMarkup and the stamp tags added at the end. This file replaces the built-in one, so a later upstream fix to
; inline highlighting does not reach here: after a helix upgrade, copy the upstream
; file again and keep the change.
; The copied part matched helix d76affac7 (25.07-990) on 2026-10-30.

;; From nvim-treesitter/nvim-treesitter
[
  (code_span)
  (link_title)
] @markup.raw.inline

[
  (emphasis_delimiter)
  (code_span_delimiter)
] @punctuation.bracket

(emphasis) @markup.italic

(strong_emphasis) @markup.bold

; Why: a CriticMarkup substitution `{~~old~>new~~}` is a strikethrough over both texts,
; with `~old~` nested in it. The grammar has no node for the new text, so the style of
; the outer node reaches it and `~old~` overrides that style. With a space before `~>`
; there is no `~old~`, and the old text takes no style of its own.
; Why the parent list: a nested strikethrough must not be crossed out, and a query
; cannot exclude a parent by its text.
([
  (inline (strikethrough) @markup.strikethrough)
  (emphasis (strikethrough) @markup.strikethrough)
  (strong_emphasis (strikethrough) @markup.strikethrough)
]
  (#not-match? @markup.strikethrough "~>"))

((strikethrough) @markup.critic.new
  (#match? @markup.critic.new "~>"))
((strikethrough (strikethrough) @markup.critic.old) @_substitution
  (#match? @_substitution "~>"))

[
  (link_destination)
  (uri_autolink)
] @markup.link.url

[
  (link_text)
  (image_description)
] @markup.link.text

(link_label) @markup.link.label

[
  (backslash_escape)
  (hard_line_break)
] @constant.character.escape

(image ["[" "]" "(" ")"] @punctuation.bracket)
(image "!" @punctuation.special)
(inline_link ["[" "]" "(" ")"] @punctuation.bracket)
(shortcut_link ["[" "]"] @punctuation.bracket)

; Why: the block tags of a particle stamp (`<!-- Qm… -->`, `<!-- /Qm… -->`) stay grey
; inside an indented canvas block too, which is parsed inline (markdown/injections.scm).
; Not the upstream html injection because: in a block with several tags it colours
; only the last one.
((html_tag) @comment
  (#match? @comment "^<!-- /?Qm"))
