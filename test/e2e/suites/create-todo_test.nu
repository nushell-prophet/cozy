# E2E for create-todo / todo-hx (vendor/dotfiles/zellij/todo-nu/todo.nu:25-63).
# Target #1 in todo/20260528-172203-zellij-interactive.md.
#
# create-todo writes todo/<ts>.md with frontmatter, opens it in helix at line 7,
# and AFTER helix exits removes the file if it is byte-identical to the template
# (and removes the freshly-created todo/ folder too). That auto-delete is the
# whole point and is invisible to any non-TTY test — we drive real helix here.
#
# Layer 2: we invoke create-todo directly in a spawned nu pane (not via its
# Super-chord keybind). Readiness/exit is gated on `pane_command` (clientless):
# "hx ..." while helix runs, back to "nu" once it quits.
#
# nutest description-tag attributes (`# [test]`) — see tab-rename_test.nu header.

use std/assert
use ../harness.nu *

# [before-each]
def setup [] {
    let session = $"e2e_createtodo_(random chars --length 8)"
    let tmp = mktemp --directory --suffix _e2e_createtodo
    let ctx = start $session
    # one nu pane per test, rooted in the temp workspace where todo/ will live
    let pane = run-nu $ctx --cwd $tmp
    { ctx: $ctx, tmp: $tmp, pane: $pane }
}

# [after-each]
def teardown [] {
    let it = $in
    stop $it.ctx
    rm --recursive --force $it.tmp
}

def launch-create-todo [it] {
    type $it.ctx "use ~/.config/zellij/todo-nu/todo.nu create-todo; create-todo" --pane $it.pane
    key $it.ctx "Enter" --pane $it.pane
    # Gate on helix's RENDERED status line, not pane_command: pane_command flips
    # to "hx" the instant it spawns, but helix hasn't entered raw mode / drawn its
    # UI yet, so early keystrokes (the first ':') get dropped. The "NOR" mode
    # indicator only appears once helix is actually ready for input.
    wait-text $it.ctx 'NOR' --pane $it.pane | ignore
    sleep 300ms
}

def wait-helix-gone [it] {
    # helix has exited and create-todo's post-quit check has run once we're back to nu
    wait-pane-command $it.ctx $it.pane '(^|/)nu$' | ignore
    # small settle for the rm/rmdir filesystem ops in create-todo's tail
    sleep 400ms
}

def todo-md-files [tmp: string]: nothing -> list<string> {
    let dir = $tmp | path join todo
    if ($dir | path exists) {
        ls $dir | where name =~ '\d{8}-\d{6}\.md$' | get name | path basename
    } else {
        []
    }
}

# [test]
def "quitting unmodified deletes the file and the new todo folder" [] {
    let it = $in
    launch-create-todo $it
    # exactly one new todo md exists while helix is open
    assert equal (todo-md-files $it.tmp | length) 1

    # quit without editing (helix opens in NOR mode): :q
    type $it.ctx ":q" --pane $it.pane
    key $it.ctx "Enter" --pane $it.pane
    wait-helix-gone $it

    # file gone AND the freshly-created todo/ folder removed
    assert equal (todo-md-files $it.tmp | length) 0
    assert (($it.tmp | path join todo | path exists) == false) "todo/ folder should be removed when it was newly created"
}

# [test]
def "editing then saving persists the file" [] {
    let it = $in
    launch-create-todo $it

    # insert a body, escape, write-quit
    key $it.ctx "i" --pane $it.pane
    type $it.ctx "real task body" --pane $it.pane
    key $it.ctx "Esc" --pane $it.pane
    type $it.ctx ":wq" --pane $it.pane
    key $it.ctx "Enter" --pane $it.pane
    wait-helix-gone $it

    let files = todo-md-files $it.tmp
    assert equal ($files | length) 1
    let body = open --raw ($it.tmp | path join todo $files.0)
    assert ($body =~ 'real task body') "edited body should be persisted"
    assert ($body =~ 'status:') "frontmatter should be intact"
}
