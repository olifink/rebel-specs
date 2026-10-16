# 13 — Game Loop Specification

**Version 1.1, draft, design only.** See `00-OVERVIEW.md` for
normative-language definitions and suite scope. Nothing here is
implemented on any reference target yet. It supersedes Rebel-Sim's
pre-spec `GAME-LOOP.md`, which was written before environments existed
and treated the driving loop, scheduling and pausing as open problems.
§11 lists what the rest of the suite gains when this is implemented. Those
documents are not changed until then.

## 1. Purpose and scope

How a game runs on a Rebel machine: what drives it, what paces it, how
it reads input, and how it draws. The answer is mostly that a game is
an ordinary **environment** (`06-ENVIRONMENTS.md`) whose step word draws
one frame. This document adds the few things that model lacks for
games, and a portable engine layer on top.

It defines:

- The game model, as a use of environments (§2).
- Frame pacing: a frame counter and `VSYNC` (§3).
- A Forth-visible clock (§4).
- Held-key state, alongside the `EKEY` event stream (§5).
- Drawing sprites and tiles from a `SPRT` bank (§6).
- The `GAME` engine module: entities, the render list, collision (§7).
- How a game is delivered and loaded (§8).

It does not specify sound, gamepads, or any particular game.

## 2. A game is an environment

A game defines its step word and switching word exactly as MEMO does
(`06-ENVIRONMENTS.md` §4):

```forth
' INVADERS-STEP ENVIRONMENT INVADERS
```

**The step word is one frame.** The driving loop calls it again each
time it returns (`06-ENVIRONMENTS.md` §5.2), so the driving loop *is*
the game loop. A step word runs the game's logic for one frame, draws
it, and waits for the next frame with `VSYNC` (§3) before returning.

Everything else follows from what environments already guarantee:

- **No stack survives a frame.** A step word is entered with an empty
  return stack and **SHOULD** be stack-neutral (`06-ENVIRONMENTS.md`
  §5.2). Game state lives in banks, never on a stack.
- **Entities are state machines, not tasks.** An entity is a record
  in a bank plus the xt of its update word. The step word calls each
  active entity's update word once per frame, and each call is
  stack-neutral. An entity that needs to "resume where it left off"
  keeps a state value in its record and dispatches on it. There is no
  per-entity stack and no multitasking (§9).
- **Pausing is switching.** Executing `HOME` (or any switching word)
  leaves the game at a step boundary, because a switch ends in `WARM`
  (`06-ENVIRONMENTS.md` §6). The game's banks stay resident: entities,
  render list, score. The user can inspect and poke them at the Forth
  prompt and switch back. Breakpoints (`04-FORTH-CORE.md` §4.5) still
  work inside a frame.
- **Re-entry redraws.** Only the text screen is saved by a switch
  (`06-ENVIRONMENTS.md` §7.3), so on `ENV-ENTER` a game redraws the
  whole frame from its own state.
- **Errors return to the game.** An uncaught error re-enters the step
  word with `ENV-RECOVER`. The game decides what that means, typically
  back to its title screen with its banks intact.
- **Saved projects carry the game.** Its banks are saved with the
  project like any other (`01-HAL.md` §6.3), so a game can be resumed
  on another target exactly where it was left.

## 3. Frame pacing

A step word that returns is called again at once, with nothing tying
it to the display. Games need the display's rhythm.

### 3.1 The frame counter

`FRAME-COUNT`, a new `SCREEN` sysvar (§11), counts display frames
since boot. It wraps at 2^32 like any cell.

A display-capable target **MUST** advance it once per displayed frame
by calling one new Type B entry point:

```c
/* Called by the target once per displayed frame: at vertical blank,
 * on a tearing-effect line, or per host animation frame. May be called
 * from interrupt context, so it only increments FRAME-COUNT and marks
 * that a frame has passed; it never calls into Forth. */
void screen_frame(void);
```

