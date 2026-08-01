# Roleplay Event Helper — Phase 1 Plan

**Status:** planning only, no implementation.
**Target client:** World of Warcraft Retail.
**Addon folder / name:** `RoleplayEventHelper` (display name "Roleplay Event Helper", short code `REH`).
**Slash commands:** `/reh`, alias `/rpevent`.

---

## 1. What this addon is

An event host builds a **preset** — a named bundle of house rules for their roleplay event — then presses one button to broadcast those rules, cleanly formatted, into the chat channel of their choice. While the event runs, the addon watches `/roll` results in the room and tells everyone whether each roll passed or failed under the preset's threshold.

The addon is a **rules communicator and dice adjudicator**. It does not enforce anything, does not touch combat, and never speaks unless the host tells it to.

### Design principles

1. **The host is always in control.** Nothing is sent to chat that the host did not explicitly trigger. No auto-greeting, no unsolicited output.
2. **Rules are free-form.** Every number is host-authored. The armor-class health table and the roll threshold ship with sensible defaults, but they are examples, not doctrine.
3. **Readable in chat.** Output must be scannable by a person watching a busy chat window, and must survive the 255-byte-per-message limit without ugly mid-word breaks.
4. **Zero required dependencies.** Any library used is embedded in the addon folder.

---

## 2. Core concept: the Preset

A **preset** is a named, saved configuration. A host might keep several: "Duelling Ring", "Gurubashi Arena Night", "Tavern Brawl (lethal)".

A preset is composed of **rule modules**. Each module can be individually enabled or disabled, and modules are announced in the order shown below (order is user-reorderable).

| # | Module | Purpose |
|---|--------|---------|
| 1 | **Event Header** | Event name, host name, one-line description. |
| 2 | **Roll Rules** | Die size, success threshold, crits, tie-breaks. |
| 3 | **Health by Armor Class** | HP per armor type, shield bonus, custom rows. |
| 4 | **Damage & Healing** | How much a successful hit takes off, healing limits. |
| 5 | **Turn Order** | How initiative is decided and how turns pass. |
| 6 | **Custom Rules** | Ordered list of free-text lines the host writes. |
| 7 | **Etiquette / OOC** | Emote length, OOC brackets, disputes, safety notes. |

### 2.1 Event Header

- `eventName` — string, e.g. "Gurubashi Arena Night"
- `hostName` — string, defaults to the player's own name, editable
- `description` — one line, e.g. "Free-for-all, last one standing wins the pot"
- `showTimestamp` — bool, appends the local time the rules were posted

### 2.2 Roll Rules

- `dieMax` — integer, default `100` (the `/roll` upper bound the host wants used)
- `successThreshold` — integer, default `10`; rolls **at or above** this succeed
- `failText` / `successText` — labels, default "FAILURE" / "SUCCESS"
- `useCritical` — bool. If on:
  - `critSuccessAt` — default `100` (roll equal or above is a critical success)
  - `critFailAt` — default `1` (roll equal or below is a critical failure)
- `tieBreak` — enum: `Reroll` / `Higher armor wins` / `Attacker wins` / `Defender wins` / `Host decides`
- `rollsPerTurn` — integer, default `1`

Announced example, using the values from the original brief (max 100, 9 and below fails):

> **Rolls:** Use `/roll 100`. **1–9 = FAILURE**, **10–100 = SUCCESS**. Natural 100 is a critical success, natural 1 is a critical failure. One roll per turn; ties are rerolled.

### 2.3 Health by Armor Class

Table of rows, each row `{ label, hp }`. Ships with defaults matching the brief, all editable, rows addable and removable:

| Row | Default HP |
|-----|-----------|
| Cloth | 10 |
| Leather | 11 |
| Mail | 12 |
| Plate | 13 |

Plus modifiers, each a named `{ label, bonus }` row:

| Modifier | Default |
|----------|---------|
| Shield equipped | +1 |

