# The backtrace errors in 0.103 are helpful but not while testing Nutest itself
# This script allow us to unpack them so they look like the original error given that
# for whatever reason, `$env.NU_BACKTRACE = 0` doesn't appear to work

export def unwrap-error []: record -> record {
    # Nushell 0.114 replaced the catch record's `json` string field with a
    # structured `details` record. Normalise back to `json` so the rest of this
    # (version-agnostic) code keeps working on both.
    let raw = $in
    let input = if 'json' in ($raw | columns) { $raw } else { $raw | insert json ($raw.details | to json) }
    let original = $input | select msg rendered json

    mut error = $original
    mut json = $error.json | from json
    while (("inner" in $json) and ($json.inner | is-not-empty)) {
        $json = $error.json | from json | get inner | first
        $error = $error | merge {
            msg: $json.msg
            json: ($json | to json)
        }
    }

    $original | merge {
        msg: $error.msg
        rendered: ($error.rendered | last-rendered)
        labels: $json.labels
        json: $error.json
    }
}

def last-rendered []: string -> string {
    let rendered = $in
    let lines = $rendered | lines
    let errors_start = $lines
        | enumerate
        | where item like "^Error: *"
        | get index

    if (($errors_start | is-empty) | (($errors_start | length) == 1)) {
        $rendered
    } else {
        $lines
            | slice ($errors_start | last)..
            | str join "\n"
    }
}
