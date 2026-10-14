# 08 — Rebel BASIC Specification

**Version 1.1, draft.** See `00-OVERVIEW.md` for normative-language definitions and
suite scope. Nothing here is implemented on any reference target yet.

## 1. Purpose and scope

Rebel BASIC is a Sinclair-flavoured BASIC for the Rebel machine. It is
an **environment** (`06-ENVIRONMENTS.md`): loaded on demand, entered by
typing `BASIC` at the Forth prompt, and written entirely in portable
Forth source, so every conformant target that can load it runs the same
BASIC.

It descends from an earlier stand-alone prototype (a line-numbered,
double-precision, tokenized-line interpreter written in C). This
document keeps that prototype's language feel and report style and
changes its machinery to fit the Rebel machine. It is not a
compatibility specification for the prototype; §15 lists what changed.

This document defines the language, its runtime model, and how it uses
the rest of the suite. It does not define a full-screen program editor
(that is MEMO's job, §3.5) or graphics, sprite, and sound statements
(§12, §16).

## 2. Architecture

### 2.1 The shape

```
   program bank (text)                 work bank
  +--------------------+    RUN     +--------------------------+
  | 10 LET a% = 0      |  compile   | compiled threaded code   |
  | @loop              | ---------> | label + symbol tables    |
  | PRINT a%           |            | variables, arrays        |
  | ...                |            | string space             |
  +--------------------+            | GOSUB / FOR stacks       |
        ^                           | DATA pool, stop state    |
        | LIST, numbered            +--------------------------+
        | line entry, editor                    |
                                     executed by the ordinary
                                     Forth inner loop
```

- **Source is text.** A program is plain text in a bank, in the same
  page format MEMO edits (§3.1). There is no tokenized line format.
- **`RUN` compiles.** The whole program is translated to token-threaded
  Forth code (`04-FORTH-CORE.md` §4), which the ordinary inner loop
  then executes. There is no second interpreter and no per-statement
  re-parsing at run time. A compiled statement is a run of calls to
  Forth words — runtime words this document's implementation defines,
  plus core and float words directly.
- **Types are static.** A variable's type is fixed by its name's suffix
  (§4), so the compiler picks integer, float, or string code for every
  operation and nothing carries a type tag at run time.
- **All lasting state is in banks.** Between statements the Forth
  stacks hold nothing of a running program (§10.2). This is what makes
  `STOP`/`CONTINUE`, the break key, and switching to another
  environment and back all work.

### 2.2 What it requires

- The environment mechanism (`06-ENVIRONMENTS.md`).
- The floating-point wordset (`07-FLOATING-POINT.md`), in full.
- The name-on-the-stack bank words (`04-FORTH-CORE.md` §6.14).
- The page bank format and the editor hand-over (`09-MEMO.md` §3,
  §9), and the `CURSOR-X`/`CURSOR-Y` sysvar constants (`03-SYSVARS.md`
  §2). §14 confirms nothing else is missing.

### 2.3 Why the compiled code needs no kernel support

Threaded code is cells holding execution tokens, and an execution token
is the address of a Code Field (`04-FORTH-CORE.md` §4.2). The compiler
therefore builds code with ordinary `!` into the work bank: a `DOCOL`
Code Field, then cells holding the xts of `LIT`, `BRANCH`, `0BRANCH`,
and the words to call, obtained once with `'` exactly as the core's own
control-flow layer does (`04-FORTH-CORE.md` §6.5). Nothing is added to
the dictionary per program, and discarding a compiled program is
resetting a pointer.

## 3. Source text

### 3.1 The program bank

A program is one bank, tag **`BAS`**, named for the program (up to 8
characters, `02-MEMORY-MODEL.md` §4.7). Several may be resident; one is
**current** (§9).

It is a **page bank** (`09-MEMO.md` §3): a 32-byte header, then pages
of `cols × rows` characters with no line terminators. That document
owns the format; what BASIC adds is how it reads one.

- **A program line is one row of a page**, with trailing spaces
  ignored. Rows are read top to bottom, page after page.
- A line is therefore at most `cols` characters. There is no
  continuation onto the next row (`09-MEMO.md` §10).
- BASIC reads a program of any geometry. It creates programs in the
  current screen's geometry, so that MEMO can edit them.
- BASIC increments the header's `revision` whenever it changes program
  text, and reads it to learn that MEMO has (§10.1).

### 3.2 Lines, statements, labels

```
[<number> | @<name>]  <statement> [ : <statement> ... ]
```

- A line holds one or more statements separated by `:`.
- A line may begin with a **line number**, `1`–`65535`, or a **named
  label**, `@` followed by an identifier. Both are optional. Either
  makes the line a jump target; nothing else about the line changes.
- A label alone on a line is allowed and labels the next statement.
- Line numbers need not ascend and impose no order: **execution order
  is text order**, top to bottom. Duplicate numbers or names are a
  compile error.
- Blank lines are ignored.

### 3.3 Comments

`REM` starts a comment that runs to the end of the line, colons
included.

### 3.4 Case

Everything outside string literals and `REM` text is case-insensitive:
keywords, function names, labels, and variable names alike. `score`,
`Score` and `SCORE` are one variable. Source text is stored as typed
and never rewritten.

### 3.5 Entering and editing a program

Two routes, both writing the same program bank:

- **Numbered-line entry at the prompt.** A line typed at the BASIC
  prompt that begins with a number is not executed; it is stored.
  - If a program line has that number, the typed line replaces it in
    place.
  - Otherwise it goes before the first numbered line with a greater
    number, or after the last non-blank row if there is none. If the
    row just above that spot is blank, the line is written there.
    If not, room is made: the rows from that spot down to the next
    blank row each move down one, across page boundaries, and the
    blank row absorbs the shift. Rows beyond that blank row do not
    move.
  - If there is no blank row before the end of the program, a page is
    added. With the bank at capacity the line is refused with
    `4 Out of memory`.
  - A number with nothing after it blanks that line's row. Nothing
    moves to close the gap.
  - A typed line longer than `cols` is refused with
    `C Nonsense in BASIC`.
- **The editor.** `EDIT` lends the current program to MEMO as
  `09-MEMO.md` §9 describes: it opens the program there and switches
  to it. Typing `BASIC` in MEMO returns. On a machine without MEMO
  loaded, `EDIT` reports `C Nonsense in BASIC`.

Unnumbered lines are never moved by numbered-line entry except as part
of the shift just described, which keeps their order.

Text is not syntax-checked when entered; errors are found when the
program is next compiled.

## 4. Types and values

| Suffix | Type | Representation |
|---|---|---|
| none | Float | IEEE 754 binary32, one cell (`07-FLOATING-POINT.md`) |
| `%` | Integer | 32-bit signed, one cell |
| `$` | String | Byte sequence in string space; two cells (address, length) |

### 4.1 Names

An identifier is a letter followed by letters, digits, or underscores,
then an optional `%` or `$`. `count`, `count%` and `count$` are three
different variables. A scalar and an array may share a name. Keywords
and function names are reserved.

### 4.2 Numbers

- **Floats** carry about seven significant decimal digits and represent
  every integer exactly up to 16,777,216 (2²⁴).
- **Integers** exist for speed: counters, coordinates, subscripts,
  addresses. `+`, `-`, `*` on two integers give an integer and **wrap**
  modulo 2³² without a report.
- **Literals.** A literal with a decimal point or exponent is a float.
  A literal without one is *adaptive*: integer when the other operand
  of its operator is integer-typed, float otherwise. So `a% + 1` is
  integer arithmetic, `7 / 2` is `3.5`, and `100000 * 100000` is the
  float `1E+10`, not a wrapped integer. Integers arise only where a
  `%` name or an integer-valued function is involved.
- **Mixing.** An operator with one integer and one float operand
  converts the integer to float.
- **Assigning a float to an integer** variable takes the floor, as
  `INT` does. A value outside the integer range reports
  `B Integer out of range`.
- **Non-finite results.** Float arithmetic never stops mid-expression
  (`07-FLOATING-POINT.md` §3). When an infinite or NaN value is
  assigned, printed, compared, or converted, the program stops with
  `6 Number too big`. Division by zero is reported this way.
- **Truth.** Comparisons give the integer `1` or `0`. Any non-zero
  value is true.

### 4.3 Strings

- A string is a sequence of 0 or more bytes; its length is limited only
  by string space.
- Literals are written in double quotes; `""` inside a literal is one
  quote character.
- Assignment copies. There are no shared or aliased strings.

### 4.4 Arrays

- `DIM` creates an array of any type with one or more dimensions.
- Subscripts run from `1` to the dimension's size. Anything else
  reports `3 Subscript out of range`.
- A string array is an array of ordinary variable-length strings.
- Using an array before its `DIM` has executed reports
  `2 Variable not found`. Executing `DIM` for an array that already
  exists reports `C Nonsense in BASIC`; `CLEAR` removes it first.

### 4.5 Initial values

After `RUN` or `CLEAR`, every scalar is `0` or the empty string.
Reading a scalar that was never assigned is not an error.

## 5. Expressions

Highest precedence first. Equal levels associate left to right, except
where noted.

| Level | Operators | Notes |
|---|---|---|
| 1 | functions, `( )`, subscripts, slices | |
| 2 | `^` | right to left; result is always float |
| 3 | unary `+` `-` | |
| 4 | `*` `/` `DIV` `MOD` | `/` always gives a float |
| 5 | `+` `-` | `+` also joins strings |
| 6 | `=` `<>` `<` `>` `<=` `>=` | numbers, or strings byte by byte |
| 7 | `NOT` | `1` if the operand is zero, else `0` |
| 8 | `AND` | |
| 9 | `OR` | |

- **`DIV` and `MOD`** convert both operands to integer (by floor) and
  give the integer quotient and remainder. A zero divisor reports
  `6 Number too big`.
- **`^`** with an integer-typed or adaptive-literal exponent is `F**N`
  (`07-FLOATING-POINT.md` §5.2), repeated squaring, so `2 ^ 3` is
  exactly `8`. Otherwise it is `F**`.
- **`AND` and `OR` select, Sinclair style, and evaluate both operands.**
  `a AND b` is `a` if `b` is non-zero, else `0`. `a OR b` is `a` if `a`
  is non-zero, else `b`. If the two operands differ in type the result
  is float.
- **A type error is a compile error**: a string where a number is
  needed, or the reverse, is `C Nonsense in BASIC`.

### 5.1 String slices

`a$(s TO e)` is characters `s` through `e`, counted from 1. Either
bound may be omitted (`a$(s TO)`, `a$(TO e)`); `a$(i)` is the single
character at `i`. If `s > e` the result is empty. Otherwise a bound
below 1 or above the length reports `3 Subscript out of range`. On an
element of a string array, the slice follows the subscripts:
`n$(3)(1 TO 4)`.

## 6. Functions

A function's result type follows its name: `$` for strings, otherwise
as listed.

### 6.1 Numeric

| Function | Result | Meaning | Error |
|---|---|---|---|
| `ABS(x)` | as `x` | Absolute value | |
| `SGN(x)` | integer | `-1`, `0`, or `1` | |
| `INT(x)` | float | Floor: `INT(-3.7)` is `-4` | |
| `SQR(x)` | float | Square root | `x < 0`: `A Invalid argument` |
| `SIN(x)` `COS(x)` `TAN(x)` | float | Radians | |
| `ASN(x)` `ACS(x)` | float | Radians | outside −1…1: `A Invalid argument` |
| `ATN(x)` | float | Radians | |
| `EXP(x)` | float | eˣ | |
| `LN(x)` | float | Natural log | `x <= 0`: `A Invalid argument` |
| `RND` | float | Uniform, `0 <= r < 1` | |
| `PI` | float | π | |

`RND`'s generator is fixed by the reference source, so a seeded
sequence is the same on every target. `RANDOMIZE n` seeds it.

### 6.2 String and conversion

| Function | Result | Meaning | Error |
|---|---|---|---|
| `LEN(s$)` | integer | Length in bytes | |
| `CODE(s$)` | integer | Code of the first character; `0` if empty | |
| `CHR$(n)` | string | One character with code `n` | outside 0…255: `B Integer out of range` |
| `STR$(x)` | string | `x` formatted as `PRINT` would (§8.3) | |
| `VAL(s$)` | float | The number written in `s$` | not a number: `C Nonsense in BASIC` |
| `INKEY$` | string | A waiting key, or empty. Never waits. | |

`VAL` reads a numeric literal, not an expression.

### 6.3 Machine access

| Function | Result | Meaning |
|---|---|---|
| `PEEK(a)` | integer | The byte at arena address `a` |
| `BANK%(n$)` | integer | Base address of the bank named `n$`; `0` if none |
| `USR`, `USR%`, `USR$` | float, integer, string | Call a Forth word (§12) |

## 7. Statements

Every statement works both in a program and typed at the prompt unless
marked *prompt only*.

### 7.1 Assignment and data

| Statement | Meaning |
|---|---|
| `[LET] v = expr` | Assign. `LET` is optional. `v` may be a scalar, an array element, or a string slice. |
| `DIM a(d1 [, d2 …])` | Create an array (§4.4). Dimensions are positive. |
| `DATA item [, item …]` | Literals for `READ`: numbers, or strings, quoted or bare. Skipped when executed. |
| `READ v [, v …]` | Take the next `DATA` items in text order. A string item read into a numeric variable is `C Nonsense in BASIC`. Past the last item: `8 End of DATA`. |
| `RESTORE [target]` | Move the `DATA` pointer to the start, or to the first `DATA` at or after the target line. |
| `RANDOMIZE [n]` | Seed `RND`. |
| `POKE a, v` | Store the low byte of `v` at arena address `a`. |
| `CLEAR` | Erase all variables and arrays, empty the `GOSUB` and `FOR` stacks, and discard any stop state. The program and breakpoints are untouched. |

### 7.2 Control flow

A **target** is a line number, an `@label`, or a numeric expression
evaluated at run time and looked up as a line number. A literal target
that does not exist is a compile error; a computed one reports
`B Integer out of range`.

| Statement | Meaning |
|---|---|
| `GOTO target` | Jump. |
| `GOSUB target` / `RETURN` | Call and return. `RETURN` with nothing to return to: `7 Return without GOSUB`. Nesting beyond the stack: `4 Out of memory`. |
| `IF c THEN stmts [ELSE stmts]` | One-line form. The `THEN` and `ELSE` parts each run to the end of the line or to `ELSE`. `THEN 100` means `THEN GOTO 100`. |
| `IF c THEN` … `[ELSE]` … `END IF` | Block form, chosen when `THEN` ends its line. Blocks nest. |
| `FOR v = a TO b [STEP s]` / `NEXT v` | `v` is a float or integer scalar. The body always runs at least once. `NEXT` adds the step and loops while `v` has not passed `b` in the step's direction. `NEXT` for a variable with no active loop: `1 NEXT without FOR`. |
| `WHILE c` … `WEND` | Test first. |
| `REPEAT` … `UNTIL c` | Test last. |
| `STOP` | Stop with `9 STOP statement`; `CONTINUE` resumes after it. |
| `END` | Finish the program with `0 OK`. Running off the end of the text does the same. |

`FOR`/`NEXT` pair at run time, as in Sinclair BASIC: `NEXT v` finds the
most recent loop on `v`, and a new `FOR` on a variable replaces any
loop already active on it. `IF` blocks, `WHILE`/`WEND` and
`REPEAT`/`UNTIL` pair by position in the text at compile time and keep
no run-time state, so jumping out of one with `GOTO` is harmless.

### 7.3 Screen and keyboard

| Statement | Meaning |
|---|---|
| `PRINT [items]` | See §8.2. |
| `INPUT ["prompt";] v [, v …]` | Show the prompt, read a line, assign. Text that is not a number for a numeric variable asks again. |
| `CLS` | Clear the screen to the current `PAPER`; cursor to the top left. |
| `INK n` / `PAPER n` | Set the permanent colors, `0`–`15` (§8.1). |
| `INVERSE n` | `1` swaps ink and paper for everything printed; `0` restores. |

### 7.4 Running and debugging

| Statement | Meaning |
|---|---|
| `RUN [target]` | `CLEAR`, compile if stale, reset the `DATA` pointer, and start at the top or at the target. |
| `CONTINUE [target]` | *Prompt only.* Resume a stopped program (§10.3), optionally stopping again at the target line. Nothing to resume: `C Nonsense in BASIC`. |
| `BREAK` | In a program: stop here with `9 Breakpoint reached`. |
| `BREAK target [, target …]` | Set breakpoints; the program stops before each such line. |
| `BREAK OFF` | Remove all breakpoints. |
| `VARS` | List every variable and array with its type, size, and value. |
| `LIST [from] [TO [to]]` | Show the program's non-blank lines, or the numbered range. Pauses for a key each screenful. |
| `DELETE from [TO [to]]` | *Prompt only.* Blank the rows of the numbered lines in the range. |
| `EDIT [target]` | *Prompt only.* Open the program in MEMO (§3.5), at the target line if one is given. |
| `EXIT` | Leave BASIC for the Forth prompt (§13). |

Typed at the prompt, `GOTO` and `GOSUB` start the program at the target
**without** clearing variables, compiling first if the program is
stale.

### 7.5 Programs

| Statement | Meaning |
|---|---|
| `NEW` | Reduce the current program to one blank page and `CLEAR`. |
| `NEW "name"` | Make the program of that name current and empty, creating its bank if there is none. No free bank slot or no room: `4 Out of memory`. |
| `LOAD "name"` | Make that program current, loading it from the open project if it is not resident. Implies `CLEAR`. No such program, or a bank of that name that is not a `BAS` bank: `C Nonsense in BASIC`. |
| `SAVE` | Write the current program to the open project. No project open, or the write fails: `C Nonsense in BASIC`. |
| `CAT` | List the resident programs. |
| `CALL "word" [, arg …]` | Call a Forth word (§12). |

## 8. Screen and keyboard model

BASIC draws through the ordinary Screen Module (`01-HAL.md` §3) and
has no display code of its own.

### 8.1 Grid, cursor, colors

- The screen is `CHAR-COLS` × `CHAR-ROWS` character cells; row and
  column count from `0` at the top left.
- **There is no scrolling.** Output past the last row wraps to the top,
  as everywhere on the machine (`01-HAL.md` §3.2).
- Colors are palette indices `0`–`15` (`02-MEMORY-MODEL.md` §4.6). The
  default palette's first eight are the Sinclair colors in Sinclair
  order: black, blue, red, magenta, green, cyan, yellow, white.
- BASIC needs the palette active. On entry it sets `PALETTE-BASE` to
  palette map 0 if it is `0`. Because `PALETTE-BASE` is saved per
  environment (`06-ENVIRONMENTS.md` §7.2), this does not leak into the
  Forth prompt.
- The permanent `INK` and `PAPER` are the `SCREEN` sysvars themselves.
  BASIC keeps no copies.

### 8.2 `PRINT`

Items are expressions, or these position and color items:

| Item | Effect |
|---|---|
| `AT row, col` | Move the cursor. |
| `TAB n` | Move to column `n` of this row, or of the next if already past it. |
| `INK n` `PAPER n` `INVERSE n` | Change the color for the rest of this statement only. |

Separators: `;` prints the next item immediately after; `,` moves to
the next 16-column zone; `'` starts a new line. A statement not ending
in `;` or `,` ends with a new line. Colors set by items revert to the
permanent ones when the statement ends, including when it ends in an
error.

### 8.3 Number format

Used by `PRINT` and `STR$`.

- An integer prints as its decimal digits, with `-` if negative.
- A float prints to at most **7 significant digits**, rounded, with
  trailing zeros and a trailing point removed: `0.1`, `3.5`, `12`,
  `-0.25`.
- A float of magnitude `1E+7` or more, or below `1E-5` and non-zero,
  prints in exponent form: one digit, a point and up to six more
  digits, then `E`, a sign, and at least two exponent digits:
  `1.5E+10`, `6.25E-06`.
- No leading or trailing space is added.

This is the format `(F.)` produces (`07-FLOATING-POINT.md` §5.3).

### 8.4 Keyboard and the break key

All input comes through the bound channel (`01-HAL.md` §5), so a remote
session drives BASIC as the keyboard does.

**Break** is the byte `0x03`, or the letter `C` while a Ctrl modifier
is held (`MODIFIERS`, `01-HAL.md` §4.4). A running program checks for
waiting input at statement boundaries (§10.2), not necessarily at every
one. A waiting break stops the program with `L BREAK into program`. Any
other waiting keys are kept, in order, for `INKEY$` and `INPUT`.

At the prompt, break discards the line being typed.

## 9. Programs and storage

- A program is a `BAS` bank, so it is saved, restored, and moved
  between targets by the ordinary project pipeline (`01-HAL.md` §6) as
  the asset `<name>.BAS`. A project saved from the Forth prompt
  includes every resident program without BASIC being involved.
- `SAVE` and `LOAD` act on single program banks within the open
  project. There are no file names or paths in BASIC.
- A new program bank is created at 16 KiB with `(BANK-CREATE)`
  (`04-FORTH-CORE.md` §6.14), with one blank page, and cannot grow
  within a session: an edit needing a page beyond its capacity is
  refused with `4 Out of memory`.
  `BANK-RESIZE` from the Forth prompt enlarges it for next time: the
  new size applies once the project is saved and restored
  (`02-MEMORY-MODEL.md` §4.8).
- A bank is never removed within a session (`02-MEMORY-MODEL.md`
  §4.9), so every program created keeps its slot until the next cold
  start. `NEW "name"` on an existing program empties and reuses its
  bank. A program is discarded for good with
  `USR%("(BANK-REMOVE)", "name")`, which drops it from the project at the
  next save.
- BASIC starts with a current program named `PROGRAM`, creating it if
  it is not resident.

## 10. Execution model

### 10.1 Compiling

Compilation reads the current program's text once and produces, in the
work bank:

- threaded code for every statement, each preceded by a **statement
  marker** (§10.2);
- a label table mapping line numbers and names to code addresses, with
  forward references patched at the end;
- symbol-table entries for variables not seen before;
- the `DATA` pool.

A program is compiled when it is **stale** and something needs to run
it: `RUN`, or `GOTO`/`GOSUB` from the prompt. It becomes stale whenever
another program is made current, or the program bank's `revision`
(§3.1) differs from the value recorded at the last compile. The second
test covers every way text can change — numbered-line entry, `DELETE`,
MEMO, or a Forth word writing the bank — without BASIC having to be
told.

**Variables survive recompilation.** The symbol table and variable
storage are separate from compiled code, and compiling only adds to
them. Only `CLEAR`, `RUN`, `NEW` and `LOAD` erase variables. This is
what lets a program be edited and restarted with `GOTO` keeping its
data.

A compile error reports `C Nonsense in BASIC` with the line and the
column where the compiler gave up, and leaves the program stale.

A line typed at the prompt without a number is compiled on its own into
a scratch area and run at once, in the same variable space.

### 10.2 Statement boundaries

A statement marker is one call compiled before each statement, carrying
that statement's source position. It:

1. records its own address as the **current position** — where to
   resume, and what to print in a report;
2. stops if a breakpoint is set on this line and this is the line's
   first statement;
3. periodically checks the keyboard for break (§8.4).

**At a marker, neither Forth stack holds anything belonging to the
program.** Expression temporaries are gone, and the `GOSUB` stack and
`FOR` stack are BASIC's own structures in the work bank, not the Forth
return stack. A program's entire state at a statement boundary is
therefore the work bank plus one code address.

### 10.3 Stopping and continuing

Every stop — `STOP`, `BREAK`, a breakpoint, the break key, an error —
is the same act: record the report code and the current position in the
work bank, then `WARM` (`06-ENVIRONMENTS.md` §5.4). BASIC's step word
is re-entered, prints the report, and shows the prompt.

Because of §10.2, nothing is lost by this. `CONTINUE` jumps back into
the compiled code at the recorded position: after the statement for
`STOP` and `BREAK`, at it for a breakpoint or the break key.

A stop state survives everything that leaves the work bank intact —
immediate statements, `VARS`, an error in something typed at the
prompt, even a switch to another environment and back. It is discarded
by `CLEAR`, `RUN`, `NEW`, `LOAD`, by the program becoming stale, and
after an error (a program stopped by an error cannot be continued).

### 10.4 The work bank

One bank, tag **`BASW`**, name `BASIC`, 64 KiB by default. It holds
compiled code, the label and symbol tables, variable and array storage,
string space, the `GOSUB` and `FOR` stacks, the `DATA` pool, pending
keys, breakpoints, and the stop state. How it is divided is the
implementation's business. Exhausting any part reports
`4 Out of memory`.

String space is compacted when it fills; variables and array elements
are the only references into it, so compaction needs no bookkeeping
beyond walking them.

The work bank holds addresses into the dictionary. It is reinitialized
— program stale, variables cleared — whenever BASIC's source is loaded,
so a work bank restored without its matching dictionary is never
trusted.

## 11. Reports

Every command and program ends with a report:

```
<code> <message>[, <line>:<statement>]
```

The position is given when a program statement was executing. `<line>`
is the line's number if it has one, otherwise `#` and its row counted
from 1 at the top of the first page, blank rows included. `<statement>` counts from 1 within the line.
A compile error gives `<line>:<column>`.

| Code | Message | When |
|---|---|---|
| `0` | `OK` | Normal completion |
| `1` | `NEXT without FOR` | `NEXT` with no active loop on that variable |
| `2` | `Variable not found` | An array used before its `DIM` |
| `3` | `Subscript out of range` | Array subscript or slice bound |
| `4` | `Out of memory` | Any part of the work bank, or a program bank, is full |
| `6` | `Number too big` | A non-finite float result; division by zero |
| `7` | `Return without GOSUB` | |
| `8` | `End of DATA` | |
| `9` | `STOP statement` / `Breakpoint reached` | |
| `A` | `Invalid argument` | Function argument outside its domain |
| `B` | `Integer out of range` | A value outside what its use allows; a computed jump to a missing line |
| `C` | `Nonsense in BASIC` | Syntax or type error; a command that makes no sense here |
| `F` | `Forth error` | A called Forth word aborted (§12) |
| `L` | `BREAK into program` | The break key |

## 12. Calling Forth

BASIC reaches everything else on the machine — sprites, banks, sysvars,
storage, other environments — by calling Forth words.

- **`CALL "word" [, arg …]`** calls a word for its effect.
- **`USR("word" [, arg …])`**, **`USR%(…)`**, **`USR$(…)`** call a word
  and take its result: one cell as a float, one cell as an integer, or
  an `addr len` pair copied into a new string.

Rules:

- The word name is a string **literal**, looked up once at compile
  time with the search order then in effect. An unknown word is a
  compile error.
- Arguments are pushed left to right. An integer or float argument is
  one cell, pushed as it is, with no conversion — the caller supplies
  the type the word expects, using `%` expressions for integer cells.
  A string argument is pushed as `addr len`.
- The word must consume its arguments and leave exactly the result the
  form implies. BASIC does not check the stack.
- A word that parses the input line (`BANK@`, `'`, `S"`) cannot be
  called this way.
- If the word aborts, BASIC reports `F Forth error` at the calling
  statement, after whatever the machine itself reported.
- A word that switches environment (`HOME`, `MEMO`) never returns; the
  program is stopped where it was, and may be continued later (§10.3).

Graphics, sprite, and sound statements are not defined here. Until the
corresponding Forth words are specified, programs use `CALL`.

## 13. BASIC as an environment

- **Definition.** BASIC's source ends with
  `' BASIC-STEP ENVIRONMENT BASIC`. Its other words live in a
  vocabulary of their own (`06-ENVIRONMENTS.md` §9).
- **Loading.** BASIC is the source module `BASIC`, loaded with
  `MODULE BASIC` (`04-FORTH-CORE.md` §6.16). Its source begins with
  `MODULE FLOAT`, so the float wordset is loaded first; on a target
  without it that line aborts and nothing of BASIC is defined. Loading
  initializes the work bank (§10.4) and does not enter BASIC.
- **The step word**, each time it is called: reads and clears
  `ENV-REASON`; on entry, shows a banner the first time only; on
  recovery, prints the pending report, or `F Forth error` if control
  came back with none recorded; then reads one line and either stores
  it (§3.5) or runs it (§10.1).
- **Leaving.** `EXIT` switches to `HOME`. Programs, variables, and any
  stop state stay in their banks, and typing `BASIC` again returns to
  them with the screen as it was left.
- **Shared interpreter state.** BASIC sets `BASE` to ten whenever it
  needs it and restores the previous value before `EXIT`.

## 14. What this needs that the suite does not yet specify

Nothing remains. The float words BASIC is built on — arithmetic, the
elementary functions behind `SIN`, `LN` and `^`, and the text
conversion behind `PRINT`, `STR$`, `VAL` and `INPUT` — all have
reference source (`07-FLOATING-POINT.md` §5).

Everything else BASIC uses is specified: bank lookup, creation, and
single-bank save and load by name (`04-FORTH-CORE.md` §6.14); the
cursor position as the `CURSOR-X`/`CURSOR-Y` sysvar constants
(`03-SYSVARS.md` §2, §5); and the page bank format and editor
hand-over (`09-MEMO.md` §3, §9).

## 15. Differences from the prototype

| Prototype | Rebel BASIC | Why |
|---|---|---|
| Tokenized lines interpreted at run time | Text compiled to Forth threaded code at `RUN` | One execution engine; Forth speed |
| One numeric type, 64-bit double | Float is 32-bit; integer `%` type added | The cell is 32 bits; integers run at full speed |
| Lines must be numbered, stored in numeric order | Numbers optional, `@labels` added, order is text order | The machine has a full-screen editor |
| Lines of any length in a line store | A line is one screen row of a page bank | Programs are MEMO documents |
| Syntax checked as each line is entered | Checked at compile time | Text may arrive from the editor |
| Keywords rewritten to upper case; variables case-sensitive | Text stored as typed; everything case-insensitive | One rule, matching the Forth dictionary |
| String variables are one letter plus `$` | Any name plus `$` | No reason for the limit |
| String arrays are fixed-width character grids | Arrays of ordinary strings | Simpler to use |
| Unassigned variable is an error | Scalars start at `0` or empty | A per-read check would cost every variable access |
| `LET` required | `LET` optional | Convenience |
| `VAL` evaluates an expression | `VAL` reads a number | No run-time compiler call inside expressions |
| `AND`/`OR`, precedence, slices, 1-based arrays, `DATA`, reports | Kept | The language's character |
| Only one-line `IF`; `FOR` loops | Block `IF`/`ELSE`/`END IF`, `WHILE`, `REPEAT` added | Structured code without line numbers |
| ANSI terminal, 8 colors, `BRIGHT`, default color `-1` | Rebel screen, 16 palette colors; `BRIGHT` and `-1` dropped | No terminal underneath |
| Own sysvar table for attributes and cursor | Uses the `SCREEN` and `CORE` sysvars | They already hold this |
| Files: `SAVE`/`LOAD`/`MERGE`/`CAT`/`DELETE` by path, auto-run | Programs are banks in the project; `MERGE`, file delete, auto-run dropped | Storage is banks and projects |
| `EXIT code` ends the process | `EXIT` returns to the Forth prompt | There is no process |
| `AUTO`, `RENUM`, `EDIT n` line editing | `EDIT` opens the editor; `AUTO`, `RENUM` dropped | Labels and the editor replace them |
| Ctrl+C via a signal | Break key polled at statement boundaries | No signals |
| — | `CALL`, `USR`, `PEEK`, `POKE`, `BANK%` | Access to the machine |

## 16. Open questions

- **Graphics, sprites, sound.** Statements such as `PLOT`, `DRAW`,
  `SPRITE`, `TILE` are wanted and wait on Forth-level words for
  `01-HAL.md` §3.4 and §3.8.
- **Time.** No `PAUSE` or clock function is defined; both need a
  Forth-visible millisecond clock. Milliseconds also outgrow a float's
  exact range within hours, so the function should be integer-typed.
- **Procedures.** `GOSUB @name` is the only subroutine form. Named
  procedures with parameters and local variables are a natural next
  step and a real design task.
- **Reading BASIC variables from Forth.** The symbol table is BASIC's
  own; no Forth word looks a variable up by name.
- **A dedicated break key.** Ctrl+C is a convention layered on the
  ordinary key stream. A key that reaches a program which never polls
  — one stuck inside a long Forth word — needs the pending-switch
  mechanism `06-ENVIRONMENTS.md` §10 also wants.
- **Integer overflow.** `%` arithmetic wraps silently (§4.2). Checking
  would cost every integer operation.
- **Renumbering and merging.** Dropped for now; cheap to add once the
  rest exists.
- **Work bank size.** Fixed at 64 KiB when BASIC is loaded. A `CLEAR n`
  form to resize it is the obvious extension.
