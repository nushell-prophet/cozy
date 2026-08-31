# Print the cozy logo banner.

const logo_path = path self | path dirname | path dirname | path join docker-files logo.ans

@category cozy
export def main []: nothing -> string {
    open --raw $logo_path
}
