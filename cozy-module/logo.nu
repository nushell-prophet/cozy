const logo_path = path self ../docker-files/logo.ans

# Print the cozy logo banner.
@category cozy
export def main []: nothing -> string {
    open --raw $logo_path
}
