# Vendored skills

Skills copied verbatim from other repos.
The body of each skill is untouched — a local change there would be silently overwritten on the next refresh, and would make the upstream diff meaningless.
The one local edit is the `40-` prefix on the directory and on the frontmatter `name`, so the skill sorts with the rest in Claude Code's menu.
To update one, re-copy it from its source, re-apply the prefix, and bump the commit below.

- `40-doc-coauthoring` — from `anthropics/skills`, subdirectory `skills/doc-coauthoring`.
  Taken at `0075614` (2025-12-04); the repo HEAD was `b29e7cf` then.
  Apache 2.0 per the repo README — the repo carries no `LICENSE` file and no per-skill header, so this is the README's blanket claim, not a marked license.
