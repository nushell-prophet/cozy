# The model names `claude --model` takes, as a completion menu.
# Why a file of its own in the module and not in completions/claude.nu: `gi new`
# and `gi open` complete their --model from it too, and the module does not
# import from the completions.

const models = [
    {value: "fable" description: "Claude Fable (latest)"}
    {value: "opus" description: "Claude Opus (latest)"}
    {value: "sonnet" description: "Claude Sonnet (latest)"}
    {value: "haiku" description: "Claude Haiku (fastest)"}
    {value: "claude-fable-5" description: "Claude Fable 5 (specific version)"}
    {value: "claude-opus-5" description: "Claude Opus 5 (specific version)"}
    {value: "claude-opus-5[1m]" description: "Claude Opus 5, 1M context"}
    {value: "claude-sonnet-5" description: "Claude Sonnet 5 (specific version)"}
]

export def "nu-complete claude models" []: nothing -> record {
    {options: {sort: false} completions: $models}
}
