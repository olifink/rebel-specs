# 06 — Environments Specification

**Draft.** See `00-OVERVIEW.md` for normative-language definitions and
suite scope. Nothing here is implemented on any reference target yet.
The rest of the suite already carries what this document needs from
it; §11 says where.

## 1. Purpose and scope

A Rebel machine boots into the Forth prompt. This document specifies
how other interactive programs — a BASIC, the MEMO full-screen editor,
whatever comes later — take over the screen and keyboard as peers of
that prompt, and how the operator moves between them.

Such a program is an **environment**. This document defines:

- What an environment is, and what the machine keeps on its behalf.
- The one change to the native driving loop that makes environments
  possible.
- The switch procedure, including what happens to the screen.
- Where an uncaught error lands while an environment is active.

It does not specify:

- Any particular environment. BASIC and MEMO each get their own
  document; this one is the contract they are both written against.
- How an environment's Forth source reaches the machine (§9).
- Concurrency. Exactly one environment runs at a time (§3.2).

## 2. Design constraints

These follow from decisions already settled elsewhere in the suite and
shape everything below.

- **One execution engine.** An environment is Forth code run by the
  same token-threaded inner loop as everything else
  (`04-FORTH-CORE.md` §4). There is no second interpreter, no second
  suspension contract, and no second set of HAL bindings. An
  environment that implements another language does so by compiling to,
  or interpreting on top of, Forth words.
- **One arena.** Environments share one arena's dictionary, stacks, and
  sysvars. They are not arenas (`02-MEMORY-MODEL.md` §6): an arena is a
  separate machine, an environment is a program on this one. The two
  are orthogonal — each arena has its own environment state — and
  nothing here depends on multi-arena support existing.
- **State lives in banks.** An environment keeps everything it wants to
  survive a switch in banks it owns. This is what makes switching cheap
  (§6) and what gets an environment's documents and programs saved,
  restored, and moved between targets by the existing project pipeline
  (`01-HAL.md` §6) with no new mechanism.
- **Minimum native mechanism.** The native surface added is two sysvar
  cells and one branch in the driving loop (§5). Everything else is
  portable Forth source.

## 3. Model

### 3.1 What an environment is

An environment is four things:

1. **A step word** — an ordinary Forth word with stack effect
   `( -- )`, called by the driving loop once per top-level iteration
   while the environment is active (§5). It is the environment's
   counterpart to "read a line and `INTERPRET` it."
2. **A name** — the dictionary word, created by `ENVIRONMENT` (§4),
   that switches into it.
3. **A saved screen** — one slot of the `ESCR` bank, holding the text
   screen as the environment last left it (§7). Claimed by
   `ENVIRONMENT` and maintained by the switch procedure, not by the
   environment.
4. **Its own banks**, as many as it needs, of whatever tags its own
   document defines. Opaque to this specification.

The Forth prompt is itself an environment in every respect but one: it
has no step word, because its top-level iteration is the native driving
loop's own (`04-FORTH-CORE.md` §5.6). It is called the **home**
environment, and it is the one environment that always exists.

### 3.2 One active environment

Exactly one environment is **active** at any moment. Every other
environment is **dormant**: none of its code is running, it has no
live stack frames, and it is nothing but its banks and its dictionary
entries. There is no suspended-mid-execution state to preserve, which
is why a switch can discard both stacks outright (§6).

### 3.3 What is shared

Everything not listed in §3.1 is shared and is **not** saved or
restored by a switch:

- The dictionary, and with it `CONTEXT`/`CURRENT`, `BASE`, and `STATE`.
  Environments can call each other's words and any Forth word; this is
  the whole interop story, and it needs no mechanism. The cost is that
  an environment which changes `BASE` or the search order and then
  switches away leaves the change behind — see §10.
- The bound input channel (`01-HAL.md` §5). Every environment reads
  keys through the same `KEY`/`KEY?`, so a remote channel drives BASIC
  or MEMO exactly as it drives the Forth prompt.
