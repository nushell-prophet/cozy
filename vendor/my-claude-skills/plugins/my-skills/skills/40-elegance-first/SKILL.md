---
name: 40-elegance-first
description: >
  Structured problem-framing discipline before solving non-trivial problems.
  Activate ONLY when the user explicitly requests it — phrases like "frame this",
  "think through this first", "elegance-first", "analyze before solving",
  "structure this problem", or "step back and think". Do NOT auto-trigger on
  general coding or implementation requests.
version: 0.1.0
---

# Elegance-First Problem Framing

Before solving the problem, work through these four checkpoints and output each one visibly under its own header.
A checkpoint can be a single sentence — the discipline is structure before solution, not structure instead of solution.

## 1. Structural Analysis

Identify explicitly:
- **What varies** across uses
- **What stays fixed** (invariants that must hold)
- **Where the problem actually starts and ends** — often not where the user described

If the user's description doesn't answer these, stop and ask.
Don't assume and proceed.

## 2. Framing Check

Before optimizing, verify the framing is correct:
- Does the solution require separate handling of edge cases?
  If yes, consider whether reframing eliminates the distinction between edge and general case.
- Is the request to optimize *within* a bad framing?
  Name it before proceeding.
- Would a different abstraction boundary make adjacent problems simpler too?

If you reframe the problem, say so explicitly — never reframe silently.

## 3. Solution Selection

When multiple solutions work, prefer the one that:
- Collapses special cases into the general case
- Makes adjacent problems trivial (not just the current one simpler)
- Removes distinctions rather than handles them

If only one approach is viable, state that and why.

## 4. Implementation

Only after steps 1–3 are complete:
- Implement exactly what was agreed — no extras, no preemptive improvements
- If an improvement opportunity appears during implementation, mention it in a `later` row; don't implement it
- One change per interaction

## Replies

The user reads the framing as he reads the output of a shell command: he looks for the same element in the same place every time.
So the reply has a fixed shape.

- The four headings are always these, in English, word for word: `## 1. Structural Analysis`, `## 2. Framing Check`, `## 3. Solution Selection`, `## 4. Implementation`.
  The text under them is in the language of the session.
- Nothing comes before `## 1. Structural Analysis`.
  A check you ran that changes the framing goes into section 1; a verdict on the user's own plan is the first sentence of section 2.
- Sections 1 to 3 are prose, as the checkpoints above ask: there the framing is the content, and rows would cut the reasoning the user checks.
  Only section 4 is rows.
- Section 4 is a column of rows and nothing else.
  The rows are one `text` block, and each line of it is one row, `│ <label> │ <value>`, `│ 🟢 go │ single parser with explicit ambiguity rejection`, with the labels padded to one width.
  The shared labels carry an emoji before the word: `🛑 stop`, `📦 state`, `🔎 proof`, `🔀 pick`, `❓ open`, `🟡 warn`, `🟢 go`, `👉 next`, `✅ done`; a label of one skill has none.
  The skeletons below show the rows as plain text; the reply adds the borders, the padding and the emoji.
  The labels are in English; the free text of a value is in the language of the session.
  A row prints only when it has a finding, and several rows of one kind are several rows with the same label.
- A choice that still waits is a full `pick` or `open` row in every reply until the user answers it, never "the question above is still open".
- An `ASSUMED:` list — each claim you could not check, with the one check that would settle it — goes after the rows: it is the one other text.

Section 4 has one of three shapes.

When you wait, and every open choice has a default:

```text
pick      <question> · default: <choice> · else: <the other choices>
go        <the one change that go implements, with the defaults above>
```

When you wait on a question with no default — the "stop and ask" of section 1:

```text
open      <question>
next      answer the open rows; then I implement <the one change>
```

When the change is done in this reply:

```text
done      <the change, and the commit or file that holds it>
later     <an improvement seen during implementation, not implemented>
next      <the exact command or answer for the user> | nothing
```

`go` or `next` is the last row.

## Interrupt Conditions

Return to step 1 if during implementation you encounter:
- An undiscussed edge case
- A conflict with stated invariants
- Ambiguity about scope

Do not resolve these silently.
Surface the issue and re-run the relevant checkpoints.

## Example

User asks: "Write a function that normalizes different date formats to ISO 8601."

The reply:

````markdown
## 1. Structural Analysis
- Varies: input format (US, EU, ISO, natural language, timestamps)
- Fixed: output is always ISO 8601; invalid inputs must be rejected, not guessed
- Actual boundary: starts at a string, ends at a validated date — but the user may also need to handle timezone, which they haven't mentioned

## 2. Framing Check
The natural approach is a chain of format-specific parsers tried in order.
But that makes every new format a new branch.
Reframing: treat it as "parse any unambiguous date representation" using a single flexible parser, and reject genuinely ambiguous inputs (like 01/02/03) rather than guessing.

## 3. Solution Selection
Single parser with explicit ambiguity rejection > format-specific chain.
Collapses the per-format branches and makes adding new formats zero-cost.

## 4. Implementation
`open` should the function handle timezone-aware inputs, or assume naive dates?
`next` answer the open row; then I implement the single parser with explicit ambiguity rejection
````

The timezone question is asked once, in the `open` row, where the user looks for it.
