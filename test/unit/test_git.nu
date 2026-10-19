use std/assert
use std/testing *
use ../../cozy-module/git.nu

# A throwaway repo per test: one committed file, so `link` has something to name.
# The Change-Id trailer is written by hand instead of through the hook, so these tests
# cover the commands and not the hook.
@before-each
def setup []: nothing -> record {
    let repo = mktemp --directory --tmpdir cozy-git-test-XXXXXX
    ^git -C $repo init --quiet
    ^git -C $repo config user.email test@example.com
    ^git -C $repo config user.name test
    {repo: $repo}
}

@after-each
def teardown []: record -> nothing {
    rm --recursive --force $in.repo
}

def commit-file [repo: path, path: string, content: string, message: string]: nothing -> string {
    mkdir ($repo | path join $path | path dirname)
    $content | save --force ($repo | path join $path)
    ^git -C $repo add $path
    $message | ^git -C $repo commit --quiet --file -
    ^git -C $repo rev-parse HEAD | str trim
}

def with-id [id: string]: nothing -> string {
    $"add\n\nChange-Id: ($id)"
}

# The message of the error a call raises; a call that returns is the failure.
def error-of [call: closure]: nothing -> string {
    try { do $call; '' } catch {|e| $e.msg }
}

const ID = 'zyxwvutsrqponmlkzyxwvutsrqponmlk'
const HOOK = path self ../../cozy-module/hooks/commit-msg
const APPLYPATCH_HOOK = path self ../../cozy-module/hooks/applypatch-msg

# Two commits made without the hook, the second turned into a patch and undone, so an `am` of it
# is the only way a Change-Id can reach the repo.
def patch-of-second-commit [repo: path]: nothing -> string {
    commit-file $repo base.txt base "base"
    commit-file $repo second.txt second "second"
    let patch = ^git -C $repo format-patch -1 --stdout
    ^git -C $repo reset --quiet --hard HEAD~1
    $patch
}

@test
def "install refuses a different hook and replaces it with force" [] {
    let repo = $in.repo
    let dest = $repo | path join .git hooks commit-msg
    "#!/bin/sh\nexit 0\n" | save --force $dest

    let err = error-of { git install-change-id-hook $repo }
    assert str contains $err 'a different commit-msg hook already exists'
    assert equal (open --raw $dest) "#!/bin/sh\nexit 0\n"

    assert equal (git install-change-id-hook $repo --force | get status) ['replaced' 'installed' 'installed']
    assert equal (open --raw $dest) (open --raw $HOOK)
    assert equal (git install-change-id-hook $repo | get status) ['already installed' 'already installed' 'already installed']
}

@test
def "install refused over a different applypatch-msg installs neither hook" [] {
    let repo = $in.repo
    let hooks = $repo | path join .git hooks
    "#!/bin/sh\nexit 0\n" | save --force ($hooks | path join applypatch-msg)

    let err = error-of { git install-change-id-hook $repo }
    assert str contains $err 'a different applypatch-msg hook already exists'
    assert (not ($hooks | path join commit-msg | path exists))
}

@test
def "an untouched verbose template aborts the commit" [] {
    let repo = $in.repo
    commit-file $repo base.txt base "base"
    git install-change-id-hook $repo
    "changed" | save --force ($repo | path join base.txt)
    ^git -C $repo add base.txt

    let res = with-env {GIT_EDITOR: true} { ^git -C $repo commit --verbose | complete }
    assert equal $res.exit_code 1 $"committed: ($res.stdout)"
    assert equal (^git -C $repo log --format=%s) "base"
}

@test
def "an untouched verbose template aborts with a custom comment char" [] {
    let repo = $in.repo
    commit-file $repo base.txt base "base"
    git install-change-id-hook $repo
    ^git -C $repo config core.commentChar ';'
    "changed" | save --force ($repo | path join base.txt)
    ^git -C $repo add base.txt

    let res = with-env {GIT_EDITOR: true} { ^git -C $repo commit --verbose | complete }
    assert equal $res.exit_code 1 $"committed: ($res.stdout)"
    assert equal (^git -C $repo log --format=%s) "base"
}

@test
def "a verbose commit with a message gets a change-id and no diff" [] {
    let repo = $in.repo
    commit-file $repo base.txt base "base"
    git install-change-id-hook $repo
    "changed" | save --force ($repo | path join base.txt)
    ^git -C $repo add base.txt

    # git runs the editor through sh with the message file as $1
    let editor = 'f() { { echo subject; cat "$1"; } > "$1.new" && mv "$1.new" "$1"; }; f'
    with-env {GIT_EDITOR: $editor} { ^git -C $repo commit --quiet --verbose }
    let msg = ^git -C $repo log -1 --format=%B | str trim
    assert ($msg =~ '^subject\n\nChange-Id: [k-z]{32}$') $"unexpected message: ($msg)"
}

