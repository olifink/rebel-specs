# 09 — MEMO Specification

**Version 1.1, draft.** See `00-OVERVIEW.md` for normative-language definitions and
suite scope. Nothing here is implemented on any reference target yet.

## 1. Purpose and scope

MEMO is the Rebel machine's full-screen editor. It is an
**environment** (`06-ENVIRONMENTS.md`), loaded on demand, entered by
typing `MEMO`, and written in portable Forth source.

It is not a flowing-text editor. A document is a stack of **pages**,
each a fixed grid of characters shown whole, and the user is always
editing one line of one page, in overwrite mode. Nothing reflows,
nothing scrolls.

MEMO edits three kinds of thing with the same keys: its own documents,
Rebel BASIC programs, and classic 64 × 16 Forth screens in a `BLKS`
bank.

This document defines:

- The page bank format MEMO edits (§3), which Rebel BASIC programs
  share (`08-BASIC.md` §3.1), and how a block bank of Forth screens is
  edited as pages (§3.4).
- Every key and exactly what it does (§4, §5).
- How a line of text is executed as Forth, which is the whole of
  MEMO's command system (§6).
- How documents are opened, and how another environment hands one over
  (§7, §9).

## 2. Model

### 2.1 The page, shown whole

A page is a grid of `cols` × `rows` characters, fixed per document
(§3.3). MEMO shows it at the top left of the screen, one page cell per
screen cell, all of it at once. The cursor never leaves it.

- A document made for this screen has a page the size of the whole
  display. Then every cell the user sees is document content: no
  status line, no margin, no chrome.
- A page smaller than the screen — a 64 × 16 Forth screen on a larger
  display — leaves the rest of the screen blank. If there is a row
  below the page, MEMO shows a **status row** there: the document's
  name and the page number. For a block bank the number is the block
  number (§3.4); for a page bank it is the page counted from 1,
  followed by the page count. Nothing else is drawn outside the page.
- A page larger than the screen in either direction cannot be shown,
  and the document is not opened.

While a page is displayed, the screen is the working copy. MEMO writes
the page back to the document bank — **commits** it — whenever it is
about to show anything else or run anything: before turning the page,
before executing a line (§6), and before leaving the environment.

### 2.2 Edits are local and lossy at the edges

Every editing operation acts on one line, or on the lines of one page,
and never on anything beyond. Where an operation pushes text past a
boundary, **the text is lost**:

- Characters pushed past the right margin are lost.
- Lines pushed past the bottom of the page are lost.

There is no overflow onto the next line or the next page, and nothing
is ever made room for automatically. Space is made explicitly, with the
keys that insert a space, split a line, or split a page. This is the
editor's central rule, and every key in §4 follows it.

### 2.3 Overwrite, always

There is no insert mode. A typed character replaces the one under the
cursor.

## 3. The page bank

A document is one bank in this format. So is a Rebel BASIC program.
MEMO edits any bank that carries this header, whatever its tag.

### 3.1 Layout

| Offset | Size | Field | Meaning |
|---|---|---|---|
| 0 | 1 byte | Magic 0 | `'P'` |
| 1 | 1 byte | Magic 1 | `'G'` |
| 2 | 1 byte | Version | `1` |
| 3 | 1 byte | Reserved | `0` |
| 4 | 1 cell | `cols` | Characters per line |
| 8 | 1 cell | `rows` | Lines per page |
| 12 | 1 cell | `pages` | Pages in use, at least `1` |
| 16 | 1 cell | `revision` | Incremented whenever page content changes |
| 20 | 1 cell | `page` | The page last shown, from `0` |
| 24 | 1 cell | `cursor-x` | Cursor column when last shown |
| 28 | 1 cell | `cursor-y` | Cursor row when last shown |
| 32 | `pages × cols × rows` | | The pages |

- A page is `cols × rows` bytes, row by row, top to bottom — the same
  layout as the `CHAR` bank, so showing a page is one block copy.
- Bytes are character codes as the screen displays them
  (`10-FONT-CODES.md`). There are no line terminators and no other
  encoding. An unused cell is a space, `0x20`.
