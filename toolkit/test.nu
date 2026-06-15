# test.nu — Verify a Docker sandbox image from the host.
#
# Spawns a fresh sandbox from the image, runs the shared post-build checks
# (cozy-module/verify.nu) against it via `docker sandbox exec`, then tears it
# down. The same checks run from inside a sandbox via `cozy verify`; this is the
# host entry point that also exercises the image build + sandbox lifecycle.
#
# Usage:
#   nu test.nu test              # test with :latest tag
#   nu test.nu test -t v5        # test specific tag
#   nu test.nu test --keep       # keep sandbox for debugging
#   nu test.nu clean             # remove leftover test sandbox

const verify = (path self | path dirname | path join .. cozy-module verify.nu)
use $verify [run-checks report]

const image = "cozy"
const sandbox = "claude-test"

export def main [] { help main }

# Run the shared checks against a fresh sandbox, clean up after.
export def "main test" [
    --tag (-t): string = "latest" # image tag to test
    --keep (-k) # keep sandbox after tests
] {
    let template = $"($image):($tag)"

    do -i { ^docker sandbox stop $sandbox }
    do -i { ^docker sandbox rm $sandbox }

    let ws = [$nu.home-dir temp sandbox-test-ws] | path join
    mkdir $ws

    print $"Image: ($template)"
    print "Creating sandbox..."
    ^docker sandbox create --debug -t $template --name $sandbox claude $ws

    mut ready = false
    for _ in 1..15 {
        if not $ready {
            $ready = try { ^docker sandbox exec $sandbox echo ok | ignore; true } catch { sleep 2sec; false }
        }
    }
    if not $ready {
        error make {msg: "Sandbox did not become ready"}
    }
    print "Sandbox ready"

    let results = run-checks (remote-runner $sandbox)

    if not $keep {
        print "Cleaning up..."
        do -i { ^docker sandbox stop $sandbox }
        do -i { ^docker sandbox rm $sandbox }
        rm -rf $ws
    }

    print ""
    report $results
}

# Remove leftover test sandbox
export def "main clean" [] {
    do -i { ^docker sandbox stop $sandbox }
    do -i { ^docker sandbox rm $sandbox }
    let ws = [$nu.home-dir temp sandbox-test-ws] | path join
    if ($ws | path exists) { rm -rf $ws }
    print "Cleaned up"
}

# Transport that runs each command inside the named sandbox via docker exec.
def remote-runner [sandbox: string]: nothing -> closure {
    {|argv|
        let r = (^docker sandbox exec $sandbox ...$argv) | complete
        {stdout: ($r.stdout | str trim), exit: $r.exit_code}
    }
}
