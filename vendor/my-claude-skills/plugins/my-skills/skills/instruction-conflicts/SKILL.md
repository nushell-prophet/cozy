---
name: instruction-conflicts
description: >
  Audit everything loaded into the context — global and project CLAUDE.md,
  .claude/rules/, output styles, skills, agents, settings and hooks — for rules
  that pull in opposite directions, then resolve them. Use this skill when the
  user asks "do my instructions contradict each other", "check my context for
  conflicts", "audit my CLAUDE.md files", "правила противоречат друг другу",
  "проверь инструкции на противоречия", or before adding a new rule to an
  instruction file. Also use when an agent appears to have ignored a rule —
  it usually obeyed a different one.
version: 0.1.0
---

Instruction files drift by design.
They are written months apart, at different levels of attention, some of them by agents editing their own rules.
Nothing in the system notices when two of them start disagreeing, and the disagreement never shows up as an error.
It shows up as an agent that follows a rule on Monday and breaks it on Tuesday, and as a user who cannot tell whether the rule was unclear or the agent was careless.

This skill finds those pairs before they cost a session, and resolves them one at a time.

## What the harness actually does with your rules

Two facts decide everything below, both from `claude-code-docs/memory.md`:

- "All discovered files are concatenated into context rather than overriding each other."
- "if two rules contradict each other, Claude may pick one arbitrarily."

So the layering — managed policy, user, project, local, and each directory from the filesystem root down to the working directory — is **reading order, not authority**.
A project rule appears after a user rule; it does not defeat it.
Nothing resolves a contradiction for you.
The pick is arbitrary, which means it can differ between two sessions on the same repo, which is exactly why this class of bug is never reproducible and always blamed on the model.

A third fact decides how to fix them: CLAUDE.md is context, not enforced configuration.
The docs are explicit — to make something impossible rather than discouraged, you need a hook or a permission rule.
A prose rule that says "never" is a strong hint, and it competes with every other strong hint in context.

## The bar: write the prompt that splits them

A pair of rules is a conflict only when you can write **the one user prompt that triggers both and sends them in opposite directions**.
Write it out, verbatim, in the finding.
If you cannot write that prompt, it is not a conflict — drop it and say nothing.

This bar is the whole difference between a useful audit and a useless one.
An audit that reports forty tensions gets skimmed once and never run again, and the three real conflicts inside it die with the other thirty-seven.
Report three.

## Four classes

**1. Direct contradiction.**
Both rules apply to the same prompt and cannot both be obeyed.

**2. Duplicate that drifted.**
The same rule written in two places, one of them updated later.
This is the worst class and the hardest to see, because neither copy looks wrong on its own and both look authoritative.
It is also the one that regenerates: fixing both copies leaves two copies, which drift again.

**3. Precedence collision.**
Both rules are stated as absolutes, they come from different sources, and neither carries an exception clause naming the other.
A real one, verified in this repo: a session-level harness instruction says "Do not call the AgentTool unless the user requested it", while `decision-provenance/SKILL.md:101` and `code-archaeology/SKILL.md:109` both instruct the agent to run the work in subagents.
Splitting prompt: `/decision-provenance why is this flag here`.
Neither text mentions the other, so the agent picks — and which way it picks is invisible to the user, who sees either a slow single-threaded run or a violated instruction, and has no reason to connect either to a skill file.

**4. Stale pointer.**
No contradiction in the text; the rule names a path, command, flag, directory or convention that no longer exists.
Mechanically checkable, so check it rather than reading for it.

### Not conflicts

Do not report these.
Each of them looks like a contradiction and is not, and reporting them is how the audit loses the user's trust:

- **A rule with its own exception.**
  The global rule "never merge on your own initiative" sits three lines above "an explicit request is the exception", and `land-branch` is that request.
  Read the whole section before pairing anything from it.
- **Scope-separated rules.**
  "Never let `todo/` reach a published repo" and "version-control everything, notes included" contradict each other only if you drop the words "published" and "internal monorepo".
- **Different granularity.**
  A general rule and a specific procedure for one case are a hierarchy, not a fight.
- **A rule nobody follows.**
  That is adherence, a different problem with a different fix.
  Note it in one line if it is in front of you; do not open a finding.

## Method

### 1. Enumerate what actually loaded

`/context` is the ground truth and only the user can run it — it is the one place that shows the system prompt, the active output style, and which skill descriptions are in context.
Ask for it when the answer depends on the harness side.
Everything on disk you can enumerate yourself:

```nushell
let dirs = (1..($env.PWD | path split | length) | each {|n| $env.PWD | path split | first $n | path join })

let project = $dirs | each {|d| [
    ($d | path join 'CLAUDE.md')
    ($d | path join 'CLAUDE.local.md')
    ($d | path join '.claude' 'CLAUDE.md')
    ($d | path join '.claude' 'settings.json')
    ($d | path join '.claude' 'settings.local.json')
] ++ (glob ($d | path join '.claude' 'rules' '**' '*.md')) } | flatten

let memory = glob $"($env.HOME)/.claude/projects/($env.PWD | str replace --all --regex '[/.]' '-')/memory/*.md"

let user = [
    /etc/claude-code/CLAUDE.md
    ~/.claude/CLAUDE.md
    ~/.claude/settings.json
] ++ (glob ~/.claude/rules/**/*.md) ++ (glob ~/.claude/output-styles/*.md) ++ (glob ~/.claude/skills/*/SKILL.md) ++ (glob ~/.claude/agents/*.md) ++ (glob ~/.claude/commands/**/*.md) ++ (glob ~/.claude/plugins/cache/*/*/*/skills/*/SKILL.md)

$user ++ $memory ++ $project
| each {|p| $p | path expand }
| uniq
| where {|p| $p | path exists }
| each {|p| {source: $p, lines: (open --raw $p | lines | length)} }
| to nuon --pretty
```

