use /home/agent/git/nu-cmd-stack/cmd-stack
$env.config.keybindings ++= [
    {
        modifier: control_alt
        keycode: char_k
        mode: [emacs]
        event: {send: executehostcommand cmd: 'cmd-stack next'}
    }
    {
        modifier: control_alt
        keycode: char_j
        mode: [emacs]
        event: {send: executehostcommand cmd: 'cmd-stack prev'}
    }
]