- The bank's **capacity** is `(size − 32) / (cols × rows)` pages,
  rounded down. A document cannot grow past it within a session
  (`02-MEMORY-MODEL.md` §4.8).
- `page`, `cursor-x`, and `cursor-y` let a document reopen where it was
  left. Changing them does not change `revision`.

### 3.2 Rules for anything that writes one

- Every page in use is fully space-filled; a newly created bank is
  zero-filled (`04-FORTH-CORE.md` §6.14), so a writer fills each page
  it brings into use.
- `revision` **MUST** be incremented by any writer that changes page
  content or `pages`. Readers use it to tell whether their view of the
  document is out of date; BASIC uses it to know a program needs
  recompiling.
- A reader treats any byte below `0x20` as a space.

### 3.3 Tags and geometry

- A MEMO document has tag **`MEMO`** and is saved as `<name>.MEM`. A
  BASIC program has tag `BAS`. The format is identical.
- **A document's geometry is fixed when it is created**, from the
  screen it was created on. MEMO opens a document only if it fits:
  `cols` no greater than `CHAR-COLS` and `rows` no greater than
  `CHAR-ROWS` (§2.1). Programs that only read a page bank, as the BASIC
  compiler does, work with any geometry.

### 3.4 Block banks: Forth screens

A bank tagged **`BLKS`** (`01-HAL.md` §6.5) is not a page bank. It has
no header: it is 1024-byte blocks back to back, block *n* at offset
*n* × 1024. MEMO edits one as it stands, without converting it, by
treating each block as a page of the classic Forth screen shape:

| | Page bank | Block bank |
|---|---|---|
| Geometry | From the header | Always 64 columns × 16 rows |
| Page *n* is at | `32 + n × cols × rows` | `n × 1024` — page *n* is block *n* |
| Pages in use | The header's `pages` | Every block: `size / 1024` |
| Last page and cursor | In the header | Remembered by MEMO, per session |
| `revision` | In the header | None |

Because a block's number is its identity — `LOAD` and every reference
between screens name blocks by number — **a block bank's pages never
move**. In a block bank:

- Page split and page join (§5.2, §5.3) do nothing.
- Turning pages never adds or removes one: Shift-Down stops at the last
  block (§5.1).

