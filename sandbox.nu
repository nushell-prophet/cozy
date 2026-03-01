def latest-tag [image: string]: nothing -> string {
    let tags = ^docker images --format json
    | lines
    | each { from json }
    | where {|x| $x.Repository == $image and ($x.Tag | str starts-with 'v') }
    | get Tag
    | each { str substring 1.. | into int }
    | sort -r

    if ($tags | is-empty) { "v1" } else { $"v($tags | first | $in + 1)" }
}

def sandboxes []: nothing -> table {
    ^docker sandbox ls --json | from json | get -o vms | default []
}

def "nu-complete sandbox names" []: nothing -> list<record<value: string, description: string>> {
    sandboxes | each {|x| {value: $x.name description: $"($x.agent) ($x.status)"} }
}

export def main [] { help sandbox }

# Build Docker image with auto-incremented vN tag, recreate existing sandboxes
export def build [
    --image (-i): string = "nushell-ai-sandbox" # image name
    --path (-p): path # Dockerfile directory
    --recreate: string@"nu-complete sandbox names" # recreate a specific sandbox
    --recreate-all # recreate all sandboxes
] {
    let dir = $path | default $env.FILE_PWD

    let sandboxes = if $recreate != null {
        sandboxes | where name == $recreate | select name workspaces
    } else if $recreate_all {
        sandboxes | select name workspaces
    } else { [] }

    let tag = latest-tag $image
    ^docker build -t $"($image):($tag)" -t $"($image):latest" $dir
    print $"($image):($tag)"

    for sb in $sandboxes {
        print $"Removing sandbox ($sb.name)..."
        ^docker sandbox stop $sb.name
        ^docker sandbox rm $sb.name
    }

    for sb in $sandboxes {
        for ws in $sb.workspaces {
            print $"Creating sandbox for ($ws)..."
            ^docker sandbox create --debug --load-local-template -t $"($image):($tag)" --name $sb.name claude $ws
        }
    }
}

# Run sandbox with latest image tag
export def run [
    project_path?: path # project to mount (default: $PWD)
    --image (-i): string = "nushell-ai-sandbox" # image name
] {
    let tag = ^docker images --format json
    | lines
    | each { from json }
    | where {|x| $x.Repository == $image and ($x.Tag | str starts-with 'v') }
    | each {|x| {tag: $x.Tag n: ($x.Tag | str substring 1.. | into int)} }
    | sort-by -r n

    if ($tag | is-empty) {
        error make {msg: $"no tags found for image '($image)'"}
    }

    let full = $"($image):($tag | first | get tag)"
    let path = $project_path | default $env.PWD
    ^docker sandbox run --load-local-template -t $full claude $path
}

# List sandboxes as a table
export def ls [] { sandboxes }

# Stop sandbox(es)
export def stop [
    ...name: string@"nu-complete sandbox names"
] {
    ^docker sandbox stop ...$name
}

# Remove sandbox(es)
export def rm [
    ...name: string@"nu-complete sandbox names"
] {
    ^docker sandbox rm ...$name
}
