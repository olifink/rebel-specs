# 00 — Overview: Rebel Machine Specification Suite

**Version 1.1.** Every document in the suite is at version 1.1, its
current state. A document still marked *draft* is specified but not
yet implemented on any reference target.

## 1. What this is

This directory is a portable, implementation-independent technical
specification for the **Rebel machine**: a token-threaded Forth engine
plus the memory model, sysvar contract, and hardware abstraction
boundary it depends on, and the system built on top of it — a way for
other interactive programs to take over the machine, a floating-point
wordset, Rebel BASIC, the MEMO editor, and the data formats they share.
It is written to be implementable **from this suite alone**, by an
engineer or coding agent with no access to any existing Rebel-family
codebase (browser simulator or bare-metal firmware).

Two concrete reference implementations already exist and independently
validate the decisions recorded here — a browser-based TypeScript
simulator (ahead on the interpreter/dictionary/primitive set) and a
bare-metal ARM firmware project (ahead on the hardware substrate: screen,
keyboard, storage, memory, scheduling). Where this suite states a rule as
settled, it is because both of those independent implementations already
converge on it, or because a real divergence between them was resolved
here in favor of one side, explicitly and with reasoning. Neither
reference implementation's source is required to read or implement
against this suite, and neither is authoritative over it — **this suite
is authoritative going forward**; an existing implementation that
diverges from it is non-conformant and needs updating, not the reverse.

## 2. Audience

Coding agents and engineers implementing a new Rebel-family target:

- A portable C/C++ implementation, buildable for any bare-metal or
  hosted target.