Options:
- `autoDetectArmor` — bool. When on, the addon reads the *host's own* equipped armor type and shield slot to show "your HP under these rules" in the UI. **Read-only convenience for the host; it never inspects or announces other players' gear.** Other participants are expected to state their own class/armor in character.
- `startingHpNote` — free-text line appended, e.g. "Announce your HP in /say before the first round."

Announced example:

> **Health:** Cloth 10 · Leather 11 · Mail 12 · Plate 13. **+1 if wearing a shield.** Announce your HP in /say before the first round.

### 2.4 Damage & Healing

- `damagePerHit` — integer, default `1`
- `critDamage` — integer, default `2`
- `healingAllowed` — bool, and if on: `healPerSuccess` (default `1`), `healsPerEvent` (default `2`, `0` = unlimited)
- `deathRule` — enum: `Out at 0 HP` / `Downed, revivable` / `Host decides`

### 2.5 Turn Order

- `initiativeMode` — enum: `Roll for initiative (high to low)` / `Host calls turns` / `Round-robin by join order` / `Free-form`
- `turnTimeSeconds` — integer, `0` = no limit
- `note` — free text

### 2.6 Custom Rules

An ordered list of plain-text lines. Add / edit / delete / move up / move down. Announced as a numbered list. This is the escape hatch for anything the structured modules do not cover ("No mounts in the ring", "Warlocks may not summon during a duel").

### 2.7 Etiquette / OOC

Free-text lines with a few one-click presets the host can insert:
- "Keep emotes to two sentences so the round moves."
- "OOC chat in double parentheses (( like this ))."
- "Disputes are settled by the host; please do not argue in character."
- "If anything makes you uncomfortable, whisper the host."

---

## 3. Announcing to chat

### 3.1 Channel targets

A dropdown on the main frame:

- `/say`, `/yell`, `/emote`
- Party, Raid, **Raid Warning**, Instance chat
- Guild, Officer
- **Custom channel** — pick from the player's joined channels by name (e.g. "MoonGuardRP")
- **Whisper** — to current target or a typed name
- **Preview only** — prints to the host's own chat frame, sends nothing.

**Decided:** *Preview only* is the fresh-install default, so a mis-click can never spam a channel. The host picks a real channel deliberately, once, and it is then remembered per preset.

Availability is validated before sending: Raid Warning requires lead or assist, Guild requires guild membership, Party/Raid require a group, custom channel requires being joined. If the target is unavailable, the send button is disabled with a tooltip explaining why.

### 3.2 Formatting and the 255-byte problem

Chat messages cap at 255 **bytes** (not characters — a UTF-8 accented character costs 2). The formatter must:

1. Build each module into one or more logical lines.
2. Split any line exceeding the limit at word boundaries, never mid-word, and never inside a `|c…|r` colour escape or `|H…|h` link.
3. Optionally prefix continuation lines with a marker (`  …`) so the reader sees they belong together.
4. Emit through a **paced queue**, one message every ~0.6–0.8s, to stay under Blizzard's chat throttle. A visible "Sending 4 of 11…" progress line with a **Cancel** button.

### 3.3 Decorations

- `useColors` — colour headings via `|cffRRGGBB…|r`. Note that colour escapes count toward the 255 bytes; the splitter accounts for this.
- `useSeparators` — a `---` rule line between modules.
- `linePrefix` — optional string prefixed to every line, e.g. `[Event]`, so the rules stand out in a busy channel.
- `announceStyle` — enum: `Full` (every enabled module) / `Summary` (header + roll rules + health only) / `Single module` (a per-module "announce just this" button).

### 3.4 Sample full announcement

```
=== Gurubashi Arena Night — hosted by Zethrel ===
Free-for-all, last one standing wins the pot.
Rolls: use /roll 100. 1-9 = FAILURE. 10-100 = SUCCESS.
Natural 100 = critical success (2 damage). Natural 1 = critical failure.
Health: Cloth 10, Leather 11, Mail 12, Plate 13. +1 with a shield.
Damage: 1 per successful hit, 2 on a critical. You are out at 0 HP.
Turn order: roll for initiative, highest goes first. 60s per turn.
1. No mounts inside the ring.
2. No consumables between rounds.
OOC chat in double parentheses (( like this )). Disputes: host decides.
```

