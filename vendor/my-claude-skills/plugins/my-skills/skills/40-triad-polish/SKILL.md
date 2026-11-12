---
name: 40-triad-polish
description: >
  Polish already-working code toward elegance using three divergent subagents and an adversarial
  reviewer, run over up to three ratcheted rounds. Use this skill whenever the user has working code
  and asks to polish, clean up, tighten, simplify, refine, "make it elegant", "make it nicer",
  "do a final pass", "cut this down", "is there a better way to write this", or says the code works
  but feels ugly. Trigger it proactively at the end of an implementation session when the user
  signals they are done building and want the result improved rather than extended. This skill runs
  AFTER a working solution exists; for framing a problem before the solution is written, use
  40-elegance-first instead. Do NOT use it to fix bugs, add features, or optimize speed.
  It is a heavy pass — three subagents over up to three rounds — on code the user names and
  wants reshaped; for one cleanup pass over the current diff, the built-in `simplify` is the
  cheaper tool and the right one. Requires subagents.
version: 0.1.0
---

Three agents rebuild, one agent attacks, the champion only changes when it loses.
Up to three rounds.

The target is elegance, not cleverness.
Elegance means a reader finishes the code and says *thanks*.
Cleverness means they say *wow*.
The second one is a defect report.

**Precondition: the code already works.** This skill does not fix bugs and does not add features.
If the code doesn't work, say so in a stop of *Replies* and stop.

## Replies

The user reads these replies as he reads the output of a shell command:
he looks for the same element in the same place every time.
So the gate reply of step 0, the round report, the report at the end and every stop have a fixed shape.

- The reply is a column of rows and nothing else: no paragraph before it, no question after it.
- The rows are one `text` block, and each line of it is one row, `│ <label> │ <value>`, with the labels padded to one width.
  The shared labels carry an emoji before the word: `🛑 stop`, `📦 state`, `🔎 proof`, `🔀 pick`, `❓ open`, `🟡 warn`, `🟢 go`, `👉 next`, `✅ done`; a label of one skill has none.
  A value of several lines, such as a commit message or a diff, goes on the next lines, each with both `│` and spaces in the label cell.
  The skeletons below show the rows as plain text; the reply adds the borders, the padding and the emoji.
- The labels, their order and the fixed values are always in English.
  The free text of a value is in the language of the session.
- A row prints only when it has something to say.
  A check that found nothing gets no row.
  The rows that always print are named under each shape.
- Several findings of one kind are several rows with the same label, the one that costs the user most first.
- The `open` rows of the gate reply carry a number, and the number stays the same in every later reply.
  A question that still waits prints again, as a full row, until the user answers it.
- A question with no default is an `open` row: `go` never answers it.
- A commit is named by its `Change-Id` trailer when the repo stamps one, by its short sha otherwise.
- `warn` is a fact that changes what the user does or expects.
  A check that passed is never a `warn`.
- An `ASSUMED:` list for an unchecked claim goes after the rows: it is the one other text.
- A reply that waits for the user ends with `go <what go does>`, and every choice that `go` makes is a `pick` row above it, with its default.
  A reply that waits for nothing ends with `next`: the exact answer or command for the user, or `nothing`.

The gate reply prints when step 0.3 asks the user whether the characterization tests describe intent, or when coverage is very thin.

```text
unit         <file, function or region> · <n> lines
surface      <what must not move>
gate         <command> → <result> · probe <n> inputs
untouchable  <branch or region> · <why: no test reaches it> · coverage by tool | by reading
open         <n>. does this characterization test describe intent? <the test, in one line>
warn         coverage is thin: <what is not reached> · the honest options: write more tests first, or polish a smaller unit
next         answer <n>, <n>: yes, or the behaviour that is a bug · then the gate freezes and round 1 starts
```

`unit`, `surface`, `gate` and `next` always print.
The `warn` row prints when coverage is very thin; it says so and does not stop the run.
A gate reply that holds only that `warn` waits for nothing: it ends with `│ 👉 next │ nothing · round 1 follows`.

The round report, after the ratchet of each round:

```text
round        <n> · champion kept | replaced by <Remove | Reframe | Boring> · <n> transplants
score        special cases <a> → <b> · concepts <a> → <b> · branches <a> → <b> · dependencies <a> → <b> · lines <a> → <b>
changed      <one change: the reframe or one transplant>
reframe      <the change to the requirements that would delete half of the code> · costs: <what> · not implemented
next         nothing · round <n+1> follows | the report follows
```

`round`, `score` and `next` always print.
`reframe` prints in the round report after which the reframing question was asked.

