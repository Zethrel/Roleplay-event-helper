# Changelog

## 1.4.2 - 2026-08-01

Fixes the multi-line boxes still refusing clicks after 1.4.1.

- Each one had a scroll frame of its own, sitting inside the editor page's
  scroll frame. Nested scroll frames compete for the click, and the edit box
  underneath never received focus -- so Health by armor, Modifiers, Custom
  rules, Etiquette and the saved roster all looked present and ignored typing.
  The inner scroll frame is gone; the page already scrolls.
- The font is now set from the font object rather than its name, since an edit
  box with no font resolved neither renders nor accepts input.
- A box grows with its text and the rows below it move down, so a long rule
  list stays reachable through the page's own scrolling instead of running
  under the next field.

## 1.4.1 - 2026-08-01

Fixes the multi-line boxes refusing to accept typing.

- The edit box inside each multi-line field had no height. A frame with no
  height has no area to click, so it could never take focus and nothing typed
  reached it -- the box looked present and ignored you. This affected Custom
  rules, Etiquette, Health by armor, Modifiers and the saved roster.
- Clicking anywhere in the panel now puts the cursor in the text, rather than
  needing a hit on the text itself.
- The box grows with its contents, so a long list scrolls instead of running
  off the bottom.

## 1.4.0 - 2026-08-01

**Scaling the threshold to smaller dice is now a choice.** *Scale the threshold
to smaller dice* on the Watcher tab:

- **off** (default, unchanged): a wounded character on `/roll 15` still needs
  the event's number, so the reduced die is the penalty
- **on**: the threshold moves with the die -- `10+` on `/roll 100` becomes `2+`
  on `/roll 15` -- keeping their odds the same and making the smaller die
  flavour rather than a handicap

With scaling on, the verdict shows what they needed:
`Bob rolled 2 (1-15, 2+) -> SUCCESS`. Nothing scales below 1 or above what the
die can roll, and the critical-failure band rounds down while the success bands
round up, so scaling never widens what counts as a critical failure.

**New presets have no turn timer.** The default was 60 seconds; it is now 0,
meaning no limit, and the timer line is left out of the announcement entirely.
Not everyone types quickly, and a countdown on someone composing an emote is
pressure the host did not ask for. Existing presets keep whatever they were
set to -- change it on the Turns tab.

## 1.3.0 - 2026-08-01

**Smaller dice are now counted.** The roll watcher used to want the exact die
from your rules and ignored everything else, so a wounded character rolling
`/roll 15` at an event running on `/roll 100` simply vanished from the log.

**Count rolls on** on the Watcher tab now offers:

- **that die or a smaller one** (new default) -- `/roll 100`, `/roll 20` and
  `/roll 15` all count; a roll on a *bigger* die still does not
- **only that exact die** -- the old behaviour
- **any die at all**

`/reh range atmost|exact|any` does the same from chat. Presets saved before
this keep the behaviour their host set up.

When a roll is counted on a different die, the verdict says which:
`Bob rolled 12 (1-15) -> SUCCESS`. Without it, a 12 reads as a near miss until
you know it was out of fifteen. The threshold is not scaled to the smaller die,
because rolling a smaller die is itself the penalty.

A roll ignored for its die now says so once, naming the die and how to accept
it, rather than disappearing silently.

## 1.2.0 - 2026-08-01

**Starting a round tells the room.** The main window's log button is now
**Start Round**: one press starts a round, announces it to your channel, and
opens the roll log. The log's own **New round** button announces too, as does
`/reh round new`. Right-clicking Start Round just opens the log, for checking
back through earlier rounds without starting anything.

The message is set on the Watcher tab and defaults to "Round {round} begins.";
`{round}` is replaced with the number. It is a placeholder rather than a
printf token deliberately, so a percent sign typed into the text prints
instead of erroring. Announcing rounds can be switched off there, which leaves
the button starting rounds silently.

A round marker is held back while a rules announcement is still going out,
rather than interleaving with it, and a preview-only preset shows the marker
locally like everything else.

## 1.1.0 - 2026-08-01

**Rounds in the roll log.** A **New round** button starts a fresh round, and
the arrows either side of the round label read back through earlier ones.
Stepping back before round one shows every round together, with each roll
marked by the round it belongs to and per-name totals for the whole event.

A log left on the current round keeps up with live rolls on its own. One
pinned to an earlier round stays there, so reading back through round two is
not interrupted every time somebody rolls. Pressing New round twice without a
roll in between does nothing, rather than stacking up empty rounds.

`/reh round` and `/reh round new` do the same from chat.

**Choosing which sections are announced.** Every section now has an
**Announce this section** toggle at the top of its tab, so an event with no
rolls or combat can leave those out without deleting the rules — the same
preset can be switched back for the next duelling night. `/reh include` lists
what is on and off, and `/reh include <section> on|off` changes it.

`moduleEnabled` was in the data model from the start but had no way to reach
it short of editing saved variables.

## 1.0.5 - 2026-08-01

Fixes the roll log not updating while it is open.

- The log window redrew only when it was opened, so a roll made while it was
  already on screen never appeared. It now updates as each roll is
  adjudicated, and when the log is cleared.
- The scroll area inside the log grows with its contents and follows the
  newest roll, instead of staying fixed at its original height so that
  everything past the first screenful was unreachable.
