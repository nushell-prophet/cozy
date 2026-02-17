if $env.WORKSPACE_DIR? != null { ^ln -sfn $env.WORKSPACE_DIR ~/ws }

# Create isolated overlay for external tools
overlay new others

# Nushell Modules
overlay use ~/git/nu-goodies/nu-goodies

$env.kv.path = ($nu.home-dir | path join .local share nushell-kv)
overlay use ~/git/nushell-kv/kv --prefix

overlay use ~/git/dotnu/dotnu --prefix
overlay use ~/git/numd/numd --prefix

use ~/git/claude-nu/claude-nu/
