# Roleplay Event Helper — CurseForge description

Paste the section below into the CurseForge project description. The editor
accepts Markdown.

---

## Roleplay Event Helper

**Announce your event's house rules to chat, then let the addon call the rolls.**

You host a duel, an arena night, a tavern brawl. You have house rules — what a
`/roll` needs to hit, how much health each armour type gets, what happens at 0
HP — and every event begins with you typing them out again, or pasting a wall of
text nobody reads.

This addon keeps those rules as a **preset**. One button sends them to the chat
channel of your choice, formatted so they can actually be read. While the event
runs it watches `/roll` results and calls each one a success or a failure
against your threshold.

**Your attendees do not need this addon.** The rules arrive as ordinary chat
text, and the watcher adjudicates the plain `/roll` everyone already uses. Only
the host installs anything.

### Getting started

1. `/reh` opens the window.
2. On the **Rolls** and **Health** tabs, set the numbers your event runs on. The
   defaults are a worked example — `/roll 100`, 10 or higher succeeds, Cloth 10
   / Leather 11 / Mail 12 / Plate 13, `+1` with a shield — and every one of them
   is meant to be changed.
3. Put your own rules on the **Rules** tab, one per line. Each line is announced
   as its own message, so they stay readable.
4. Choose where they go with the channel button at the bottom left. The preview
   pane above shows the exact messages that will be sent, before you send them.
5. Press **Announce Rules**.
6. Press **Start Round** to call a round, announce it, and open the roll log.
   Set the watcher to **verdicts to me** and every `/roll` is judged as it
   happens.

A new preset is set to **preview only**, so your first press can never surprise
a channel by accident.

### What it does

**Presets.** Health by armour class, roll thresholds, criticals, damage,
healing, turn order, custom rules, etiquette lines. Keep one per event and
switch between them.

**Only the rules you want.** Every section has an *Announce this section*
toggle, so a tavern night can leave out the combat rules without deleting them.

**A live preview.** The exact chat messages, with byte counts and a time
estimate. Nothing is ever sent that you have not already seen.

**Readable output.** Messages are split at word boundaries, never mid-word or
mid-character, and paced so the client does not drop them. Announcements can be
cancelled part-way.

**The roll watcher.** `Bob rolled 74 -> SUCCESS`, judged against your own rules
and your own wording. Verdicts can stay private to you or go to the channel.

**Whose rolls count.** Everyone in your party or raid, only chosen raid
subgroups, a saved roster, or every roll heard. The subgroup filter is for large
events: put combatants in subgroups 1–2 and the audience in 3–8, and spectators
rolling for fun are ignored.

**Wounded characters.** A character rolling a reduced die — `/roll 15` at an
event running on `/roll 100` — is counted, and the verdict names the die. You
choose whether the threshold scales with it or the smaller die is the penalty.

**Rounds.** Start a round, announce it, and read back through earlier rounds in
the log with per-name totals for the whole event.

**Cross-realm and any locale.** Names are matched whether or not the realm is
spelled with a space, and roll results are parsed from the client's own format
string rather than English text.

**Sharing.** Export a preset as a short `REH1:` string to hand to another host,
and import theirs.

### Commands

`/reh` opens the window; `/reh help` lists everything. `/rpevent` works as an
alias.

The ones worth knowing: `/reh announce`, `/reh channel party`, `/reh watch on`,
`/reh round new`, `/reh log`, `/reh export`.

### Worth knowing

Your client limits how much an addon may send to `/say`, `/yell`, `/emote`,
whispers and custom channels in one go. A long rule set may stop part-way there;
the addon tells you exactly where and pressing **Announce Rules** again carries
on from that message. **Party, raid, guild and officer chat have no such limit.**

The addon never speaks unless you ask it to. It says nothing at login, the roll
watcher always starts switched off, and it never inspects other players' gear or
scans the area — it reads your own group's roster and nothing else.

### Requirements

World of Warcraft **Retail**, interface `120007` (patch 12.0.7).

### Licence

MIT. The bundled libraries (LibStub, LibDeflate, LibSerialize) are
redistributed under their own licences, included with them.

### Bugs and suggestions

Please report anything odd on the
[issue tracker](https://github.com/Zethrel/Roleplay-event-helper/issues) — the
more specific the better ("message 2 of 10 to /say" is the kind of detail that
gets things fixed quickly).

---

☕ **If this addon saves you time at your events, you can support development at
[ko-fi.com/zethrel](https://ko-fi.com/zethrel).**