Everything else — every key in §4, and executing a line (§6) — is
identical. A status written by an executed line is a `\` comment, so a
screen that carries one still loads.

**Agreement with the block words.** Where a target has a block buffer
pool (`BLOCK`, `UPDATE`, `FLUSH`; `04-FORTH-CORE.md` §9), MEMO and the
pool **MUST NOT** disagree: the page MEMO shows for block *n* is what
`n BLOCK` would return, and after MEMO commits it, `n BLOCK` returns
the edited text. MEMO achieves this by reading and writing through
those words. On a target with no buffer pool it reads and writes the
bank directly.

A machine whose screen is smaller than 64 × 16 cannot edit Forth
screens with MEMO.

## 4. Keys

MEMO reads raw key events (`EKEY`, `04-FORTH-CORE.md` §6.9), because
most of its keys have no character. "Shift" means either Shift key.
Below, *the line* is the row the cursor is on, and *blank* means all
spaces.

### 4.1 Moving

| Key | Effect |
|---|---|
| Left, Right, Up, Down | Move one cell. The cursor stops at the page's edges; it never wraps and never changes page. |
| Home | To column 0. |
| Tab | To the next tab stop: the next column that is a multiple of 8, or the last column if there is none. No text changes. |
| End | To just after the line's last non-space character, or the last column if the line is full. |
| Enter | To column 0 of the next line. On the last line, to column 0 of the same line. |

### 4.2 Typing and rubbing out

| Key | Effect |
|---|---|
| Any character key | Replace the character under the cursor and move right. At the last column the cursor stays put, so further typing replaces that one cell. |
| Backspace | Move left one cell and replace the character there with a space. Nothing to the right moves. At column 0, nothing happens. |

### 4.3 Making and removing space in a line

| Key | Effect |
|---|---|
| Shift-Tab | **Insert spaces up to the next tab stop**: from 1 to 8 of them, enough to bring the character under the cursor to the next multiple of 8. Everything from the cursor rightward moves that far right, and what passes the right margin is lost, as with Shift-Space. The cursor moves with the text, to the tab stop, so a second Shift-Tab indents by a further 8. |
| Shift-Space | **Insert a space** at the cursor. The character under the cursor and everything to its right move one cell right; the line's last character is lost. The cursor does not move. *(On a blank line this key splits the page instead — §5.2.)* |
| Delete | **Delete the character** under the cursor. Everything to its right moves one cell left and a space enters at the right margin. The cursor does not move. |
| Shift-Delete, Alt-Backspace | **Clear to the end of the line**: the character under the cursor and everything to its right become spaces. The cursor does not move. Both chords do it, because on keyboards whose Delete is itself a remapped chord (ChromeOS's Search- or Alt-Backspace) Shift-Delete may never reach the machine. |
| Shift-Backspace | Away from column 0: the same as Delete. At column 0: **join** this line to the one above (§4.4). |

### 4.4 Splitting and joining lines

**Shift-Enter splits the line at the cursor.** The text from the cursor
to the right margin moves to the start of a new line inserted directly
below; its old cells become spaces. Every line below moves down one,
and the page's last line is lost. The cursor goes to column 0 of the
new line. On the page's last line there is nowhere to insert: the text
from the cursor rightward is erased and the cursor stays.

**Shift-Backspace at column 0 joins the line to the one above.** Let
*j* be the column just after the last non-space character of the line
above (`0` if that line is blank). The current line's text is copied to
the line above starting at column *j*; whatever does not fit before the
right margin is lost. Every line below moves up one, and the page's
last line becomes blank. The cursor goes to column *j* of the line
above.

If the line above is full (*j* equals `cols`) nothing could be kept, so
the key does nothing.

On the first line of a page, Shift-Backspace at column 0 joins the page
to the previous one instead (§5.3).

## 5. Pages

### 5.1 Turning pages

| Key | Effect |
|---|---|
| Shift-Down | Show the next page. On the last page: if that page is not blank and the bank has capacity, add a blank page and show it; otherwise nothing. |
| Shift-Up | Show the previous page. If the page being left is the last one and is blank, it is removed from the document. On the first page, nothing. |

In a block bank the set of pages is fixed (§3.4): Shift-Down on the
last block and Shift-Up on the first do nothing, and no page is ever
added or removed.

The cursor keeps its column and row across a page turn. The display
changes all at once; there is no scrolling.

### 5.2 Splitting a page

**Shift-Space on a blank line splits the page there.** A new page is
inserted after the current one. The lines below the cursor's line move
to the top of the new page, in order; the rest of the new page is
blank, and the lines that moved are blanked on the current page. Later
pages move one place along. The cursor and the page shown do not
change.

On the last line of a page this inserts an empty page after it.

If the bank is at capacity the key does nothing.

### 5.3 Joining pages

**Shift-Backspace at column 0 of a page's first line joins the page to
the previous one.** Let *k* be the number of lines on the previous page
up to and including its last non-blank line (`0` if it is blank). The
current page's lines are copied, from the top, onto the previous page
starting at line *k*; lines that do not fit on that page are lost. The
current page is removed and later pages move one place back. The
previous page is shown, with the cursor at column 0 of line *k*.

If the previous page has no blank line at its end (*k* equals `rows`)
nothing could be kept, so the key does nothing. On the first page the
key does nothing.

Splitting a page and joining it again restores it exactly, apart from
the blank line the split was made on.

## 6. Executing Forth

MEMO has no command language and no command line. **Shift-Esc executes
the line the cursor is on as Forth**, and that is the whole command
system: a command is typed into the document, wherever there is a line
for it, and run from there.

**Shift-Esc on a blank line leaves MEMO.** It commits the page and
switches to the home environment, exactly as executing `HOME` from a
line would, but with nothing written to the page: no output and no
status.

### 6.1 What the user sees

```
before                          after Shift-Esc on the first line

