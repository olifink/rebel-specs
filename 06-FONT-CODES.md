# FONT-CODES.md

Code point assignments for Rebel's font bank. One entry per byte value,
8 bytes/char (row 0 = top, MSB = leftmost pixel). This doc tracks *what's
assigned where*, not glyph design — see the font editor / BDF references
for that.

## 0x00–0x1F — Control

Unassigned. Reserved for control/graphics use, not yet specified.

## 0x20–0x7E — ASCII

Standard ASCII, unmodified. Deliberately **not** following JIS X 0201's
usual substitutions at these positions:

| Code | Char | Note |
|------|------|------|
| 0x5C | `\`  | Kept as backslash (JIS X 0201 would put ¥ here) — needed for full-line Forth comments |
| 0x7E | `~`  | Kept as tilde (JIS X 0201 would put an overline here) — not a real Japanese typographic feature, just legacy ASCII-slot politics; no reason to inherit it |

No half-width/full-width distinction anywhere in Rebel's font — every
glyph, Latin or kana, occupies the same 8x8 cell.

## 0x7F — Reserved

Unassigned (DEL in ASCII; not currently used).

## 0x80–0xA0 — Unassigned

Reserved. Candidates for later: Euro sign (€), other Latin-1 punctuation
not yet needed.

## 0xA1–0xDF — JIS X 0201 kana

Half-width-kana code positions, drawn as full 8x8 (not compressed 4-wide)
glyphs. Sourced from Misaki Gothic's **fullwidth** katakana Unicode block
glyphs (U+30A1–U+30F3 range, plus fullwidth punctuation and the spacing
dakuten/handakuten marks), re-homed to these single-byte positions — see
`bdf_to_rebel_bank.py`. Misaki's own U+FF61–U+FF9F glyphs were *not* used,
since those are drawn narrow (4-wide) for pairing under a full-width kanji
cell, which doesn't apply here.

| Code | Char | Name | Source (Unicode) |
|------|------|------|-------------------|
| 0xA1 | 。 | ideographic full stop | U+3002 |
| 0xA2 | 「 | left corner bracket | U+300C |
| 0xA3 | 」 | right corner bracket | U+300D |
| 0xA4 | 、 | ideographic comma | U+3001 |
| 0xA5 | ・ | katakana middle dot | U+30FB |
| 0xA6 | ヲ | WO | U+30F2 |
| 0xA7 | ァ | small A | U+30A1 |
| 0xA8 | ィ | small I | U+30A3 |
| 0xA9 | ゥ | small U | U+30A5 |
| 0xAA | ェ | small E | U+30A7 |
| 0xAB | ォ | small O | U+30A9 |
| 0xAC | ャ | small YA | U+30E3 |
| 0xAD | ュ | small YU | U+30E5 |
| 0xAE | ョ | small YO | U+30E7 |
| 0xAF | ッ | small TU | U+30C3 |
| 0xB0 | ー | prolonged sound mark | U+30FC |
| 0xB1 | ア | A | U+30A2 |
| 0xB2 | イ | I | U+30A4 |
| 0xB3 | ウ | U | U+30A6 |
| 0xB4 | エ | E | U+30A8 |
| 0xB5 | オ | O | U+30AA |
| 0xB6 | カ | KA | U+30AB |
| 0xB7 | キ | KI | U+30AD |
| 0xB8 | ク | KU | U+30AF |
| 0xB9 | ケ | KE | U+30B1 |
| 0xBA | コ | KO | U+30B3 |
| 0xBB | サ | SA | U+30B5 |
| 0xBC | シ | SI | U+30B7 |
| 0xBD | ス | SU | U+30B9 |
| 0xBE | セ | SE | U+30BB |
| 0xBF | ソ | SO | U+30BD |
| 0xC0 | タ | TA | U+30BF |
| 0xC1 | チ | TI | U+30C1 |
| 0xC2 | ツ | TU | U+30C4 |
| 0xC3 | テ | TE | U+30C6 |
| 0xC4 | ト | TO | U+30C8 |
| 0xC5 | ナ | NA | U+30CA |
| 0xC6 | ニ | NI | U+30CB |
| 0xC7 | ヌ | NU | U+30CC |
| 0xC8 | ネ | NE | U+30CD |
| 0xC9 | ノ | NO | U+30CE |
| 0xCA | ハ | HA | U+30CF |
| 0xCB | ヒ | HI | U+30D2 |
| 0xCC | フ | HU | U+30D5 |
| 0xCD | ヘ | HE | U+30D8 |
| 0xCE | ホ | HO | U+30DB |
| 0xCF | マ | MA | U+30DE |
| 0xD0 | ミ | MI | U+30DF |
| 0xD1 | ム | MU | U+30E0 |
| 0xD2 | メ | ME | U+30E1 |
| 0xD3 | モ | MO | U+30E2 |
| 0xD4 | ヤ | YA | U+30E4 |
| 0xD5 | ユ | YU | U+30E6 |
| 0xD6 | ヨ | YO | U+30E8 |
| 0xD7 | ラ | RA | U+30E9 |
| 0xD8 | リ | RI | U+30EA |
| 0xD9 | ル | RU | U+30EB |
| 0xDA | レ | RE | U+30EC |
| 0xDB | ロ | RO | U+30ED |
| 0xDC | ワ | WA | U+30EF |
| 0xDD | ン | N | U+30F3 |
| 0xDE | ゛ | dakuten (voiced sound mark) | U+309B |
| 0xDF | ゜ | handakuten (semi-voiced sound mark) | U+309C |

## 0xE0–0xFF — Unassigned

Reserved. No plan yet.

## Deferred

- Euro sign (€) — code point not yet chosen.
- Any codepoints beyond this table (0x80–0xA0, 0xE0–0xFF) — open for
  future assignment as need arises, per Rebel's usual "defer until
  concrete need" approach.

## Provenance

Glyph shapes at 0xA1–0xDF converted from `misaki_gothic.bdf` (Misaki
Gothic, © 2002–2021 Num Kadoma, free/libre, littlelimit.net) via
`bdf_to_rebel_bank.py`. Kept as a reference font in the font editor.