@test
def "a commit that git am applies gets a change-id" [] {
    let repo = $in.repo
    let patch = patch-of-second-commit $repo
    git install-change-id-hook $repo

    $patch | ^git -C $repo am --quiet
    let trailers = ^git -C $repo log -1 --format='%(trailers:key=Change-Id,valueonly)' | str trim
    assert ($trailers =~ '^[k-z]{32}$') $"no change-id stamped: ($trailers)"
}

@test
def "git am stops when the commit-msg hook is missing" [] {
    let repo = $in.repo
    let patch = patch-of-second-commit $repo
    git install-change-id-hook $repo
    rm ($repo | path join .git hooks commit-msg)

    let res = $patch | ^git -C $repo am --quiet | complete
    assert not equal $res.exit_code 0
    assert equal (^git -C $repo rev-list --count HEAD | str trim) '1'
}

@test
def "a revert names the reverted change-id and gets its own" [] {
    let repo = $in.repo
    git install-change-id-hook $repo
    commit-file $repo a.txt a (with-id $ID)

    ^git -C $repo revert --no-edit HEAD | ignore
    let body = ^git -C $repo log -1 --format=%b
    assert str contains $body $"This reverts change ($ID)."
    let own = ^git -C $repo log -1 --format='%(trailers:key=Change-Id,valueonly)' | str trim
    assert ($own =~ '^[k-z]{32}$') $"no change-id stamped: ($own)"
}

@test
def "a revert of a merge names the change-id and gets its own" [] {
    let repo = $in.repo
    git install-change-id-hook $repo
    commit-file $repo base.txt base "base"
    ^git -C $repo switch --quiet --create side
    commit-file $repo a.txt a (with-id $ID)
    ^git -C $repo switch --quiet "@{-1}"
    ^git -C $repo merge --quiet --no-ff --no-edit side
    let merge_id = ^git -C $repo log -1 --format='%(trailers:key=Change-Id,valueonly)' | str trim

    ^git -C $repo revert --no-edit --mainline 1 HEAD | ignore
    assert str contains (^git -C $repo log -1 --format=%b) $"This reverts change ($merge_id), reversing"
    let own = ^git -C $repo log -1 --format='%(trailers:key=Change-Id,valueonly)' | str trim
    assert ($own =~ '^[k-z]{32}$') $"no change-id stamped: ($own)"
}

@test
def "a rebase replays an old revert unchanged" [] {
    let repo = $in.repo
    commit-file $repo base.txt base "base"
    commit-file $repo a.txt a (with-id $ID)
    ^git -C $repo revert --no-edit HEAD | ignore
    ^git -C $repo branch side HEAD~2
    git install-change-id-hook $repo
    let before = ^git -C $repo log -1 --format=%B

    ^git -C $repo switch --quiet side
    commit-file $repo side.txt side "side"
    ^git -C $repo rebase --quiet side "@{-1}"
    assert equal (^git -C $repo log -1 --format=%B) $before
}

@test
def "install updates an older copy of its own hook without force" [] {
    let repo = $in.repo
    let dest = $repo | path join .git hooks commit-msg
    open --raw $HOOK | lines | first 2 | append 'exit 0' | str join "\n" | save --force $dest

    assert equal (git install-change-id-hook $repo | get status) ['updated' 'installed' 'installed']
    assert equal (open --raw $dest) (open --raw $HOOK)
    assert equal (open --raw ($repo | path join .git hooks applypatch-msg)) (open --raw $APPLYPATCH_HOOK)
}

@test
def "link names the change-id of the commit that last touched the file" [] {
    let repo = $in.repo
    commit-file $repo a.txt one (with-id $ID)
    commit-file $repo other.txt x (with-id 'kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk')

    assert equal (git link ($repo | path join a.txt)) $"($repo)@($ID):a.txt"
}

@test
def "link path is relative to the repo root" [] {
    let repo = $in.repo
    commit-file $repo dir/sub/a.txt one (with-id $ID)

    assert equal (git link ($repo | path join dir sub a.txt)) $"($repo)@($ID):dir/sub/a.txt"
}

@test
def "link falls back to the sha when the commit carries no change-id" [] {
    let repo = $in.repo
    let sha = commit-file $repo a.txt one 'add, no trailer'

    assert equal (git link ($repo | path join a.txt)) $"($repo)@($sha):a.txt"
}

@test
def "link refuses a file with uncommitted changes" [] {
    let repo = $in.repo
    commit-file $repo a.txt one (with-id $ID)
    'two' | save --force ($repo | path join a.txt)

    let err = error-of { git link ($repo | path join a.txt) }
    assert str contains $err 'uncommitted changes'
}

@test
def "link refuses an untracked file" [] {
    let repo = $in.repo
    commit-file $repo a.txt one (with-id $ID)
    'x' | save ($repo | path join new.txt)

    let err = error-of { git link ($repo | path join new.txt) }
    assert str contains $err 'not tracked'
}