- The framebuffer's pixel content. Only the character grid is saved
  (§7.3).

## 4. Defining an environment

```forth
' MEMO-STEP ENVIRONMENT MEMO
```

`ENVIRONMENT` — `( xt "name" -- )`, a bootstrap-layer library word
(`04-FORTH-CORE.md` §7.2). Creates a dictionary word `name` holding an
**environment record**, and claims that environment's saved-screen
slot (§7.1). Executing `name` later switches into the environment
(§6).

`name` **MUST** be at most 8 characters, because it is stored in the
slot's 8-byte name field (§7.2). `ENVIRONMENT` **MUST** `ABORT` if the
name is longer, or if no slot is free.

The record is two cells in the word's body:

| Cell | Field | Meaning |
|---|---|---|
| 0 | step xt | The step word. `0` only in the home record. |
| 1 | slot | Address of this environment's slot in the `ESCR` bank. |

The bootstrap layer **MUST** define the home record itself, under the
name `HOME` (tentative — §10), with a step xt of `0`. Executing `HOME`
from any environment returns to the Forth prompt.

## 5. The driving loop

### 5.1 Sysvar contract — `ENV` group

Field meanings are fixed here; byte offsets are `03-SYSVARS.md`'s to
assign (§11).

| Field | Meaning |
|---|---|
| `ENV-ENTRY` | Step xt of the active environment, or `0` when the home environment is active. Fresh-boot value `0`. **The only field the native driving loop branches on.** |
| `ENV-REASON` | Why the next step call is happening (below). Written by the driving loop and the switch procedure, read and cleared by the step word. Meaningless while `ENV-ENTRY` is `0`. |
| `ENV-CURRENT` | Address of the active environment's record. Used only by portable code; the native layer never reads it. Set to the home record by the bootstrap layer. |

`ENV-REASON` values:

| Value | Name | Meaning |
|---|---|---|
| 0 | `ENV-STEP` | Ordinary repeat: the previous step call returned normally. |
| 1 | `ENV-ENTER` | First call after a switch into this environment. |
| 2 | `ENV-RECOVER` | First call after control was thrown back to top level — by `WARM`, `ABORT`, or any uncaught error. |

### 5.2 Required native behavior

`04-FORTH-CORE.md` §5.6 reduces a target's driving loop to: read a
line, reset the input cursor, call `INTERPRET`, repeat. That becomes:

```
forever:
    if ENV-ENTRY = 0:
        read a line, reset the input cursor, INTERPRET     (unchanged)
    else:
        EXECUTE the word at ENV-ENTRY
```

and the existing recovery path — the one that already runs after
`WARM`, `ABORT`, or an uncaught error, clearing both stacks and rolling
back a half-built definition (`04-FORTH-CORE.md` §5.5, §6.12, §8) —
gains one step at its end:

```
    if ENV-REASON = ENV-STEP:  ENV-REASON := ENV-RECOVER
```

The comparison matters: a switch (§6) sets `ENV-ENTER` and then calls
`WARM`, and the recovery path **MUST NOT** overwrite that.

That is the whole native change. In particular:

- The step word is executed through the ordinary threading loop, so it
  suspends at a blocking `KEY` exactly as any Forth word does
  (`04-FORTH-CORE.md` §4.4). No new suspension point exists.
- The return stack is empty when a step word is entered. The data stack
  is whatever the previous step left, as it is between Forth lines; a
  step word **SHOULD** be stack-neutral.
- A step word that returns is simply called again. One that loops
  forever internally is equally valid, since `WARM` can unwind it.
- Error reporting is unchanged: an uncaught error is still reported
  through `hal_report_error` (`01-HAL.md` §8) before the step word is
  called again.

### 5.3 What a step word does

A step word **MUST** read `ENV-REASON` and store `ENV-STEP` back before
doing anything that could fail, so a failure during its own start-up is
seen as a fresh `ENV-RECOVER` and not a repeat of the same reason.

