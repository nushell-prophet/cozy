# The note of a park

A fork of the session runs this procedure.
It writes one note and commits it.
It does not start the work that the note describes.

1. **Where.** The `todo/` folder that the prompt of the fork names.
   `mkdir todo` when it is absent.
   The file is `<yyyyMMdd>-<slug>.md`.
   The date is today.
   The slug is a few English words, lowercase, with `-` between them.
   If the file exists, add `-1`, `-2`, … to the name.

2. **Frontmatter:**
   the template of `gi open <slug>` and `create-todo`,
   plus the session id from `printenv CLAUDE_CODE_SESSION_ID`: a fork has the id of its parent.

   ```yaml
   ---
   status: draft #draft | accepted | in_progress | completed | rejected
   agents-mode: co-editing #read-only | grammar-fixes | co-editing
   updated: '<yyyyMMdd>' #yyyyMMdd
   origin_session: <session id>
   ---
   ```

   The key is `origin_session`, not `session`:
   `gi` reads a `todo/` note with `session:` as a canvas,
   and `gi open` would then resume this session, which belongs to another task.
   `origin_session` is the address that `40-why-is-this` follows into the transcripts.

   `status: draft` marks a note with no decision yet.
   `status: accepted` marks an idea that the user checked and decided to implement,
   when the implementation must wait:
   for example, it needs much testing and can break the workflow if it lands in one go.
   The body says why it waits.
   `accepted` is the word of PEP and RFC processes for "decided, not implemented".

3. **Body:** `# <title>`, then what a reader needs to act without this session:
   - what was found, and how it showed: the command and its real output, in `# =>` lines;
   - where: a change-id link (`cozy git link <file>`, in cozy) or a path with a quote, never a bare sha;
   - the words of the user about it, verbatim;
   - why it waits, and the first step when someone picks it up.

   Keep it short.

4. **Commit** only the note, on the current branch of the repo that holds it:

   ```sh
   git -C <todo folder> add <file>
   git -C <todo folder> commit --message 'todo: add <slug>' -- <file>
   ```

   The path after `--` keeps out of the commit what the session staged for its own task:
   the session works on in parallel with the fork.
   If the repo is in a rebase, a merge or on a detached `HEAD`, do not commit:
   leave the note uncommitted and say so in the line of step 5.

5. **Return** this line in the last message; the prefix `parked:` lets the session find it among other lines:

   ```text
   parked: <path of the note> · <commit> · on <branch>
   ```

   `<commit>` is the `Change-Id` trailer of the commit when the repo stamps one, its short sha otherwise.
   If a step failed, return `parked: not parked: <the cause in one line>` instead.
