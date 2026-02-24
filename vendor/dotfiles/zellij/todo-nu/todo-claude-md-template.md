# Todo folder - project tasks (including completed ones)

Todo files are created by the user or via the `/create-update-todo` command.

## File naming rules

### Format

`YYYYMMDD-HHMM-short_title.md`
- HHMM - creation time for uniqueness within the day
- short_title - brief description (3-4 words with dashes)
- Example: `20250911-1430-analytics-task.md`

### When creating a new file

Always include short_title in the filename

### When updating an existing file

- If file is `YYYYMMDD-HHMM.md` WITHOUT short_title → add short_title via `git mv` (generate from task content)
- If file already has `YYYYMMDD-HHMM-short_title.md` → DO NOT rename

## Creating and updating todo files

Use the `/create-update-todo` command which supports two modes:
- **Creating new todo**: pass task description
- **Updating existing todo**: pass path via `@path/to/todo.md`

**Compactness principle:** Goal is maximally compact todos without information duplication.

When updating, the command may modify/replace any sections for brevity, **except** the `## Task from user (original)` block - it is protected from rephrasing. The command CANNOT modify existing text but MUST add new user clarifications at the end of the section after an empty line.

## Handling completed tasks

**KEY RULE:** Task status is managed via frontmatter. Files remain in the `todo/` folder.

### Workflow for tasks:

1. **When starting work:** update `status: in_progress` in frontmatter
2. **When finishing:** update `status: completed` in frontmatter
3. **Add results:** append "## Execution result" section to the file
4. **Commit changes** with reference to the todo file

### Execution results format

When adding "## Execution result" section to todo file:

- **DO NOT include code fragments** - results should be described in text
- **Focus on what was achieved** - not the code that did it
- **Describe results through their meaning and significance** - what changed, what problem was solved, what data was obtained

**Example:**

```markdown
## Execution result

Created a script for analyzing data seasonality. The script extracts data from the database, groups by relevant dimensions, calculates metrics.

Results are saved to CSV file with appropriate columns.
```

## Git commit rules

### Mandatory todo references in commits

**For commits when creating/updating todo file:**

- **If task came from chat session** → can use: `"Task received in chat"`
- **In all other cases** → todo file reference is MANDATORY

**Formats:**

- Creation: `todo add: [brief description] (todo/YYYYMMDD-HHMM-title.md)`
- Update: `todo update: [what changed] (todo/YYYYMMDD-HHMM-title.md)`

**For commits when executing todo task:**

- **ALWAYS** include todo file reference (no exceptions)
- Format: `feat: completed task YYYYMMDD-HHMM-title\n\nTodo reference: todo/YYYYMMDD-HHMM-title.md`

## Task status management

### Status in frontmatter

Task status is managed via frontmatter (NOT by moving files):

```yaml
---
task-name: feature-improvement
status: in_progress
created: 2025-10-03
updated: 2025-10-03
completed: 2025-10-04
related_files:
  - path/to/related/file
  - docs/related-doc.md
---
```

**Possible values:**
- `status`: draft | in_progress | completed
  - `draft` - task created but work not started
  - `in_progress` - task in progress
  - `completed` - task finished
- `completed`: date added when status changes to completed
- `related_files`: optional, for explicit link to project files

**Workflow transitions:**

```
draft → in_progress → completed
  ↑          ↓
  └──(rollback on error)
```

**Usage in commands:**

- `/create-update-todo` - creates new todos with `draft` status
- `/execute-todo` - transitions `draft` → `in_progress` → `completed` with checks at each stage

### Viewing tasks by status

#### Unix way

```bash
# Active tasks
grep -l "status: in_progress" todo/*.md

# Drafts
grep -l "status: draft" todo/*.md

# Statistics
grep "^status:" todo/*.md | cut -d: -f3 | sort | uniq -c
```

#### Nushell way

```nu
# Active tasks (in progress)
ls todo | where type == file | insert status {|i|
  open $i.name | split row -r "---\n?" | get 1? | try {from yaml | get status -o}
} | where status == "in_progress"

# Incomplete tasks (drafts and in progress)
ls todo | where type == file | insert status {|i|
  open $i.name | split row -r "---\n?" | get 1? | try {from yaml | get status -o}
} | where status not-in [completed] | sort-by name

# All tasks with metadata
ls todo | where type == file | insert metadata {|i|
  open $i.name | split row -r "---\n?" | get 1? | try {from yaml}
} | select name metadata
```

### Task history

Task history is available via git log:

```bash
# Find all commits related to task
git log --grep="20251001-1200"

# View history of specific todo file
git log -- todo/20251001-1200-task.md

# View how task status changed
git log -p -- todo/20251001-1200-task.md | grep -A1 "^[+-]status:"
```

### related_files field (OPTIONAL)

The `related_files` field is optional. Add it only if explicit link between task and project files is needed:

```yaml
related_files:
  - src/feature/module.py
  - docs/feature-spec.md
  - config/settings.yaml
```

#### When to use

- Task affects several specific files (code, documentation, configuration)
- Quick navigation to related files is needed
- Omit if relationship is obvious from task description

## Todo file structure

Use this structure for creating or updating todo files:

```markdown
---
task-name: [brief name based on analysis]
status: draft
created: [current date]
updated: [current date]
---

# [Task title - rephrased version]

## Task from user (original)

#### Section protected from rephrasing

The `/create-update-todo` command CANNOT modify or rephrase existing text in this section.

#### Adding clarifications

When clarifying task in chat, the command MUST add literal user remarks at the end of the section after an empty line.

**Example:**

```
## Task from user (original)

Create a script for data analysis

Add date filtering

Export result to CSV
```

When creating new todo: original user task text.

## Task description (extended version)

[Detailed description of what needs to be done, based on task analysis.
Include context, goal and expected result]

## Requirements

[Formulate specific requirements based on analysis:]
- [ ] Functional requirements
- [ ] Technical constraints
- [ ] Success criteria

## Implementation plan

[Propose step-by-step execution plan:]
- [ ] Step 1: [description]
- [ ] Step 2: [description]
- [ ] ...

## Affected files

[If determinable from task context]
- Existing files: [code, documentation, configuration]
- New files: [what will be created]

## Dependencies

[If applicable]
```

## Organization principles

1. **Status in frontmatter** - single source of truth
2. **Files stay in `todo/`** - not moved when completed
3. **Don't delete files** - history is stored in git
4. **Mandatory todo references in all commits**
5. **YYYYMMDD-HHMM-short_title format for all tasks**
6. **Use grep/nushell** - don't create derived data

This ensures simplicity, preservation of complete task history and traceability of all changes.