---

## 4. Roll watcher

While armed, the addon listens for roll results in the room and adjudicates them against the active preset.

### 4.1 How it works

- Hook `CHAT_MSG_SYSTEM`. Roll results arrive as system messages.
- Parse using the client's own `RANDOM_ROLL_RESULT` global string converted to a pattern, **not** a hardcoded English string — this keeps the watcher working on every locale.
- Extract `playerName`, `roll`, `min`, `max`.

### 4.2 Filtering

- Ignore rolls whose `min`/`max` do not match the preset's expected range (default: only `1-100`), with a toggle to accept any range.
- Optional roster filter: only adjudicate rolls from names on the participant list (see 4.4).

### 4.3 Output

Two independent switches:
- **Show in my chat frame** (default on) — local, private, costs nothing.
- **Announce to channel** (default **off**) — posts the verdict to the chosen channel. Rate-limited and paced by the same queue as §3.2, because a 20-person free-for-all can produce a burst of rolls.

Verdict line format:

> `Zethrel rolled 74 → SUCCESS` · `Zethrel rolled 4 → FAILURE (critical)`

### 4.4 Session log

A scrollable list of the event's rolls: name, value, verdict, timestamp. Per-name tallies (successes / failures / crits). Buttons: **Clear**, **Copy to clipboard** (a selectable multi-line edit box, since addons cannot write to the system clipboard directly).

The roster is built passively from names seen rolling — the addon does not scan the area or track anyone who has not rolled.

### 4.5 Safety

- Armed/disarmed state is explicit and visible, and **disarms on logout and on reload**. The addon never wakes up talking.
- A hard cap on announced verdicts per minute; if exceeded, it falls back to local-only output and tells the host why.

---

## 5. Preset sharing — export / import strings

- **Export:** serialize the preset table → compress → Base64-ish encode → prefix with a version tag, producing `REH1:…`. Shown in a selectable edit box with a "select all" helper so the host can Ctrl+C it into Discord.
- **Import:** paste the string, the addon validates the version tag and checksum, shows a **preview of what will be imported** (event name, module count), and requires a confirm click. Imports never silently overwrite — a name collision prompts for rename / overwrite / cancel.
- **Libraries — decided:** embed `LibSerialize` + `LibDeflate` under `Libs/`. Both are permissively licensed, battle-tested (WeakAuras uses this exact pair for its import strings), and remove the need to hand-roll a serializer and its edge cases. Vendored into the addon folder, so the addon has no external dependencies and users install one thing.
- Corrupt or wrong-version strings fail with a clear message, never an error spew.

Out of scope for now (deliberately): addon-to-addon channel sync. Attendees receive the rules through the chat announcement, which works whether or not they have the addon installed.

---

## 6. User interface

### 6.1 Main window

Opened by `/reh`, a minimap button (LibDBIcon, embedded), or a Compartment addon button.

```
┌─ Roleplay Event Helper ─────────────────────────────────┐
│ ┌── Presets ──┐  ┌── Editor ──────────────────────────┐ │
│ │ Duel Ring  ▸│  │ [Header][Rolls][Health][Damage]    │ │
│ │ Arena Night │  │ [Turns][Custom][Etiquette]         │ │
│ │ Tavern      │  │ ─────────────────────────────────  │ │
│ │             │  │  (module editor fields)            │ │
│ │ + New       │  │                                    │ │
│ │ ⧉ Copy      │  │                                    │ │
│ │ ✕ Delete    │  │                                    │ │
│ │ ↥ Export    │  │                                    │ │
│ │ ↧ Import    │  │                                    │ │
│ └─────────────┘  └────────────────────────────────────┘ │
│ ┌── Live preview ───────────────────────────────────┐   │
│ │ exactly what will be sent, line by line, with a   │   │
│ │ byte count and message-count badge                │   │
│ └───────────────────────────────────────────────────┘   │
│ Channel: [ Preview only ▾ ]   [ Announce Rules ]        │
│ Roll watcher: ( ) Off  (•) Local  ( ) Announce   [Log]  │
└─────────────────────────────────────────────────────────┘
```

