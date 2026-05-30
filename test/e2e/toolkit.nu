# Canonical runner for the zellij e2e suite.
#
# Forces serial execution (threads: 1): every test drives a REAL zellij session
# with a PTY client and live TUIs (helix/fzf). Running suites/tests concurrently
# makes many sessions contend for CPU, slowing renders past the poll timeouts —
# a nondeterministic flake. Serial is the correct model for interactive e2e.
#
#   nu toolkit.nu test                 # run everything
#   nu toolkit.nu test --suite lstd    # one suite
#   nu toolkit.nu test --match basename

use ~/repos/nutest/nutest

const SUITES = (path self | path dirname | path join suites)

export def "main test" [
    --suite: string = ".*"   # regex over suite names (file stem without _test)
    --match: string = ".*"   # regex over test names
    --fail                   # exit non-zero if any test fails (CI)
]: nothing -> any {
    let dir = $SUITES
    if $fail {
        nutest run-tests --path $dir --strategy { threads: 1 } --match-suites $suite --match-tests $match --fail
    } else {
        nutest run-tests --path $dir --strategy { threads: 1 } --match-suites $suite --match-tests $match
    }
}

export def main [] {
    print "cozy zellij e2e harness. Run: nu toolkit.nu test"
}
