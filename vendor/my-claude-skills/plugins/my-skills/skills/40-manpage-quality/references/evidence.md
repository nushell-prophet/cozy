# Evidence for the rules in ../SKILL.md

Read this when a rule in the skill looks arbitrary, when the user challenges one, or before changing a rule.
Every number here was measured; the command that produced it is given so it can be re-run.

**Provenance.**
These counts were re-run in the session that wrote this file: corpus size, "the user", "you", "The default is", "simply", "Note that", "mutually exclusive", "silently", "is not an error", the marketing-word set, `.Xr` total, `.Nd` trailing periods, and the per-section page counts.
The rest — the option-mood sample, the rendered sentence-length distribution, the colon-introduction rate, the section-ordering violations, the SEE ALSO sort conformance, the `.Nd` length distribution and the `.Dd` year histogram — come from the research pass, with the command shown.
Re-running gave counts within about 5% of the research pass every time, so treat an unverified figure as accurate to that order and re-run before quoting it as exact.

## The corpus

A local copy of the OpenBSD manual tree, at `upstream-big-repos/obsd-man/usr/share/man`.

    export LC_ALL=C
    find man1 man4 man5 man7 man8 -maxdepth 1 -type f -exec grep -l '^\.Dd' {} + | sort > corpus.txt
    wc -l < corpus.txt          # 1520

Two filters matter, and dropping either poisons the result:

- **Only files with a `.Dd` line.** The ~254 pages without one, and all 728 pages in man3p, are generated from Perl POD by `Pod::Man`. They are machine output, not examples of anyone's writing.
- **`grep -a` is load-bearing.** Four files are ISO-8859, not UTF-8 (`man5/isakmpd.conf.5`, `man5/sasyncd.conf.5`, `man8/isakmpd.8`, `man8/sasyncd.8`). Plain `grep` calls them binary and silently matches nothing, which is how a 100% figure reads as 99.7%.

Arch subdirectories (`man4/amd64` and friends) are excluded; including them gives 1935 files.

## Stated rules, from the corpus's own meta-documentation

These come from `man7/mdoc.7`, `man7/man.7`, `man7/roff.7` and `man1/mandoc.1`, and are quoted rather than inferred.

- Canonical section order — `mdoc.7:120-163`, the MANUAL STRUCTURE skeleton.
  Three sections are marked "Not used in OpenBSD": LIBRARY, IMPLEMENTATION NOTES, SECURITY CONSIDERATIONS.
- "This begins with an expansion of the brief, one line description in NAME" — `mdoc.7:288-289` on DESCRIPTION.
- "List the options in alphabetical order, uppercase before lowercase for each letter and with no regard to whether an option takes an argument. Put digits in ascending order before all letter options." — `mdoc.7:306-309`.
- "Example usages. This often contains snippets of well-formed, well-tested invocations. Make sure that examples work properly!" — `mdoc.7:366-368`. The only imperative with an exclamation mark in the document.
- "Cross-references should conventionally be ordered first by section, then alphabetically (ignoring case)." — `mdoc.7:394-395`. And "This section should exist for most manuals" — `mdoc.7:393`, the only section given that status.
- "Common misuses and misunderstandings should be explained in this section." — `mdoc.7:423-424` on CAVEATS.
- "Known bugs, limitations, and work-arounds should be described in this section." — `mdoc.7:426-427` on BUGS.
- EXIT STATUS was historically documented under DIAGNOSTICS, "a practise that is now discouraged" — `mdoc.7:359-361`, `mdoc.7:376-379`.
- "It's helpful to document both the file name and a short description of how the file is used (created, modified, etc.)." — `mdoc.7:350-352` on FILES.
- "Each sentence should terminate at the end of an input line." — `roff.7:305-309`. `mandoc` lints the breach as "new sentence, new line" (`mandoc.1:1815-1818`).

**The gap that shaped this skill.** Nothing in those four documents states a rule about tense, voice, person, sentence length, or whether EXAMPLES should exist.
Grep for those terms returns nothing.
The register is real but unwritten, so the skill derives it from the corpus and cites counts instead of citing a rulebook.

`mandoc` does lint the structure, and that list is worth knowing because it is the machine-checkable half of the house style: first section must be NAME, NAME must hold only `.Nm` and `.Nd`, `.Nd` must come last in NAME, standard sections must appear in conventional order, no duplicate section title, no cross-reference to a page's own name, SEE ALSO sorted and punctuated one way, input lines under 80 bytes, no trailing whitespace (`mandoc.1:960-1326`).

## Register

    # third person vs second person
    xargs -a corpus.txt grep -ahow 'the user' | wc -l          # 716
     xargs -a corpus.txt grep -ail '^[^.]*\byou\b' | wc -l         # 130 of 1520 pages

"you" clusters in imported pages — `mail.1` 29, `patch.1` 27, `vi.1` 25, `csh.1` 18 — not in OpenBSD-authored ones.
`ssh.1` is the visible exception, with one prose use at `ssh.1:299` and a third-person-verb style inherited from Ylonen's original.

Option-description mood, over 4914 `.It Fl X` descriptions: 1972 (40%) open with a bare imperative, 370 (7.5%) with a third-person verb.
Most common openers: Use 248, Specify 245, Print 242, Do 182, Set 157, Display 147.

Sentence length, N=1100 rendered sentences over 10 pages (`groff -mandoc -Tascii`, split on sentence boundaries): median 12 words, mean 15.7, 42% under 10, 77% under 20, 95th percentile 36.

