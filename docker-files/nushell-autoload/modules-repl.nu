# modules-repl.nu — interactive-only module additions (REPL niceties).
# Autoload runs this in interactive sessions; non-interactive `-c` consumers
# skip it (they --config modules-core.nu instead — see that file's header).
# Why: don't add anything here that a `nu -c` caller needs — that belongs in
# modules-core.nu. These are session tools with no meaning in a one-shot `-c`.

use ~/repos/claude-nu/claude-nu/

use ~/.config/zellij/todo-nu/todo.nu lstd

use ~/repos/nu-cmd-stack/cmd-stack