```forth
: BASIC-STEP  ( -- )
  ENV-REASON @  ENV-STEP ENV-REASON !
  DUP ENV-ENTER   = IF  SHOW-BANNER    THEN
      ENV-RECOVER = IF  REPORT-PENDING THEN
  READ-LINE RUN-LINE ;
```

- On `ENV-ENTER`, the text screen has already been restored (§6); the
  environment redraws anything the character grid does not capture
  (§7.3) and otherwise carries on.
- On `ENV-RECOVER`, both stacks are empty and anything the environment
  was executing is gone. Its banks are intact. It **MUST** return to a
  usable top level of its own — a prompt, a redrawn editor — and
  **MUST NOT** fall back to the Forth prompt as a way of handling the
  error.

### 5.4 Errors inside an environment

The suite has no `THROW`/`CATCH` (`04-FORTH-CORE.md` §8), so an
environment cannot catch an error raised deep inside its own code. The
recovery path gives it the equivalent:

- **For its own errors** (a BASIC syntax error, a division by zero it
  detects itself): record what went wrong in one of its own banks, then
  call `WARM`. `WARM` unwinds silently, with no `hal_report_error`
  call, and the step word reports the recorded error when it is
  re-entered with `ENV-RECOVER`.
- **For engine-level errors** it did not anticipate: `ABORT` reports
  through `hal_report_error` as always, and the step word is re-entered
  with `ENV-RECOVER` and nothing recorded. A full-screen environment
  redraws itself, since the report may have written over its display.

When `THROW`/`CATCH` is eventually designed, an environment may use it
internally; this contract does not change.

## 6. Switching

Executing an `ENVIRONMENT`-defined word performs the switch below. It
is portable Forth source, identical on every target, and **MUST NOT**
be reimplemented natively.

1. **Save the outgoing screen** into the active environment's slot
   (§7.2) and set the slot's *valid* cell `TRUE`.
2. **Repoint**: store the incoming record's address in `ENV-CURRENT`
   and its step xt in `ENV-ENTRY`.
3. **Restore the incoming screen**: if the incoming slot's *valid*
   cell is `TRUE`, restore it (§7.2); otherwise `CLS`.
4. Store `ENV-ENTER` in `ENV-REASON`.
5. **`WARM`.**

Step 5 is what makes a switch a switch and not a nested call. `WARM`
discards both stacks and the rest of the current input line and returns
control to the driving loop (`04-FORTH-CORE.md` §6.12), which then
reads `ENV-ENTRY` afresh. Nothing of the outgoing environment's
execution survives, however deep the call that requested the switch
was, and switching back and forth any number of times leaves no
residue on either stack.

Consequences worth stating:

- **A switch never returns.** Code after a switching word in the same
  definition or on the same input line does not run.
- **Switching to the active environment** is permitted and is a
  restart: its step word is re-entered with `ENV-ENTER`.
- **A switch is always available**, not only at a prompt. Requesting
  one mid-computation abandons the computation, by design; an
  environment that wants to protect unsaved work does so before calling
  the switching word.
- **A switch does not happen while compiling** in the ordinary case: a
  switching word is not `IMMEDIATE`, so inside a definition it is
  compiled, not run. `WARM` leaves `STATE` untouched
  (`04-FORTH-CORE.md` §6.12), so a switch forced from an `IMMEDIATE`
  word mid-definition would carry compile state into the incoming
  environment; that **MUST NOT** be done.

## 7. The saved screen

### 7.1 The `ESCR` bank

All saved screens live in one bank, tag and name **`ESCR`**, per-arena,
created at boot like `CHAR` and `ATTR` (`02-MEMORY-MODEL.md` §4.6). It
holds a 16-byte header and `8` fixed-size slots, one per environment:

```
slot size  = align4(48 + CHAR-COLS × CHAR-ROWS × 2)
bank size  = 16 + 8 × slot size        (rounded up to a size class)
```

| Offset | Size | Contents |
|---|---|---|
| 0 | 4 | Slot count (`8`) |
| 4 | 4 | Slot size in bytes |
| 8 | 8 | Reserved, `0` |
| 16 | 8 × slot size | The slots |

