# E2E for the PWD env_change tab-rename + ·N dedup hook
# (vendor/dotfiles/nushell/autoload/hooks-config.nu, lines ~19-48).
# Target #5 in todo/20260528-172203-zellij-interactive.md — the cleanest Layer 2
# target (no TUI): spawn a nu pane, cd, assert the tab name via query-tab-names.
#
# Uses nutest description-tag attributes (`# [test]`) not `@test`: the vendored
# nutest predates nu 0.113's `attr`-command requirement, so `@test` fails to
# parse but the `[tag]` form still discovers correctly.

use std/assert
use ../harness.nu *

# [before-each]
def setup [] {
    # unique session per test so concurrent tests never collide or touch t92
    let session = $"e2e_tabrename_(random chars --length 8)"
    let tmp = mktemp --directory --suffix _e2e_tabrename
    { ctx: (start $session), tmp: $tmp }
}

# [after-each]
def teardown [] {
    let it = $in
    stop $it.ctx
    rm --recursive --force $it.tmp
}

# [test]
def "cd renames the tab to the dir basename" [] {
    let it = $in
    let dir = $it.tmp | path join "myproject"
    mkdir $dir

    let pane = run-nu $it.ctx
    type $it.ctx $"cd ($dir)" --pane $pane
    key $it.ctx "Enter" --pane $pane

    let names = wait-tab $it.ctx "myproject"
    assert ("myproject" in $names)
}

# [test]
def "second tab in a same-named dir gets the dot-N suffix" [] {
    let it = $in
    let a = $it.tmp | path join "alpha" "proj"
    let b = $it.tmp | path join "beta" "proj"
    mkdir $a
    mkdir $b

    let p1 = run-nu $it.ctx
    type $it.ctx $"cd ($a)" --pane $p1
    key $it.ctx "Enter" --pane $p1
    wait-tab $it.ctx "proj" | ignore

    new-tab $it.ctx
    let p2 = run-nu $it.ctx
    type $it.ctx $"cd ($b)" --pane $p2
    key $it.ctx "Enter" --pane $p2

    let names = wait-tab $it.ctx "proj·2"
    assert ("proj" in $names)
    assert ("proj·2" in $names)
}

# [test]
def "leading dashes are stripped from the tab name" [] {
    let it = $in
    let dir = $it.tmp | path join "--dashy"
    mkdir $dir

    let pane = run-nu $it.ctx
    type $it.ctx $"cd ($dir)" --pane $pane
    key $it.ctx "Enter" --pane $pane

    # hook does: str replace -r '^-+' '' → "dashy"
    let names = wait-tab $it.ctx "dashy"
    assert ("dashy" in $names)
    assert ("--dashy" not-in $names)
}
