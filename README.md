# Nushell-prophet's ai-sandbox (docker based convenient terminal environment)

I spent a huge amount of time tuneing my terminal setup to make it convenient and powerful. I believe terminal newbies can use it as an inspiration or as a tool that works out of the box.

## Preambule

That's work-in-progress education project with video demos on the way.

## Technologies

### Docker sandbox

My ai-sandbox is based on `docker sandbox`, so it is:
- MacOS and Windows compatible
- isolated
- convenient
- with builtin ai agents (I personally tested it on `claude code`)

### Nushell

A modern shell for AI era: Nushell 0.110.0 with sensible settings, that I've choosen over 3 years of Nushell experience.

Nushell has built-in MCP functionality that allows ai agents to use all of it's reach functionality. The functionality is activated for `claude code` out of the box.

### Zellij

Zellij is extremely convenient and powerful terminal multiplexer.

### Helix-editor

Helix is my terminal text editor. It plays nicely with Nushell, and quite newbie-friendly. It is used in my environment, so hitting `cmd+shift+e` will open the current pane's scroollback for editing in helix. So it becomes a breaze to copy the contents.

### Lazygit

Lazygit - is a god-sent interface for git. It simplifies a lot my everyday git operations, and I would like to demo it. Lazygit is integrated into zellij, so wherever user will hit `cmd+alt+l`, lazygit will jump in a floating window to stage files and do other git staff.

### Broot

Broot is a file manager with a tree like structure and fuzzy-search. It can be called by using the command `cmd+shift+b`. And the can be quit with copied relative to git repo path with `:pbq` or a full path `:pbfq`. The path will be copied into clipboard and can be pasted anywhere.

### FZF

I use fzf for navigating Nushell history.

In Nushell there are keybindings:
- `ctrl+f` to spawn fzf with Nushell history, to insert after selecting the command into commandline.
- `alt+f` to spawn fzf with `^currently-entered-commandline`, to replace the current commandline with the selection.

In fzf `tab` and `shift-tab` select several commands. When several commands selected, they, after hitting enter they will be placed delimeted by `;\n`

### Wezterm

I use Wezterm for connecting to this environment. The settings can be found here.

The killer feature of Wezterm is a `ctrl+shift+space` shortcut, to highlight paths and nushell's structured output elements, for quick copying.

I spawn wezterm with this command:

`wezterm start -- docker sandbox exec -it -w /Users/user/git/container nushell-ai-container nu -l --commands 'print -n $"\e]1337;SetUserVar=SANDBOX_MODE=b24=\e\\"; zellij attach -c sandbox'`

## Nushell modules

### numd

`numd` is a module for literate programming, it parses .md files with code nushell code blocks, executes them, captures output and uptates the .md files.

### dotnu

`dotnu embeds` is another tool for literate programming. It executes parses nushell scripts for '| print $in' lines, executes the whole script, captures output and pastes the results of execution back to the `.nu` file with results commented `# =>` just after the line that ouputed them into console. 

### claude-nu

That's my friesh claude's convenience nushell toolbox for parsing `claude` sessions and outputting their results into nushell structured format. 
