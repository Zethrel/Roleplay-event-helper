# Roleplay Event Helper

A World of Warcraft addon for people who host roleplay events.

Build a **preset** of your event's house rules — health per armor class, what a
`/roll` needs to hit to succeed, turn order, whatever else you run — then press
one button and the rules go out to the chat channel of your choice, formatted so
they are actually readable. While the event runs, the addon watches `/roll`
results from your group and calls each one a success or a failure against your
threshold.

Attendees do not need the addon. The rules arrive as ordinary chat text, and the
watcher adjudicates the plain `/roll` everyone already uses.

---

## Status

**Early development — not yet usable at an event.**

| Milestone | State |
|-----------|-------|
| M0 — Skeleton: loads clean, `/reh`, saved variables | ✅ done |
| M1 — Data layer: presets, defaults, migrations | ✅ done |
| M2 — Formatter and preview | ✅ done |
| M3 — Announcer (first milestone where it talks) | ✅ done |
| M4 — Main UI | ✅ done |
| M5 — Roll watcher | ✅ done |
| M6 — Export / import strings | next |
| M7 — Polish and first release | |

The full feature design lives in [`docs/PHASE1-PLAN.md`](docs/PHASE1-PLAN.md).

## Requirements

- World of Warcraft **Retail**, interface `120007` (patch 12.0.7).

## Installing (development build)

Copy the `RoleplayEventHelper` folder into:

```
World of Warcraft/_retail_/Interface/AddOns/
```

so that `Interface/AddOns/RoleplayEventHelper/RoleplayEventHelper.toc` exists,
then restart the client or `/reload`.

## Commands

| Command | Effect |
|---------|--------|
| `/reh` | Open or close the main window |
| `/reh help` | Command list |
| `/reh list` | List your presets, marking the active one |
| `/reh show [name]` | Show a preset's rules in detail |
| `/reh preview [name]` | Show exactly what would be sent to chat, sending nothing |
| `/reh announce [name]` | Send the rules to the chosen channel |
| `/reh channel [type] [name]` | Choose where announcements go |
| `/reh cancel` | Stop an announcement in progress |
| `/reh use <name>` | Switch the active preset |
| `/reh new <name>` | Create a preset from the defaults |
| `/reh copy <new name>` | Copy the active preset |
| `/reh rename <new name>` | Rename the active preset |
| `/reh delete <name>` | Delete a preset (asks to confirm) |
| `/reh reset` | Reset the active preset to defaults (asks to confirm) |
| `/reh confirm` | Confirm the pending action |
| `/reh watch [on\|off\|announce]` | Arm or disarm the roll watcher |
| `/reh log [clear]` | Show this session's rolls and per-name totals |
| `/reh filter [mode]` | Whose rolls are tracked |
| `/reh subgroups <numbers>` | Raid subgroups counted as combatants |
| `/reh roster [import\|add\|remove\|clear]` | Edit the saved roster |
| `/reh mute <name>` / `/reh unmute <name>` | Ignore one name this session |
| `/reh version` | Addon version, client build, and interface numbers |

`/rpevent` works as an alias for `/reh`. Preset names may contain spaces.

### Announcing

`/reh channel` picks the target: `preview` (default), `say`, `yell`, `emote`,
`party`, `raid`, `warning`, `instance`, `guild`, `officer`,
`channel <name>`, or `whisper <name>`. Short aliases work — `/reh channel rw`.

A new preset announces to **preview only**, so the first press can never
surprise a channel. The addon refuses to send when the target is not available
— not in the raid, not in that channel, no assist for a raid warning — and says
which it is rather than failing silently.

Messages are paced (0.7s apart by default) so the client does not drop them.
`/reh cancel` stops mid-announcement. If the client refuses a message, the queue
stops and reports which message failed, rather than leaving half a rule set in
the channel.

Deleting and resetting ask for confirmation, because preset names get similar
fast ("Duel Ring", "Duel Ring 2") and a mistyped delete otherwise costs you an
evening's setup. The prompt expires after 30 seconds, and any other command
cancels it, so a stale prompt can never be answered by a later `confirm`.

If the client updates to a patch newer than the addon's TOC, the addon says so at
login and tells you the exact `## Interface:` number to change it to.

## Running the tests

The addon is tested outside the game against a stub of the WoW API, so bootstrap
regressions get caught without a client. Requires Lua 5.1 (the version WoW uses):

```sh
./Tests/run.sh          # VERBOSE=1 ./Tests/run.sh to see every check
```

The suites cover the TOC staying consistent with the code, a clean load and
event bootstrap, saved variables persisting across a reload, no stray globals,
preset create/copy/rename/delete/reset, and the validation layer's handling of
corrupt or hand-edited saved data.

## The window

`/reh` opens the main window. On the left is your preset list with New, Copy,
Rename and Delete. On the right are tabbed editors — Event, Rolls, Health,
Damage, Turns, Rules, Etiquette. Along the bottom is the **live preview**: the
exact messages that will be sent, with byte counts and an estimate of how long
the announcement takes. Editing any rule updates it immediately.

Health rows and rule lists are edited as plain text, one entry per line
(`Cloth 10`, `Shield equipped +1`), so a whole rule set can be pasted in or out.

The Announce button disables itself when the target is unavailable and the
status line says which condition failed, so a greyed-out button never leaves you
guessing.

## The roll watcher

`/reh watch on` starts adjudicating `/roll` results against the active preset —
`Bob rolled 74 -> SUCCESS`. `/reh watch announce` also posts each verdict to
your channel, capped at 20 a minute so a busy free-for-all cannot flood it.

**The watcher always starts off.** It is never running because it was running
last week, and arming is not saved across a reload or a logout.

Whose rolls count is set per preset:

| Filter | Tracks |
|--------|--------|
| `group` | Everyone in your party or raid (default) |
| `subgroup` | Only the raid subgroups you choose |
| `roster` | A saved name list, independent of the group |
| `everyone` | Every roll heard |

`subgroup` is the one for large events: put combatants in raid subgroups 1–2 and
the audience in 3–8, and spectators rolling for fun are ignored. An empty
selection means the whole raid, never nobody.

A raid caps at 40. If your event outgrows that, `/reh roster import` snapshots
the current group into a list that survives group changes. And when rolls are
being ignored by your filter, the addon says so once — silently dropping a
participant's roll is worse than adjudicating a stranger's.

Cross-realm names are normalized on both sides, so `Faraway-Moon Guard` matches
whether the roster or the system message spells it with a space.

## Design principles

1. **The host is in control.** Nothing reaches chat that the host did not
   explicitly trigger. No auto-greeting, no output on login.
2. **Every number is yours.** The armor-class health table and roll threshold
   ship with defaults, but they are examples, not rules.
3. **No required dependencies.** Any library used is bundled.
4. **Minimal reach.** The addon reads your own group's roster and your own
   equipped gear. It does not scan the area or inspect other players.
