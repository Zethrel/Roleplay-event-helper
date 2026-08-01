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
| M1 — Data layer: presets, defaults, migrations | next |
| M2 — Formatter and preview | |
| M3 — Announcer (first milestone where it talks) | |
| M4 — Main UI | |
| M5 — Roll watcher | |
| M6 — Export / import strings | |
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
| `/reh` | Command list |
| `/reh version` | Addon version, client build, and interface numbers |

`/rpevent` works as an alias for `/reh`.

If the client updates to a patch newer than the addon's TOC, the addon says so at
login and tells you the exact `## Interface:` number to change it to.

## Running the tests

The addon is tested outside the game against a stub of the WoW API, so bootstrap
regressions get caught without a client. Requires Lua 5.1 (the version WoW uses):

```sh
lua5.1 Tests/M0_Bootstrap.lua
```

It checks that the TOC is consistent with the code, that the addon loads and
registers cleanly, that saved variables persist across a reload, that no stray
globals are created, and that the interface-version self-check fires correctly.

## Design principles

1. **The host is in control.** Nothing reaches chat that the host did not
   explicitly trigger. No auto-greeting, no output on login.
2. **Every number is yours.** The armor-class health table and roll threshold
   ship with defaults, but they are examples, not rules.
3. **No required dependencies.** Any library used is bundled.
4. **Minimal reach.** The addon reads your own group's roster and your own
   equipped gear. It does not scan the area or inspect other players.
