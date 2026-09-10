# The runtime's fixed guest path — the same constant `container.nu` documents
# next to its `--ssh` flag.
const SOCK = "/var/host-services/ssh-auth.sock"

# Show or switch whether this shell can reach the host ssh-agent that
# `container.nu up --ssh-agent` forwards into the guest.
#
# The runtime sets SSH_AUTH_SOCK for every guest process; the autoload
# host-ssh-agent.nu hides it on every interactive start, so the default is
# off. `--enable` sets it for the current shell and what it spawns from now
# on; `--disable` hides it again. `--env` is what makes the change land in the
# caller's shell rather than vanish with this command.
#
# Why off by default: parallel clients of that socket lose their answers and
# hang, and the container's terminal can freeze with them
# (https://github.com/apple/container/issues/2247). Keep it on only in the pane that signs, and
# only while it signs.
export def --env main [
    --enable # let this shell and its children reach the forwarded agent
    --disable # hide the agent again (the default state of every new shell)
]: nothing -> nothing {
    if $enable and $disable {
        error make --unspanned {msg: "--enable and --disable together — pick one"}
    }
    if $enable {
        if not ($SOCK | path exists) {
            error make --unspanned {msg: $"no forwarded agent at ($SOCK) — this container was created without `--ssh-agent`, and the forward is fixed at creation"}
        }
        $env.SSH_AUTH_SOCK = $SOCK
    }
    if $disable {
        # Only the forwarded socket: on a host install, or under another
        # runtime, the variable names a real agent this command does not own.
        let current = $env.SSH_AUTH_SOCK? | default ''
        if $current == $SOCK {
            hide-env SSH_AUTH_SOCK
        } else if $current != '' {
            error make --unspanned {msg: $"SSH_AUTH_SOCK is ($current), not the forwarded host agent — not touching it"}
        }
    }
    print (status)
}

# One line: the switch, then what stands behind it. `timeout` because a wedged
# relay makes `ssh-add` hang forever, and the status must not join it.
def status []: nothing -> string {
    let forwarded = $SOCK | path exists
    let current = $env.SSH_AUTH_SOCK? | default ''
    let enabled = $current == $SOCK
    let switch = if $enabled { $"(ansi green)enabled(ansi reset)" } else { $"(ansi yellow)disabled(ansi reset)" }
    let agent = if $current != '' and not $enabled {
        $"SSH_AUTH_SOCK points at another agent, ($current)"
    } else if not $forwarded {
        "no agent forwarded into this container"
    } else if not $enabled {
        $"agent forwarded at ($SOCK), hidden from this shell"
    } else {
        # Exit 1 is "answers, holds no keys" — the agent is fine, add a key on
        # the host. Anything else after 5 s is the frozen relay: the cure is on
        # the mac, and it is also what wakes a frozen terminal.
        let r = ^timeout 5 ssh-add -l | complete
        match $r.exit_code {
            0 => {
                let n = $r.stdout | lines | where $it != '' | length
                let word = if $n == 1 { 'key' } else { 'keys' }
                $"agent answers, ($n) ($word)"
            }
            1 => "agent answers, no keys — `ssh-add --apple-use-keychain ~/.ssh/id_ed25519` on the host adds one"
            _ => $"(ansi red)agent does not answer in 5 s(ansi reset) — the relay is likely wedged; on the mac: `killall ssh-agent` — it wakes the relay, and launchd restarts the agent on its next use"
        }
    }
    $"host ssh-agent: ($switch) — ($agent)"
}
