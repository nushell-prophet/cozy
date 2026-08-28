---
name: 40-manpage-quality
description: >
  Write reference documentation to the standard of an OpenBSD manual page — every
  branch of the behaviour answered in the text, every default given its own
  sentence, and a section that states plainly what is broken. Use this skill when
  the user asks to "write the docs", "document this command", "write a man page",
  "improve the README", "напиши документацию", "как в man-страницах", or when a
  document is reviewed for quality rather than for typos. Also use when readers
  keep asking something the document already claims to cover — the page described
  the feature and left the behaviour to be discovered by running it.
version: 0.1.0
---

Most software documentation describes features.
The reader still has to run the program to find out what it actually does: what happens with no argument, whether the file is overwritten or appended to, which option wins when two conflict.
An OpenBSD manual page answers those in the text, one sentence after the sentence that raises them.
That is the whole difference, and it is reproducible.

This skill is not about mdoc markup.
The target may be a README, a module doc, a `--help` text, or a real manual page.
What transfers is the register, the completeness bar, and the section contract.

The evidence base is the OpenBSD manual tree: 1520 hand-written mdoc pages in sections 1, 4, 5, 7 and 8.
Every number quoted below was measured over those files.
`references/evidence.md` holds the measurements with the commands that produced them; read it when a rule here looks arbitrary or when the user challenges one.

## The bar

A sentence stays if it answers a question the reader would otherwise have to answer by running the program.

Everything else is a deletion candidate.
This is the test to apply to your own draft, sentence by sentence, before you hand it over.

**Document the behaviour and the promise, never the implementation.**
The reader is going to depend on what you write, so anything you describe becomes a contract you must keep.
`inet.4` states the boundary outright: "Users should not depend on details of the current implementation, but rather the services exported."
Internals go in comments and commit bodies, not in the page.

The signature example is five words, in `doas.1`:

    The working directory is not changed.

Nothing prompted it.
It exists because a careful reader would wonder, and the alternative is that they test it.

## The register

**The program is the subject, the tense is present, and the mood is indicative.**
"The `doas` utility executes the given command as another user."
Not "you can use doas to run commands".

**The human is named in the third person.**
"The user" appears 716 times in the corpus; "you" appears in the prose of 130 pages out of 1520, and clusters in imported third-party pages, not in ones written for OpenBSD.
Writing "the user" instead of "you" changes the genre: the sentence becomes a statement about a system, not an instruction to a person.

**Option descriptions switch to the bare imperative.**
Of 4914 sampled option descriptions, 40% open with a bare imperative verb and only 7.5% with a third-person verb.
"Disable the packet filter." "Specify the line to use." "Print the version and exit."

**Write short.**
Median sentence in the corpus: 12 words.
77% are under 20 words.
One idea per sentence, and a stack of short declaratives where ordinary docs write one comma-chained sentence.

**Break lines at sentence ends.**
`mandoc` lints this as "new sentence, new line", and the user's global rules ask for the same thing.
The two agree, so there is nothing to reconcile.

**Plain words are not in tension with this register.**
OpenBSD prose is dense in content, not in vocabulary: common words, short sentences, exact technical terms kept exact.
Keep the user's B1–B2 word-choice rule and add the register on top of it.

### What is banned, and what only looks banned

Verified by counting the whole corpus, because a banned-word list built from intuition is wrong here.

Truly absent, all marketing register: "please note" 0, "keep in mind" 0, "coming soon" 0, "blazing" 0, "state of the art" 0, "user-friendly" 0, "seamless" 1, "powerful" 4, "we recommend" 1.

Not absent, and do not purge them:

- "simply" — 84 uses, including `ssh.1`.
  It means "does nothing more than", never "just do X, it's easy".
- "Note that" — 412 line-initial uses.
  A bare note is fine; "please note" is not.
- "we" — 110 uses, and only inside worked examples: "In the example below, we look at encrypting communication for an IRC client".
- Future tense — 14 "in the future", 7 "not yet implemented".
  Always framed as a current limitation, never as a roadmap promise.
- Hedging — "usually" 236, "typically" 123.
  These mark real variability in the system.
  What is near zero is hedging about the *author*: "hopefully" 2, "arguably" 0.

The rule underneath: hedge about the world when the world varies, never about your own claim.

## The unasked branch

This is the core move, and the part that takes real work.
For every behaviour you document, walk this list and answer in the text whatever applies:

- **No argument given.** "If no files are specified, all of them are checked."
- **The target already exists.** "If the given file already exists, it is appended to."
- **The target is missing.** "The logfiles already have to exist with the correct permissions."
- **The value is rejected.** Name the error: "if used in an ioctl, `EINVAL` will be returned."
- **Two options conflict.** "`-N` and `-r` are mutually exclusive" — the corpus says this 42 times.
  And it says the opposite where it holds: "It is not an error to specify more than one of…", 14 times.
