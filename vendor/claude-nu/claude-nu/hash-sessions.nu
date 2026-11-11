# claude-nu hash-sessions - the sessions a hash appeared in.
use timeline.nu
use sessions.nu [messages]

# The kind of a hash and the regex that finds it in a transcript, from its
# shape alone: {kind, pattern}. Kinds: sha-prefix, sha1, sha256, change-id, cid.
# Why the shape is enough: the alphabets do not overlap — git shas are hex, a
# Change-Id is the letters k-z, a CID starts with `Qm` or `b` and runs longer
# than any sha.
# Why hex and Change-Id match as a prefix (`\b` in front only): a short sha and
# the 8-letter Change-Id head are how commits are named in prose, and the
# leading `\b` keeps a short sha from matching inside a longer hex run.
export def hash-shape [hash: string]: nothing -> record {
    let h = $hash | str trim

    # Why the CID check comes before the lowercasing: base58 (`Qm…`) is
    # case-sensitive.
    if $h =~ '^Qm[1-9A-HJ-NP-Za-km-z]{44}$' or $h =~ '^b[a-z2-7]{58,}$' {
        return {kind: cid pattern: $'\b($h)\b'}
    }
    let h = $h | str lowercase

    if $h =~ '^[0-9a-f]{4,64}$' {
        let kind = match ($h | str length) {
            40 => "sha1"
            64 => "sha256"
            _ => "sha-prefix"
        }

        return {kind: $kind pattern: $'\b($h)'}
    }
    if $h !~ '^[k-z]{8,32}$' {
        error make {
            msg: $"Not a hash shape: ($hash)"
            help: "expected a git sha or its prefix (4-64 hex), a Change-Id or its prefix (8-32 letters k-z), or an IPFS CID (Qm… or b…)"
        }
    }
    {kind: change-id pattern: $'\b($h)'}
}

# The sessions a hash appeared in, one row per session: {session, user, shell,
# assistant, tool_use, tool_result, first, last, project, project_name}. The five
# counts say where the hash stood — the user typed it, a `!` command of the user
# named or printed it, the agent wrote or thought it, it went into a tool call,
# or it came back in a result — and `first`/`last`
# are the timestamps of its first and last appearance. Sorted by `user`, then by
# `last`, newest first.
# The kind of hash comes from its shape (see `hash-shape`). Scoping and the time
# window work as in `timeline`, which does the search with `messages`: no input reads the
# current project, piped session or project rows narrow it.
# Why the counts are split: every `git log` repeats a sha, so a bare hit count
# is mostly tool output; the one where the user named the hash is the session
# that was about it.
# Why `user` and `shell` come from `messages`: a timeline block of a user record
# reads the same whether it was typed or printed by `!git log`; only the record
# tells them apart, and `messages` reads that as `kind`.
@category claude-nu
@example "the sessions where I named a commit, across every project" { claude-nu projects | claude-nu hash-sessions 5b51153c4 | where user > 0 }
@example "the dialogue of the session that was most about a Change-Id" { claude-nu hash-sessions mymlzxnw | first | claude-nu messages --include-responses }
export def main [
    hash: string # A git sha or prefix, a Change-Id or prefix, or an IPFS CID
    --since: any # Only appearances at or after this point — a duration means ago (`1wk`), or a datetime/date string
    --until: any # Only appearances at or before this point
]: [nothing -> table record -> table table -> table list<string> -> table] {
    let input = $in
    let shape = hash-shape $hash
    let said = $input
        | messages $shape.pattern --since $since --until $until
        | where kind in [typed bash-input bash-output]
        | group-by session
    let blocks = $input
        | timeline $shape.pattern --since $since --until $until
        | group-by session

    # Why the sessions of `said` too: a prompt typed while the agent worked is
    # an attachment record, which `messages` reads and `timeline` does not, so
    # a hash named only there has no block.
    $blocks
    | columns
    | append ($said | columns)
    | uniq
    | each {|session|
        let rows = $blocks | get --optional $session | default []
        let said_rows = $said | get --optional $session | default []
        let count = {|role kinds| $rows | where role == $role and kind in $kinds | length }
        let all = $rows | select timestamp project project_name | append ($said_rows | select timestamp project project_name)

        {
            session: $session
            user: ($said_rows | where kind == typed | length)
            shell: ($said_rows | where kind != typed | length)
            assistant: (do $count assistant [text thinking])
            tool_use: (do $count assistant [tool_use])
            tool_result: (do $count user [tool_result])
            first: ($all.timestamp | math min)
            last: ($all.timestamp | math max)
            project: $all.0.project
            project_name: $all.0.project_name
        }
    }
    | sort-by --reverse user last
}
