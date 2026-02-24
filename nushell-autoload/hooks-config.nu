$env.config.hooks = {
    pre_prompt: [{ null }] # run before the prompt is shown
    pre_execution: [{ null }] # run before the repl input is run
    env_change: {
        PWD: [
            {
                condition: {|_ after| not ($after | path join 'toolkit.nu' | path exists) }
                code: "hide toolkit"
                # code: "overlay hide --keep-env [ PWD ] toolkit"
            }
            {
                # seems like the hook below is redundant as env_change presupposes change
                # condition: {|_, after| $_ != null}
                code: "if $env.ZELLIJ_SESSION_NAME? != null {
                            let pwd = pwd | path basename;
                            let tabs = zellij action query-tab-names
                            | lines

                            let length = $tabs
                            | where $it =~ $\"^($pwd)\\(·|$)\"
                            | length

                            if $length > 0 and ($tabs | last) =~ 'Tab #\\d+' {
                                $'($pwd)·($length + 1)'
                            } else {$pwd}
                            | str replace -r '^-+' ''
                            | zellij action rename-tab $in
                        }"
            }

            {
                condition: {|_ after| $after | path join 'toolkit.nu' | path exists }
                code: "
                      print $'(ansi default_underline)(ansi default_bold)toolkit(ansi reset) module (ansi green_italic)detected(ansi reset)...'
                      print $'(ansi yellow_italic)activating(ansi reset) (ansi default_underline)(ansi default_bold)toolkit(ansi reset) module with `(ansi default_dimmed)(ansi default_italic)use toolkit.nu(ansi reset)`'
                      use toolkit.nu
                      # overlay use --prefix toolkit.nu
                      "
            }

            {|before _|
                if $before == null {
                    let file = ($nu.home-dir | path join ".local" "share" "nushell" "startup-times.nuon")
                    if not ($file | path exists) {
                        mkdir ($file | path dirname)
                        touch $file
                    }
                    let ver = (version)
                    open $file | append {
                        date: (date now)
                        time: $nu.startup-time
                        build: ($ver.build_rust_channel)
                        allocator: ($ver.allocator)
                        version: ($ver.version)
                        commit: ($ver.commit_hash)
                        build_time: ($ver.build_time)
                        bytes_loaded: (view files | get size | math sum)
                    } | collect { save --force $file }
                }
            }
        ]
    }

    display_output: {
        metadata access {|meta|
            match $meta.content_type? {
                "application/x-nuscript"|"application/x-nuon"|"text/x-nushell" => { nu-highlight }
                "application/json" => { ^bat --language=json --color=always --style=plain --paging=never }
                _ => { }
            }
        }
        | if (term size).columns >= 100 { table -e } else { table }
    }

    # run to display the output of a pipeline
    command_not_found: { null } # return an error message when a command is not found
}
