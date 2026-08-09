# Host-side consistency checks for cozy's duplicated / derived config.
# Pure file comparisons — no sandbox or image build required. Run before
# building (or in CI) to catch drift that a runtime smoke test can't.
#
#   nu toolkit/check.nu        # run every check; non-zero exit on any drift

const cozy_root = (path self | path dirname | path dirname)
const vendor_yml = ($cozy_root | path join toolkit vendor.yml)
const manifest = ($cozy_root | path join cozy-module vendored-repos.nuon)
const dockerfile = ($cozy_root | path join Dockerfile)
const bootstrap = ($cozy_root | path join cozy-module install bootstrap.nu)
const kit_spec = ($cozy_root | path join sbx-kit spec.yaml)
const compose = ($cozy_root | path join compose.yaml)
const container_nu = ($cozy_root | path join toolkit container.nu)

# Env vars that MUST agree across the three injection points: the Dockerfile
# ENV block, sbx-kit/spec.yaml's environment.variables, and the export block
# bootstrap.nu writes to /etc/sandbox-persistent.sh. Their formats differ
# (Docker directive vs YAML vs shell), so they can't share one literal — this
# guard turns silent drift into a loud failure instead.
const shared_env_keys = [XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME HELIX_RUNTIME LANG]

# Keys that only two of the three sources carry: the Dockerfile ENV and the kit
# spec. They are deliberately absent from bootstrap.nu's block — that block is
# sourced by every login shell in the sandbox, and TERM belongs to the terminal
# that connected, not to a file. HOME is the container's, not something a login
# rc should assert. But Dockerfile and kit must still agree with each other, and
# nothing checked them at all: a TERM_PROGRAM changed in one place and not the
# other is exactly the silent drift the block above exists to catch.
#
# Not HOME, though the audit that prompted this listed it: the Dockerfile omits
# it on purpose (an ENV is image-wide, so `ENV HOME=/home/agent` would hand a
# root exec the agent's home — see the comment at Dockerfile:101). Both sides
# derive it from the passwd entry instead, and only the kit has to spell it out.
const paired_env_keys = [TERM COLORTERM TERM_PROGRAM HOMEBREW_NO_ASK HOMEBREW_NO_AUTO_UPDATE]

# The PATH prefix the Dockerfile prepends (before its `${PATH}`) — sbx-kit/spec.yaml
# has no ${PATH} to expand, so it must start with this exact prefix.
#
# Prefix only, deliberately: the Dockerfile's tail *is* `${PATH}`, whatever the
# base image happens to set, and no file in this repo says what that expands to.
# Comparing full tails would mean hardcoding a second guess at the base image's
# PATH here — a guard that fails when the base changes and is right for no
# reason when it passes. The tails can still drift; proving it needs a built
# image, which belongs to `cozy verify`, not to a file-comparison check.
const path_prefix = '/home/agent/.local/bin:/home/agent/.cargo/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin'

# Normalize a value for comparison: strip surrounding quotes and expand the
# $HOME the shell/Docker forms use to the literal /home/agent the kit spells out.
def norm-env [v: string]: nothing -> string {
    $v | str trim | str trim --char '"'
    | str replace --all '${HOME}' '/home/agent'
    | str replace --all '$HOME' '/home/agent'
}

def dockerfile-env [keys: list<string>]: nothing -> record {
    let text = open --raw $dockerfile
    $keys | reduce --fold {} {|k acc|
        let m = $text | parse --regex ('(?m)^[ \t]*(?:ENV[ \t]+)?' + $k + '=(?<v>\S+)')
        if ($m | is-empty) { $acc } else { $acc | insert $k (norm-env $m.v.0) }
    }
}

# No `^` anchor: the first export shares its line with the `let env_exports = '`
# that opens the block, so an anchored pattern silently drops whichever key
# happens to be first — and a key missing from a source reads as "no drift".
def bootstrap-env []: nothing -> record {
    let text = open --raw $bootstrap
    $shared_env_keys | reduce --fold {} {|k acc|
        let m = $text | parse --regex ('(?m)export[ \t]+' + $k + '="(?<v>[^"]*)"')
        if ($m | is-empty) { $acc } else { $acc | insert $k (norm-env $m.v.0) }
    }
}

def kit-env [keys: list<string>]: nothing -> record {
    let vars = open $kit_spec | get environment.variables
    $keys | reduce --fold {} {|k acc|
        let v = $vars | get --optional $k
        # `into string`: YAML types unquoted values, so HOMEBREW_NO_ASK: 1 is an
        # int here while every other source spells it as text.
        if ($v == null) { $acc } else { $acc | insert $k (norm-env ($v | into string)) }
    }
}

