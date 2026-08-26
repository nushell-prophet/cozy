# Puts a freshly built binary in place of one that may be running right now.
#
# Why not a plain `cp`: writing into a file the kernel is executing fails with
# ETXTBSY ("Text file busy"). `cozy install nushell` run from a nushell session
# hits this every time — the shell doing the install holds ~/.cargo/bin/nu open.
# A rename replaces the *name* instead of the file, so the running process keeps
# its old inode and the next launch picks up the new one.
#
# Why the check matters: nushell's `cp` prints the OS error to stderr and lets
# the script continue, so the install used to report success while leaving the
# old binary in place. `mv` raises, so the failure now stops here.
export def main [
    src: path
    dest: path
]: nothing -> nothing {
    # Not a plain rename of $src because: the build directory may sit on another
    # filesystem, where rename(2) fails. Copying beside $dest keeps it one FS.
    let staged = $dest + ".new"
    cp $src $staged
    mv --force $staged $dest
}
