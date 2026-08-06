# modules-repl.nu — interactive-only module additions (REPL niceties).
# Autoload runs this in interactive sessions; non-interactive `-c` consumers
# skip it (they --config modules-core.nu instead — see that file's header).
# Why: don't add anything here that a `nu -c` caller needs — that belongs in
# modules-core.nu. These are session tools with no meaning in a one-shot `-c`.

use ~/repos/claude-nu/claude-nu/
# Only the two completions claude-nu still owns. Everything else (zellij, fd,
# chafa, sandbox-exec) moved to the dotfiles repo and is loaded by the
# `completions.nu` autoload deployed beside this file — not from here.
use ~/repos/claude-nu/completions/claude.nu *
use ~/repos/claude-nu/completions/nu.nu *

use ~/.config/zellij/todo-nu/todo.nu lstd

# `init` registers the keybindings (ctrl+s push, ctrl+alt+j/k scroll);
# a bare `use` loads the commands but binds no keys.
use ~/repos/nu-cmd-stack/cmd-stack; cmd-stack init --quiet
