# 07 — Floating-Point Wordset Specification

**Draft.** See `00-OVERVIEW.md` for normative-language definitions and
suite scope. Nothing here is implemented on any reference target yet.

## 1. Purpose and scope

This document adds floating-point arithmetic to the Rebel Forth system
as an **optional wordset**: a target either provides every word below
or none of them. It exists because Rebel BASIC needs real numbers, and
it is specified separately from `04-FORTH-CORE.md` because a target
with no use for BASIC has no use for this.

It defines:

- The representation of a float and where it lives (§2).
- The arithmetic rules that make results bit-identical on every target
  (§3).
- The wordset, split into a small native kernel and a portable
  Forth-source layer on the same terms as `04-FORTH-CORE.md` §2.2 (§4,
  §5).
- How a float literal is written in Forth source (§6).

It does not define BASIC's numeric semantics — type suffixes, implicit
conversion, `PRINT` formatting, which results are errors. Those belong
to the BASIC specification, which is built on the words here.

## 2. Representation

**A float is an IEEE 754 binary32 value occupying exactly one cell, on
the ordinary data stack.**

- The cell's 32 bits are the binary32 encoding: bit 31 sign, bits 30–23
  exponent, bits 22–0 fraction. In memory it is little-endian like any
  other cell (`02-MEMORY-MODEL.md` §2).
- There is **no separate float stack** and no float-specific memory
  access. `DUP`, `SWAP`, `>R`, `@`, `!`, `,`, `VARIABLE`, `CONSTANT`
  and every other cell-wide word work on floats unchanged, because to
  them a float is a cell.
- The stack is untyped, as it always was. Nothing records whether a
  cell holds an integer or a float; `1 S>F 1 +` is a legal and
  meaningless program. Keeping track is the programmer's job in Forth
  and the compiler's job in BASIC.
- Stack comments use `r` for a cell holding a float.

`02-MEMORY-MODEL.md` §2 formerly required a separate float stack,
following standard Forth practice. That practice exists because a float
is usually wider than a cell. Here the two are the same width, so a
second stack would buy nothing and cost a new bank, new sysvars, a
duplicate set of stack words, and a second thing for `WARM`, the
suspension contract, and session save/restore to carry. That rule is
reversed there, with a pointer to this section.

One consequence is free: a saved session, a `DATA` bank of floats, or a
BASIC variable area holding floats moves between targets with no
conversion, since the bits mean the same thing everywhere.

## 3. Arithmetic rules

The suite's portability claim — pause a session on one target, resume
it identically on another — holds for floats only if every target
computes the same bits. These rules exist for that and nothing else.

1. **Every KERNEL operation in §4 is correctly rounded** per IEEE 754:
   the result is the exact mathematical result rounded to binary32.
   This is what makes native implementations agree; it is not a
   quality goal.
2. **Rounding is always round-to-nearest, ties-to-even.** There is no
   word to change it.
3. **Subnormal numbers are computed, not flushed to zero.** A target
   whose FPU has a flush-to-zero or denormals-are-zero mode **MUST**
   leave it off.
4. **No wider intermediates and no fused operations.** `F*` followed by
   `F+` rounds twice. A native implementation **MUST NOT** contract
   them into a fused multiply-add or carry extended precision between
   words.
5. **Nothing traps.** Overflow yields an infinity, division of a
   non-zero by zero yields an infinity, an invalid operation yields
   NaN, exactly as IEEE 754 specifies. No float word calls `ABORT`.
   A caller that wants an error tests the result (`FINITE?`, §5).
6. **NaN is canonical.** Any word that returns a NaN **MUST** return
   the single bit pattern `0x7FC00000`. Hosts differ in the NaN
   payloads they generate, and this is the one place IEEE 754 leaves
   results host-dependent.
7. **Signed zero is preserved** as IEEE 754 specifies; `-0.0` and
   `+0.0` compare equal.

Two notes for implementers, neither normative:

- A hosted target whose only native float is binary64 satisfies rule 1
  for `F+`, `F*`, `F/` and `FSQRT` by computing in binary64 and
  rounding the result to binary32. For these four operations the double
  rounding is provably harmless.
- A target with no FPU uses its toolchain's software float library, or
  its own. Either is conformant if it meets rules 1–7.

## 4. KERNEL words

Native on every target that provides this wordset. Each is here under
`04-FORTH-CORE.md` §2.2's rule 4: it is the minimal basis, and its
contract is IEEE 754 itself, so there is nothing a Forth-source
reference definition would add.