2 3 + .                         2 3 + . \ ok
some older text                 5
more older text                 more older text
```

- **Output replaces the lines below the command.** Whatever the line
  prints is written starting at column 0 of the next line, overwriting
  as many lines as it needs. Lines it does not reach are untouched. A
  line that prints nothing changes nothing below it.
- **Output stops at the bottom of the page.** Lines of output that do
  not fit below the command are lost (§2.2). A command on the last line
  has no room for output at all.
- **The result goes on the command's own line**, after the command:
  `\ ok` if it ran to the end, `\ error` if it did not.
- The cursor stays where it was.

### 6.2 The status is a comment

The status is written as a Forth comment — a `\` and the rest of the
line (`04-FORTH-CORE.md` §6.7) — so that a line can be executed again
with its previous status still on it.

- The text executed is the whole line with trailing spaces removed.
  Forth itself ignores everything from a `\` onward.
- The status is written one space after the command. If the line
  already ends in a comment — its last `\` that stands alone as a word
  — the status replaces that comment, so repeated execution does not
  pile statuses up. A comment the user wrote there is replaced too.
- A status that does not fit before the right margin is cut off there.

### 6.3 What executing a line does

Output is not written into the page directly, because the Screen Module
wraps from the last row to the first (`01-HAL.md` §3.2) and would run
on over the top of the page. It is captured on a cleared screen and
copied in.

1. **Commit** the page (§2.1) and note which document, page, and line
   the command is on. From here to step 6 the document bank is the
   truth and the screen is scratch.
2. Clear the screen and put the cursor at the top left.
3. Interpret the line with `EVALUATE` (`04-FORTH-CORE.md` §6.15), with
   the search order as MEMO found it. MEMO's internal words live in a
   vocabulary of its own (`06-ENVIRONMENTS.md` §9), but that vocabulary
   is **not** put in front of the search order. Vocabularies branch
   (`04-FORTH-CORE.md` §7.2), so one created when MEMO was loaded cannot
   see any `FORTH` word defined after it, the user's own words
   included. A line that switches environment, such as `HOME`, would
   also leave the search order changed. Everything a command needs,
   `MEMO-OPEN` and `EDIT` among them, is in `FORTH`.
4. **Capture.** The output is the screen's rows from the top through
   the row the cursor ended on — or through the row above, if the
   cursor ended at column 0. If the cursor is still at the top left,
   there is no output. Copy those rows into the noted page, starting at
   the line after the command, as many as fit. Each row is copied to
   the page's width; on a page narrower than the screen, output beyond
   the page's right margin is lost.
5. Write the status on the command's line (§6.2) and increment the
   document's `revision`.
6. Reload the page from the bank and show it, with the cursor where it
   was.

Output longer than one screen wraps over its own beginning on the
scratch screen before it is captured, so what is kept is not its first
lines. Such output did not fit on the page in any case.

A word that is meant to change the document changes the bank
(§7.2), between steps 1 and 4. Captured output and the status are then
written over the result.

### 6.4 Errors and switches

- **If the line aborts**, the machine reports the error as always and
  MEMO's step word is re-entered for recovery (`06-ENVIRONMENTS.md`
  §5.3). MEMO carries on from step 4 with the status `\ error`.
  Anything the machine printed about the error on the screen — the
  offending word, a message — is captured as output and so appears
  below the command. MEMO cannot put the message itself in the status:
  the suite has no error codes yet (`04-FORTH-CORE.md` §8), and the
  report goes to the target's own surface (`01-HAL.md` §8), which need
  not be the screen.
- **If the line switches environment**, it never returns. Nothing is
  captured and no status is written. The document was committed in
  step 1, and `MEMO` later returns to the same page and cursor.
- **If the line opens another document**, output and status still go
  to the document the command is in; step 6 then shows the newly
  current one.
- A line may define words. A definition must be complete on its line.

### 6.5 What this makes possible

- **Any Forth word is an editor command.** `BANK-SAVE NOTES` saves the
  document. `BASIC` or `HOME` switches environment. `MEMO-OPEN LETTER`
  opens another document.
- **A document is a worksheet.** Calculations and their results sit
  together on the page, and a line can be changed and run again.
- **A page can hold its own commands.** A page of Forth lines is a
  menu: put the cursor on one and press Shift-Esc.
- **Extending the editor is defining words.** A word that centres a
  line or searches the document is an ordinary colon definition working
  on the page bank (§7.2).

## 7. Documents

### 7.1 Words

These are in the `FORTH` vocabulary once MEMO is loaded.

| Word | Effect |
|---|---|
| `MEMO` | `( -- )` — enter the editor on the current **page document**, at its recorded page and cursor. Never on a block bank: see below. |
| `MEMO-OPEN name` | `( "name" -- )` — make the named bank the current document, then, if MEMO is the active environment, show it. `ABORT` if it cannot be opened. |
| `(MEMO-OPEN)` | `( addr len -- flag )` — the same with the name on the stack; `FALSE` instead of `ABORT`. Never enters MEMO. |
| `EDIT` | `( n -- )` — edit Forth screen `n`: make the bank named `BLKS` the current document at block `n`, cursor at the top left, and enter MEMO. `ABORT` if there is no such bank or no such block, or the screen is smaller than 64 × 16. |
| `MEMO-LOAD name` | `( "name" -- )` — interpret the named document as Forth source: every line of every page in use, page 0 first and top to bottom, each passed to `EVALUATE` (`04-FORTH-CORE.md` §6.15). `ABORT` if there is no such bank or it is not a page document. See below. |
| `(MEMO-LOAD)` | `( addr len -- flag )` — the same with the name on the stack; `FALSE` instead of `ABORT`. |

`MEMO-OPEN` decides how to treat a bank from the bank itself: a bank
tagged `BLKS` is opened as a block bank (§3.4), any other must carry a
page bank header. So `MEMO-OPEN BLKS` and `0 EDIT` reach the same
screens; `EDIT` is the classic Forth spelling and goes straight to a
block, and `MEMO-OPEN` also opens a block bank kept under another
name.

**The current page document.** Opening a page bank makes it the
*current page document*, which `MEMO` always enters on: MEMO's own
full-screen world. A block bank is a detour. Opening one, with `EDIT`
or with `MEMO-OPEN`, shows it until MEMO is next entered with `MEMO`,
which returns to the current page document, at its own page and cursor.
Opening a block bank never changes the current page document.

Opening a name that has no bank creates a `MEMO`-tagged page bank of
16 KiB with one blank page in the current screen geometry. Opening
fails if the bank exists but is neither a block bank nor a valid page
bank, if its page does not fit the screen (§2.1), or if it cannot be
created.

MEMO starts with the document `NOTES` current, creating it if needed.
The current document's name is ordinary dictionary state: it survives
switching environments and is reset when MEMO is reloaded.

**`MEMO-LOAD`.** Because `STATE` carries over from line to line, a
definition may span lines and pages, and a document of Forth source is
loaded the way a block of screens is with `LOAD`. Like `LOAD`, it
compiles with `CONTEXT` set to `CURRENT` for the duration, and restores
`CONTEXT` afterwards. It reads the bank in place and changes nothing
about MEMO's own state: the current document, page and cursor are left
as they were, so `MEMO-LOAD` may be run from a line in MEMO (§6) to load
another document. A document may `MEMO-LOAD` another; one that loads
itself recurses until the return stack overflows, which is an ordinary
error. A `BLKS` bank is refused, because its screens already have
`LOAD`. A status comment left on a line by §6.2 is a `\` comment, so a
document that has been worked on in MEMO still loads.

### 7.2 Working on a document from Forth

A document is memory. From a slot (`(BANK-FIND)`), the header fields
and every page are at fixed offsets (§3.1), and any Forth word may read
them. A word that writes page content **MUST** increment `revision`.
Run from inside MEMO (§6), such a word sees the committed document and
its changes appear when the page is reloaded (§6.3).

### 7.3 Saving

There is no MEMO save command. A document is a bank: it is saved with
the project, or on its own with `BANK-SAVE name`, like any other
(`04-FORTH-CORE.md` §6.14).

## 8. MEMO as an environment

- **Definition.** MEMO is the source module `MEMO`, loaded with
  `NEEDS MEMO` (`04-FORTH-CORE.md` §6.16). Its source ends with
  `' MEMO-STEP ENVIRONMENT MEMO`. Loading it does not enter it
  (`06-ENVIRONMENTS.md` §9).