The portable layer owns the counter. The HAL only reports that a frame
happened. A target may skip frames during which nothing can be waiting
on one, such as an idle prompt (`01-HAL.md` §3.9).

### 3.2 `VSYNC`

| Word | Effect | |
|---|---|---|
| `VSYNC` | `( -- )` | **KERNEL** |

Suspends until `FRAME-COUNT` differs from the value it had when
`VSYNC` was called, exactly as `KEY` suspends on the channel
(`04-FORTH-CORE.md` §4.3, §4.4). It is KERNEL for the same reason `KEY`
is: it may suspend.

A target that double-buffers presents the drawn frame at this point.
This is the frame boundary GAME-LOOP's old draft called `FLIP`, so no
separate flip word is defined. A target with no display returns at once.

`VSYNC` is how a game, and anything else, waits a frame. A busy loop
reading `FRAME-COUNT` is legal but wastes the machine.

## 4. Time

`hal_millis` (`01-HAL.md` §7.1) exists, but no Forth word reads it.
Games and BASIC's `PAUSE` (`08-BASIC.md` §16) both need one.

| Word | Effect | |
|---|---|---|
| `MS@` | `( -- n )` — milliseconds since boot, from `hal_millis`. Wraps at 2^32. Compare differences, never absolute values. | **KERNEL** |
| `MS` | `( n -- )` — waits at least `n` milliseconds, calling `VSYNC` while it waits so the machine stays responsive. | BOOTSTRAP |

## 5. Held keys

`KEY` and `EKEY` deliver **events**. A game needs **state**: is Left
held right now? The portable Keyboard Module (`01-HAL.md` §4.3) already
sees every press and release, so it keeps that state.

- **`KEYS-DOWN`**: 256 bits in the `KEYBOARD` sysvar group (§11), one
  per usage code. Bit *u* is set while key *u* is held. The modifier
  pseudo-codes `0x80`–`0x87` are included, so Shift is a held key like
  any other.
- The module updates it on every raw event, **before** queueing the
  event. Reading a key with `KEY` or `EKEY` never changes it.
- The bits are cleared at boot, and by `COLD`. A key released while
  focus was elsewhere is the host's to report as a release.

| Word | Effect | |
|---|---|---|
| `KEY-DOWN?` | `( usage -- flag )` — `TRUE` while that key is held. | BOOTSTRAP: a bit test on `KEYS-DOWN` |

Auto-repeat (`01-HAL.md` §4.3) adds repeated presses to the event
stream while a key is held, marked by bit 24 of `EKEY`'s event, and
never touches `KEYS-DOWN`. A game that wants no repeats stores `0` in
`REPEAT-DELAY` when it starts.

Event reading and state reading coexist. A game reads `KEY-DOWN?` for
movement, and `EKEY?`/`EKEY` for one-shot actions like pausing. Events
it never reads pile up in the queue and are dropped when it fills, so a
game that only polls state **SHOULD** drain the queue once per frame.

## 6. Sprites and tiles

### 6.1 The active sprite bank

`SPRITE-BASE`, the first field of the reserved `SPRITE` sysvar group
(§11), holds the base address of the active `SPRT` bank. `0` means none.
It is the same pattern as `FONT-BASE` and `PALETTE-BASE`. Making a bank
active is an ordinary store:

```forth
BANK@ SHIPS SPRITE-BASE !
```

This also closes `12-WORLD-MAP.md`'s open gap: a room's tile indices
resolve against the active sprite bank.

### 6.2 Words

| Word | Effect | |
|---|---|---|
| `SPRITE` | `( x y n -- )` — draws entry `n` of the active sprite bank with its top-left corner at pixel `(x, y)`, through `hal_blit_sprite` (`01-HAL.md` §3.8). Clipped by the HAL; index 0 transparent; the entry's own flip flags apply. | **KERNEL** |
| `TILE` | `( col row n -- )` — the same at character cell `(col, row)`: `SPRITE` at `(col × CHAR-CELL-W, row × CHAR-CELL-H)`. | BOOTSTRAP |

