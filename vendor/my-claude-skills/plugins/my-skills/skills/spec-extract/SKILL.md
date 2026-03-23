---
name: spec-extract
description: >
  Extract a minimal, revision-ready specification from an existing codebase. Use this skill whenever
  the user wants to understand what their project does without reading all the code, needs a spec
  document generated from existing implementation, asks to "reverse-engineer a spec," wants a project
  overview or summary for handoff, or says things like "what do we have," "summarize the project,"
  "generate a spec from code," "I need to review the architecture," or "document what exists."
  Also trigger when the user mentions extracting contracts, interfaces, or feature maps from code.
  Works best on projects up to ~5K LOC but handles larger ones by focusing on public interfaces.
---

# Spec Extract

Generate a minimal specification from existing code — just enough to revise the project without
re-reading the implementation. The output is a "revision map": what exists, what each piece does,
how pieces connect, and what's unfinished.

The core technique is **reverse contract extraction**: for each module or feature, capture its
interface (inputs, outputs, types), its invariants (what must always be true), and its purpose
(one sentence explaining why it exists). Everything else is noise for revision purposes.

**Assume agent-written code unless told otherwise.** Code developed through LLM agents — especially
across multiple conversation threads — has specific failure modes. Each thread operates in an
isolated context window, so features developed in separate sessions can make contradictory
assumptions about shared data structures, reimplement the same utility differently, use
inconsistent naming, or handle errors in incompatible ways. These **session seams** are invisible
from within any single thread but become obvious when you lay all features side by side. A key
job of this skill is to find them.

## Why this shape

A specification for revision has different needs than a specification for implementation.
Implementation specs are detailed and prescriptive. Revision specs are compressed and relational —
you need to see the topology (what connects to what) and the contracts (what each piece promises)
so you can reason about changes without loading the full codebase into your head.

The target compression: **~1 spec line per 15-25 lines of code**. A 1500 LOC project produces
a 60-100 line spec. If the spec is longer, it's not minimal. If it's shorter, it's probably
missing contracts.

## Workflow

### Phase 1: Scan structure

Map the project layout. Identify:
- Entry points (main files, CLI handlers, exports)
- Module boundaries (directories, files that form logical units)
- Test files (these reveal intended behavior — they ARE specs)
- Config and metadata files

Run a directory listing and note file sizes. Files over 200 LOC likely contain multiple
concerns. Files under 30 LOC are usually glue or config.

```bash
# Get project structure with line counts
find . -type f \( -name '*.py' -o -name '*.ts' -o -name '*.js' -o -name '*.rs' -o -name '*.go' -o -name '*.nu' \) \
  ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/target/*' \
  -exec wc -l {} + | sort -n
```

### Phase 2: Identify features

Group files into features. A "feature" is the smallest unit that makes sense to discuss
independently — it has a clear purpose, interface, and boundary. Typical signals:
- A directory with related files
- A module with a public API
- A CLI subcommand
- A class or set of functions that collaborate on one responsibility

For each candidate feature, read the file(s) and extract:
1. **Purpose** — one sentence, starts with a verb (Validates..., Converts..., Manages...)
2. **Interface** — the public contract: function signatures, CLI flags, config keys, types accepted and returned
3. **Dependencies** — what other features/modules this one calls or imports
4. **Invariants** — rules that must hold (from assertions, validation logic, comments, error handling)
5. **Status** — complete / partial / stub (infer from TODOs, unimplemented branches, test coverage)

Read test files for each feature. Tests often express intended behavior more precisely
than the implementation, and they reveal edge cases the author was thinking about.

### Phase 3: Map data flow

Identify the core data types/structures that flow between features. For each:
- Name and shape (fields, variants)
- Where it's created, where it's consumed
- Validation rules or constraints

This is the connective tissue — without it the feature list is just an index.

### Phase 4: Detect session seams

Compare features side by side looking for inconsistencies that suggest different context windows.
Concrete patterns to check:

**Contract mismatches.** Feature A produces output in format X, Feature B consumes the same data
but expects format Y. This happens when both features were specified against an idea of the shared
type rather than against each other's actual code.

**Duplicate utilities.** Two features implement the same operation (parsing, validation, formatting)
independently. Look for functions with similar names, similar signatures, or similar logic in
different files. Agent sessions tend to write what they need locally rather than discovering
existing helpers.

**Naming drift.** The same concept called `pack` in one feature, `bundle` in another, `package`
in a third. Check names of variables, functions, CLI flags, and config keys across feature
boundaries.