- **Requirements.** A keyboard delivering raw events (`EKEY`) and a
  visible cursor (`CURSOR-VISIBLE`, `01-HAL.md` §3.5). MEMO cannot be
  driven through a byte channel (§10).
- **The step word**, each time it is called: reads and clears
  `ENV-REASON`. On entry it shows the current document's recorded page,
  dropping any note of a command that was in progress. On recovery, if
  a command was in progress, it finishes that command as an error
  (§6.4); otherwise it just reloads the page. Then it reads one key
  event and acts on it.
- **Entry and the saved screen.** The environment switch restores
  MEMO's saved screen (`06-ENVIRONMENTS.md` §7) and MEMO then shows the
  page from the bank over it. The bank, not the saved screen, is what
  MEMO trusts.
- **Colors.** A page has no color information. MEMO shows it in the
  current `INK` and `PAPER`.
- **Leaving.** Shift-Esc on a blank line (§6), or any switching word
  executed as in §6. The page is committed first either way.

## 9. Editing on behalf of another environment

An environment whose data is a page bank can lend it to MEMO:

1. Set the bank header's `page`, `cursor-x`, and `cursor-y` if it wants
   the editor to open somewhere particular.
2. `(MEMO-OPEN)` the bank's name.
3. Execute `MEMO`.

