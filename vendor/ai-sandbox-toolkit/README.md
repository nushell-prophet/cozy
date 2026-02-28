# ai-sandbox-toolkit

Maintain running [ai-sandbox](https://github.com/nushell-prophet/ai-sandbox) containers without recreating them.

Rebuilding a sandbox means re-authenticating Claude and losing session state. This toolkit updates modules, syncs repos, and persists shell history inside a live container — so you don't have to rebuild.

Symlinked at `~/toolkit.nu` inside the container and auto-activated via Nushell hooks.

## Commands

### `toolkit sync-repos`

Pulls the latest changes for a predefined set of Nushell module repos under `~/git/`. Handles branch switching, dirty working tree detection, and converting vendored directories to proper git repos.

```nushell
use toolkit.nu; toolkit sync-repos       # skip repos with local changes
use toolkit.nu; toolkit sync-repos -f    # force: discard local changes and switch branches
```

### `toolkit mount init`

Idempotent initialization of multi-repo workspaces. Discovers git subdirectories, registers them as git submodules, generates `.gitmodules` and `.gitignore`. Safe to re-run after adding new directories.

```nushell
use toolkit.nu; toolkit mount init
```

Sets `git config --global safe.directory '*'` — intentional for sandboxed environments where file ownership differs from the container user.

### `toolkit history export`

Exports Nushell's SQLite history database to a timestamped `.nuon` file. Reads the database directly, so it works from any context (interactive shell, scripts, `nu -c`).

```nushell
use toolkit.nu; toolkit history export                    # default: ~/mounted/sandbox-state/history-<timestamp>.nuon
use toolkit.nu; toolkit history export ./my-history.nuon  # custom path
```

### `toolkit history import`

Imports history records from a `.nuon` file back into the SQLite database. Without a path, reads from the `history-latest.nuon` symlink created by export.

```nushell
use toolkit.nu; toolkit history import                    # from latest export
use toolkit.nu; toolkit history import ./my-history.nuon  # from specific file
```

Note: import does not deduplicate — running it twice inserts all records again.

## License

[MIT](LICENSE)