`SPRITE` is KERNEL because it hands the HAL a resolved byte span
(`01-HAL.md` §2.1), which Forth cannot form. The portable work that
`01-HAL.md` §3.8 assigns to the portable layer happens inside it:
finding the entry, bounds-checking `n`, and producing the palette. That
includes the offset cache (`11-SPRITE-BANK.md`), optional and never
stale (`11-SPRITE-BANK.md`), so no separate `BUILD-BANK` word is needed. An
`n` out of range draws nothing. With no active bank, `SPRITE` does
nothing.

These replace the tentative `SPRITE!`/`TILE!` names in
`11-SPRITE-BANK.md`. Drawing is framebuffer-only, exactly as §3.8
specifies: a `TILE` over text is erased by the next redraw of that cell.

## 7. The `GAME` engine module

Portable Forth, loaded with `NEEDS GAME` (`04-FORTH-CORE.md` §6.16).
It is a convenience, not a requirement: a game may use §3–§6 directly.
Word names below are proposals.

### 7.1 Entities

An **entity table** is one bank: a header, then fixed-size records.
Each record holds an active flag, the xt of its update word, and
entity-specific data the game lays out itself.

- `ENTITIES ( -- )`, run once per frame, calls the update word of
  every active entity in table order, each with the record's address
  on the stack: `( record -- )`.
- An update word may deactivate its own record, or activate a free
  one: spawning a bullet is filling a free record.

### 7.2 The render list

Kept separate from the entity table, as in the old draft: not every
entity draws (a timer, a trigger), and some draw several sprites (a
boss, a shadow). A **render list** is one bank of fixed-size slots:

| Field | Meaning |
|---|---|
| `flags` | Active, h-flip, v-flip, layer. |
| `x`, `y` | Pixel position. |
| `entry` | Index into the active sprite bank. |

An entity moves its sprite by writing its slot: a plain store, never a
draw call. `RENDER ( -- )`, run once per frame after `ENTITIES` and
before `VSYNC`:

1. Restores the background, by default a full redraw: `CLS` or the
   current room's tiles (`12-WORLD-MAP.md`).
2. Draws every active slot, in layer order, with `SPRITE`.

Full redraw is the default because it is simple and always correct. A
dirty-rectangle variant, restoring only where slots were last frame, is
a performance option a game may substitute. The slot layout supports
both.

### 7.3 Collision

`OVERLAP? ( x1 y1 w1 h1 x2 y2 w2 h2 -- flag )`: axis-aligned bounding
box overlap. It is general-purpose and belongs to the module, not to
sprites. Entities test what they need as part of their own update.
Collisions are not stored.

### 7.4 A frame, put together

```forth
: INVADERS-STEP ( -- )
  ENV-REASON @  ENV-STEP ENV-REASON !
  ENV-STEP = 0= IF  REDRAW-ALL  THEN   \ entered or recovered
  ENTITIES  RENDER  VSYNC ;
```

## 8. Delivery

- **A game is a source module.** `NEEDS INVADERS` loads `invaders.fth`,
  which begins with `NEEDS GAME`, defines its words in a vocabulary of
  its own, and ends with its `ENVIRONMENT` line. `INVADERS` then
  starts it. Loading never enters it (`06-ENVIRONMENTS.md` §9).
- **Assets are banks**: sprite sheets (`SPRT`), world maps (`DATA`,
  `12-WORLD-MAP.md`), tables. They are created or loaded by the module,
  or come from the project (`BANK-LOAD`).
- **Writing a game on the machine itself** happens in MEMO. MEMO needs
  one addition for that, already among its open questions
  (`09-MEMO.md` §10): `MEMO-LOAD name` interprets a document's pages as
  Forth source, line by line, as `EVALUATE-LINES` does. Then a game is
  written in MEMO, run with `MEMO-LOAD`, and saved with the project.
