local wezterm = require 'wezterm'

-- ============================================================================
-- LOCAL SETTINGS IMPORT (optional)
-- ============================================================================
local ok, local_settings = pcall(require, 'local_settings')
if not ok then
  local_settings = {}
  wezterm.log_info("No local_settings.lua found, using defaults")
end

-- ============================================================================
-- CONFIGURATION CONSTANTS
-- ============================================================================
local DEFAULTS = {
  font_size = 17.0,
  zen_font_size = 30,
  initial_cols = 220,
  initial_rows = 220,
  max_fps = 255,
  -- Why: deep navy distinguishes the host terminal at a glance from sandbox
  -- sessions, which set a black background via `sbxw --background`.
  background = '#0a0e27',
}

for k, v in pairs(DEFAULTS) do
  if local_settings[k] == nil then
    local_settings[k] = v
  end
end

-- Initialize configuration
local config = wezterm.config_builder and wezterm.config_builder() or {}

-- ============================================================================
-- STARTUP & SHELL
-- ============================================================================
-- Helper function to find executable using system PATH and common locations
local function find_executable(cmd)
  -- Try system PATH first
  local handle = io.popen('which ' .. cmd .. ' 2>/dev/null')
  if handle then
    local result = handle:read("*a"):gsub("%s+$", "")
    handle:close()
    if result ~= "" then return result end
  end

  -- Get user home directory dynamically
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""

  local paths = {}
  if home ~= "" then
    paths = {
      home .. "/.cargo/bin/",
      home .. "/.local/bin/",
      home .. "/bin/",
    }
  end

  -- Append system paths
  for _, p in ipairs({
    "/opt/homebrew/bin/",
    "/usr/local/bin/",
    "/usr/bin/",
    "/bin/",
  }) do
    table.insert(paths, p)
  end

  for _, path in ipairs(paths) do
    local full_path = path .. cmd
    local file = io.open(full_path, "r")
    if file then
      file:close()
      return full_path
    end
  end
end

-- Store nu_path globally for use in keybindings
local nu_path = find_executable('nu')

local function setup_shell()
  if not nu_path then
    wezterm.log_info("Nushell not found, using system default shell")
    return
  end

  local zellij_path = find_executable('zellij')
  config.default_prog = zellij_path
    and { nu_path, '-l', '--execute', 'zellij attach -c prophet' }
    or { nu_path }
end

-- Setup shell
pcall(setup_shell)
config.check_for_updates = false

-- ============================================================================
-- ENVIRONMENT
-- ============================================================================
local function setup_environment()
  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
  if home == "" then
    wezterm.log_warn("Unable to determine home directory")
    return {}
  end
  return {
    XDG_CONFIG_HOME = home .. "/.config",
    XDG_DATA_HOME = home .. "/.local/share",
  }
end

-- Setup environment
local ok, env_vars = pcall(setup_environment)
config.set_environment_variables = ok and env_vars or {}

-- ============================================================================
-- APPEARANCE
-- ============================================================================
-- Font configuration
config.font_size = local_settings.font_size

-- Color settings
if local_settings.background then
  config.colors = {
    background = local_settings.background,
  }
end

-- Window settings
config.initial_cols = local_settings.initial_cols
config.initial_rows = local_settings.initial_rows
config.hide_tab_bar_if_only_one_tab = true
-- Why: on the macOS host the native title bar showed through as transparent;
-- the user wants an ordinary solid bar. This flag paints it in the window
-- background colour, and TITLE|RESIZE keeps the default title and border.
config.window_decorations = "TITLE|RESIZE|MACOS_USE_BACKGROUND_COLOR_AS_TITLEBAR_COLOR"
config.window_padding = { left = 10, right = 10, top = 10, bottom = 10 }

-- Platform-specific settings
local is_macos = wezterm.target_triple:find("darwin") ~= nil
if is_macos then
  config.native_macos_fullscreen_mode = true
end

