# sandbox-toolkit

Runtime toolkit for [cozy](https://github.com/nushell-prophet/cozy) sandboxes. Loaded as the `cozy` overlay inside the container.

Maintains running sandboxes without rebuilding — updates modules, syncs repos, and persists shell history.

## Commands

### `cozy sync-repos`

Pulls the latest changes for all Nushell module repos under `~/repos/` (including the cozy repo itself). Handles branch switching, dirty working tree detection, and converting vendored directories to proper git repos.

```nushell
cozy sync-repos       # skip repos with local changes
cozy sync-repos -f    # force: discard local changes and switch branches
```

### `cozy mount init`

Idempotent initialization of multi-repo workspaces. Discovers git subdirectories, registers them as git submodules, generates `.gitmodules` and `.gitignore`. Safe to re-run after adding new directories.

```nushell
cozy mount init
```

### `cozy dev-link`

Replaces vendored `~/repos/` copies with symlinks to the mounted workspace. Enables edit-and-test without rebuild.

```nushell
cozy dev-link
```

### `cozy sandbox-state history export`

Exports Nushell's SQLite history database to a timestamped `.nuon` file.

```nushell
cozy sandbox-state history export                    # default: ~/workspace/mounted/sandbox-state/history-<timestamp>.nuon
cozy sandbox-state history export ./my-history.nuon  # custom path
```

### `cozy sandbox-state history import`

Imports history records from a `.nuon` file back into the SQLite database. Without a path, picks the most recent `history-*.nuon` file by name. Deduplicates and skips entries already present.

```nushell
cozy sandbox-state history import                    # from latest export
cozy sandbox-state history import ./my-history.nuon  # from specific file
```

## License

[MIT](LICENSE)