A machine therefore has at most eight environments, home included.
One bank of fixed slots — the shape `PAL` already uses for its 16
palette maps — is chosen over a bank per environment because it needs
no bank creation from Forth source: `ENVIRONMENT` finds its slot with
ordinary memory reads, and nothing in this document depends on a
bank-creation primitive `04-FORTH-CORE.md` does not yet specify.

The bootstrap layer **MUST** write the header and mark every slot free
before defining `HOME`, which then claims slot 0.

**Claiming a slot.** `ENVIRONMENT` scans the slots in order. If one
already carries the environment's name, it adopts that slot as it
stands, saved screen included — which is how an environment reloaded
after `FORGET` gets its screen back. Otherwise it takes the first free
slot, writes the name, and sets *valid* to `FALSE`. A slot is freed
only by zeroing its name field by hand; nothing does so automatically.

### 7.2 Slot layout and procedure

| Offset | Size | Contents |
|---|---|---|
| 0 | 8 | Environment name, ASCII, NUL-padded. All zero = free slot. |
| 8 | 4 | *Valid* — HAL boolean. `FALSE` until the first switch away from this environment has stored a screen. |
| 12 | 4 | Reserved, `0` |
| 16 | 4 | `CURSOR-X` |
| 20 | 4 | `CURSOR-Y` |
| 24 | 4 | `INK` |
| 28 | 4 | `PAPER` |
| 32 | 4 | `CURSOR-VISIBLE` (`0` on a target without the field) |
| 36 | 4 | `PALETTE-BASE` |
| 40 | 8 | Reserved, `0` |
| 48 | `CHAR-COLS × CHAR-ROWS` | Copy of the `CHAR` bank's grid |
| … | `CHAR-COLS × CHAR-ROWS` | Copy of the `ATTR` bank's grid |

**Save** copies the six sysvars and both grids in. **Restore** copies
them back out and then calls `REDRAW` (`01-HAL.md` §3.2's
`redraw_all()`), which repaints the framebuffer from `CHAR` and, when a
palette is active, from `ATTR`. Both grid copies **SHOULD** go through
`hal_mem_copy` (`01-HAL.md` §9).

This is the same repoint-and-redraw idea `02-MEMORY-MODEL.md` §6.2
describes for attaching an arena, done by copying because environments
share one `CHAR` bank where arenas each have their own.

### 7.3 What is not saved

- **Pixel content.** Anything drawn with the pixel or sprite primitives
  (`01-HAL.md` §3.4, §3.8) lives only in the framebuffer and is lost on
  a switch away. An environment that draws graphics redraws them when
  re-entered with `ENV-ENTER`.
- **Palette contents.** `PALETTE-BASE` is saved, the `PAL` bank's maps
  are not. Environments wanting different colors use different map
  slots, which is what the 16 slots are for.
- **The active font.** `FONT-BASE` is left as found.

## 8. Lifecycle

- **`COLD`** resets every sysvar and the bank layout
  (`04-FORTH-CORE.md` §4.6), so `ENV-ENTRY` returns to `0`, every
  environment's dictionary entries and banks are gone, and the reloaded
  bootstrap layer recreates `HOME`. The machine is at the Forth prompt.
- **`FORGET`** of a dormant environment removes its record and code.
  Its banks stay resident and its `ESCR` slot stays claimed; reloading
  the environment adopts the slot again (§7.1). Forgetting the **active**
  environment, or any word its step word depends on, leaves `ENV-ENTRY`
  dangling and **MUST NOT** be done; switch to `HOME` first. This is
  not checked, consistent with `FORGET`'s other documented limits.
- **Project save and restore.** `ENV` sysvars travel with `SYSV`,
  records with `DICT`, and every saved screen in the one `ESCR` asset. A project
  saved with full session state while an environment was active resumes
  in that environment. A project saved with content banks only resumes
  at the Forth prompt with every environment's documents intact.

