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

**v1.11.0**, in use and being fixed as the game finds things. Covered by 1159
checks across twelve suites, which run against a stub of the WoW API rather than
the client -- see the [changelog](CHANGELOG.md) for what that does and does not
catch.

| Milestone | State |
|-----------|-------|
| M0 — Skeleton: loads clean, `/reh`, saved variables | ✅ done |
| M1 — Data layer: presets, defaults, migrations | ✅ done |
| M2 — Formatter and preview | ✅ done |
| M3 — Announcer (first milestone where it talks) | ✅ done |
| M4 — Main UI | ✅ done |
| M5 — Roll watcher | ✅ done |
| M6 — Export / import strings | ✅ done |
| M7 — Polish and first release | ✅ done |

The full feature design lives in [`docs/PHASE1-PLAN.md`](docs/PHASE1-PLAN.md).

## Requirements

- World of Warcraft **Retail**, interface `120007` (patch 12.0.7).

## Installing

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
| `/reh include [section] [on\|off]` | Choose which sections are announced |
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
| `/reh round [new]` | Start a new round, or show the current one |
| `/reh loot [on\|off\|test <roll>]` | The result table read off each roll |
| `/reh effects [list\|test <roll>]` | Open the roll effects window |
| `/reh filter [mode]` | Whose rolls are tracked |
| `/reh subgroups <numbers>` | Raid subgroups counted as combatants |
| `/reh range [atmost\|exact\|any]` | Which dice sizes count |
| `/reh roster [import\|add\|remove\|clear]` | Edit the saved roster |
| `/reh mute <name>` / `/reh unmute <name>` | Ignore one name this session |
| `/reh export [name]` | Get a shareable string for a preset |
| `/reh import [string]` | Import a preset from a string |
| `/reh minimap` | Show or hide the minimap button |
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

## Releasing

Tagging is the release. Pushing a `v*` tag runs the test suites and then builds
and uploads the addon zip from [`.pkgmeta`](.pkgmeta):

```sh
git tag -a v1.11.0 -m "Roleplay Event Helper v1.11.0"
git push origin v1.11.0
```

The CurseForge project id is already set in the TOC. One thing is still needed
before the first automated upload: **`CF_API_KEY`** as a repository secret
(*Settings → Secrets and variables → Actions*), taken from your CurseForge
account's API Tokens page.

Without it the workflow still packages the zip and attaches it to a GitHub
release; it just does not upload to CurseForge.

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

## Your first event in four steps

1. `/reh` opens the window. On the **Rolls** and **Health** tabs, set the numbers
   your event runs on — the defaults are `/roll 100`, 10 or higher succeeds, and
   Cloth 10 / Leather 11 / Mail 12 / Plate 13 with `+1` for a shield.
2. Add anything else on the **Rules** tab, one rule per line.
3. Pick where it goes with the channel button at the bottom left, then press
   **Announce Rules**. The preview pane above shows exactly what will be sent.
4. Set the watcher to **verdicts to me** and it will call each `/roll` a success
   or failure as your event runs.

## The window

`/reh` opens the main window. On the left is your preset list with New, Copy,
Rename and Delete. On the right are tabbed editors — Event, Rolls, Health,
Damage, Turns, Loot, Rules, Etiquette. Along the bottom is the **live preview**: the
exact messages that will be sent, with byte counts and an estimate of how long
the announcement takes. Editing any rule updates it immediately.

**The windows resize.** Drag the grip in the bottom-right corner to make one
bigger; double-click the grip to go back to the default. Each window remembers
its own size between sessions.

| Window | Where the extra room goes |
|---|---|
| Main | Most of the height to the preview, so a long rule set reads in one go; width to the editor |
| Roll log | All of it to the text |
| Roll effects | Width to the message boxes, the one field that runs out of room |

Health rows and rule lists are edited as plain text, one entry per line
(`Cloth 10`, `Shield equipped +1`), so a whole rule set can be pasted in or out.

Each custom rule and etiquette line is announced as its own chat message, so
what you typed on separate lines arrives on separate lines. Two thoughts that
belong together can be typed on one line.

The Announce button names its target — `Announce to party chat`, or
`Preview only` when the preset sends nothing. It disables itself when that
target is unavailable and the status line beneath says which condition failed,
so a greyed-out button never leaves you guessing.

The preview shows a byte count only when a message is getting close to the
255-byte limit, or in red when a rule was too long and had to be split in two.
Separator lines are dimmed and counted separately in the summary, since they are
the one part of the message count you can delete without losing a rule.

A tab whose section is switched out of the announcement carries a small red dot,
so a missing section is visible from the strip rather than found by clicking
through every tab.

## Events without combat

Not every event needs rolls. Each tab has an **Announce this section** toggle,
so the roll, health, damage and turn rules can be left out of a tavern night
without deleting them — turn them back on for the next duel. `/reh include`
does the same from chat.

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

**Start Round** on the main window starts a round, announces it to your channel
("Round 2 begins."), and opens the roll log. Right-click it to just open the log.
The message is editable on the Watcher tab, where announcing rounds can also be
turned off.

The log groups rolls into **rounds**. **New round** starts a fresh one; the
arrows read back through earlier rounds, and stepping back past round one shows
the whole event together with per-name totals. The log follows live rolls while
you are on the current round and holds still while you are reading an earlier
one.

A raid caps at 40. If your event outgrows that, `/reh roster import` snapshots
the current group into a list that survives group changes. And when rolls are
being ignored by your filter, the addon says so once — silently dropping a
participant's roll is worse than adjudicating a stranger's.

