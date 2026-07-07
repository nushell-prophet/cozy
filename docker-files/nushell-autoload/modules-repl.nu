# modules-repl.nu — interactive-only module additions (REPL niceties).
# Autoload runs this in interactive sessions; non-interactive `-c` consumers
# skip it (they --config modules-core.nu instead — see that file's header).
# Why: don't add anything here that a `nu -c` caller needs — that belongs in
# modules-core.nu. These are session tools with no meaning in a one-shot `-c`.

use ~/repos/claude-nu/claude-nu/
use ~/repos/claude-nu/completions/claude.nu *
use ~/repos/claude-nu/completions/nu.nu *
use ~/repos/claude-nu/completions/fd.nu *
# Not `use zellij.nu *` because: its subcommands are exported bare ("action …");
# the no-star form prefixes them with the module name -> `zellij action …`
use ~/repos/claude-nu/completions/zellij.nu

use ~/.config/zellij/todo-nu/todo.nu lstd

use ~/repos/nu-cmd-stack/cmd-stack