Defaults, line-initial: "The default is" 560, "The default value is" 129, "Defaults to" 130, "By default" 375.

## Absences, counted

All over the 1520-file corpus with `.\"` comment lines stripped first, so license headers do not pollute the counts.

Zero or near zero: "please note" 0, "keep in mind" 0, "coming soon" 0, "in a future release" 0, "blazing" 0, "state of the art" 0, "best-in-class" 0, "easy to use" 0, "user-friendly" 0, "we recommend" 1, "seamless" 1, "hopefully" 2, "powerful" 4, "intuitive" 6, "obviously" 7, "arguably" 0.

**Present, contrary to the folklore** — this is why the skill forbids a banned-word pass:

- "simply" 84, including `ssh.1:1599` "`ssh` will simply ignore a private key file if it is accessible by others". The sense is "does nothing more than".
- "Note that" 412 line-initial.
- "just" 224, "actually" 103, "very" 160, "really" 50.
- First person plural: 110 lines in 58 files after excluding the `we(4)` driver page, all inside worked examples.
- "please" 7 — four are quoted program output, two are jokes that survived (`dhcpd.8:523`, `authpf.8:398`).
- Future statements: "in the future" 14, "not yet implemented" 7, "will be added" 8 — every one framed as a current limitation.
- Calibrated hedging: "usually" 236, "typically" 123, "generally" 66, "probably" 51.

## Structure, measured

Section presence, n=1520:

NAME 100.0%, DESCRIPTION 100.0%, SEE ALSO 97.8%, SYNOPSIS 89.0%, HISTORY 76.1%, AUTHORS 50.9%, FILES 30.1%, EXAMPLES 16.8%, BUGS 16.6%, STANDARDS 13.0%, EXIT STATUS 12.2%, CAVEATS 10.5%, DIAGNOSTICS 7.7%, ENVIRONMENT 7.0%.

Presence is strongly section-dependent: EXIT STATUS is 49% in man1 and 0% in man4; FILES is 73% in man5 and 12% in man4; AUTHORS is 69% in man4.
So "which sections a good page has" has no single answer — the four-section core is mandatory and the rest follow the subject.

Ordering: 4 pages out of 1520 violate the canonical relative order (0.26%), and all four make the same swap, EXAMPLES before FILES.
293 distinct orderings appear; the top five cover 43% of pages.
The order is a total order pages sample from, not a template they copy.

    while read -r f; do grep -a '^\.Sh' "$f" | sed 's/^\.Sh[[:space:]]*//'; done < corpus.txt

`.Nd` one-line description: exactly one per file in all 1520.
Characters min 6, median 32, p90 53, max 103. Words min 2, median 5, max 14.
Ends with a period: **0**. Starts uppercase: 50.3%, and that half is proper nouns — man4 is 85% uppercase because of vendor and chip names, man1 only 6.9%.

Page length, comment lines excluded: median 79 lines, p90 357, max 8252 (`tmux.1`).
Half the corpus is under ~100 lines.

EXAMPLES: 256 pages have the section, holding 811 blocks; median 2 blocks per page.
Of those blocks, 83.8% are introduced by a line ending in a colon, 13.6% by other prose, 2.1% by nothing.

SEE ALSO: median 4 entries, p90 8.
Checked all 1307 pages with two or more entries — 1300 conform to "section number ascending, then alphabetical" (99.5%); four of the seven failures are locale collation artifacts, leaving 3 genuine violations (99.77%).

Cross-references: 13588 line-initial `.Xr`, median 6 per page, mean 8.9.
6492 of them (47.8%) are in SEE ALSO — so **the majority sit inline in the body**.

`.Dd` dates: median year 2021, 58.8% dated 2020 or later, only 8.4% before 2013.
1517 of 1520 use CVS keyword substitution so the date updates itself on edit.
The pages are genuinely maintained, which is why the corpus is worth measuring at all.

## Sentences worth keeping on file

Answered branches:

- "The working directory is not changed." — `man1/doas.1:66`
- "If no rule matches, the action is denied." — `man5/doas.conf.5:95`
- "If the given file already exists, it is appended to." — `man1/cu.1:170`
- "Should `pfctl` be unable to load a ruleset, an error occurs and the original ruleset remains in place." — `man8/pfctl.8:68`
- "Anchor names with characters after the terminating null byte are considered invalid; if used in an ioctl, `EINVAL` will be returned." — `man4/pf.4:89-92`
- "It is not an error to specify more than one of…" — `man1/find.1:140`, and 12 other pages

Honest sections:

- "This manual page is woefully incomplete, because it does not at all attempt to explain the information printed by `ipcs`." — `man1/ipcs.1:147`
- "The `vmstat` display looks out of place because it is (it was added in as a separate display rather than created as a new program)." — `man1/systat.1:820`
- "British spelling was done by an American." — `man1/spell.1:246`
- "`script` places everything in the log file, including linefeeds and backspaces. This is not what the naive user expects." — `man1/script.1:122`
- "The `-s` and `-S` options are currently not implemented." — `man1/cpio.1:313`
- "Users should not depend on details of the current implementation, but rather the services exported." — `man4/inet.4:180`

Security stated as mechanism, with the concession first:

- "An attacker cannot obtain key material from the agent, however they can perform operations on the keys that enable them to authenticate using the identities loaded into the agent." — `man1/ssh.1:124-131`