**Inconsistent assumptions.** One feature treats a value as optional (checks for null), another
treats it as required (accesses directly). One feature uses UTF-8, another assumes ASCII. One
handles errors by returning Result/Option, another throws/panics.

**Dead branches.** Code paths that were part of an earlier design iteration but no longer connect
to anything. Agent sessions sometimes leave scaffolding from abandoned approaches because the
agent doesn't have the broader context to know it's dead.

**Contradictory invariants.** Feature A asserts `x > 0`, Feature B can produce `x = 0` under
certain conditions. This is the most dangerous kind of seam — it only fails at runtime along a
specific path.

For each seam found, record: which features are involved, what the mismatch is, and how severe
it is (cosmetic / functional / correctness-threatening).

### Phase 5: Synthesize the spec

Produce a single markdown file using the template below. Every line must earn its place.
If a section would be empty, omit it. If a feature's interface is obvious from its name
and purpose, keep the interface entry minimal.

## Output template

```markdown
# [Project Name]

[One sentence: what this project does and for whom.]

## Architecture

[2-4 sentences: languages, key frameworks, overall structure pattern (CLI tool / library /
server / pipeline), and the one thing someone new must understand first.]

## Data Types

### [TypeName]
[Shape description — fields with types, or variant list. Only types that cross feature boundaries.]

## Features

### [Feature Name]
**Purpose:** [one sentence, starts with verb]
**In:** [input types/params] → **Out:** [output types/return]
**Depends on:** [other features, external services]
**Invariants:** [what must always hold — omit if none beyond type safety]
**Status:** complete | partial([what's missing]) | stub

### [Next Feature...]

## Cross-Cutting

[Global patterns: error handling strategy, logging, configuration approach.
Only include if there IS a consistent pattern. 2-3 sentences max.]

## Seams

[Inconsistencies between features that suggest isolated development sessions.
Each entry names the involved features and classifies severity.]

### [Seam description]
**Between:** Feature A ↔ Feature B
**Issue:** [concrete mismatch — types, names, assumptions, duplicated logic]
**Severity:** cosmetic | functional | correctness
**Resolution:** [brief suggestion — which side should win, or what shared contract to extract]

## Unresolved

- [Known gaps, TODOs extracted from code, open design questions]
- [Decisions that were deferred — visible from commented-out code, TODO markers, or stub implementations]
```

## Calibration guidance

**Too shallow** — the spec just lists file names and one-word descriptions. You can't tell
what the inputs/outputs are. You couldn't reason about the impact of changing feature X on
feature Y. Fix: add interface contracts and dependency links.

**Too deep** — the spec restates implementation logic in English ("iterates through the list,
checks each item against the filter, then maps..."). You're reading pseudocode, not a contract.
Fix: describe what the function promises (postconditions), not how it works.

**Right level** — you could hand this spec to a developer (or an AI agent) who has never seen
the code, and they could: (a) understand what the project does in 2 minutes, (b) identify which
features they'd need to modify for a given change, (c) predict side effects of that change from
the dependency and invariant information.

**Seams section too alarmist** — every minor naming difference is flagged. Focus on mismatches
that would cause runtime failures or silent data corruption. Naming drift is worth noting but
only if it creates actual confusion (e.g., a CLI flag and the internal variable refer to
different concepts using the same word).

**Seams section empty** — unlikely for multi-session agent-written code. Double-check: compare
function signatures that handle the same data type across features, and compare error handling
strategies. If the code is genuinely consistent, note that explicitly — it's useful information.

## When the project has conversation history

If past conversation threads or commit messages are accessible, mine them for:
- **Decision rationale** — why alternatives were rejected (add to relevant feature or to Unresolved)
- **Intended scope** — features discussed but not yet implemented (add to Unresolved)
- **Naming context** — non-obvious names explained in conversation (add as parenthetical to feature Purpose)

Decision rationale is high-value information that exists nowhere in the code. Capture it.

## After generating the spec

Present it to the user for review. Ask specifically:
1. Does every feature listed here actually exist? (catches hallucinated features)
2. Is anything missing? (catches features the scan missed — often config/setup code)
3. Are the dependency arrows correct? (catches misunderstood data flow)
4. Do the seams look right? (the user may know that an apparent inconsistency is intentional,
   or may spot seams the analysis missed because they remember the conversation context)

The spec is a living document. After review, save it alongside the codebase (e.g., `SPEC.md`
at the project root). It should be version-controlled and updated when features change.
