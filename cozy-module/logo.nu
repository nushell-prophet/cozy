const logo_path = path self | path dirname | path dirname | path join docker-files logo.ans

# Print the cozy logo banner.
@category cozy
export def main []: nothing -> string {
    open --raw $logo_path
}
