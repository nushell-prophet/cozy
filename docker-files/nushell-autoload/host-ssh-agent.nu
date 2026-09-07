# Hide the forwarded host ssh-agent from every process started in this shell.
# Why: with `container.nu up --ssh-agent` the runtime sets SSH_AUTH_SOCK for
# every process in the guest, and parallel clients of that socket (a test
# suite signing with `ssh-keygen -Y sign`, several agents committing with -S
# at once) lose their answers on live connections and hang; the container's
# terminal can freeze with them, and only `killall ssh-agent` on the mac
# frees them (https://github.com/apple/container/issues/2247). Signing is
# occasional, the machine lives for days, so the default is off: the socket
# stays in place, nothing reaches it until `cozy use-host-ssh-agent --enable`
# turns it back on in the one pane that signs.
# Only the forwarded socket, by its fixed guest path: this autoload runs on
# every install path, host included, and a host's own agent must stay.
if ($env.SSH_AUTH_SOCK? | default '') == '/var/host-services/ssh-auth.sock' {
    hide-env SSH_AUTH_SOCK
}