## 9. Loading

Environments other than `HOME` are **not** part of the bootstrap layer.
They are loaded on demand, and this document does not specify the
delivery mechanism, for the same reason `04-FORTH-CORE.md` §7.1 does
not: a block-resident source loaded with `LOAD`, a cart, or a host file
are all valid. What is fixed is the outcome:

- After loading, exactly one `ENVIRONMENT`-defined word with the
  environment's name exists.
- An environment **SHOULD** define its internal words in a vocabulary
  of its own, leaving only its switching word in `FORTH`.
- Loading **MUST NOT** switch into the environment as a side effect.
  Loading and entering are separate acts.
- Loading twice **SHOULD** be harmless; an environment's source guards
  against redefining itself.

Whether a target is required to be *able* to load any particular
environment is that environment's own document's call. The mechanism in
§4–§7 is **REQUIRED** on every target with a self-hosted outer
interpreter, since it costs almost nothing and its absence would make
every environment non-portable.

## 10. Open questions

- **The name `HOME`.** `FORTH` is taken by the vocabulary. `QUIT` is
  the classic word for "back to the outer interpreter" but classically
  preserves the data stack, which this does not.
- **Shared interpreter state.** `BASE`, `CONTEXT`, and `CURRENT` are
  not saved per environment (§3.3). Saving them in the record is cheap;
  not done until a real collision shows it is needed.
- **A switch hotkey.** A key that switches environments from anywhere
  is attractive, but a key edge arrives through a Type B call-in
  (`01-HAL.md` §4.2), possibly in interrupt context, and cannot call
  `WARM` itself. It needs a pending-switch request that the driving
  loop or `KEY` honors. Not designed.
- **Multiple sessions.** `01-HAL.md` §5.6 allows several sessions
  sharing one arena's sysvars; the `ENV` group is then shared too, and
  one session's switch would move all of them. Undefined until
  concurrent sessions are themselves defined.
- **Listing environments.** No registry exists beyond the dictionary;
  `WORDS` shows them among everything else. A dedicated listing word
  needs a chain through the records that `FORGET` would have to
  maintain.
- **Distinguishing `WARM` from `ABORT` on re-entry.** Both arrive as
  `ENV-RECOVER`. §5.4's recorded-error pattern makes the distinction
  unnecessary so far.

## 11. Where the rest of the suite carries this

| Document | What it holds |
|---|---|
| `03-SYSVARS.md` §12 | The `ENV` group's byte layout: base `0x1C0`, `ENV-ENTRY` (0), `ENV-REASON` (4), `ENV-CURRENT` (8). |
| `04-FORTH-CORE.md` §5.6 | The driving loop's `ENV-ENTRY` branch. |
| `04-FORTH-CORE.md` §6.12, §8 | The recovery path's and `WARM`'s `ENV-REASON` step. |
| `04-FORTH-CORE.md` §7.2 | `ENVIRONMENT`, `HOME`, and the `ENV-STEP`/`ENV-ENTER`/`ENV-RECOVER` constants as bootstrap-layer library words. |
| `02-MEMORY-MODEL.md` §4.6 | The `ESCR` bank tag. |
| `01-HAL.md` §6.3 | The `ESCR` → `.ESC` asset extension. |

## 12. Conformance checklist

| Requirement | § |
|---|---|
| The driving loop executes `ENV-ENTRY` when non-zero, and runs the unchanged Forth line loop when zero | §5.2 |
| The recovery path sets `ENV-REASON` to `ENV-RECOVER` only when it holds `ENV-STEP` | §5.2 |
| `ENVIRONMENT`, the switch procedure, and screen save/restore are portable Forth source, never native | §4, §6, §7 |
| A switch ends in `WARM` and leaves both stacks empty | §6 |
| The `ESCR` bank exists at boot with its header initialized; every environment, including home, holds one named slot in it | §7.1 |
| An active environment recovers to its own top level after any error, never to the Forth prompt | §5.3 |
| Loading an environment does not enter it | §9 |