- The preview pane had the same latent problem and is fixed with it: a long
  rule set can now be scrolled.

## 1.0.4 - 2026-08-01

Fixes a Lua error when the client stops accepting messages mid-announcement,
and lets a stopped announcement carry on.

- `ADDON_ACTION_BLOCKED` fires *during* `SendChatMessage`, so the handler that
  stops the queue ran while the sender was still on the stack. The sender then
  read a queue that had already been cleared: "attempt to get length of field
  'messages' (a nil value)". Everything the send needs is now captured before
  the call, and the queue state is re-checked afterwards.
- `/say`, `/yell`, `/emote`, whispers and custom channels turn out to allow
  only a limited number of addon messages behind one click, rather than
  refusing all but the first. A blocked announcement now remembers where it
  stopped, and pressing Announce again carries on from that message instead of
  restarting and repeating what already landed.
- `/reh cancel` discards a pending continuation.

## 1.0.3 - 2026-08-01

Fixes announcements to `/say` stopping after the first message.

- The client refuses an addon send to `/say`, `/yell`, `/emote`, whispers and
  custom channels unless a hardware event is behind it. A timer callback has
  none, so the first message of an announcement arrived and every one after it
  was blocked. Those channels now send every message in the call stack of the
  click that started the announcement, which keeps the event behind all of
  them. Party, raid, guild and officer chat are unaffected and stay paced.
- The send mode is chosen per channel by default (`/reh sendmode auto`), so
  this needs no setting up. `paced` and `burst` still force one.
- A blocked send now stops the announcement and explains it **once**, naming
  the message and offering a channel that works, instead of producing one
  error line per remaining message.
- Choosing a restricted channel says so at the time rather than letting the
  host discover it mid-event.

## 1.0.2 - 2026-08-01

Diagnostics for the "Interface action failed because of an AddOn" message.

- That message is not a Lua error, so `/console scriptErrors 1` never shows
  it. The addon now listens for `ADDON_ACTION_BLOCKED` and
  `ADDON_ACTION_FORBIDDEN` and reports which function the client blocked,
  and which message of the announcement it happened on. `/reh blocked`
  lists them along with the client build and locale.
- Adds `/reh sendmode burst`, which sends every message in the call stack of
  the click that started the announcement instead of spacing them out with a
  timer. If the client requires a hardware event behind a send, a timer
  callback has none, and burst mode restores it.
- A cancelled announcement now says it was cancelled by you, so it cannot be
  mistaken for the addon giving up on its own.

## 1.0.1 - 2026-08-01

Fixes announcements arriving as a single message.

- The client silently drops an outgoing chat message that contains colour
  escapes. `SendChatMessage` returns normally and nothing errors, so the
  addon counted every dropped message as sent: a six-message announcement
  delivered only the one line that happened to have no colour in it, while
  reporting all six as sent.
- Rule text bound for chat is no longer coloured, and escapes are stripped
  from every message before it is sent -- including colour codes a host
  pastes into a rule themselves, which would otherwise make that one rule
  vanish with no explanation.
- The preview pane therefore shows exactly what is sent, which was always
  the intent.
- The "Colour the announcement" option is removed, since it could only ever
  break delivery. Local output -- `/reh show`, the preview numbering, roll
  verdicts in your own chat frame -- is still coloured.

## 1.0.0 - 2026-08-01

First release. Everything described in
[`docs/PHASE1-PLAN.md`](docs/PHASE1-PLAN.md) is implemented and covered by
702 checks across eight test suites that run outside the client.

**Presets**
- Named rule presets with health by armor class, roll thresholds, criticals,
  damage, turn order, custom rules and etiquette lines
- Create, copy, rename, delete and reset, with confirmation on the destructive ones
- Saved data is validated on every load, so a hand-edited file cannot break the addon

**Announcing**
- Live preview of the exact chat messages, with byte counts and a time estimate
- Byte-safe splitting that never breaks a colour code, hyperlink or UTF-8 character
- Adjacent rules are packed into fewer messages
- Paced send queue with cancel, and channel availability checked before sending
- Say, yell, emote, party, raid, raid warning, instance, guild, officer, custom
  channels and whispers; new presets default to preview only

**Roll watcher**
- Adjudicates ordinary `/roll` results against the active preset
- Group, raid-subgroup, saved-roster and everyone filters
- Cross-realm name matching and locale-independent roll parsing
- Session log with per-name totals; verdicts optionally announced, rate-capped
- Always starts disarmed

**Sharing**
- Export and import presets as `REH1:` strings
- Imports are validated as untrusted input and confirmed before saving

**Interface**
- Main window with preset list, tabbed editors, live preview and announce controls
- Roll log window, transfer window, minimap button and addon compartment entry
- Options tab for colours, message packing, send delay and the minimap button

**Known gaps**
- The test suites run against a stub of the WoW API, not the client. Anything
  purely visual -- window layout, sizing, text clipping, whether all nine editor
  tabs fit across the tab strip -- is unverified, as is the behaviour of the
  Blizzard templates the interface builds on.
- No broker (Titan Panel / ElvUI datatext) plugin. The minimap button is
  self-contained so the addon has no external dependencies.
- English only, though every user-facing string goes through the localization
  table, so adding a locale needs no code changes.