- **The operation fails partway.** Name the state left behind: "Should `pfctl` be unable to load a ruleset, an error occurs and the original ruleset remains in place."
- **Nothing matches.** Name the fallback: "The last matching rule determines the action taken. If no rule matches, the action is denied."
- **Something is ignored.** Say "silently" out loud — the corpus does, 45 times.
- **What does not change.** The `doas.1` move above.

**The default gets its own sentence, after the effect, never a parenthesis.**
"The default is" opens a line 560 times.
Give the number, its unit, and where the number comes from when that is knowable: "The default is 56, which translates into 64 ICMP data bytes when combined with the 8 bytes of ICMP header data."

**Every accepted keyword is listed with its own gloss.**
Never "accepts several modes".
If order matters between them, state the order.

**Verbosity levels are distinct behaviours, not "more output".**
"When used together with `-v v`, `pfctl` will loop and show updated queue statistics every five seconds."

## Structure

The canonical order, from `mdoc.7`, is a total order that pages sample from — not a template to fill in:

NAME, SYNOPSIS, DESCRIPTION, ENVIRONMENT, FILES, EXIT STATUS, EXAMPLES, DIAGNOSTICS, ERRORS, SEE ALSO, STANDARDS, HISTORY, AUTHORS, CAVEATS, BUGS.

Take only the sections that apply, and keep them in that relative order.
The corpus obeys this at 99.7% — 4 violations in 1520 pages.
Presence is the opposite of uniform: NAME and DESCRIPTION 100%, SEE ALSO 98%, SYNOPSIS 89%, but EXAMPLES only 17% and BUGS 17%.
An empty section is worse than a missing one.

What each section owes the reader:

- **NAME** — one line, no trailing period (0 of 1520 have one), median 5 words, and it is a description, not a slogan.
- **SYNOPSIS** — the invocation syntax only. Options in alphabetical order, digits first, uppercase before lowercase.
- **DESCRIPTION** — opens by saying what the thing *is and does*, in one or two sentences, before any qualification.
  Motivation, if any, comes second and is historical, not promotional.
- **FILES** — the path *and* how it is used: created, read, modified.
- **EXIT STATUS** — enumerate the *reasons*, not the numbers.
  "The config file could not be parsed." "The password was incorrect." "The message file is too large."
- **EXAMPLES** — introduced by a sentence ending in a colon, then the block; that is the house form at 84% of blocks.
  `mdoc.7` gives exactly one imperative here: "Make sure that examples work properly!"
- **SEE ALSO** — sorted by section number, then alphabetically. 99.8% conform. Median 4 entries.
- **HISTORY** — when it first appeared and where it came from. 76% of pages have this.

**Split a topic into its own section only when a reader may need it without reading the rest.**
`ssh.1` spins out X11 FORWARDING and VERIFYING HOST KEYS on that test.
`doas.1` keeps its whole environment handling as three sentences inside DESCRIPTION, because nobody needs it alone.
Size alone is not a reason to split.

**Cross-reference mid-sentence, not in a trailing list.**
The corpus carries 13588 cross-references, and 52% of them sit in the body, where a noun would sit: "the `umask(2)` is set to values appropriate for the target user".
A page that links its neighbours mid-sentence never has to re-explain their job.

**For a README or module doc**, map the sections rather than copying the names: NAME becomes the one-line summary at the top, SYNOPSIS becomes the usage block, EXIT STATUS becomes the failure list, CAVEATS and BUGS keep their names or become "Limitations".
The order and the contract survive the rename; the mdoc heading names do not have to.

## The section that says what is broken

253 pages have BUGS, 159 have CAVEATS.
This is the hardest section to write and the one that most separates the corpus from vendor documentation.

**BUGS is for what is wrong. CAVEATS is for what is correct but surprising.**

What is admitted there, with the cause named rather than a label pasted on:

- The defect and its mechanism: "`locate` may fail to list some files that are present… This is because `locate` only reports files that are present in a periodically reconstructed database."
- Options that do not work: "The `-s` and `-S` options are currently not implemented."
- Design the author now regrets: "The `vmstat` display looks out of place because it is."
- The limit of the abstraction, not just of the code.
- **The documentation's own inadequacy**: "This manual page is woefully incomplete, because it does not at all attempt to explain the information printed by `ipcs`."

The tone is flat declarative.
No apology, no "we are working on it", and no mitigation unless a real one exists — when there is one, name it: "Use `find(1)` to locate files that are of a more transitory nature."