@test
def "link refuses a file outside a git repo" [] {
    let dir = mktemp --directory --tmpdir cozy-git-test-XXXXXX
    'x' | save ($dir | path join a.txt)

    let err = error-of { git link ($dir | path join a.txt) }
    rm --recursive --force $dir
    assert str contains $err 'not a git repository'
}

@test
def "link refuses a commit that carries two change-ids" [] {
    let repo = $in.repo
    commit-file $repo a.txt one $"add\n\nChange-Id: ($ID)\nChange-Id: kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk"

    let err = error-of { git link ($repo | path join a.txt) }
    assert str contains $err '2 Change-Id trailers'
}

@test
def "resolve prints the file at the change-id and at its prefix" [] {
    let repo = $in.repo
    commit-file $repo a.txt one (with-id $ID)
    commit-file $repo a.txt two 'edit, no trailer'

    assert equal (git resolve $"($repo)@($ID):a.txt") one
    assert equal (git resolve $"($repo)@($ID | str substring ..7):a.txt") one
}

@test
def "resolve prints the file at a sha" [] {
    let repo = $in.repo
    let sha = commit-file $repo a.txt one 'add'
    commit-file $repo a.txt two 'edit'

    assert equal (git resolve $"($repo)@($sha):a.txt") one
    assert equal (git resolve $"($repo)@($sha | str substring ..7):a.txt") one
}

@test
def "resolve refuses an unknown change-id" [] {
    let repo = $in.repo
    commit-file $repo a.txt one (with-id $ID)

    let err = error-of { git resolve $"($repo)@kkkkkkkk:a.txt" }
    assert str contains $err 'no commit'
}

@test
def "resolve refuses a change-id carried by two commits" [] {
    let repo = $in.repo
    commit-file $repo a.txt one (with-id $ID)
    commit-file $repo b.txt two (with-id $ID)

    let err = error-of { git resolve $"($repo)@($ID):a.txt" }
    assert str contains $err '2 commits'
}

@test
def "resolve refuses a string that is not a link" [] {
    let err = error-of { git resolve 'just/a/path.txt' }
    assert str contains $err 'not a link'
}

# The editor-less reword recipe: an `amend!` commit, then `rebase --autosquash` puts its message
# onto the target.
def reword-with-amend-bang [repo: path, target: string]: nothing -> nothing {
    ^git -C $repo commit --quiet --allow-empty --message $"amend! ($target)" --message "reworded"
    with-env {GIT_SEQUENCE_EDITOR: true} { ^git -C $repo rebase --quiet --interactive --autosquash HEAD~3 }
}

@test
def "an amend commit named by subject gets a fresh change-id" [] {
    let repo = $in.repo
    commit-file $repo base.txt base "base"
    git install-change-id-hook $repo
    commit-file $repo a.txt a (with-id $ID)
    commit-file $repo b.txt b "later"

    reword-with-amend-bang $repo add
    let reworded = ^git -C $repo log --format='%s %(trailers:key=Change-Id,valueonly)' HEAD~1 -1 | str trim
    assert ($reworded =~ '^reworded [k-z]{32}$') $"unexpected: ($reworded)"
    assert not equal $reworded $"reworded ($ID)"
}

# Why two commits of one subject: autosquash picks one of them, and an id copied from the other
# would name two changes. A sha names one.
@test
def "an amend commit named by sha keeps the change-id of its target" [] {
    let repo = $in.repo
    commit-file $repo base.txt base "base"
    git install-change-id-hook $repo
    let sha = commit-file $repo a.txt a (with-id $ID)
    commit-file $repo b.txt b "add"

    reword-with-amend-bang $repo ($sha | str substring 0..11)
    assert equal (^git -C $repo log --format='%s %(trailers:key=Change-Id,valueonly)' HEAD~1 -1 | str trim) $"reworded ($ID)"
    assert not equal (^git -C $repo log -1 --format='%(trailers:key=Change-Id,valueonly)' | str trim) $ID
}

@test
def "an amend that carries an empty change-id gets a fresh one" [] {
    let repo = $in.repo
    commit-file $repo base.txt base "base"
    git install-change-id-hook $repo

    ^git -C $repo commit --quiet --allow-empty --amend --message "new" --trailer "Change-Id: "
    let msg = ^git -C $repo log -1 --format=%B | str trim
    assert ($msg =~ '^new\n\nChange-Id: [k-z]{32}$') $"unexpected message: ($msg)"
}

@test
def "a message that is only an empty change-id aborts the commit" [] {
    let repo = $in.repo
    commit-file $repo base.txt base "base"
    git install-change-id-hook $repo

    let result = "Change-Id:\n" | ^git -C $repo commit --quiet --allow-empty --file - | complete
    assert not equal $result.exit_code 0
    assert equal (^git -C $repo log -1 --format=%s | str trim) "base"
}