- **Carts** (`01-HAL.md` §6.3's `CART`) are the natural packaging for a
  finished game, its module and assets together. They are not designed
  yet.

## 9. Explicitly deferred

- **True multitasking**: per-entity stacks, `PAUSE`-style task
  switching. It would extend `02-MEMORY-MODEL.md` and `03-SYSVARS.md`
  with several stack pairs. Not needed while entities are state
  machines (§2).
- **Interrupt-driven logic**: running game code from the frame
  interrupt. `screen_frame()` deliberately never calls Forth.
- **Multi-core distribution**: rendering on one core, logic on another.
- **Sound, gamepads.** A gamepad is likely a second source of
  `KEYS-DOWN`-style state. Not designed.
- **Animation**: frame advance is an entity choosing a different
  `entry` for its slot, not a property of the render list or the bank.

## 10. Open questions

- ~~**The sprite bank's entry count.**~~ Resolved in
  `11-SPRITE-BANK.md`: an 8-byte header (`'S','P'`, version, entry
  count) now precedes the palette.
- **Layer order** in the render list: how many layers, and whether
  isometric depth sorting (`12-WORLD-MAP.md`) is `RENDER`'s job or the
  game's.
- **Frame rate.** `VSYNC` paces to the display, which may be 50, 60 or
  more Hz. Whether games need a fixed logic rate is open, and so is
  whether that is `FRAME-COUNT` arithmetic in the game or a module word.
- **Draining the event queue** (§5): whether `VSYNC` should do it for a
  game that only reads state, or whether that stays the game's job.

## 11. Where the rest of the suite will carry this

Each lands with the implementation. Rows marked **Done** have landed.

| Document | Change |
|---|---|
| `01-HAL.md` §3.9 | **Done:** `screen_frame()`, a Type B entry point, and `FRAME-COUNT`'s meaning. |
| `01-HAL.md` §4.3 | **Done:** the Keyboard Module maintains `KEYS-DOWN`. |
| `03-SYSVARS.md` §6 | **Done:** `SCREEN` offset 40, `FRAME-COUNT`. |
| `03-SYSVARS.md` §7 | **Done:** `KEYBOARD` offsets 8–39, `KEYS-DOWN`, 256 bits as 8 cells. |
| `03-SYSVARS.md` §9 | **Done:** `SPRITE` offset 0, `SPRITE-BASE`. The group stops being reserved. |
| `04-FORTH-CORE.md` §6.17 | **Done:** `VSYNC`, `MS@`, `SPRITE` (KERNEL); `MS`, `KEY-DOWN?`, `TILE` (BOOTSTRAP). |
| `09-MEMO.md` §7 | `MEMO-LOAD`. |
| `11-SPRITE-BANK.md` | **Done:** `SPRITE`/`TILE` replace `SPRITE!`/`TILE!`; the entry-count header; an offset cache optional and never stale. |
| `12-WORLD-MAP.md` | **Done:** tile indices resolve against `SPRITE-BASE`; the open gap is closed. |

## 12. Conformance checklist

| Requirement | § |
|---|---|
| A display-capable target advances `FRAME-COUNT` once per displayed frame, via `screen_frame()` | §3.1 |
| `VSYNC` suspends as `KEY` does until `FRAME-COUNT` changes | §3.2 |
| `MS@` reads `hal_millis`; `MS` waits by calling `VSYNC` | §4 |
| `KEYS-DOWN` tracks every held key, modifiers included, and is updated before the event is queued | §5 |
| `SPRITE` draws from the bank at `SPRITE-BASE` through `hal_blit_sprite`, drawing nothing for a bad index or no bank | §6 |
| A game is an environment whose step word draws one frame and is stack-neutral; its state lives in banks | §2 |
