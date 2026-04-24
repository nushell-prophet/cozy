if $env.WORKSPACE_DIR? != null { ^ln -sfn $env.WORKSPACE_DIR ~/workspace/mounted }

# Create isolated overlay for external tools
overlay new others

# Nushell Modules
overlay use ~/repos/nu-goodies/nu-goodies

overlay use ~/repos/cozy/sandbox-toolkit/ as cozy --prefix

$env.kv.path = (
    if $env.WORKSPACE_DIR? != null {
        $env.WORKSPACE_DIR | path join 'sandbox-state' 'nu-kv-values' | tee { mkdir $in }
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
