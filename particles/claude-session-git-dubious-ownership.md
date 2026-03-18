---
date: 2026-03-18
session: ae98886e-5ae0-4ff1-a859-f2b646326c70
---

# Session

## User

> lazygit
2026/03/18 23:11:04 An error occurred! Please create an issue at: https://github.com/jesseduffield/lazygit/issues

*errors.errorString Error getting repo paths: 'git -C /Users/user/git/ai-sandbox-dev-container/cozy rev-parse --path-format=absolute --show-toplevel --absolute-git-dir --git-common-dir --is-bare-repository --show-superproject-working-tree' failed: fatal: detected dubious ownership in repository at '/Users/user/git/ai-sandbox-dev-container/cozy'
To add an exception for this directory, call:

        git config --global --add safe.directory /Users/user/git/ai-sandbox-dev-container/cozy

github.com/jesseduffield/lazygit/pkg/commands/git.go:67 (0x5a0838)
github.com/jesseduffield/lazygit/pkg/gui/gui.go:323 (0x70dd5c)
github.com/jesseduffield/lazygit/pkg/gui/gui.go:883 (0x711bd8)
github.com/jesseduffield/lazygit/pkg/gui/gui.go:904 (0x712318)
github.com/jesseduffield/lazygit/pkg/utils/utils.go:80 (0x3a4358)
github.com/jesseduffield/lazygit/pkg/gui/gui.go:903 (0x712298)
github.com/jesseduffield/lazygit/pkg/app/app.go:277 (0x760a9c)
github.com/jesseduffield/lazygit/pkg/app/app.go:48 (0x760a65)
github.com/jesseduffield/lazygit/pkg/app/entry_point.go:177 (0x762564)
github.com/jesseduffield/lazygit/main.go:23 (0x7637a8)
internal/runtime/atomic/types.go:194 (0x609b4)
runtime/asm_arm64.s:1447 (0x9dfc4)


---

why this happens with lazygit?

## Assistant



**Rephrased:** Why does lazygit fail with a "dubious ownership" error?

Git's `safe.directory` check triggers when the repository owner differs from the user running git. Inside the sandbox, the mounted workspace at `/Users/user/git/ai-sandbox-dev-container/cozy` is owned by the host user (likely uid 501), but the sandbox runs as a different user (e.g., `agent`). Git treats this ownership mismatch as suspicious and refuses to operate.

lazygit simply calls `git rev-parse` under the hood, which hits this check and fails.

**Fix:** add the safe.directory exception, as git suggests:

```
git config --global --add safe.directory /Users/user/git/ai-sandbox-dev-container/cozy
```

To make this persistent across sandbox rebuilds, you could add it to your Dockerfile or dotfiles setup. One option: add a wildcard to trust all directories:

```
git config --global --add safe.directory '*'
```

Want me to check whether your Dockerfile or dotfiles already handle `safe.directory`, and add it if not?

## User

what this safe.directory does?

## Assistant



**Rephrased:** What does `safe.directory` do?

Git 2.35.2+ added a security check: before operating on a repository, git verifies the repo directory is owned by the same user running the command. If not, it refuses to work — preventing a scenario where a malicious user plants a crafted `.git/config` (with hooks, aliases, etc.) in a directory you might `cd` into.

`safe.directory` is the allowlist that bypasses this check for specific paths. When you add a path there, you're telling git: "I trust this repo even though I don't own it."

The wildcard `'*'` disables the check entirely — reasonable inside an isolated sandbox where ownership mismatches are expected and there's no untrusted user.

## User

ok, yes this to Dockerfile, but comment the reason

## Assistant

Line 52 already has `git config --global`. I'll add `safe.directory` there.

Done. The wildcard `safe.directory` is added at line 52 with a comment explaining the ownership mismatch and why the wildcard is acceptable in this context.

Committed. `Dockerfile` only, with the reasoning in the commit body.

## User

Is it possible to add wildcard to add repos only from $env.WORKSPACE_DIR/ ?

## Assistant



**Rephrased:** Is it possible to restrict `safe.directory` to only repos under `$WORKSPACE_DIR/` instead of using a wildcard?

No. `safe.directory` accepts either an exact absolute path or the literal `*` wildcard. There's no glob/prefix matching — you can't write `safe.directory = /some/path/*` to trust all subdirectories.

The alternatives are:

1. **Enumerate specific paths** — but you don't know them at build time since the workspace path comes from the host at `docker sandbox create`.
2. **Set it at runtime** — an autoload script or entrypoint that runs `git config --global --add safe.directory $WORKSPACE_DIR` on sandbox start. This would be tighter than `*`, but adds moving parts.

Given the sandbox is isolated and single-user, the wildcard is the pragmatic choice. Want me to try the runtime approach instead?

## User

it's one user, but with agents inside. I don't understand how dangerous it is. Probably not that much, as it is a sandbox, right?

## Assistant



**Rephrased:** It's a single-user sandbox but with AI agents running inside. How dangerous is disabling the safe.directory check in this context?

The threat `safe.directory` guards against: a malicious actor plants a `.git/` directory with crafted hooks in a path you'll `cd` into. When you run `git status` there, the hook executes arbitrary code as you.

In your sandbox:

- There's no untrusted user who could plant a malicious `.git/`
- The agents *are* already running arbitrary code — that's their purpose
- The sandbox is ephemeral and isolated from the host
- The worst case is an agent tricks another agent via a crafted repo, but agents can already run arbitrary commands anyway

So yes, in this context the wildcard is effectively zero additional risk. The check protects shared multi-user machines, not single-user sandboxes.