# Open an sbx sandbox in a new WezTerm window and attach to its zellij session.
# The Apple `container` twin of this is `nu toolkit/container.nu attach`.

use ./wezterm.nu *

def "nu-complete sandbox names" [] {
    ^sbx ls --json | from json | get sandboxes
    | each {|x| {value: $x.name description: $"($x.status) ($x.workspaces | str join ' ')"} }
}

export def main [
    sandbox_name: string@"nu-complete sandbox names"
    --config-file: path
    --background: string@"nu-complete wezterm background" = "000000" # hex without '#'
    --no-job # don't create background job for the proces
    --zellij-session: string = '' # zellij session name to use instead of sandbox name
] {
    attach-window [sbx exec -it $sandbox_name] ($zellij_session | default --empty $sandbox_name) --config-file $config_file --background $background --no-job=$no_job
}
