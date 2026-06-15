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

# Env vars that MUST agree across the three injection points: the Dockerfile
# ENV block, sbx-kit/spec.yaml's environment.variables, and the export block
# bootstrap.nu writes to /etc/sandbox-persistent.sh. Their formats differ
# (Docker directive vs YAML vs shell), so they can't share one literal — this
# guard turns silent drift into a loud failure instead.
const shared_env_keys = [XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME HELIX_RUNTIME LANG]

# The PATH prefix the Dockerfile prepends (before its `${PATH}`) — sbx-kit/spec.yaml
# has no ${PATH} to expand, so it must start with this exact prefix.
const path_prefix = '/home/agent/.local/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin'

# Normalize a value for comparison: strip surrounding quotes and expand the
# $HOME the shell/Docker forms use to the literal /home/agent the kit spells out.
def norm-env [v: string]: nothing -> string {
    $v | str trim | str trim --char '"'
    | str replace --all '${HOME}' '/home/agent'
    | str replace --all '$HOME' '/home/agent'
}

def dockerfile-env []: nothing -> record {
    let text = open --raw $dockerfile
    $shared_env_keys | reduce --fold {} {|k acc|
        let m = $text | parse --regex ('(?m)^[ \t]*(?:ENV[ \t]+)?' + $k + '=(?<v>\S+)')
        if ($m | is-empty) { $acc } else { $acc | insert $k (norm-env $m.v.0) }
    }
}

def bootstrap-env []: nothing -> record {
    let text = open --raw $bootstrap
    $shared_env_keys | reduce --fold {} {|k acc|
        let m = $text | parse --regex ('(?m)^export ' + $k + '="(?<v>[^"]*)"')
        if ($m | is-empty) { $acc } else { $acc | insert $k (norm-env $m.v.0) }
    }
}

def kit-env []: nothing -> record {
    let vars = open $kit_spec | get environment.variables
    $shared_env_keys | reduce --fold {} {|k acc|
        let v = $vars | get --optional $k
        if ($v == null) { $acc } else { $acc | insert $k (norm-env $v) }
    }
}

# Compare the shared env keys across the three sources. Returns rows so a
# mismatch shows exactly which key and which source disagrees.
def "main env" []: nothing -> table {
    let d = dockerfile-env
    let b = bootstrap-env
    let k = kit-env
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

    let dpath = (dockerfile-env-path)
    let kpath = (kit-env-path)
    let path_row = {
        key: 'PATH (prefix)'
        dockerfile: ($dpath | default '(missing)')
        bootstrap: '(n/a)'
        kit: ($kpath | default '(missing)')
        ok: (($dpath | default '' | str starts-with $path_prefix) and ($kpath | default '' | str starts-with $path_prefix))
    }

    let all = $rows | append $path_row
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

# Run every check; errors (non-zero exit) if any drift is found.
export def main [] {
    main manifest | print
    print (main env)
    print $"(ansi green)All consistency checks passed(ansi reset)"
}