If you cannot write this section, you do not yet know the software well enough to document it.

## Verification

Documentation is a set of claims about behaviour, so the user's verification rule applies to every line of it.

- **Every flag, default, path and exit code you write down is confirmed by running the thing.**
  Not read from the source and paraphrased — run it.
- **Every example is executed before it ships.**
  This is the one instruction `mdoc.7` gives with an exclamation mark.
- **A behaviour you could not trigger is labelled ASSUMED** at the claim, and repeated in the report with the one check that would settle it.
- **A blocked check is reported, not replaced.**
  If the command needs hardware or root you do not have, say so; do not substitute a weaker check and present the result.

Coverage is part of the bar: every option in the interface appears in the document, or the document is not finished.
Say which options you could not exercise.

## Output

Hand back the document, then a short report in this shape:

    Covered: <n> of <m> options, <n> of <m> exit codes.
    Verified by running: <the commands, one line each>
    ASSUMED: <claim> — settled by: <the check>
    Not documented: <name> — <why>

Quote behaviour from real output, do not paraphrase it.
A paraphrased error message is a new error message, and the reader will grep for the one you invented.

## What the corpus cannot show

Everything above was measured on the page.
These six were not measured — they are asserted about the process that produced the page, from context, and the artefact cannot prove them.
Treat them as ASSUMED and say so if you pass them on.
They are here because they explain the numbers better than the numbers explain themselves.

**The manual is authoritative, not descriptive.**
The section above sends you one way only: check the document against the program.
In the culture that produced this corpus the arrow runs both ways.
A disagreement between page and behaviour is a defect, and the code is sometimes what gets fixed.
So write the page as a contract you are willing to enforce, and when the two disagree, fix one of them — never soften the sentence until it covers both.

**Freshness is a mechanism, not a virtue.**
The median page dates from 2021 because an interface change without the page edit is an incomplete patch, and a reviewer rejects it.
Nobody is being diligent; the process makes the omission visible.
Apply it the same way: the documentation edit belongs in the commit that changes the behaviour, not in a documentation pass afterwards.
A doc pass is what you do when the mechanism is missing.

**The reader is a competent peer, mid-task.**
This is never stated in the corpus, and it decides almost everything else.
Thirty pages use the term "file descriptor"; none of them defines it.
The reader arrives as often by searching inside a pager as by reading from the top, which is why options are in alphabetical order — that is an index, not a preference — and why a default is restated at the option instead of being centralised.
The requirement underneath: **every section must survive being entered directly.**
Write each one as if it is the only part that will be read.

**Terseness is funded by the graph.**
A page can be 79 lines because a neighbour holds the rest, and there are 8 cross-references per page to reach it with.
A README has no neighbours.
So when the target is a standalone document, the register still applies but the economy does not: inline the one paragraph a manual page would have pointed at.
Applying the terseness without the graph produces a document that is short and unusable.

**Re-edit, do not accrete.**
No page in the corpus carries an "update:" note, a correction paragraph, or a FAQ appendix.
When the behaviour changed, the sentence describing it was rewritten where it stood.
Accretion is the normal way documentation rots: each fact is true, and together they no longer describe anything.
Integrate the new fact where it belongs, and delete what it replaced.

**Undocumentable is a design smell.**
The BUGS section above says that if you cannot write it, you do not know the software.
The general form is stronger and points the other way.
When a behaviour cannot be stated in a sentence — the flag whose meaning depends on three others, the function whose contract needs a paragraph of conditions — the defect is usually in the interface, not in your prose.
Say so, name the interface, and let the person who owns it decide.
Do not rescue a bad design with good writing; that hides the cost exactly where it would otherwise be paid.

## Traps

**Do not turn this into a banned-word pass.**
The register is carried by sentence shape and by answered branches, not by purging "simply".
A document with no forbidden words and no answered branches has failed.

**Do not write a tutorial.**
A manual page tells the reader what the program does; it does not walk them through a first session.
If the user wants a guide, that is a different document, and it can sit next to this one.

**Do not pad the structure.**
An empty EXAMPLES or a STANDARDS section saying "none" is worse than the missing section.
Only 17% of the corpus has EXAMPLES.

**Do not copy mdoc markup into markdown.**
`.Nd`, `.Xr` and `.Bd` are one output format's macros.
What transfers is what goes in them.

**Do not invent the BUGS section.**
List what you found and can name.
An empty BUGS section is honest only if you looked; say in the report that you looked.

**Do not soften a limit into a feature.**
"Only 15 partitions are supported" is the sentence.
Not "supports up to 15 partitions for flexibility".