- A hand-optimized assembly implementation for a specific core (e.g.
  RP2350's Hazard3 RISC-V or Cortex-M33 cores) built directly against
  this suite rather than by transliterating the C/C++ implementation.

This suite is deliberately **generic**: it names no specific CPU,
board, toolchain, or vendor SDK. Anything target-specific belongs in a
target's own porting notes, not here.

## 3. Document index

The suite has four parts. Read the core first; everything else is
built on it and leaves it unchanged except where a document says so.

### 3.1 The core

What every conformant target implements.

| # | Document | Status | Covers |
|---|---|---|---|
| 01 | [`01-HAL.md`](01-HAL.md) | **v1.1** | The hardware abstraction boundary: screen (text, pixels, sprite blit), keyboard and the input-channel abstraction, storage and project files, memory block operations, timing, error reporting. What every target must supply, and what is portable and must never be reimplemented per target. |
| 02 | [`02-MEMORY-MODEL.md`](02-MEMORY-MODEL.md) | **v1.1** | The cell, the flat per-arena address space, banks and their size classes, the arena-resident bank table (`MMAP`), resizing and removing banks, multi-arena isolation. |
| 03 | [`03-SYSVARS.md`](03-SYSVARS.md) | **v1.1** | The `SYSV` bank's header, its grouped layout and per-field byte offsets, the naming convention, and the field-presence-signals-capability rule. |
| 04 | [`04-FORTH-CORE.md`](04-FORTH-CORE.md) | **v1.1** | Dictionary header, token-threaded dispatch, the outer interpreter and driving loop, the primitive catalog (KERNEL vs. BOOTSTRAP) including the bank, raw-key and `EVALUATE` words, the bootstrap Forth-source layer, the error model. |

### 3.2 The system layer

Built on the core. All draft: specified, not yet implemented on any
reference target.

| # | Document | Status | Covers |
|---|---|---|---|
| 06 | [`06-ENVIRONMENTS.md`](06-ENVIRONMENTS.md) | **v1.1**, draft | How interactive programs other than the Forth prompt take over screen and keyboard as its peers: the environment record, the driving loop's one added branch, switching, per-environment saved screens, error recovery. **Required** on any target with a self-hosted outer interpreter. |
| 07 | [`07-FLOATING-POINT.md`](07-FLOATING-POINT.md) | **v1.1**, draft | An optional floating-point wordset: IEEE 754 binary32 in one cell on the data stack, the rules that keep results bit-identical across targets, eight native words, and everything else in portable Forth. |
| 07 | [`07-FLOATING-POINT.fth`](07-FLOATING-POINT.fth) | **v1.1**, draft | The normative reference source for `07-FLOATING-POINT.md`'s Forth layer: derived words, elementary functions, text conversion. |
| 08 | [`08-BASIC.md`](08-BASIC.md) | **v1.1**, draft | Rebel BASIC: a Sinclair-flavoured BASIC that runs as an environment and compiles program text to Forth threaded code at `RUN`. Typed by name suffix, optional line numbers and labels, stop/continue debugging, calls into Forth. Loadable; needs `06` and `07`. |
| 09 | [`09-MEMO.md`](09-MEMO.md) | **v1.1**, draft | MEMO: a full-screen, line-centric, overwrite-mode page editor that runs as an environment, where any line can be executed as Forth. Edits its own documents, BASIC programs, and 64 × 16 Forth screens. Defines the page bank format. Loadable; needs `06`. |
| 13 | [`13-GAME-LOOP.md`](13-GAME-LOOP.md) | **v1.1**, draft | How a game runs: an environment whose step word draws one frame, paced by `VSYNC` and a frame counter, reading held keys, drawing sprites and tiles from the active `SPRT` bank, and the `GAME` engine module (entities, render list, collision). Loadable; needs `06`. |

### 3.3 Data formats

Payload formats for particular bank tags, defined independently of any
one program that uses them.

| # | Document | Status | Covers |
|---|---|---|---|
| 10 | [`10-FONT-CODES.md`](10-FONT-CODES.md) | **v1.1** | Which glyph sits at each of the 256 character codes: ASCII, and JIS X 0201 kana in the upper half. |
| 11 | [`11-SPRITE-BANK.md`](11-SPRITE-BANK.md) | **v1.1**, draft | The `SPRT` bank: a 16-color palette and 4-bit-per-pixel entries, blitted freely as sprites or on the character grid as tiles (`01-HAL.md` §3.8). |
| 12 | [`12-WORLD-MAP.md`](12-WORLD-MAP.md) | **v1.1**, draft | Rooms and the world graph for flip-screen games — isometric, top-down, and platform — stored in `DATA` banks. |

### 3.4 Implementation-specific

| # | Document | Status | Covers |
|---|---|---|---|
| 05 | [`05-REMOTE-TRANSPORTS.md`](05-REMOTE-TRANSPORTS.md) | **v1.1**, draft, design-only | Specific to Rebel-Sim, not target-generic, and without RFC 2119 language (see its own §0). A transport contract for the remote-terminal wire protocol, which Rebel-Sim's `REMOTE-TERMINAL.md` defines, and a survey of possible transports. |

## 4. Normative language

This document and every document in this suite use the requirement
levels from RFC 2119:

- **MUST** / **REQUIRED** — an absolute requirement of a conformant
  implementation.
- **MUST NOT** — an absolute prohibition.
- **SHOULD** / **RECOMMENDED** — a strong recommendation; a conformant
  implementation may deviate only for a specific, documented reason,
  and should weigh the consequences.
- **SHOULD NOT** — the inverse.
- **MAY** / **OPTIONAL** — genuinely at the implementer's discretion.

A **conformant target** is one that implements every MUST/REQUIRED item
applicable to it (some are gated by target capability — e.g. a target
with no display is not required to implement graphics draw operations)
and does not violate any MUST NOT.

## 5. Governing design principles

These hold across every document in the suite, not just the HAL one.
Where a specific document restates one, it's for that document's own
readability, not because the rule is local to it:

- **One 32-bit, little-endian cell, everywhere, no exceptions.**
  (Full treatment: `02-MEMORY-MODEL.md`.)
- **Sysvars are the only portable/native boundary.** Forth source reads
  and writes target-specific or subsystem state exclusively through
  `@`/`!` on sysvar cells — never by branching on which target it's
  running on. If a behavior can be expressed as "read a sysvar, act the
  same way everywhere," it belongs in portable Forth source. If it
  genuinely needs different code per target, it belongs behind this HAL
  boundary, not scattered through Forth source with conditionals.
- **Token-threaded dispatch**, not indirect-threaded or subroutine
  models. (Full treatment: `04-FORTH-CORE.md`.) Irrelevant to the HAL
  boundary itself, listed here only because it's a suite-wide
  invariant.
- **HAL boolean convention:** `TRUE = -1` (all bits set at the cell
  width), `FALSE = 0` — never C-style `1`/`0` — for any value that
  ends up on the Forth data stack or in a sysvar cell.
- **Minimum real mechanism, not ahead of need.** This suite documents
  what a conformant implementation must actually provide today. Where a
  plausible future need is visible but not yet load-bearing anywhere
  (e.g. multi-arena management, per-channel-type configuration, bank
  compaction), it is named as an explicit open extension point,
  not designed prematurely and not silently ignored.

## 6. How to read a spec in this suite

Each document distinguishes two kinds of content, called out explicitly
wherever the distinction matters:

- **Portable logic** — behavior that is bit-for-bit identical on every
  conformant target, implemented exactly once against the interfaces
  this suite defines, and never reimplemented, only linked/ported.
- **The per-target boundary** — the actual, minimal set of functions a
  new target must supply, and the entry points target-specific driver
  code must call into the portable layer.

Conflating the two is the most common way an otherwise-careful port
drifts from this specification — duplicating portable logic per target
invites the two copies to diverge over time. Where a document marks
something portable, treat "port it once, share it" as a requirement,
not a suggestion.