| Word | Effect | Notes |
|---|---|---|
| `F+` | `( r1 r2 -- r1+r2 )` | |
| `F*` | `( r1 r2 -- r1×r2 )` | |
| `F/` | `( r1 r2 -- r1÷r2 )` | |
| `FSQRT` | `( r -- √r )` | Correctly rounded. A negative argument gives NaN; `-0.0` gives `-0.0`. |
| `F<` | `( r1 r2 -- flag )` | `FALSE` if either is NaN. |
| `F=` | `( r1 r2 -- flag )` | Numeric equality: `FALSE` if either is NaN, `TRUE` for `-0.0` and `+0.0`. Not a bit comparison; use `=` for that. |
| `S>F` | `( n -- r )` | Signed integer to float, rounded per §3 when `n` has more than 24 significant bits. |
| `F>S` | `( r -- n )` | Truncates toward zero. **Saturates**: a value above the integer range gives `0x7FFFFFFF`, below it `0x80000000`, NaN gives `0`. |

`F>S`'s out-of-range behavior is spelled out because every host does
something different here by default — undefined behavior in C, modular
wrap in JavaScript — and a target **MUST** implement the saturation
explicitly, not inherit its host's.

Flags follow the HAL boolean convention (`TRUE = -1`).

## 5. BOOTSTRAP words

Portable Forth source over §4, loaded with the wordset. As in
`04-FORTH-CORE.md` §2.3, a target **MAY** implement any of these
natively, provided the result is bit-identical to the reference
definition.

### 5.1 Derived arithmetic and tests

| Word | Effect | Definition |
|---|---|---|
| `FNEGATE` | `( r -- -r )` | Flip bit 31. `: FNEGATE SIGN-BIT XOR ;` with `SIGN-BIT` the cell `0x80000000`. Applies to NaN and zero alike. |
| `FABS` | `( r -- \|r\| )` | Clear bit 31. |
| `F-` | `( r1 r2 -- r1-r2 )` | `: F- FNEGATE F+ ;` — identical to IEEE subtraction for every non-NaN input, and NaN is canonical either way (§3). |
| `F0=` | `( r -- flag )` | `: F0= FABS 0= ;` |
| `F0<` | `( r -- flag )` | `: F0< 0 F< ;` — integer `0` is the bit pattern of `+0.0`. |
| `F>` | `( r1 r2 -- flag )` | `: F> SWAP F< ;` |
| `FMIN` `FMAX` | `( r1 r2 -- r )` | Built on `F<`. If either argument is NaN the result is NaN. |
| `FNAN?` | `( r -- flag )` | `: FNAN? DUP F= 0= ;` |
| `FINITE?` | `( r -- flag )` | `TRUE` unless `r` is an infinity or NaN — exponent field not all ones. The test a caller uses to turn §3 rule 5's silent results into its own errors. |
| `FLOOR` | `( r -- r' )` | Largest integral float not above `r`. Values of magnitude 2²⁴ or more, infinities, and NaN are returned unchanged; the rest go through `F>S`/`S>F` with a one-step downward adjustment for negative non-integers. |
| `FTRUNC` | `( r -- r' )` | As `FLOOR`, rounding toward zero. |

### 5.2 Elementary functions

| Word | Effect |
|---|---|
| `FSIN` `FCOS` `FTAN` | `( r -- r' )`, argument in radians |
| `FATAN` | `( r -- r' )`, result in radians |
| `FEXP` | `( r -- e^r )` |
| `FLN` | `( r -- ln r )`; NaN for a negative argument, negative infinity for zero |
| `F**` | `( r1 r2 -- r1^r2 )` |

**These MUST NOT be implemented by calling the host's math library.**
Unlike §4's operations, IEEE 754 does not require elementary functions
to be correctly rounded, and real libraries differ in the last bits.
Each is therefore defined by **one shared Forth-source reference
definition**, built only from §4 and §5.1, and that source is the
normative definition of the result. Because §4 is bit-identical
everywhere, anything built purely on it is too.

A native version is permitted only if it reproduces the reference
algorithm operation for operation in binary32 under §3's rules — in
practice, a transliteration.

The reference source does not exist yet (§8).

### 5.3 Conversion to and from text

