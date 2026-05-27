# WORKSPACE_DIR is the host-rendered path. On macOS/Linux it's also valid in-VM
# (sbx bind-mounts at the same absolute path). On Windows sbx leaves it as
# "C:\Users\..." (or "C:/Users/...") while the actual mount lives at
# "/c/Users/...". Rewrite $env.WORKSPACE_DIR to the in-VM path once here so
# every downstream consumer can read it directly — no symlink intermediary.
def resolve-workspace-mount [host: string] {
    if ($host | path exists) { return $host }
    let normalized = $host | str replace -ra '\\' '/'
    let m = $normalized | parse -r '^(?<drive>[A-Za-z]):/(?<rest>.*)$'
    if ($m | is-empty) {
        error make {msg: $"WORKSPACE_DIR ($host) not resolvable inside VM"}
    }
    let candidate = $"/($m.drive.0 | str downcase)/($m.rest.0)"
    if not ($candidate | path exists) {
        error make {msg: $"WORKSPACE_DIR ($host): translated to ($candidate) but path doesn't exist"}
    }
    $candidate
}

if $env.WORKSPACE_DIR? != null { $env.WORKSPACE_DIR = (resolve-workspace-mount $env.WORKSPACE_DIR) }

# Create isolated overlay for external tools
overlay new others

# Nushell Modules
overlay use ~/repos/nu-goodies/nu-goodies

overlay use ~/repos/cozy/cozy-module/ as cozy --prefix

$env.kv.path = (
    if $env.WORKSPACE_DIR? != null {
        $env.WORKSPACE_DIR | path join sandbox-state nu-kv-values | tee { mkdir $in }
    } else {
        $nu.home-dir | path join .local share nu-kv
    }
)
overlay use ~/repos/nu-kv/kv --prefix

overlay use ~/repos/dotnu/dotnu --prefix
overlay use ~/repos/numd/numd --prefix

use ~/repos/claude-nu/claude-nu/

use ~/.config/zellij/todo-nu/todo.nu lstd

use ~/repos/nu-cmd-stack/cmd-stack
