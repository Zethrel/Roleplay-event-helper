# Changelog

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