| Word | Effect |
|---|---|
| `>FLOAT` | `( addr len -- r TRUE \| FALSE )` — parses decimal text: optional sign, digits with an optional decimal point, optional `E` exponent with optional sign. Always decimal, regardless of `BASE`. Leaves only `FALSE` if the text is not a number in that form. |
| `(F.)` | `( r -- addr len )` — formats `r` as decimal text in the scratch area (`PAD`). |
| `F.` | `( r -- )` — `(F.) TYPE SPACE`. |

Like §5.2, these are defined by shared Forth source, for the same
reason: a host's own number parsing and printing differ in rounding
and in format.

`(F.)` produces the format `08-BASIC.md` §8.3 specifies for a float: at
most 7 significant digits, trailing zeros removed, exponent form at
`1E+7` and above or below `1E-5`. An infinity prints as `INF` or
`-INF`, NaN as `NAN`. The precision `>FLOAT` guarantees is still open
(§8).

## 6. Float literals

The outer interpreter is **unchanged**. `NUMBER` (`04-FORTH-CORE.md`
§5.4, §6.13) still recognizes integers only, and a token such as `1.5`
is still an unrecognized word.

A float literal is written with a parsing word:

```forth
F# 1.5  F# 2  F*  F.
: HALF  ( r -- r/2 )  F# 0.5 F* ;
```

`F#` — `( "number" -- r )`, **BOOTSTRAP, `IMMEDIATE`**, dual-mode on
`STATE` exactly as `BANK@` is (`02-MEMORY-MODEL.md` §4.7): it takes the
next token with `WORD`, converts it with `>FLOAT`, and either pushes
the cell or compiles it as a `LIT`. A token `>FLOAT` rejects is an
`ABORT`.

This costs Forth source some convenience and keeps the wordset
genuinely optional: nothing in the bootstrap core changes when it is
absent, and no existing token changes meaning when it is present.
BASIC is unaffected, since its compiler parses its own literals and
calls `>FLOAT` directly.

## 7. Presence and loading

- **All or nothing.** A target provides every word in §4–§6 or none.
  As with optional sysvar fields (`03-SYSVARS.md` §2), presence is the
  capability signal: Forth source asks whether `F+` is defined.
- **Delivery is the target's choice.** The §4 words are native, so they
  are part of the target's build. The §5–§6 source may be loaded at
  boot with the bootstrap layer or on demand, the same latitude
  `04-FORTH-CORE.md` §7.1 and `06-ENVIRONMENTS.md` §9 give.
- **`COLD`** removes the Forth-source layer along with everything else
  in the dictionary; a target that loads it at boot reloads it.
- The words go in the `FORTH` vocabulary. None of them collides with a
  word `04-FORTH-CORE.md` defines.

## 8. Open questions

- **The elementary-function reference source** (§5.2) has to be
  written, and choosing its algorithms is real work: range reduction
  for `FSIN`/`FCOS`, and how much accuracy to buy with how many
  operations. Until it exists, those seven words have a contract and no
  definition.
- **`>FLOAT` precision** (§5.3). Whether parsing is correctly rounded
  for all inputs or only up to some digit count. Seven-digit printing
  does not round-trip every float, so a value printed and read back
  may differ in its last bits whatever is decided here.
- **`F**` with integer exponents.** BASIC handles the common case
  itself, by repeated multiplication when the exponent is an integer
  (`08-BASIC.md` §5). Whether `F**` should also special-case integral
  float exponents is undecided.
- **Float literals in the outer interpreter.** If `F#` proves too
  awkward in practice, `NUMBER` could fall back to `>FLOAT` for tokens
  containing a decimal point while `BASE` is ten. Deliberately not done
  now (§6).
- **Degrees.** No degree-mode switch or conversion words are defined;
  BASIC can supply its own.

## 9. Conformance checklist

| Requirement | § |
|---|---|
| The wordset is present in full or absent in full | §7 |
| A float is one binary32 cell on the data stack; no separate float stack exists | §2 |
| §4's operations are correctly rounded, round-to-nearest-even, with subnormals, no fused or extended-precision intermediates | §3 |
| No float word traps or calls `ABORT`; every NaN returned is `0x7FC00000` | §3 |
| `F>S` truncates toward zero and saturates; NaN gives `0` | §4 |
| §5.2 and §5.3 are computed by the shared Forth-source definitions or a bit-identical transliteration, never by a host library | §5.2, §5.3 |
| `NUMBER` and `INTERPRET` are unchanged; float literals enter through `F#` | §6 |
