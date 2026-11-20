###file O.nu
export def completions-macos-apps []: nothing -> list<string> {
    ls /Applications --short-names | get name | each { str replace --regex '\.app$' '' | $'"($in)"' }
}

# Open a file in the specified macOS application or reveal it in Finder (--app flag supports completions)
# > O O.nu --app "Sublime Text"
@category platform
export def 'O' [
    filepath?: path
    --app (-a): string@'completions-macos-apps' = 'Snagit 2022.app' # App to open with; the default is the author's screenshot app, pass --app to use another
    --reveal (-r) # Reveal app in Finder
]: [path -> nothing nothing -> nothing] {
    if $filepath == null { } else { $filepath }
    | if $reveal {
        ^open --reveal $in
    } else {
        ^open -a $app $in
    }
}

###file ramdisk-create.nu
# Create ramdisk in macOS
@category platform
export def --env 'ramdisk-create' [
    size: filesize = 4194304kb
]: nothing -> nothing {
    let vol = (hdiutil attach -nobrowse -nomount $'ram://($size | into int | $in * 1.024 / 1000 * 2)' | str trim);

    sleep 2sec
    (^diskutil erasevolume HFS+ RAMDisk $vol)
    cd /Volumes/RAMDisk
}