The report, after the last round:

```text
polished     <unit> · <n> rounds · champion kept | replaced by <Remove | Reframe | Boring> · <n> transplants
gate         <command> → <result> · probe <n> inputs byte-identical · coverage by tool | by reading
score        special cases <a> → <b> · concepts <a> → <b> · branches <a> → <b> · dependencies <a> → <b> · lines <a> → <b> · verdict <thanks | wow> → <thanks | wow>
changed      <one change: the reframe or one transplant>
rejected     <what> · <why>
trade        <the count-winner ranked below a thanks candidate> · <what the trade was> · overrule: "take <candidate>"
reframe      <the change to the requirements that would delete half of the code> · costs: <what> · not implemented
flagged      <a branch flagged as suspicious and left alone> · <the coverage gap behind it>
ended        <the stop rule that ended the run>
commit       <Change-Id | short sha> · log in its body | proposed
warn         <a fact that changes what the user does or expects>
next         <the exact answer or command for the user> | nothing
```

The rows and their steps:

- `gate`: `coverage by tool | by reading` says how step 0.3 made the untouchable list.
- `score`: counted by the one adversary, with one method for all rounds.
  When two counters were used, each round gets its own `score` row, and a `warn` row says that the rounds do not compare.
- `changed`: one row per change applied in *Ratchet*, over all rounds.
- `rejected`: every "could not remove" of the agents and every reframe the adversary killed, one row each — the half that the next reader needs.
- `trade`: the stop rule where a *thanks* candidate outranked the count-winner; the user can overrule it.
- `reframe`: the answer to the reframing question, brought to the user and not implemented.
- `flagged`: the untouchable branches the agents flagged, and why they were untouchable.
- `ended`: why the run stopped, as *Stop rules* asks.
- `commit`: the polish commit, whose body holds the log of *Close the loop*; `proposed` when the repo asks before a commit, with the full message on the next lines of the row.
- `warn`: a transplant kept that the adversary named as out of scope (speed, a bug fix, a feature).
- `next`: `take <candidate>` when a `trade` row stands, the answer that commits a proposed commit, or `nothing`.

`polished`, `gate`, `score`, `ended` and `next` always print, and `next` is the last row.

A stop — the code does not work, the gate cannot be built, a subagent found a bug in a round — has this shape:

```text
stop      <step or round>: <the cause in one line>
state     nothing changed | <what changed; the champion is at <path or commit>>
proof     <one line, or the output of a command on the next lines>
pick      <question> · default: <choice> · else: <the other choices>
go        <what go does: the defaults above>
next      <the exact action for the user>
```

`stop`, `state` and one of `go` and `next` always print.
`go` is there only when the agent can go on with a default.
When only the user can act, `next` ends the reply instead.

## Step 0 — Freeze the baseline

Never start without a way to prove behavior is unchanged.
Cutting code you cannot verify is vandalism with good intentions.
Four things get fixed before any agent is spawned.

### 0.1 Name the unit

State exactly what is being polished: this file, this function, this module.
Three rounds means twelve agents, each carrying the unit in full, so an oversized unit gets slow and expensive before it gets good.

Rough ceiling: a few hundred lines.
Above that, do not fan out on the whole thing.
Ask the adversary to read it once and name the two or three weakest spots, then run the rounds on those.

### 0.2 Name the frozen surface

Say which surface must not move: the CLI output, the public API, the exported names, the wire format, the database schema.
"Observable behavior" is obvious for a script and ambiguous for a library — internal reshaping can quietly relocate a public function.
Write the boundary down.
Agent F works right up against it and needs to know where it is.

Comments are frozen with the code they annotate.
An agent may drop one only when it deletes the code the comment explains, and may reword one only when the new code makes the old wording wrong.
Without that line Agent R cuts every `# Why:` as "not required by the tests", which is true and is the wrong test.
The adversary checks the other direction: a comment has to explain the code as it stands, for a reader who never saw this run.
One that narrates the change — what was here before, what moved, what was tried — is history, and history belongs in the commit body; count it as a defect.

### 0.3 Build the gate

- Tests exist → run them, record the pass list.
- No tests → write characterization tests: feed representative inputs, record what comes out, assert on it.
  Show them to the user in the gate reply of *Replies* and ask whether they describe intent before freezing.
  Some captured behavior is a bug the user has been living with; they decide.
- Cannot verify at all → tell the user in a stop of *Replies*, and stop.
  Do not proceed on vibes.

