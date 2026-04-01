const claude_dir = '~/.claude'
const credentials_file = '~/.claude/.credentials.json'
const settings_file = '~/.claude/settings.json'
const sandbox_state_dir = '~/workspace/mounted/sandbox-state'

def sandbox-state-path [filename: string]: nothing -> path {
    let dir = $sandbox_state_dir | path expand
    mkdir $dir
    $dir | path join $filename
}

# Export Claude Code OAuth credentials and settings to sandbox-state for preservation.
#
# Copies ~/.claude/.credentials.json and ~/.claude/settings.json into
# ~/workspace/mounted/sandbox-state/. The mounted directory survives sandbox
# recreation, so exported state can be imported into a fresh sandbox without
# re-authenticating.
export def export [
    path?: path # Output file for credentials (default: ~/workspace/mounted/sandbox-state/credentials.json)
]: nothing -> nothing {
    let cred_src = $credentials_file | path expand
    if not ($cred_src | path exists) {
        error make {msg: $"credentials file not found: ($cred_src). Run `claude login` first."}
    }
    let cred_dst = $path | default (sandbox-state-path 'credentials.json')
    cp $cred_src $cred_dst
    print $"Exported credentials to ($cred_dst)"

    let settings_src = $settings_file | path expand
    if ($settings_src | path exists) {
        let settings_dst = sandbox-state-path 'settings.json'
        cp $settings_src $settings_dst
        print $"Exported settings to ($settings_dst)"
    }
}

# Import Claude Code OAuth credentials and settings from sandbox-state.
#
# Copies credentials.json and settings.json from ~/workspace/mounted/sandbox-state/
# into ~/.claude/. Skips import if credentials already exist (no overwrite).
# Settings are merged: existing keys are preserved, exported keys are added.
export def import [
    --force (-f) # Overwrite existing credentials
    path?: path  # Input file for credentials (default: ~/workspace/mounted/sandbox-state/credentials.json)
]: nothing -> nothing {
    let cred_src = $path | default (sandbox-state-path 'credentials.json')
    if not ($cred_src | path exists) {
        error make {msg: $"credentials file not found: ($cred_src). Run `cozy sandbox-state credentials export` first."}
    }
    let cred_dst = $credentials_file | path expand
    if ($cred_dst | path exists) and (not $force) {
        print "Credentials already exist, skipping import. Use --force to overwrite."
        return
    }
    let dst_dir = $claude_dir | path expand
    mkdir $dst_dir
    cp $cred_src $cred_dst
    print $"Imported credentials to ($cred_dst)"

    let settings_src = sandbox-state-path 'settings.json'
    if ($settings_src | path exists) {
        let settings_dst = $settings_file | path expand
        let merged = if ($settings_dst | path exists) {
            open $settings_dst | merge (open $settings_src)
        } else {
            open $settings_src
        }
        $merged | save -f $settings_dst
        print $"Imported settings to ($settings_dst)"
    }
}