-- ============================================================================
-- PERFORMANCE
-- ============================================================================
config.front_end = "WebGpu"
config.webgpu_power_preference = "HighPerformance"
config.max_fps = local_settings.max_fps
config.animation_fps = local_settings.max_fps

-- ============================================================================
-- BEHAVIOR
-- ============================================================================
config.switch_to_last_active_tab_when_closing_tab = true
config.skip_close_confirmation_for_processes_named = {
  'bash', 'sh', 'zsh', 'fish', 'tmux', 'nu',
}
config.mouse_wheel_scrolls_tabs = false
config.enable_kitty_keyboard = true

-- When set to true (the default), wezterm will configure
-- the SSH_AUTH_SOCK environment variable for panes spawned in
-- the local domain.
config.mux_enable_ssh_agent = false

-- ============================================================================
-- KEY BINDINGS
-- ============================================================================
config.disable_default_key_bindings = true

-- Why: wezterm splits a run of wrapped rows into logical lines of about 1024
-- cells, and selection_text adds a newline for each logical line after the
-- selected one, though none of its cells is selected. So a word copied from such
-- a run ends in one newline per remaining piece. A quick select match never ends
-- in a newline by itself, so the trim removes only what wezterm added.
-- Cost: a capital label pastes directly (send_paste), and that text keeps them.
local quick_select_copy = wezterm.action_callback(function(window, pane)
  local text = window:get_selection_text_for_pane(pane)
  -- Why the extra parentheses: gsub also returns a count, and that count would
  -- land in the destination argument.
  window:copy_to_clipboard((text:gsub('\n+$', '')), 'ClipboardAndPrimarySelection')
end)

