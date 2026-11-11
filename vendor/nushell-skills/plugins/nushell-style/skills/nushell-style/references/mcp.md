# Nushell MCP Server

Nushell has a built-in MCP (Model Context Protocol) server, started with `nu --mcp`.
Included by default since v0.110.
It exposes Nushell's shell capabilities as tools.

## Transport

- stdio — `nu --mcp`, the default, since 0.110
- HTTP — `nu --mcp --mcp-transport http`, port 8080, since 0.111

Set a custom HTTP port with `--mcp-port`:

```bash
nu --mcp --mcp-transport http --mcp-port 3000
```

Since 0.116 the HTTP server binds `127.0.0.1` by default, so other hosts on the network cannot reach it; before 0.116 it bound `0.0.0.0` (source-checked).
0.116 lists `--mcp-host` in `nu --help`, but rejects it with `Unknown flag '--mcp-host'` (source-checked for 0.116.1).
Since 0.117 `--mcp-host` works.

A new bind address alone does not open the server to other machines.
The server also checks the `Host` header of each request.
By default it accepts only `localhost`, `127.0.0.1` and `::1`, with any port, and answers any other host with `403 Forbidden: Host header is not allowed`.
`--mcp-allowed-hosts` (v0.117) names the hosts that clients connect to.
The list replaces the default, so add `localhost` when local clients still connect:

```bash
nu --mcp --mcp-transport http --mcp-host 0.0.0.0 --mcp-allowed-hosts mybox.lan,localhost
```

`--mcp-allowed-origins` (v0.117) does the same for the `Origin` header that browsers send: a request with an `Origin` outside the list gets a 403.
Without the flag the server does not check `Origin`, and a request with no `Origin` header always passes.
Both flags take one comma-separated value, or several words up to the next flag.

HTTP transport supports request cancellation, 30-minute idle session cleanup, and structured error codes with line/column details.

## Adding to Claude Code

```bash
# stdio (default)
claude mcp add --transport stdio nushell -- nu --mcp

# HTTP
claude mcp add --transport http nushell http://localhost:8080
```

## Tools

- `evaluate` — execute Nushell or shell commands, returns structured output
- `list_commands` — list/search available Nushell native commands, one line each: `<signature> - <description>`
- `command_help` — usage, description, flags and parameters of one command; it shows no input/output types and no examples, so `evaluate` `help <name>` for those

`list_commands` and `command_help` name a command the way you call it (v0.117).
After `alias st = str trim`, `list_commands` lists `st` on its own line, and `command_help st` works.
After `use spam`, a module command is listed as `spam foo bar`.
An alias shows only the parameters it leaves to you: `alias home = cd ~` is `home {flags}`.

## Key Behaviors

**Persistent state** — variables and environment changes persist across `evaluate` calls (REPL-style):

```nu
# Call 1
let x = 42
# Call 2
$x  # → 42
```

**Structured output** — native Nushell commands return NUON, not text.
No need to pipe to `to json`.
Since 0.114 the evaluation result is emitted as NUON directly (previously it was wrapped as an escaped string inside the response — 0.114 also uses raw strings `r#'...'#` to cut escaping), and success/error responses are additionally exposed as MCP `structuredContent` JSON for clients that support structured tool output.

**History** — `$history` is a `list<any>` with the output of every earlier `evaluate` call.
Each response carries `history_index`; read that result back by its index:

```nu
# response: {cwd: ..., history_index: 7, timestamp: ..., output: ...}
$history.7                       # the full output of that call
$history.7 | where size > 1mb    # slice a saved result instead of running the command again
```

- Use the index, not `$history | last`: `last` is the call just before the current one, so it changes with every call.
- Indices are stable (v0.117).
  `$history` keeps the newest `NU_MCP_HISTORY_LIMIT` results (default 100), an older index reads as `null`, and `$history | length` counts every result of the session.
  In 0.116, eviction shifted every entry down by one, so an old index pointed at a later result.
  Once the buffer was full, each new result also got the same index (source-checked).
- To keep a result past the limit, save it with `let`.
- A result that was `null` is stored as `[]`, so `null` at an index means the entry was evicted.
- A call that fails, or that is promoted to a background job, stores nothing and takes no index.
- Lowering `$env.NU_MCP_HISTORY_LIMIT` trims `$history` to the new limit (v0.117).

**One evaluation at a time** (v0.117) — `evaluate` calls run one at a time, also when the client sends them together.
Calls sent together can run in either order, so send a call that depends on another only after its response.
A slow call holds the next one until it ends or is promoted to a background job; `list_commands` and `command_help` do not wait.
In 0.116 two calls sent together could get the same `history_index`, and one of them lost its `$history` entry and its `$env` changes.
There, each call worked on its own copy of the state, and the call that ended last replaced the state (source-checked).

**`$ans` does not work here** — the last-result variable is filled only by the interactive REPL loop, so in an MCP session it parses but stays `null`, even after setting `$env.config.max_last_result_size` (which defaults to `0b` anyway).
Use `$history` for the previous result.

**The session is not interactive** (v0.117) — `$nu.is-interactive` is `false` in `nu --mcp`; in 0.116 it was `true` (source-checked).
The server still loads `env.nu`, `config.nu` and the autoload files, but config code behind `if $nu.is-interactive` no longer runs.

**Truncation** — on by default: when the output is larger than 10kib, the response carries `note: "output truncated, full result in $history.<n>"` instead of `output`.
Adjust the limit with `$env.NU_MCP_OUTPUT_LIMIT`; `0b` turns truncation off:

```nu
$env.NU_MCP_OUTPUT_LIMIT = 100kb
```

**Long evaluations become background jobs** (since 0.112) — an `evaluate` call that runs past the promote timeout (default 120sec; 10sec when introduced) or is cancelled by the client is promoted to a background job instead of being discarded.
The tool call then errors with a job id; collect the result with `job recv`.
Promoted jobs appear in `job list` as `mcp: <command>` and can be stopped with `job kill`.
Before a known long-running command, widen the window so it stays synchronous:

```nu
$env.NU_MCP_PROMOTE_AFTER = 10min
```

**The `NU_MCP_*` settings need typed values** — an int for `NU_MCP_HISTORY_LIMIT`, a filesize for `NU_MCP_OUTPUT_LIMIT`, a duration for `NU_MCP_PROMOTE_AFTER`.
Set them with `$env` inside the session or in `config.nu`.
A value from the process environment, such as the `env` block of the client's MCP config, arrives as a string, and the server ignores it with no warning.