**Wounded characters rolling smaller dice are counted.** An event on `/roll 100`
also tracks `/roll 20` and `/roll 15` by default, and the verdict names the die
when it differs — `Bob rolled 12 (1-15) -> SUCCESS`. By default the threshold is **not** scaled down, so the
smaller die is itself the penalty; *Scale the threshold to smaller dice* on the
Watcher tab keeps their odds the same instead. `/reh range exact` restores
strict matching.

Cross-realm names are normalized on both sides, so `Faraway-Moon Guard` matches
whether the roster or the system message spells it with a space.

## Loot tables

Not every roll is a fight. On the **Loot** tab you can give the event a result
table, and the addon reads each roll off it:

```
1-3    an anchovy
4-10   an old boot
11-89  a river trout
90-99  a gleaming salmon
100    the legendary whale
```

Someone rolls a 3 and, a few seconds later, `Rennek has caught an anchovy.`
One entry per line — a range or a single number. The line itself is yours:
`{name}`, `{item}` and `{roll}` are filled in.

**Write the same range more than once for several possible results**, and one
is picked at random:

```
4-7    a salmon
4-7    a trout
4-7    a carp
```

Only an identical range joins the pool, so a narrow band listed above a wide one
still wins outright — `100 the legendary whale` above `90-100 a big fish` keeps
working. `/reh loot test 5` lists every alternative a roll could give.

It is **off by default**, has its own send switch separate from the watcher's
verdicts, and obeys the same filter as everything else — whoever the watcher
ignores is not handed a fish. A roll no band covers says nothing unless you give
it something to say. `/reh loot test 3` shows what a roll would give without
waiting for one.

The table can be announced with your rules like any other section, or left out
of the announcement to keep the catches a surprise.

**One limitation, worth knowing before the event.** The result is sent a few
seconds after the roll rather than from a button press, and the client will not
let an addon reach `/say`, `/yell`, `/emote`, whispers or custom channels that
way. Party, raid, guild, officer and instance chat are delivered every time. The
addon says so once when you set it up against a restricted channel; if your
event runs in `/say`, turn *Send results to my channel* off and read them out.

## Roll effects

The loot table answers *what did that roll catch*. An effect answers *what
happens on that roll*, and it can do three things the table cannot. Open it with
**Roll effects...** on the Loot tab, or `/reh effects`.

| | |
|---|---|
| **Fires on** | a number, a range, a success, a failure, a critical either way, or every roll |
| **How many** | all the effects that match, not just the first — or tick **one of these at random** on a group sharing a trigger and only one fires |
| **Each one has** | its own chance, delay, and destination |

So a fishing night can say `Rennek's line snaps.` on a natural 1, `A monster!`
on a critical success 25% of the time, and `A splash.` on every cast — three
separate lines, each on its own timing.

`{name}`, `{roll}` and `{result}` are filled in, and `{item}` reaches across to
whatever the loot table gave that same roll, so the catch and what happens next
can be two lines rather than one crowded one.

**Try it** in the window — or `/reh effects test 1` — shows what a roll would
set off without waiting for anyone to roll it and without sending anything.
Chance and delay are ignored there so you see every effect that matches.
`/reh effects list` reads the whole set back in plain English.

Effects are per preset and travel in export strings. An event with none behaves
exactly as it did before they existed.

The delayed-message limitation from the loot table applies here too — but an
effect set to **to me only** is never subject to it, which is how to run this at
a `/say` event: the addon tells you what happened and you say it in character.

### When nothing arrives in chat

Three things stop a result reaching the room, and each says so once rather than
leaving you guessing mid-event:

- **the roll watcher is off** — no rolls are being read at all, so nothing can
  fire. This is the usual one. The window's status line says it while it is
  true, and switching results on says it too.
- **the channel is not available** — not in that party, not in that raid.
- **the preset is still on preview only**, which sends nothing by design.

## Sharing presets

**Export** turns a preset into a string starting `REH1:` — short enough to paste
into Discord. **Import** takes it back. Strings survive being wrapped across
lines by a chat client, and an import shows you what you are about to get before
anything is saved. If the name collides with one you already have, you choose
between overwriting and keeping both; nothing is replaced silently.

Attendees do not need to import anything — the rules reach them as ordinary chat
text. This is for handing a rule set to another host.

An imported preset is treated as untrusted input: size-capped before
decompression, then coerced through the same validation as a hand-edited saved
file, so a malformed or hostile string cannot produce a preset that misbehaves
later.

## Bundled libraries

`Libs/` contains three vendored libraries, unmodified:

| Library | Licence | Used for |
|---------|---------|----------|
| [LibStub](https://www.wowace.com/projects/libstub) | Public domain | Library registry |
| [LibDeflate](https://github.com/SafeteeWoW/LibDeflate) | zlib | Compressing export strings |
| [LibSerialize](https://github.com/rossnichols/LibSerialize) | MIT | Serializing presets |

## Licence

[MIT](LICENSE). The libraries in `RoleplayEventHelper/Libs/` are third-party
work redistributed under their own licences, which ship alongside them.

## Support

If this saves you time at your events, you can support development at
[ko-fi.com/zethrel](https://ko-fi.com/zethrel). Entirely optional — the addon is free and always will
be.

## Design principles

1. **The host is in control.** Nothing reaches chat that the host did not
   explicitly trigger. No auto-greeting, no output on login.
2. **Every number is yours.** The armor-class health table and roll threshold
   ship with defaults, but they are examples, not rules.
3. **No required dependencies.** Any library used is bundled.
4. **Minimal reach.** The addon reads your own group's roster and your own
   equipped gear. It does not scan the area or inspect other players.
