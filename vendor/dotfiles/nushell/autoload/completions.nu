# Load the external-CLI completions that ship next to this file, in
# ~/.config/nushell/completions/.
#
# Why a loader instead of dropping the files straight into this autoload dir:
# autoload `source`s a file, and every completion file is built on
# `export extern main` (the "file name IS the command name" convention). That
# name only resolves through `use` — `source completions/fd.nu` registers a
# command literally called `main`, not `fd`. So each file has to be `use`d, by
# name, and a hand-kept list is the only way: `use` takes no glob.
#
# Nushell also does not recurse into autoload subdirectories, so the completion
# files cannot live one level down from here and be picked up on their own.

use ~/.config/nushell/completions/fd.nu *
use ~/.config/nushell/completions/chafa.nu *
use ~/.config/nushell/completions/sandbox-exec.nu *

# Not `use zellij.nu *` because: its subcommands are exported bare ("action …");
# the no-star form prefixes them with the module name -> `zellij action …`
use ~/.config/nushell/completions/zellij.nu
