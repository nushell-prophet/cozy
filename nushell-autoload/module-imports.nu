if $env.WORKSPACE_DIR? != null { ^ln -sfn $env.WORKSPACE_DIR ~/workspace/mounted }

# Create isolated overlay for external tools
overlay new others

# Nushell Modules
overlay use ~/repos/nu-goodies/nu-goodies

$env.kv.path = (
    if $env.WORKSPACE_DIR? != null { $env.WORKSPACE_DIR } else { 
        $nu.home-dir | path join .local share nushell-kv
    }
)
overlay use ~/repos/nushell-kv/kv --prefix

overlay use ~/repos/dotnu/dotnu --prefix
overlay use ~/repos/numd/numd --prefix

use ~/repos/claude-nu/claude-nu/

use ~/.config/zellij/todo-nu/todo.nu lstd