Three layers that snippet cannot reach, so name them explicitly instead of pretending the list is complete: the harness system prompt (quotable from your own context, absent from disk), the output style in effect, and MCP server instructions.
Two more load conditionally and are easy to forget: a `CLAUDE.md` in a subdirectory loads only when a file in that directory is read, and a path-scoped rule in `.claude/rules/` loads only on a matching file.
A conflict involving either one fires on some prompts and not others — say so in the finding, because it explains why the user saw the rule obeyed yesterday.

### 1b. Read the harness prompt as one of the sources

The system prompt is a source like any other, and it is the one the user cannot see, cannot edit, and did not write.
It changes with the surface, the model, and the permission mode, and every change of it is a change of the rule set nobody reviewed.
So pair it against the global file deliberately rather than waiting for a conflict to surface — that is where the highest-frequency findings live, because a harness rule applies to every prompt.
It also contradicts *itself* often enough to be worth a pass on its own: an appended mode preamble does not know what the base prompt already said.
Resolution never lands on the harness side.
It lands on the file you can edit, or on a setting, and the finding says which.

### 2. Mechanical pass first

Cheap, checkable, and it clears the ground before the reading starts.
Every path, command, flag and directory a rule names: does it exist.
Every hook in `settings.json`: does its command resolve.
Every skill: does the directory name match the `name:` in frontmatter, and does any name repeat across user, project and plugin sources.
Trim the value before comparing — a `SKILL.md` saved with CRLF line endings carries the `\r` into the name and reports a mismatch that is not one (`keep-a-changelog` does this today).
`/doctor` already covers a slice of this — invalid settings files, duplicate subagent names, CLAUDE.md content derivable from the codebase.
Ask for its output rather than reimplementing it, and spend your effort on what it cannot do.

### 3. Regroup by topic

This is the step that makes conflicts visible, and skipping it is why they stayed invisible until now.
Reading file by file, each file is coherent — it was written in one sitting by one author with one intent.
The conflict is a property of a **pair**, and a pair only forms when you break file order.

So take one topic at a time and pull every rule about it from every source into one list, with `file:line` on each.
Topics that actually collide, in rough order of how often: branching and merging; committing and message content; when to ask versus when to act; output format and verbosity; which tools to use and when to spawn agents; comments and documentation; language and terminology; testing and verification.
Twenty rules in one topic list, read together, and the pairs announce themselves.

### 4. Check each candidate pair against the bar

Write the splitting prompt.
Then look for an exception clause in either source before opening the finding — the resolution is often already written three lines away.

## Resolution

The report is not the deliverable.
A resolved conflict is.

- **One authority per rule.**
  Delete the copy; never sync two copies.
  Two copies of a rule drift again by definition — that is what class 2 is.
  The same principle the fail-fast rule states for code: do not enforce one invariant in two places.
- **Put the rule at the narrowest layer where it is true.**
  A rule in the global file that only holds for Nushell repos belongs in a Nushell repo.
  Rules pushed up a level to be safe are what fills the global file with things that then contradict specific projects.
- **If it must never happen, prose cannot hold it.**
  Move it to a `PreToolUse` hook or a permission deny rule and delete the sentence, or keep the sentence and accept it as guidance.
  Keeping both is the same defect one layer up.
- **`claudeMdExcludes`** is the right tool when the conflict comes from another team's file in a monorepo, rather than editing their file.
- **Never rewrite the user's instruction files silently.**
  They carry his reasoning in his own voice, and an agent tidying prose reliably keeps the rule and deletes the why.
  Propose the exact edit as a diff, take one confirmation, then apply it.
- **Record the resolution where it survives** — the commit body, with the date and what the two rules were.
  Otherwise the next agent reads the surviving rule, finds it arbitrary, and re-opens the question you just closed.

## Output

Order findings by how often the splitting prompt actually occurs, not by how severe they look.
A conflict that fires on every commit outranks one that fires on a yearly release.

```
<topic>  [class 1-4]
  A > "<verbatim rule>"           <file>:<line>
  B > "<verbatim rule>"           <file>:<line>
  splits on: "<the user prompt that triggers both>"
  → <one proposed resolution: delete which copy, or scope which one, or move to a hook>
```

Quote verbatim.
A paraphrase of a rule is a new rule, and the user cannot check a paraphrase against what he meant when he wrote it.

## When to run it

- After any session in which an agent edited an instruction file — that is the drift this skill exists for.
- Before adding a new rule: the same rule may already exist elsewhere, in different words, and adding the second copy is how class 2 is born.
- When an agent "ignored" an instruction.
  It usually obeyed a different one.
  Finding which is faster than rewriting the rule that was already fine.

## Traps

- **This audit is itself a prime source of drift.**
  You are editing the files that govern every future session, on the strength of your own reading of them.
  Edit surgically, one conflict per change, and let the user confirm each.
- **A skill body and a skill description behave differently.**
  Descriptions sit in context every session, so two descriptions claiming the same trigger phrase collide on every prompt.
  Bodies load on demand and two of them rarely meet, so a conflict between two skill bodies is real but rare — rank it accordingly.
- **The harness system prompt is not a file.**
  You can quote it from your own context, but you cannot diff it, and it changes with the session, the model and the surface.
  Label such a quote as observed in this session and never propose an edit to it — propose the edit to the file on the other side of the pair.
- **A found conflict is not proof the rule was ever broken.**
  If the user wants to know whether it actually cost him something, that is `decision-provenance` and the session transcripts, not this skill.
- **Absence is a finding only with its scope.**
  "No conflicts" means nothing without the list of sources you enumerated and the topics you grouped.
  Print both.