The user edits, and returns by executing the lender's own switching
word (`BASIC`). The lender compares `revision` with the value it last
saw to learn whether anything changed.

This is all Rebel BASIC's `EDIT` does (`08-BASIC.md` §3.5). MEMO keeps
no record of who lent a document and has no "return" key; both
environments are simply peers.

## 10. Open questions

- **Lines wider than the page.** A line is at most the page's `cols`
  characters, which on a narrow display is tight, for BASIC source
  especially. A continuation convention would be a property of whoever
  reads the page, not of MEMO.
- **Moving documents to a smaller screen.** A document opens on any
  screen at least as large as its page (§2.1), but not on a smaller
  one. A conversion word that re-pages a document, truncating or
  re-splitting lines, is the obvious tool and is not designed.
- **Remote use.** `EKEY` reads the keyboard, not the bound channel, so
  MEMO cannot be driven by a remote session. It would need an agreed
  byte encoding for the keys in §4 and §5.
- **Color and emphasis.** Pages are characters only. Per-cell
  attributes would double the page size and are deferred until wanted.
- ~~**Loading a page as Forth source.**~~ Resolved: `MEMO-LOAD` (§7.1)
  interprets a whole document.
- **Word-processing words.** Centring, justifying, searching, and
  replacing are expected to be Forth words over the page bank (§6.5).
  None is specified.
- **Undo.** There is none, and §2.2 makes several keys destructive, as
  does command output (§6.1). The committed copy of the page in the
  bank is a natural one-step undo for everything done since the page
  was shown.
- **Where the page number shows.** A page smaller than the screen gets
  a status row (§2.1). A document whose page fills the screen has
  nowhere to show which page of how many is displayed; a word that
  prints it can be executed like any other.
- **Error text in the status.** Today the status can only say `error`
  (§6.4). Once the Forth core has error codes it should carry one.

## 11. Conformance checklist

| Requirement | § |
|---|---|
| A page bank has §3.1's header and layout; every writer increments `revision` on a content change | §3 |
| The page is shown whole at the top left; outside it MEMO draws only the status row, and only when a row below the page exists | §2.1 |
| A `BLKS` bank is edited in place as 64 × 16 pages, page *n* being block *n*; its pages are never inserted, removed, or moved | §3.4 |
| MEMO and the block buffer pool never disagree about a block's content | §3.4 |
| No operation moves text across the right margin or the bottom of a page; what is pushed past either is lost | §2.2 |
| Line join and page join do nothing when nothing could be kept | §4.4, §5.3 |
| The page is committed before any page turn, any executed line, and any environment switch | §2.1, §6.3 |
| An executed line's output is captured and written below the command, never above it and never past the bottom of the page; its status is written on its own line as a `\` comment | §6.1–§6.3 |
| Shift-Esc on a blank line commits the page and switches to `HOME` | §6 |
| `MEMO` always enters on the current page document; a block bank is shown only when opened by `EDIT` or `MEMO-OPEN` | §7.1 |
| A document whose page does not fit the screen is refused | §2.1, §3.3 |