config.keys = {
  { key = ' ', mods = 'SHIFT|CTRL', action = wezterm.action.QuickSelectArgs { action = quick_select_copy } },
  { key = 'x', mods = 'SHIFT|CTRL', action = wezterm.action.ActivateCopyMode },
  { key = 'p', mods = 'SHIFT|CTRL', action = wezterm.action.ActivateCommandPalette },
  -- Prefills the search box from the current selection, empty otherwise
  { key = 'f', mods = 'SHIFT|CTRL', action = wezterm.action.Search 'CurrentSelectionOrEmptyString' },
  { key = 'v', mods = 'CMD',        action = wezterm.action.PasteFrom 'Clipboard' },
  { key = '=', mods = 'CMD',        action = wezterm.action.IncreaseFontSize },
  { key = '-', mods = 'CMD',        action = wezterm.action.DecreaseFontSize },
  { key = '0', mods = 'CMD',        action = wezterm.action.ResetFontSize },
  { key = 'q', mods = 'CMD',        action = wezterm.action.QuitApplication },

  -- Why: Claude Code doesn't recognize Shift+Enter for newlines without an explicit Kitty-style CSI u sequence
  { key = 'Enter', mods = 'SHIFT', action = wezterm.action.SendString '\x1b[13;2u' },

  -- I use those keybidings here to check that to fix Wezterms cmd+shift passing for zellij.
  -- cmd+shift+a
  { key = 'a', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[97;10u' },
  -- cmd+shift+b
  { key = 'b', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[98;10u' },
  -- cmd+shift+c
  { key = 'c', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[99;10u' },
  -- cmd+shift+d
  { key = 'd', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[100;10u' },
  -- cmd+shift+e
  { key = 'e', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[101;10u' },
  -- cmd+shift+f
  { key = 'f', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[102;10u' },
  -- cmd+shift+g
  { key = 'g', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[103;10u' },
  -- cmd+shift+h
  { key = 'h', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[104;10u' },
  -- cmd+shift+i
  { key = 'i', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[105;10u' },
  -- cmd+shift+j
  { key = 'j', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[106;10u' },
  -- cmd+shift+k
  { key = 'k', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[107;10u' },
  -- cmd+shift+l
  { key = 'l', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[108;10u' },
  -- cmd+shift+m
  { key = 'm', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[109;10u' },
  -- cmd+shift+n (new wezterm instance with its own Dock icon, running pure nushell)
  -- Why: SpawnCommandInNewWindow reuses the same OS process, so the new window
  -- ends up under the existing Dock icon. `open -n` asks LaunchServices for a
  -- fresh app instance (own Dock icon + foreground activation, side-stepping
  -- wezterm issue #6202 where `wezterm start --always-new-process` opens in the
  -- background on macOS).
  -- `--always-new-process` is required: without it, the freshly-launched
  -- wezterm-gui detects the existing mux via its unix socket, delegates the
  -- spawn to the running instance, and exits — collapsing the new window back
  -- under the old Dock icon.
  { key = 'n', mods = 'CMD|SHIFT', action = wezterm.action_callback(function()
    wezterm.background_child_process({ 'open', '-n', '-a', 'WezTerm', '--args', 'start', '--always-new-process', '--', nu_path or 'nu' })
  end)},
  { key = 'n', mods = 'ALT|CMD',   action = wezterm.action_callback(function()
    wezterm.background_child_process({ 'open', '-n', '-a', 'WezTerm', '--args', 'start', '--always-new-process', '--', 'zsh' })
  end)},
  -- cmd+shift+o
  { key = 'o', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[111;10u' },
  -- cmd+shift+p
  { key = 'p', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[112;10u' },
  -- cmd+shift+q
  { key = 'q', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[113;10u' },
  -- cmd+shift+r
  { key = 'r', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[114;10u' },
  -- cmd+shift+s
  { key = 's', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[115;10u' },
  -- cmd+shift+t
  { key = 't', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[116;10u' },
  -- cmd+shift+u
  { key = 'u', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[117;10u' },
  -- cmd+shift+v
  { key = 'v', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[118;10u' },
  -- cmd+shift+w
  { key = 'w', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[119;10u' },
  -- cmd+shift+x
  { key = 'x', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[120;10u' },
  -- cmd+shift+y
  { key = 'y', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[121;10u' },
  -- cmd+shift+z
  { key = 'z', mods = 'CMD|SHIFT',  action = wezterm.action.SendString '\x1b[122;10u' },
}

-- ============================================================================
-- COPY MODE / SEARCH KEY TABLES
-- ============================================================================
-- Defining search_mode replaces the whole default table, so the defaults are
-- reproduced here. Why: default Enter = PriorMatch, which never leaves the
-- search box. Rebind Enter to AcceptPattern so it closes search and returns to
-- copy mode with the cursor on the match -- from there CTRL-v starts a block
-- selection at that corner. Enter-as-PriorMatch is redundant with CTRL-p/Up.
config.key_tables = {
  search_mode = {
    { key = 'Enter', mods = 'NONE', action = wezterm.action.CopyMode 'AcceptPattern' },
    { key = 'Escape', mods = 'NONE', action = wezterm.action.CopyMode 'Close' },
    { key = 'n', mods = 'CTRL', action = wezterm.action.CopyMode 'NextMatch' },
    { key = 'p', mods = 'CTRL', action = wezterm.action.CopyMode 'PriorMatch' },
    { key = 'r', mods = 'CTRL', action = wezterm.action.CopyMode 'CycleMatchType' },
    { key = 'u', mods = 'CTRL', action = wezterm.action.CopyMode 'ClearPattern' },
    { key = 'PageUp', mods = 'NONE', action = wezterm.action.CopyMode 'PriorMatchPage' },
    { key = 'PageDown', mods = 'NONE', action = wezterm.action.CopyMode 'NextMatchPage' },
    { key = 'UpArrow', mods = 'NONE', action = wezterm.action.CopyMode 'PriorMatch' },
    { key = 'DownArrow', mods = 'NONE', action = wezterm.action.CopyMode 'NextMatch' },
  },
}

-- ============================================================================
-- QUICK SELECT PATTERNS
-- ============================================================================
local hash_patterns = {
  -- git commit ranges: hash..hash (two-dot) and hash...hash (three-dot),
  -- matched as one block. Must precede the bare-hash/jj rules below so the
  -- whole range wins over selecting a single side.
  "\\b[0-9a-f]{7,64}\\.{2,3}[0-9a-f]{7,64}\\b",

  -- jj change IDs (use k-z alphabet to avoid forming words)
  "\\b[k-z]{8,12}\\b",

  -- Change-Id trailers from cozy's commit-msg hook: 32 letters of the same
  -- k-z alphabet. The rule above cannot reach them: no \b falls after letter 12.
  -- Their 8-letter short form is already covered by the rule above.
  "\\b[k-z]{32}\\b",

  -- IPFS CIDv0 (cybergraph particles): Qm and 44 base58 characters, and any
  -- prefix of one from 10 characters up. The short form is 10 characters,
  -- planned for quote and block tags such as <!-- Qm3adfKK7w --> ... <!-- /Qm3adfKK7w -->.
  -- Why every length from 10 to 46: nushell often truncates a long cell in a
  -- table (Qm3adfKK7wXYZ…), and the cut can fall at any length.
  -- Why the /? and the capture group: in the closing tag the path rule starts
  -- at the `/` and would copy `/Qm3adfKK7w`. This rule starts there too, wins
  -- by its earlier place, and wezterm copies the capture group, the CID alone.
  -- Inside a real path (seals/Qm3adfKK7w) the path rule still wins.
  "/?\\b(Qm[1-9A-HJ-NP-Za-km-z]{8,44})\\b",
}

local quick_select_patterns = {
  -- The text typed after a ❯ prompt (Claude Code's TUI), trimmed at both ends.
  -- Why \x{a0}: Claude Code puts a no-break space after the ❯, not a plain one.
  -- Why it sits before the path rule: a prompt like `/40-land-branch` starts
  -- where the path match starts, and on an equal start the earlier rule wins.
  "(?<=❯[ \\x{a0}])\\S(?:.*\\S)?",

  -- file:line:col (rg --vimgrep, nushell table rows, stack traces,
  -- nushell error headers like ╭─[/path/to/file.nu:1946:63])
  "[^\\s│╭─\\[]+:\\d+:\\d+",

  -- Table patterns
  -- $env.config.table.mode = "default"
  -- $env.config.table.header_on_separator = true
  -- $env.config.footer_mode = "Always"
  "(?<=─|╭|┬)([a-zA-Z0-9 _%.-]+?)(?=─|╮|┬)", -- Headers
  -- Column values. Why the first character excludes the space: an empty cell,
  -- or a blank line inside a lazygit/nushell box, is all spaces between two │
  -- and would otherwise be offered as a match.
  "(?<=│ )([a-zA-Z0-9_.-][a-zA-Z0-9 _.-]*?)(?= │)",

  -- git diff paths without the a/ or b/ prefix, so the selection pastes as a
  -- real path. The built-ins already strip it on the `--- a/x` and `+++ b/x`
  -- lines; this covers `diff --git a/x b/x` and any other bare a/x.
  -- Why a capture group and not a lookbehind: the path rule below starts at the
  -- `a`, and the leftmost start wins, so a match that starts after `a/` loses.
  -- This rule starts at the `a` too and wins by its earlier place; wezterm then
  -- copies the highest capture group that matched, i.e. the path alone.
  -- Cost: a real directory named a or b loses its first segment.
  "(?<![.\\w\\-@~])[ab]/([^/\\s│]+(?:/+[^/\\s│]+)*)(?<![.,;:!?)\\]>\"'`])",

  -- Markdown inline code: copies the text between the backticks. One line only;
  -- 2+ characters so a ``` fence line matches nothing.
  -- Cost: the span starts left of its content, so a hash or range inside it
  -- gets no label of its own -- only the whole span.
  "`([^`\\n]{2,200}?)`",

  -- Anchor marker: copies the text between ⟦ and ⟧. Agents wrap in it a place
  -- in a document that their chat reply names (⟦NR-10⟧, a heading, a phrase).
  -- Why not the backtick rule above: Claude Code renders inline code without
  -- the backticks, so in its TUI that rule finds nothing to match.
  -- Why ⟦ ⟧: one cell wide, and rare in terminal output, so the rule gives
  -- few false labels. One line only, like the backtick rule.
  "⟦([^⟧\\n]{1,120})⟧",

  -- Markdown heading of level 2 to 6, with its #s: a canvas in helix names a
  -- section this way, and a fragment link takes the line as it is.
  -- Why not level 1: a single # starts a comment in nushell, bash and toml.
  -- Why │ is excluded: it is the border of a zellij pane beside helix.
  -- Cost: the whole line is one label, so a path or a code span inside a
  -- heading gets no label of its own.
  "(?<!#)#{2,6} [^\\s│](?:[^\\n│]*[^\\s│])?",

  -- Bare file names: README.md, toolkit.nu, Cargo.lock.
  -- Why a fixed list of extensions: any extension would also match field
  -- access (config.keys, wezterm.action) and bare domains (github.com).
  -- The lookbehind keeps it off the tail of a path, a $var.field or a name.
  "(?<![\\w.\\-/@~$])[\\w-]+(?:\\.[\\w-]+)*\\.(?:md|nu|nuon|lua|toml|json|yaml|yml|kdl|rs|py|sh|txt|csv|lock|pub|patch|ots|sig|jsonl|hjson|scm|png)\\b",

  -- File paths: absolute, relative and ~-prefixed; strips trailing punctuation
  -- (. , ; : " ' `) via lookbehind.
  -- Why the leading (?:[.\w\-@~]+)?: wezterm concatenates our patterns and its
  -- 14 built-in ones into ONE alternation, and the leftmost match wins -- only
  -- on an equal start position does our earlier place in the list win. The
  -- built-in path pattern (?:[.\w\-@~]+)?(?:/+[.\w\-@]+)+ starts at the `~` or
  -- at the first directory name, i.e. left of a bare `/`, so for `~/a/b.nu.`
  -- and `a/b.nu.` it used to beat us and drag the sentence dot along.
  -- Mirroring its opening class makes both alternatives start together.
  -- Not disable_default_quick_select_patterns because: that would also drop the
  -- built-in URL, sha, uuid, ip and hex-colour patterns.
  "(?:[.\\w\\-@~]+)?(?:/+[^/\\s│]+)+(?<![.,;:!?)\\]>\"'`])",
}

for i, p in ipairs(hash_patterns) do
  table.insert(quick_select_patterns, i, p)
end

config.quick_select_patterns = quick_select_patterns
config.quick_select_remove_styling = true

-- Option+Shift+Space: quick select over hashes only. `patterns` replaces the
-- built-in and configured sets, so the bare git sha (a built-in) is listed here.
local hash_only_patterns = { "\\b[0-9a-f]{7,64}\\b" }
for i, p in ipairs(hash_patterns) do
  table.insert(hash_only_patterns, i, p)
end
table.insert(config.keys, {
  key = ' ', mods = 'ALT|SHIFT',
  action = wezterm.action.QuickSelectArgs { patterns = hash_only_patterns, action = quick_select_copy },
})

-- ============================================================================
-- DYNAMIC CONFIGURATION (ZEN MODE)
-- ============================================================================
-- Demo mode for screencasts. Activate in wezterm (outside of zellij) via:
-- 'on' | encode base64 | $"\e]1337;SetUserVar=ZEN_MODE=($in)\e"
-- 'off' | encode base64 | $"\e]1337;SetUserVar=ZEN_MODE=($in)\e"
wezterm.on('user-var-changed', function(window, pane, name, value)
  local overrides = window:get_config_overrides() or {}
  if name == "ZEN_MODE" then
    overrides.font_size = value == "on" and local_settings.zen_font_size or nil
  end
  window:set_config_overrides(overrides)
end)

return config
