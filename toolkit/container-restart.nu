# Cheatsheet — getting the Apple `container` cage back after the runtime restarts
# (`container system stop/start`, a Docker-for-Mac-style upgrade, a reboot).
#
# READ THIS FILE, DO NOT RUN IT. Every step is a `#` comment on purpose: which
# case applies depends on what survived the restart, and pasting the wrong one
# deletes a working agent. The `error make` below enforces that.

error make {msg: "toolkit/container-restart.nu is a cheatsheet, not a script — open it, find the case that matches your state, and paste those lines yourself."}

# ── What a restart leaves behind ──────────────────────────────────────────────
#
# Both containers are *stopped*, not absent. `cozy-caged` usually survives — check.
#
# toolkit/container-up.nu has no restart mode, and neither invocation recovers
# from this state:
#   - a plain re-run     → "a container named X already exists"  (container-up.nu:290)
#   - --reload-egress    → dead end: the proxy is not running, so the address the
#                          agent was built with cannot be read  (container-up.nu:309)
#
# --reload-egress is for editing the allowlist while the proxy runs. Not this.

# ── Case A — keep the agent (its home, its Claude state) ──────────────────────
#
# container system start
# container network list                        # cozy-caged must be listed
# container start cozy-egress
# container start my-agent
# container exec cozy-egress hostname -I        # take the 192.168.216.x one
# container exec my-agent printenv HTTPS_PROXY  # must name that same address
#
# The exit is baked into the agent's env when it is created and cannot be
# changed afterwards. Apple `container` has no static-IP flag, so a restarted
# proxy may come back somewhere else — if the two disagree, the agent has no way
# out at all. Go to case B.
#
# Nothing probes the cage on this path, so do it by hand — same probe as
# container-up.nu's assert-caged and `cozy verify`'s `egress: no direct route`:
#
# container exec my-agent curl -sS --noproxy '*' --max-time 10 -o /dev/null -w '%{http_code}\n' https://1.1.1.1
#
# 000 is the pass: the connection never happened. Any real HTTP status means
# traffic leaves unfiltered and the cage is open.

# ── Case B — rebuild the agent (the proxy moved, or you don't need its state) ─
#
# Loses whatever lives inside the container; the mounted host folders are untouched.
#
# container system start
# container delete my-agent                     # must go first — the script refuses to touch it
# nu toolkit/container-up.nu my-agent ~/path/to/project
#
# No --reload-egress here: ensure-egress sees the proxy `stopped` (not absent),
# deletes it and starts a fresh one, the agent is created with the new address,
# and assert-caged proves the cage before the script reports success.

# ── Case C — cozy-caged is gone ───────────────────────────────────────────────
#
# Same as case B. The script creates the network when the name is missing, so
# nothing extra is needed:
#
# container delete my-agent
# container delete cozy-egress                  # if it lingers, attached to nothing
# nu toolkit/container-up.nu my-agent ~/path/to/project
#
# A network that is present is still only a name — nothing observable says it was
# made with --internal. That is why the probe in case A is not optional.