**Then measure coverage.** This is not optional, and it is the part most likely to be skipped.
The tests define what the cutters are allowed to delete, so anything they don't reach reads as dead weight and dies.
List the uncovered branches and mark them **untouchable**: an agent may flag one for the user's attention, but may not remove it.
When no coverage tool is installed, do it by hand: read each test, name the branches it reaches, and everything else is uncovered.
Say in the report that the list was made by reading.
Pre-existing code the tests barely reach is not polished at all — mark the whole region untouchable, not its uncovered lines.
A header renderer the tests pin at two shapes is a region where every "simplification" is either a bug fix or a surface move the gate cannot see.
If coverage is very thin, say so — the honest options are to write more tests first or to polish a smaller unit.

### 0.4 Score and name the champion

Score the current code (see Scorecard) and write the numbers down.
The current code is the champion.
It changes only by losing a fight.

## Scorecard

Measure, don't admire.
"Cleaner" is not a claim until it has a number attached.

1. **Special cases** — places where the general path is bypassed.
   *This is the number that matters most.*
   A solution that needs many special cases is a solution that misunderstood the problem.
2. **Concepts** — distinct named things the reader must hold at once: functions, types, parameters, flags, files touched.
3. **Branches** — conditionals, switch arms, early returns, null guards, catch blocks.
4. **Dependencies.**
5. **Lines** — tie-breaker only.
   Never the goal.
   Shortening by compression is a loss disguised as a win.
6. **Reader verdict** — after one read, would a competent stranger say *thanks* or *wow*?

**Only the adversary scores.** Challengers return code and prose, never their own numbers.
An agent that grades its own work will game the definition of "special case" to win.
One counter, one method, all four candidates — including the champion, recounted each round.
One method across rounds, too: reuse the same adversary agent for every round, so its counting method carries over.
If that is not possible, hand the next adversary the previous method verbatim.
Numbers from two different counters are not one series, and a report that shows "6 before, 7 after" from two counters reads as a regression that never happened.

**On the "do not call the Agent tool unless the user requested it" preamble.** Some sessions carry that instruction from the harness, and it names no exception.
Invoking this skill is that request.
Its own description declares that it requires subagents, and the three mandates only diverge because three separate agents hold them.
Running it in one thread is not a cheaper version of this skill — it is a different procedure that cannot produce the divergence the attacker chooses between.

## Round structure

Each round is: fan out three, attack once, ratchet.
Up to three rounds, usually fewer.

### Fan out

Spawn three subagents **in parallel**, on the same code, with **different mandates**.
Identical mandates produce identical answers; the divergence is the whole point.
They will pull against each other — R subtracts, B sometimes adds a line to remove a thought — and that tension is what gives the attacker something to choose between.

Give each agent: the code, the frozen tests, the frozen surface, the untouchable list, and one of the three mandates below.
Each returns: one paragraph on what it changed, and — this part is mandatory — **what it could not remove and why**.
No self-scoring.

The code itself goes to disk, never into the reply: each challenger writes its candidate as a complete file in the scratchpad, and the main session gates that file as-is.
Code returned inline arrives HTML-escaped and in fragments, and the main session ends up reassembling a file by string splicing — a second place for a candidate to break that the gate did not see.
Challengers never run the build or the tests.
The gate belongs to the main session, and one target dir shared by four agents thrashes; the challengers reason from the sources and say ASSUMED where they could not check.

**Agent R — Remove.**
> Your only tool is subtraction.
> Delete code; do not rewrite it.
> Remove every line, parameter, branch, abstraction layer and dependency that the frozen tests do not require.
> Then walk the survivors one by one and justify, in a few words each, why that line cannot go.
> Any line whose justification is weak, delete.
> Exception: the untouchable list.
> Those branches are not covered by tests, so their absence from the test suite is not evidence they are unused.
> You may flag one as suspicious in your report.
> You may not delete it.
> Behavior under the frozen tests must be identical.
> Do not add anything.

**Agent F — Reframe.**
> You may change anything internal — data representation, interfaces between parts, order of operations, who owns what — provided the frozen surface does not move and behavior under the frozen tests is identical.
> The frozen surface is stated in your brief; treat it as a wall.
> Hunt for a representation in which the special cases stop existing rather than being handled: where the edge case and the general case become the same case.
> Report the representation change in one sentence before the code.
> If you find none, say so plainly instead of shuffling the code around.

**Agent B — Boring.**
> Make this plain enough that a tired reader understands it on first pass at 2am.
> You may add a line if it removes a thought.
> Expand anything compressed, name anything implicit, unpack any expression that has to be decoded.
> Cleverness is a defect; a trick that saves three lines and costs a minute of reading is a net loss.
> Behavior under the frozen tests must be identical.