The **live preview** is the centerpiece: the host sees the exact chat output, including how it splits across messages, before anything is sent.

### 6.2 Implementation notes for the UI

- Built on Blizzard's own widget API and templates (`BackdropTemplate`, `UIPanelButtonTemplate`, `ScrollFrame`, `EditBox`) — no Ace3 GUI dependency, keeping the addon light and the look native.
- Frame position saved; `UISpecialFrames` so Escape closes it.
- Every input validated on change, with numeric fields clamped to sane ranges (e.g. threshold cannot exceed die max).

### 6.3 Slash commands

| Command | Effect |
|---------|--------|
| `/reh` | Toggle the main window |
| `/reh announce` | Announce the active preset to the saved channel |
| `/reh preview` | Print the active preset to your own frame |
| `/reh use <name>` | Switch active preset |
| `/reh watch on\|off` | Arm / disarm the roll watcher |
| `/reh list` | List saved presets |
| `/reh help` | Command list |

---

## 7. Data model (SavedVariables sketch)

Account-wide `RoleplayEventHelperDB`, with a per-character pointer to the last active preset.

```lua
RoleplayEventHelperDB = {
  dbVersion   = 1,
  activePreset = "Arena Night",
  settings = {
    minimapButton = { hide = false, minimapPos = 220 },
    framePoint    = { "CENTER", nil, "CENTER", 0, 0 },
    sendDelay     = 0.7,
    useColors     = true,
  },
  presets = {
    ["Arena Night"] = {
      header  = { eventName = "...", hostName = "...", description = "...", showTimestamp = false },
      rolls   = { dieMax = 100, successThreshold = 10, useCritical = true,
                  critSuccessAt = 100, critFailAt = 1, tieBreak = "reroll", rollsPerTurn = 1 },
      health  = { rows = { { label = "Cloth", hp = 10 }, ... },
                  modifiers = { { label = "Shield equipped", bonus = 1 } },
                  note = "..." },
      damage  = { perHit = 1, onCrit = 2, healingAllowed = false, deathRule = "out" },
      turns   = { mode = "initiative", turnTimeSeconds = 60, note = "" },
      custom  = { "No mounts inside the ring.", "No consumables between rounds." },
      etiquette = { "OOC in double parentheses." },
      moduleOrder   = { "header", "rolls", "health", "damage", "turns", "custom", "etiquette" },
      moduleEnabled = { header = true, rolls = true, health = true, ... },
      channel = { type = "CHANNEL", target = "MoonGuardRP" },
    },
  },
}
```

A `dbVersion` field is present from day one so future schema changes can migrate rather than reset people's work.

---

## 8. Proposed file layout for Phase 2

```
RoleplayEventHelper/
├── RoleplayEventHelper.toc
├── Libs/
│   ├── LibStub/
│   ├── LibSerialize/
│   ├── LibDeflate/
│   ├── LibDataBroker-1.1/
│   └── LibDBIcon-1.0/
├── Core/
│   ├── Init.lua          -- namespace, event frame, ADDON_LOADED, DB bootstrap
│   ├── Defaults.lua      -- default preset, default settings
│   ├── Database.lua      -- get/set, migrations, preset CRUD
│   └── Util.lua          -- byte-safe string splitting, colour helpers, validation
├── Modules/
│   ├── Formatter.lua     -- preset table  → ordered list of chat lines
│   ├── Announcer.lua     -- paced send queue, channel validation, cancel
│   ├── RollWatcher.lua   -- CHAT_MSG_SYSTEM parsing, adjudication, tallies
│   └── Transfer.lua      -- export / import strings
├── UI/
│   ├── MainFrame.lua
│   ├── PresetList.lua
│   ├── Editors.lua       -- one editor pane per module
│   ├── Preview.lua
│   └── RollLog.lua
├── Locales/
│   └── enUS.lua          -- all user-facing strings behind L["..."]
└── README.md
```