# Compare the shared env keys across the three sources. Returns rows so a
# mismatch shows exactly which key and which source disagrees.
def "main env" []: nothing -> table {
    let d = dockerfile-env ($shared_env_keys ++ $paired_env_keys)
    let b = bootstrap-env
    let k = kit-env ($shared_env_keys ++ $paired_env_keys)
    let rows = $shared_env_keys | each {|key|
        let dv = $d | get --optional $key
        let bv = $b | get --optional $key
        let kv = $k | get --optional $key
        let vals = [$dv $bv $kv] | compact
        {
            key: $key
            dockerfile: ($dv | default '(missing)')
            bootstrap: ($bv | default '(missing)')
            kit: ($kv | default '(missing)')
            ok: (($vals | uniq | length) == 1 and ($vals | length) == 3)
        }
    }

    # Two sources, so the bootstrap column reads n/a — but both must carry the
    # key and agree. A key silently dropped from one file is drift too, which is
    # why a missing value fails rather than being skipped.
    let paired_rows = $paired_env_keys | each {|key|
        let dv = $d | get --optional $key
        let kv = $k | get --optional $key
        {
            key: $key
            dockerfile: ($dv | default '(missing)')
            bootstrap: '(n/a)'
            kit: ($kv | default '(missing)')
            ok: ($dv != null and $dv == $kv)
        }
    }

    let dpath = (dockerfile-env-path)
    let kpath = (kit-env-path)
    let path_row = {
        key: 'PATH (prefix)'
        dockerfile: ($dpath | default '(missing)')
        bootstrap: '(n/a)'
        kit: ($kpath | default '(missing)')
        ok: (($dpath | default '' | str starts-with $path_prefix) and ($kpath | default '' | str starts-with $path_prefix))
    }

    let all = $rows | append $paired_rows | append $path_row
    let bad = $all | where not ok
    if ($bad | is-not-empty) {
        print ($all | select key dockerfile bootstrap kit ok)
        error make {msg: $"env drift: ($bad | get key | str join ', ') disagree across Dockerfile / sbx-kit/spec.yaml / bootstrap.nu"}
    }
    $all | select key ok
}

def dockerfile-env-path []: nothing -> string {
    let m = open --raw $dockerfile | parse --regex '(?m)^[ \t]*(?:ENV[ \t]+)?PATH=(?<v>\S+)'
    if ($m | is-empty) { '' } else { norm-env $m.v.0 }
}

def kit-env-path []: nothing -> string {
    norm-env (open $kit_spec | get environment.variables | get --optional PATH | default '')
}

# The generated manifest must list exactly vendor.yml's repos plus cozy. Names
# only — vendor.nu is the sole writer of the URLs, so correct names imply
# correct URLs by construction.
def "main manifest" []: nothing -> record {
    let want = open $vendor_yml | get repo | append cozy | sort
    let have = open $manifest | get name | sort
    if $want != $have {
        let missing = $want | where {|r| $r not-in $have }
        let extra = $have | where {|r| $r not-in $want }
        error make {msg: $"vendored-repos.nuon is stale — run `nu toolkit/vendor.nu`. missing: ($missing | str join ', '); extra: ($extra | str join ', ')"}
    }
    {check: manifest, repos: ($have | length), ok: true}
}

# The egress proxy is pinned by digest in two places — compose.yaml for the
# docker path, toolkit/container.nu for the Apple `container` one. Both cage
# the agent behind the same proxy holding the same policy, so the two literals
# must agree, and nothing but this check makes them. The digest itself is also
# asserted: replacing it with a floating tag silently un-pins the one container
# that has internet, which no comparison of the two copies would catch.
def "main egress-image" []: nothing -> record {
    let compose_ref = open $compose | get services.egress.image
    let m = open --raw $container_nu | parse --regex "(?m)^const egress_image = '(?<v>[^']+)'"
    let up_ref = if ($m | is-empty) { '(missing)' } else { $m.v.0 }
    if $compose_ref != $up_ref {
        error make {msg: $"egress image drift: compose.yaml has ($compose_ref), toolkit/container.nu has ($up_ref)"}
    }
    if not ($compose_ref | str contains '@sha256:') {
        error make {msg: $"egress image ($compose_ref) is not pinned by digest — the proxy that holds the policy must not float"}
    }
    {check: 'egress-image', ref: $compose_ref, ok: true}
}

# Run every check; errors (non-zero exit) if any drift is found.
export def main [] {
    main manifest | print
    main egress-image | print
    print (main env)
    print $"(ansi green)All consistency checks passed(ansi reset)"
}
