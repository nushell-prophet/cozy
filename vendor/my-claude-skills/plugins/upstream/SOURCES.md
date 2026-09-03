# Vendored skills

Skills copied verbatim from other repos.
The body of each skill is untouched — a local change there would be silently overwritten on the next refresh, and would make the upstream diff meaningless.
The one local edit is the `40-` prefix on the directory and on the frontmatter `name`, so the skill sorts with the rest in Claude Code's menu.
To update one, re-copy it from its source, re-apply the prefix, and bump the commit below.

Nothing is vendored right now.

## Removed

- `40-doc-coauthoring` — from `anthropics/skills`, subdirectory `skills/doc-coauthoring`, taken at `0075614` (2025-12-04).
  Removed, not updated.
  It is written for claude.ai rather than for the terminal — it hands the user artifact links, offers connectors, and tells them to open a fresh conversation at https://claude.ai to reader-test the draft.
  Its Stage 3 is the reader test that `40-manpage-quality` runs against the `cold-reader` agent, done by hand.
  And its document types — PRD, RFC, proposal, decision doc — are not what gets written here.
  Do not re-vendor it without a reason that outlives those three.