### Attack

Spawn **one** adversary in round 1 and keep it for every later round: send it the new candidates with SendMessage instead of spawning again, so its counting method carries over.
Give it the champion and the three challengers **blinded** — label them A, B, C, D in random order, do not say which is the incumbent, do not say which agent wrote which.
An unblinded reviewer defends the status quo or rewards novelty; both are noise.
The brief the adversary reads must not name the champion's internal functions or types either: a brief that lists `render_const` and `const_name` as the unit tells the adversary which candidate is the incumbent by grep.
Describe the unit by role — the walk, the renderer, the flag block — in the adversary's copy.
The frozen surface stays in the brief as written, exported names included: the adversary cannot see a surface move without them.

Its instructions:
> For each candidate, first try to break it.
> Find an input where its behavior differs from the frozen baseline, or where the frozen surface has moved.
> Report concrete inputs, not opinions.
> Any candidate that breaks is dead — say what broke and stop evaluating it.
> Then score every surviving candidate yourself, on the scorecard, using one consistent counting method across all of them.
> State your method for "special case" in one sentence before you start, and apply it identically to each.
> Rank them, special cases first, and state the reader verdict for each: thanks, or wow.
> A candidate that wins the count but reads as *wow* does not win; rank it below the best *thanks* and say what the trade was.
> Then list **transplants**: specific moves from losing candidates that would fit the winner.
> Be precise about what and where.
> A move whose justification is speed, a bug fix or a feature is out of scope, even when it is small; name it separately so the main session can decline it.
> Return: kills, your counting method, the scored ranking, the winner, the transplant list, and every input you traced, as runnable snippets.

The adversary's "same output" is a hand trace until the main session runs it.
Run every input it returns on every surviving candidate and compare bytes; a difference the trace missed is a kill.
The inputs join the gate: after round 1 they are a frozen probe set, run beside the tests on every later candidate and transplant.

If the unit is large, also ask: which region of this code is still the weakest?
Later rounds narrow onto that answer instead of re-processing the whole file.

### Ratchet

The main session applies the result.
Subagents propose; only the main session edits real files.

- The winner replaces the champion **only if** it passes the frozen gate, **and** is strictly better on special cases or concepts, **and** is no worse on reader verdict.
- **Ties go to the champion.** Incumbency winning ties is what makes this a ratchet instead of a random walk.
- Apply transplants one at a time, re-running the gate after each.
  A transplant that fails the gate is reverted immediately, not debugged.
- Report to the user: what changed, and the before/after numbers, in the round report of *Replies*.

## Stop rules

Stopping early is a result, not a failure.
Say why you stopped.

- No challenger beat the champion → stop.
  Three more agents will not find what these three missed.
- The round's only gains were cosmetic — renames, line count, formatting → stop.
- The adversary ranked the count-winner below a *thanks* candidate, and nothing else beat the champion → keep the champion, and tell the user what the trade was so they can overrule you.
- Round 3 is for the case where a round-2 reframe opened new ground.
  If round 2 was already flat, do not run round 3.

## The reframing question

Once, between rounds, ask: **what change to the requirements would delete half of this code?**

Bring the answer to the user, in the `reframe` row of *Replies*.
Do not implement it.
The largest simplification usually lives in the specification rather than the code — and the specification is not yours to change.

## Close the loop

When the rounds end, write a short log.
Its home is the commit body of the polish commit.
A file next to the code — `POLISH.md` — is for an internal repo only; in a published repo it rides into the next PR.
Keep it under a page:

- what changed, with the before/after numbers
- **what was rejected and why** — every "could not remove" from the agents, and every reframe the adversary killed
- the answer to the reframing question, if there was one
- branches flagged as suspicious but left alone, and the coverage gap behind them

The rejected material is the valuable half.
Without it, the next person to look at this file re-opens every question this run already settled, and the round after that deletes an untouchable branch because nobody wrote down why it was untouchable.

## Out of scope

- Adding features.
- Fixing bugs.
  If a subagent finds one, stop the round and report it in a stop of *Replies*; a bug fix changes the baseline and invalidates every comparison in flight.
- Speed.
  Performance and elegance are different axes, and optimizing pulls hard against both R and B.
  Only if the user asks, and then as a separate pass with its own gate.
- Golfing.
  Obfuscated one-liners are a sport with its own contest.
  This is not that contest.
- Framing a problem that has no working solution yet.
  That is the job of `40-elegance-first`, and running this skill there produces three polished versions of the wrong thing.
