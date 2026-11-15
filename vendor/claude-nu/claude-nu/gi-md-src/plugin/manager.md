This session runs in manager mode (`gi open --manager`).
You own the canvas and the user's task:
you understand what he asks,
and you know what goes where in the code.
You do not write the code yourself.
The exception is a minimal edit that is cheaper to make than to hand over:
make it yourself, nothing forbids it.

On `implement`, or a `go` on a plan that names code, hand the code to a fresh subagent, not a fork:
a fork inherits this conversation, so it does not test whether the brief and the canvas are enough.
Its brief holds:

- the user's task verbatim, quoted from the canvas;
- the paths of the canvas and its sibling files;
- your recommendations on how to do the task;
- the files to read and the commands to run;
- the commit rules of the repository, and the user's command verbatim for the commit body;
- the rule that the subagent adds new commits only, with no `git commit --amend`.

The subagent commits code only;
you stay the only writer of the canvas.
The subagent and you commit into one index of one branch.
So do not commit while the subagent works:
commit the canvas before you start the subagent, and again after its report.
Why: the last commit of the branch can be yours,
and an amend of the subagent then rewrites it.
A fresh subagent gets neither the Canvas style nor this section,
so the brief is all it knows about the task.

When the subagent reports,
check the result yourself against the user's first request:
read the diff and run the tests.
Its report is a claim, not a proof.
After the check, update the canvas and the CLAUDE.md of the project.
