# E2E for lstd (vendor/dotfiles/zellij/todo-nu/todo.nu:4-23).
# Target #2 in todo/20260528-172203-zellij-interactive.md.
#
# lstd lists active todo/*.md (hiding completed/rejected) into an fzf picker with
# a bat preview, binds ctrl-e to `zellij edit {}` on the highlighted file, and on
# Enter tees the chosen path to pbcopy.
#
# We invoke lstd directly in a spawned nu pane (Layer 2), wait for fzf to render,
# then drive it. Readiness uses pane_command='fzf' plus fzf's rendered "N/N"
# counter.
#
# OSC-52 LIMITATION: pbcopy here (~/.local/bin/pbcopy) emits an OSC-52 escape
# (\033]52;c;...) to /dev/tty. zellij consumes that escape; it never renders into
# the grid and leaves no filesystem trace. The clipboard side-effect is therefore
# NOT observable in this headless harness — we assert the selection/edit-pane path
# instead (per the task's stated fallback).
#
# nutest description-tag attributes (`# [test]`) — see tab-rename_test.nu header.

use std/assert
use ../harness.nu *

# [before-each]
def setup [] {
    let session = $"e2e_lstd_(random chars --length 8)"
    let tmp = mktemp --directory --suffix _e2e_lstd
    mkdir ($tmp | path join todo)
    # two active todos + one completed (which lstd is supposed to hide)
    "---\nstatus: 'draft'\n---\n\nalpha task\n" | save ($tmp | path join todo "20260101-000001.md")
    "---\nstatus: 'in_progress'\n---\n\nbeta task\n" | save ($tmp | path join todo "20260101-000002.md")
    "---\nstatus: 'completed'\n---\n\ngamma done\n" | save ($tmp | path join todo "20260101-000003.md")
    let ctx = start $session
    let pane = run-nu $ctx --cwd $tmp
    { ctx: $ctx, tmp: $tmp, pane: $pane }
}

# [after-each]
def teardown [] {
    let it = $in
    stop $it.ctx
    rm --recursive --force $it.tmp
}

def launch-lstd [it] {
    type $it.ctx "use ~/.config/zellij/todo-nu/todo.nu lstd; lstd" --pane $it.pane
    key $it.ctx "Enter" --pane $it.pane
    wait-pane-command $it.ctx $it.pane 'fzf' | ignore
    # fzf draws a "current/total" counter once the picker is up
    wait-text $it.ctx '\d+/\d+' --pane $it.pane
}

# [test]
def "lstd launches the fzf picker rendering the todo list" [] {
    let it = $in
    let rendered = launch-lstd $it
    assert ($rendered =~ '\d+/\d+') "fzf should render its item counter"
    # fzf is the foreground program in the pane
    assert (panes $it.ctx | where id == 1 | get 0.pane_command | str contains "fzf")
}

# [test]
def "ctrl-e spawns a zellij edit pane for the highlighted file" [] {
    let it = $in
    launch-lstd $it
    let before = panes $it.ctx | length

    key $it.ctx "Ctrl e" --pane $it.pane
    # ctrl-e:execute-silent(zellij edit {}) opens a new helix pane
    let edit_cmd = wait-pane-command $it.ctx "terminal_2" 'hx'

    assert equal (panes $it.ctx | length) ($before + 1)
    assert ($edit_cmd =~ 'hx') "new pane should be running helix via `zellij edit`"
}

# [test]
# Status filter: completed/rejected todos are hidden from the picker. This
# regressed on nu 0.113 — `open` on a .md parses markdown into a TABLE, so the
# `split row` over frontmatter errored on every todo, the `try {...} | default
# "draft"` swallowed it, every todo became "draft", and nothing was filtered (the
# fzf items even became nu error strings). Fixed by `open --raw $i.name` in
# todo.nu. Requires a build re-vendored at/after that fix for the deployed
# ~/.config copy this test invokes.
def "lstd hides completed todos - intended contract" [] {
    let it = $in
    let rendered = launch-lstd $it
    let counter = $rendered | lines | where $it =~ '\d+/\d+' | first
    # 2 active todos → fzf should show "2/2", not "3/3"
    assert ($counter =~ '2/2') $"expected 2 active items, got: ($counter)"
}
