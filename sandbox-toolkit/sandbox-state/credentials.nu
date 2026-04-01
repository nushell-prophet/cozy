const credentials_file = '~/.claude/.credentials.json'
const sandbox_state_dir = '~/workspace/mounted/sandbox-state'

def sandbox-state-path [filename: string]: nothing -> path {
    let dir = $sandbox_state_dir | path expand
    mkdir $dir
    $dir | path join $filename
}

# Export Claude Code OAuth credentials to sandbox-state for preservation.
#
# Copies ~/.claude/.credentials.json into ~/workspace/mounted/sandbox-state/.
# The mounted directory survives sandbox recreation, so exported credentials
# can be imported into a fresh sandbox without re-authenticating.
export def export [
    path?: path # Output file (default: ~/workspace/mounted/sandbox-state/credentials.json)
]: nothing -> nothing {
    let src = $credentials_file | path expand
    if not ($src | path exists) {
        error make {msg: $"credentials file not found: ($src). Run `claude login` first."}
    }
    let dst = $path | default (sandbox-state-path 'credentials.json')
    cp $src $dst
    print $"Exported credentials to ($dst)"
}

# Import Claude Code OAuth credentials from sandbox-state.
#
# Copies credentials.json from ~/workspace/mounted/sandbox-state/ into ~/.claude/.
# Skips import if credentials already exist (no overwrite).
export def import [
    --force (-f) # Overwrite existing credentials
    path?: path  # Input file (default: ~/workspace/mounted/sandbox-state/credentials.json)
]: nothing -> nothing {
    let src = $path | default (sandbox-state-path 'credentials.json')
    if not ($src | path exists) {
        error make {msg: $"credentials file not found: ($src). Run `cozy sandbox-state credentials export` first."}
    }
    let dst = $credentials_file | path expand
    if ($dst | path exists) and (not $force) {
        print "Credentials already exist, skipping import. Use --force to overwrite."
        return
    }
    let dst_dir = $dst | path dirname
    mkdir $dst_dir
    cp $src $dst
    print $"Imported credentials to ($dst)"
}
