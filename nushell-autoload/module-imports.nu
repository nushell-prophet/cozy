# Create isolated overlay for external tools
overlay new others

# Nushell Modules
overlay use /home/agent/git/nu-goodies/nu-goodies

$env.kv.path = '/home/agent/.local/share/nushell-kv'
overlay use /home/agent/git/nushell-kv/kv --prefix

overlay use /home/agent/git/dotnu/dotnu --prefix
overlay use /home/agent/git/numd/numd --prefix

use /home/agent/git/claude-nu/claude-nu/
