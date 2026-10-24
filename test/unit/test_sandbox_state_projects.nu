use std/assert
use std/testing *
use ../../cozy-module/sandbox-state/projects.nu

# A HOME with one live session, and an empty snapshot directory beside it.
@before-each
def setup []: nothing -> record {
    let root = mktemp --directory --tmpdir cozy-projects-test-XXXXXX
    let home = $root | path join home
    let live = $home | path join .claude projects

    mkdir ($live | path join '-proj')
    'one' | save ($live | path join '-proj' a.jsonl)
    let snap = $root | path join state projects

    mkdir $snap
    {root: $root home: $home live: $live snap: $snap}
}

@after-each
def teardown []: record -> nothing {
    rm --recursive --force $in.root
}

# The message of the error a call raises; a call that returns is the failure.
def error-of [call: closure]: nothing -> string {
    try { do $call; '' } catch {|e| $e.msg }
}

@test
def "snapshot refuses a filled snapshot before restore has run" [] {
    let t = $in

    'old' | save ($t.snap | path join stale.jsonl)

    let err = with-env {HOME: $t.home} { error-of { projects snapshot $t.snap } }

    assert str contains $err 'has not run on this machine'
    assert ($t.snap | path join stale.jsonl | path exists)
}

@test
def "snapshot runs on an empty snapshot without restore" [] {
    let t = $in

    with-env {HOME: $t.home} { projects snapshot $t.snap | ignore }

    assert equal (open --raw ($t.snap | path join '-proj' a.jsonl)) 'one'
}

@test
def "restore keeps the machine id of an earlier restore" [] {
    let t = $in
    let marker = $t.home | path join .claude .cozy-projects-restored

    'machine-a' | save $marker
    with-env {HOME: $t.home} { projects restore $t.snap | ignore }

    assert equal (open --raw $marker) 'machine-a'
}

@test
def "snapshot moves a file gone from live into projects-deleted" [] {
    let t = $in

    with-env {HOME: $t.home} { projects restore $t.snap | ignore }
    mkdir ($t.snap | path join '-moved')
    'kept' | save ($t.snap | path join '-moved' b.jsonl)

    with-env {HOME: $t.home} { projects snapshot $t.snap | ignore }
    let backed = glob $"($t.root)/state/projects-deleted/*/-moved/b.jsonl"

    assert not ($t.snap | path join '-moved' | path exists)
    assert equal ($backed | length) 1
    assert equal (open --raw ($backed | first)) 'kept'
}

@test
def "snapshot backs up no file it only updates" [] {
    let t = $in

    with-env {HOME: $t.home} { projects restore $t.snap | ignore }
    with-env {HOME: $t.home} { projects snapshot $t.snap | ignore }
    'one two' | save --force ($t.live | path join '-proj' a.jsonl)

    with-env {HOME: $t.home} { projects snapshot $t.snap | ignore }

    assert equal (open --raw ($t.snap | path join '-proj' a.jsonl)) 'one two'
    assert not ($t.root | path join state projects-deleted | path exists)
}

const MODULE = path self ../../cozy-module/sandbox-state/projects.nu

# `snapshot` warns on stderr, so it runs in a child `nu` whose stderr is kept.
def snapshot-as [home: path snap: path]: nothing -> record {
    with-env {HOME: $home} {
        ^$nu.current-exe --no-config-file --commands $"use '($MODULE)'; projects snapshot '($snap)'" | complete
    }
}

# A second HOME on the same snapshot: the second machine.
def second-home [t: record]: nothing -> path {
    let home = $t.root | path join home-b

    mkdir ($home | path join .claude projects '-other')
    'b' | save ($home | path join .claude projects '-other' c.jsonl)
    $home
}

@test
def "snapshot warns when another machine wrote it after the last restore here" [] {
    let t = $in
    let b = second-home $t

    with-env {HOME: $t.home} { projects restore $t.snap | ignore }
    with-env {HOME: $b} { projects restore $t.snap | ignore }
    snapshot-as $b $t.snap | ignore

    let run = snapshot-as $t.home $t.snap

    assert equal $run.exit_code 0
    assert str contains $run.stderr 'another machine wrote this snapshot'
}

@test
def "snapshot stays quiet after a restore that follows the other machine" [] {
    let t = $in
    let b = second-home $t

    with-env {HOME: $t.home} { projects restore $t.snap | ignore }
    with-env {HOME: $b} { projects restore $t.snap | ignore }
    snapshot-as $b $t.snap | ignore
    with-env {HOME: $t.home} { projects restore $t.snap | ignore }

    let run = snapshot-as $t.home $t.snap

    assert equal $run.stderr ''
    assert ($t.snap | path join '-other' c.jsonl | path exists)
}
