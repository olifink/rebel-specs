# Design to-dos: Rebel and the Net-Stick

Open design work for making the Rebel machine and Rebel-Net-Stick
(`NET-STICK.md`, beside this file) one coherent solution. It comes from a
cross-check of `NET-STICK.md` against the channel, remote-terminal and
transport designs (2026-10-16). Items are roughly in the order they
should be settled. The spec suite defines what every Rebel target
implements; most of the gaps are on the Rebel side of the link, not in
the stick.

## What already fits

- **Framing.** The stick reuses the remote terminal's frame shape
  unchanged (`0xA5` sync, id, length, payload, mod-256 checksum, resync
  by rescan, no ACKs), with its own message-id catalog.
- **Layering.** Postboxes are a stateful device module above a raw
  duplex link, not a `Channel`. Channels stay input-only and
  stream-shaped (`01-HAL.md` §5).
- **Non-blocking, polled.** The 32-bit ready mask follows the HAL's
  non-blocking rule. A blocking wait is the same suspension `KEY`,
  `VSYNC` and `(MODULE-READ)` already use (`04-FORTH-CORE.md` §4.4).
- **Credentials stay on the stick.** The target table means Rebel only
  ever names an index, so no secret is ever in Rebel memory or a saved
  project. Given that a session can be saved and resumed anywhere, this
  is the design's most important property.
- **Transport independence.** `05-REMOTE-TRANSPORTS.md`'s
  `Transport`/`ByteSink` contract applies unchanged: the stick is one
  more byte pipe.

## Settled

- **AI and other large or streaming answers are condensed by the stick,
  never streamed to Rebel** (Oliver, 2026-10-16). An AI service is
  another target type whose answer the stick condenses into a small
  postbox response, exactly as it condenses an HTTP/HTML page instead
  of passing the page through as is. Rebel sees one complete,
  Rebel-sized response per request, so the box lifecycle stays
  `PENDING` → `READY`, with no partial or streaming state. A
  consequence: the 64 KiB ceiling of the protocol's u16 lengths and
  offsets is not a practical limit. `NET-STICK.md` §8 records this.

## Open

1. **One shared link-framing document.** The frame shape is defined in
   Rebel-Sim's `REMOTE-TERMINAL.md` §3 and adopted by its
   `CHANNELS-DESIGN.md` §3a. Both live outside this suite, yet two
   protocols, the remote terminal and the stick, now depend on it. Move
   it into the suite as one normative document that both protocols
   reference.
2. **A duplex device-link HAL.** `NET-STICK.md` assumes a
   `SerialChannel` that can also write, but the suite has no duplex
   link: channels are input-only by design (`01-HAL.md` §5.2), and
   whether to add a write side or a separate duplex type is still open
   in `CHANNELS-DESIGN.md`. Define a small link HAL that is not a
   `Channel`: attach and detach, non-blocking read, write, and
   presence. Discussed 2026-10-16: the stick link should **not** be a
   two-way `Channel`. A channel is what `KEY` reads, typed characters,
   while the stick link carries framed protocol messages that nothing
   would ever read keys from. The postbox module sits on a link, and so
   could the remote terminal's board side. See item 11 for the separate
   question of channel output.
3. **The postbox module as portable code**, written once and shared by
   every target like the keyboard module (`01-HAL.md` §4.3). It owns the
   box states and the ready mask, and runs the frame parser. Its drain
   point (`NET-STICK.md` §10) follows the existing call-in pattern: a
   Type B `net_tick()` the target's loop calls, like `keyboard_tick()`
   and `screen_frame()`.
4. **A `NET` sysvar group** (`03-SYSVARS.md`): the ready mask
   (`NETSTICK-READY` has no group or offset yet), plus what `HELLO`
   reports (stick present, Wi-Fi up, time synced, box count), so
   programs detect the capability by field presence, as for every
   other optional subsystem.
5. **The Forth words.** `NET-SEND`, `NET-READY?` and `NET-READ` are only
   sketched (`CHANNELS-DESIGN.md` §3a). They should follow the
   conventions settled since:
   - name-on-the-stack forms that return `0`/`FALSE` rather than
     aborting, as the bank words do (`04-FORTH-CORE.md` §6.14);
   - responses read into a bank or buffer through the pull-based chunks;
   - a blocking `NET-WAIT` that suspends as `KEY` does, with a timeout
     against `MS@`.
6. **Box ownership across environments.** Environments are peers
   (`06-ENVIRONMENTS.md`): a game, MEMO and BASIC could all use the
   network, and postboxes are global. An allocator, a word that claims a
   free box and releases it, keeps two programs off the same box.
7. **What survives a session.** Box states and the target table live on
   the stick; the Rebel side's ready mask is transient. Proposal: the
   target table is session-scoped, re-registered after every `HELLO`,
   normally by the program that uses it. That is deterministic and
   portable across project restore, `COLD`, and re-plugging, and it
   settles `NET-STICK.md` §13 item 2 without a `TARGET_LIST` message.
8. **Recovering a lost `POSTBOX_READY`** (`NET-STICK.md` §13 item 3). Since
   nothing is retransmitted, a dropped frame leaves a box waiting
   forever. A small `POSTBOX_STATUS` query, sent when a wait times out,
   closes the gap.
9. **A Rebel-Sim development path.** The simulator is the design lab:
   - build the postbox module against a *virtual stick* in the app,
     backed by `fetch` like `FetchModuleHal`, so the Forth words and
     their use can be designed before any hardware exists;
   - later, talk to a real ESP32 over WebSerial with the same module;
   - test both through loopback tests like the remote terminal's.
10. **Stick-side questions still open in `NET-STICK.md` §13:**
    - the box count (item 1);
    - eviction if Rebel never releases a box (item 4);
    - the format of a condensed response (item 5), which matters more
      now that every answer is condensed (Settled, above);
    - `config` and response specs for each service type beyond HTTP
      (item 6), AI now among them;
    - Wi-Fi and credential provisioning (item 7).
11. **Stream output on a channel, for headless and serial consoles.**
    The constraint that channels are input-only (`01-HAL.md` §5.2) is
    right for display targets, whose screen is a framebuffer of
    positioned, coloured text that MEMO and games depend on and that a
    byte stream cannot carry. But a headless target, driven over a UART
    with no screen, has nowhere to send `EMIT`/`TYPE` output. The same
    goes for a plain serial console, or a telnet-like session over the
    stick. Proposal (2026-10-16), to settle when a headless target or a
    stick console is actually built:
    - relax "input only" to "a channel may have a write side for stream
      output";
    - a session bound to such a channel also sends `EMIT`/`TYPE`/`CR` to
      it, following §5.6's session model;
    - on a display target the screen HAL is written as now; on a
      headless one the channel is the only output;
    - positioned and graphics output (`AT-XY`, `CHAR!`, sprites) never
      goes through a channel;
    - §5.2's wording that output "was never channel-shaped" is true of
      the screen only, and changes accordingly.