Localization is stubbed from the start — strings go through `L[...]` even while only `enUS` exists — because retrofitting it later is miserable.

---

## 9. Phase 2 milestones

Each milestone is independently testable in-game.

**M0 — Skeleton (½ day)**
TOC with the correct live `## Interface:` value (read from the client via `select(4, GetBuildInfo())` as the very first task), addon loads clean, `/reh` prints a hello, SavedVariables persists across reload.

**M1 — Data layer**
Defaults, preset CRUD, active-preset switching, migration scaffold. Verified via slash commands before any UI exists.

**M2 — Formatter + preview**
Preset → chat lines, byte-safe splitting, colour handling, `/reh preview`. This is the highest-risk piece for correctness, so it lands before anything can actually talk.

**M3 — Announcer**
Channel dropdown, availability validation, paced queue with cancel and progress. First milestone where the addon speaks.

**M4 — Main UI**
Window, preset list, module editors, live preview pane, announce button.

**M5 — Roll watcher**
Locale-safe parsing, adjudication, local output, session log, then the opt-in announce mode with its rate cap.

**M6 — Export / import**
Serialization, versioned strings, import preview and confirm, collision handling.

**M7 — Polish**
Minimap button, tooltips on every control, `/reh help`, README with screenshots, first tagged release.

---

## 10. Name check and prior art

### 10.1 Name availability — clear

Searched CurseForge, Wago Addons, WoWInterface and GitHub in August 2026. **No addon is published under the name "Roleplay Event Helper."** The nearest names are:

| Existing addon | Why it is not a conflict |
|----------------|--------------------------|
| Roleplaying Helper / Roleplaying Helper 2 | Old, listed under discontinued mods. Different function entirely: auto-emotes and phrases fired by game events. |
| Roleplay Log | A synced text box the party leader edits so latecomers can catch up. |

"Roleplaying Helper" is close enough to be worth noting — a searcher could confuse the two — but it is a long-dead addon with an unrelated purpose, so the name is safe to take. Registering the CurseForge/Wago project slug early is still worth doing.

### 10.2 Prior art — where this addon fits

Several established addons run RP combat, and it is worth being clear that this one is not competing with them:

| Addon | What it does |
|-------|--------------|
| **DiceMaster** | Full D20 tabletop layer: dice notation, health bars, custom traits and abilities. |
| **RPToolkit** | An event system built on D&D 5e mechanics — turn order, player actions, defence prompts. |
| **RP Combat Dice**, **Game Master Dice** | Dice rollers with combat-oriented helpers. |

Those are **systems** — everyone at the event must install them for the mechanics to work. This addon solves a different, smaller, more common problem: **the host has house rules and needs everyone in the room to know them, right now, in chat.** The rules land as plain chat text, so attendees need nothing installed at all. The roll watcher then adjudicates the ordinary `/roll` everyone already uses, rather than replacing it with a custom dice system.

That is the whole positioning, and it should stay that way. Growing this into a full combat system would put it in a crowded field against mature addons; staying the thing that *explains the rules and calls the rolls* keeps it uniquely useful.

---

## 11. Open items to confirm during Phase 2

1. **Interface version.** Must be read from the live client; a wrong `## Interface:` number makes the addon show as out-of-date. First task of M0.
2. **`SendChatMessage` restrictions.** Blizzard periodically tightens what addons may send and when (hardware-event requirements, throttles, restricted channels). Verify current behaviour on the live client at M3 and adapt the queue — including a graceful "your client blocked this send" path rather than a silent failure.

### Resolved in Phase 1

- **Default channel:** Preview only. *(§3.1)*
- **Export/import:** embed LibSerialize + LibDeflate. *(§5)*
- **Name:** "Roleplay Event Helper" is unclaimed and safe to use. *(§10.1)*

---

## 12. Explicit non-goals

- No combat log parsing, no automation of actual game combat.
- No inspection or announcement of other players' gear, class, or spec.
- No addon-to-addon preset sync (revisit after release if there is demand).
- No enforcement — the addon informs, the host rules.
- No auto-posting on a timer, and no output the host did not trigger.
