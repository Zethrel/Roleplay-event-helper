# Changelog

## Unreleased

**The Fishing Night starter now whispers the catch.** A fresh one arrives set to
*to the roller*, so only the person who cast is told what they landed. They can
announce it in their own words, make a meal of hauling it in, or say nothing and
let the dock wonder.

Three things changed with it, so the default actually works:

- the result line reads **"You reel in a fat carp."** rather than naming the
  roller in the third person, because it arrives as a whisper to the one person
  it happened to. Point it back at your channel and it wants rewording.
- the rules now say the catch is whispered, and invite people to tell the dock
  in their own words
- **the results table is no longer announced with the rules.** The `/roll` is
  public, so posting the table lets anyone read "18-19 = a sturgeon" off a roll
  they watched — the whisper would be theatre. Switch the Loot section back on
  under *Include in the announced rules* if you would rather publish it.

The room's reactions are unchanged and still public: nobody drops a tankard
privately.

Existing presets are untouched. This is the starter only, so make a fresh
Fishing Night to pick it up.

## 1.18.0 - 2026-08-04

**"Set all to..." in the roll effects window.** One click points every effect at
the same destination — your channel, yourself, or the roller — for an evening
you want kept private, or read out in the room. `/reh effects all roller` does
the same from chat.

It changes each row rather than linking them. Every effect still says where it
goes, so "who sees this line" is answered by looking at the line, and you can
still set one row back on its own afterwards.

That is deliberate, and worth saying why: a roll effect is not always aimed at
the same people as the catch. *"Somebody drops their tankard watching you land
it"* is the room watching — nobody drops a tankard privately. So the two stay
independent, with a fast way to line them up when you do want them the same.

## 1.17.1 - 2026-08-04

**Two settings were both called "Announce", and meant different things.**
Reported from an event: a host switched *Announce this section* off on the Loot
tab expecting results to stop reaching chat, and they carried on.

They do different jobs, and the labels now say so:

- **Include in the announced rules** (top of every tab) — whether the section
  appears in the rules you post *before* the event. It changes nothing about
  what happens during it.
- **Give each roll a result** (Loot tab) — what happens *during* the event.
  This, and *Send the result* beside it, are what decide whether anything
  reaches chat after a roll.

Nothing about the behaviour changed; it was always this way, and now it reads
that way.

**Fixed: 1.17.0 could stop whispering entirely.** Reported straight away — a
whisper that arrived in 1.16.0 sent nothing in 1.17.0.

The refusal check added in 1.17.0 read a counter *before* the send, so anything
wrong with that read took the send down with it. Nothing sits between you and
the send now: the whisper goes out first and everything after it is only
description, guarded so it cannot fail in a way that costs you a line.

Two related repairs:

- another addon being refused while this one was sending counted as *our*
  refusal, so a perfectly good whisper could be reported as `(NOT sent)`
- the same read is now defensive, so a half-updated install — one file new,
  another still the old one — cannot stop whispers going out

If you are on 1.17.0 and whispers went quiet, this is why.

## 1.17.0 - 2026-08-04

**The results table can now be whispered to whoever rolled.** *Send the result*
on the Loot tab is no longer a checkbox but a choice of three, the same three a
roll effect has:

| | |
|---|---|
| **to my channel** | the room is told what was caught — what the checkbox used to do when it was on |
| **to me only** | it comes to you to read out — what the checkbox used to do when it was off |
| **to the roller** | whispered to them alone |

The last one is the reason this exists. Being told *"Rennek caught the salmon"*
in front of everyone hands Rennek the outcome and leaves him nothing to play.
Whispered, he can announce it in his own words, make a meal of landing it, keep
it to himself, or lie about it. The addon knows what was caught; the person who
caught it decides what that means.

Your existing presets keep the behaviour you gave them — the old checkbox is
read once and turned into the matching choice.

**An effect set to "to the roller" now works even while the preset is on
preview only.** Preview answers "where do my rules and results get announced",
and a line meant for one person is not an announcement — you picked that
destination on that effect, which is as explicit as picking a channel. So a host
running an evening in preview, reading the rules out by hand and broadcasting
nothing, can still have the addon tell each person privately what only they
noticed.

Everything else about preview is unchanged: an effect aimed at your channel
still says nothing to the room, and still tells you the preset is on preview.

**Fixed: a whispered effect that your client refused was reported as sent.**
A refusal is not an error the addon can catch -- the client fires the "Interface
action failed because of an AddOn" event and carries on -- so 1.16.0 checked the
wrong thing and told you the line had gone when nobody received it.

The line now reads `(NOT sent to Rennek)` in your own frame when the whisper was
refused, and `(to Rennek)` only when it actually left. The one-time explanation
and `/reh blocked` were already there and now fire when they should.

## 1.16.0 - 2026-08-04

**A roll effect can now be whispered to whoever rolled.** A third destination
on each effect row, alongside *to my channel* and *to me only*: **to the
roller**. For the things one person notices on their own cast, which do not
belong in front of the whole room.

One caveat worth knowing before you build an event around it. Your client wants
a click behind any whisper an addon sends, and a roll arrives without one, so it
may refuse them. Rather than leave you guessing, the addon:

- always shows you the line in your own frame, marked with who it went to, so
  nothing is lost even when the whisper does not arrive
- says so once if your client refuses, and points at `/reh blocked` for the
  detail
- shows `(would whisper Rennek)` while the preset is still on preview
- prints to your own frame instead of erroring when the roller is you, since
  nobody can whisper themselves

Test it with one roll from someone else in your group before the event: either
the whisper lands, or the addon tells you it was refused.

## 1.15.1 - 2026-08-03

**The Fishing Night starter's effects now fire on the result rather than on the
numbers.** With verdicts silenced, its critical bands became the event's own
idea of a great cast and a wasted one — 18 and up is the catch of the evening, a
natural 1 is a snapped line — and the reactions hang off those instead of
repeating `18-20` and `1`. Move the critical band on the Rolls tab and the
reactions move with it.

It also demonstrates the thing worth knowing about the new toggle: an event can
switch its verdicts off and still use them. Nothing is announced as a success,
and the effects that fire on one work exactly as before.

Only the starter changed. A Fishing Night preset you already created is
untouched.

## 1.15.0 - 2026-08-03

**Rolls do not have to be a success or a failure.** New toggle on the Rolls tab:
**Call rolls a success or failure**, on by default.

Reported from a fishing night: a 7 announced `Rennek rolled 7 -> FAILURE` and
then, three seconds later, `Rennek reels in a fat carp.` The two lines
contradicted each other, because at that event the roll decides *what happens*,
not *whether it worked*.

Switched off:

- nothing is called a SUCCESS or a FAILURE, and no verdict is announced to the
  room — the roll is still shown to you as `Rennek rolled 7`
- the announced rules drop the success bands and the critical rules, keeping
  how to roll and how many rolls each person gets
- everything downstream keeps working: the roll log, the per-name tallies, the
  loot table and roll effects, including effects that fire on a result

**Fishing Night and Tavern Night now ship with it switched off**, which is what
they always should have done. Existing presets are untouched — the toggle is on
unless you turn it off.

## 1.14.0 - 2026-08-03

**The roll effects window opened underneath the main window.** It opened at the
centre of the screen, which is exactly where the main window sits, in the same
drawing layer — so it arrived behind it and the button looked like it had done
nothing. Fixed, along with everything around it:

- It now opens **beside** the main window, anchored to its right edge, so it
  keeps station if you move or resize the main window.
- **Where you drag it is where it stays**, this session and the next. Both it
  and the roll log now remember their positions the way the main window already
  did.
- **Clicking any window brings it to the front**, and opening one raises it. Two
  windows in the same layer were previously settled arbitrarily, which is not a
  behaviour anyone can learn.
- The roll log opens beside the main window too, staggered down from the effects
  window so two open at once are visibly two windows.

**The Loot tab's button now says how many effects you have** — `Roll effects...
(3)` — so you can tell there are some without opening the window to look.

## 1.13.0 - 2026-08-03

**A rejected edit now complains on the field, not in your chat frame.** Typing
`ten` into a number box used to put a red line in the same frame you are running
the evening from — next to the rolls, the verdicts and the room's roleplay,
where it either scrolled past unread or pushed something that mattered off the
top. The box goes red and says why instead, and clears itself after a few
seconds. The roll effects window does the same for its number boxes, which
previously just swallowed bad input without a word.

**Every field has a tooltip.** Twenty had none — including the ones most worth
explaining: what a critical band actually covers, what `0` means in *Heals per
event* and *Seconds per turn*, and what each turn-order mode does. A test now
enforces it, so a field added later cannot arrive undocumented.

## 1.12.0 - 2026-08-03

**Starter presets.** The **New** button now offers four worked events instead of
going straight to a blank one:

| Starter | What it shows |
|---|---|
| **Duel Ring** | Initiative, armor-based health, a turn timer, first to zero loses |
| **Fishing Night** | A full results table with several fish per band picked at random, plus roll effects for the room's reaction |
| **Tavern Night** | No combat at all: house rules, etiquette, and a drinks table you read out yourself |
| **Arena Brawl** | A raid-sized free-for-all where only the fighting subgroups are adjudicated |

Each one arrives complete — rules, etiquette, the numbers, and the sections it
does not need already switched off — and every one announces to **preview only**
until you pick a channel. `/reh templates` lists them, `/reh template fishing`
creates one, and `/reh template duel Friday Duels` names it while creating it.

Making the same starter twice is fine: the second is `Fishing Night 2`.

They exist because a blank preset is a form to fill in, while a worked event is
something to read and change — and because the loot table and roll effects were
otherwise invisible until someone went looking for them.

**Fixed: alternatives were announced as separate bands.** A table with three
fish written against `4-7` announced `4-7 = a salmon. 4-7 = a trout. 4-7 = a
carp.`, which reads to the room like the host made a mistake and never says that
a 5 can give any of them. It now reads `4-7 = a salmon, a trout or a carp.`

## 1.11.0 - 2026-08-03

Four changes aimed at the same thing: the window telling you what it is about
to do, without you having to work it out.

- **The preview is quieter.** Every message used to carry a byte count, so half
  the ink in the pane went on a number that only matters near the 255-byte
  limit. Now a count appears in amber only when a message is getting long, and
  in red when a rule was too long and had to be split across two messages --
  which is worth finding out in the preview rather than in the channel.
- **Separators are called out.** They are dimmed in the preview, and the
  summary names them: `13 messages (5 separators), about 8 seconds`. They are
  the one part of that count you can delete without losing a rule.
- **Tabs show which sections are left out.** A section switched out of the
  announcement keeps all its rules, which from the tab strip looked identical
  to one that is still in it. Those tabs now carry a small red dot, and the
  tooltip says how to switch it back on.
- **The announce button names its target.** It reads `Announce to party chat`,
  or `Preview only` when the preset sends nothing. The target used to be on one
  button and the action on another, so confirming where an announcement was
  about to go meant reading the far corner of the window.

## 1.10.0 - 2026-08-03

**The roll log and the roll effects window resize too.** Same grip in the
bottom-right corner, same double-click to go back to the default, and each
window remembers its own size.

- The **roll log** gives all the extra room to the text, which is what a host
  reading back through a busy round wants.
- The **roll effects** window gives the extra width to the message boxes, the
  one field on a row that can run out of space.

**Fixed: the status line was hidden behind the preview.** Sentences like
`You are not in a party.` were printed under the preview pane's bottom edge, so
only the lower half of the text was visible — which is why the announce button
could be greyed out with no readable reason next to it. The status line now has
a strip of its own.

**Fixed: on a roll effect row, the remove button sat on top of the delay box.**
The right-hand controls are now chained leftwards from the corner instead of
each being placed at a measured offset, so they stay together at any width.

## 1.9.0 - 2026-08-03

**The window can be dragged out.** Grab the grip in the bottom-right corner and
pull. Asked for so the whole preview can be read at once instead of scrolled
through.

- Most of the extra height goes to the **preview** — that being the reason to
  make the window bigger — and the rest to the editor, which also runs long.
  The preview never takes more than half the interior, so the tab you are
  editing always has room.
- Extra width goes to the editor and the preview. The preset list stays as wide
  as it was: a preset name does not need more room, and the rules beside it do.
- The size is remembered between sessions, the same way the position already
  was. **Double-click the grip** to go back to the default.
- The tab strip re-wraps as the window widens, so ten tabs fold onto one row
  instead of staying on two.

At its default size the window is laid out exactly as before, so nothing moves
for anyone who does not drag it.

## 1.8.0 - 2026-08-03

**Several possible results for the same roll, one picked at random.** Write a
range more than once and the addon chooses between them:

```
1      your line breaks
2-3    a shrimp
4-7    a salmon
4-7    a trout
4-7    a carp
```

A 5 catches a salmon, a trout or a carp. Three lines reading `4-7` are three
fish in the same water, not a mistake. Precedence is unchanged: only an
identical range joins the pool, so a narrow band listed above a wide one still
wins outright. `/reh loot test 5` lists every alternative a roll could give.

The same thing on the effects side: tick **one of these at random** on two or
more effects that share a trigger and only one of them fires. Left unticked
they all fire, exactly as before.

**Results that cannot reach the channel now say so.** Reported from a real
event: everything set up, nothing arriving in party chat, and no explanation.
There were three ways for that to happen silently, and all three now speak up
once:

- the roll watcher is off, so no rolls are being read at all — the most likely
  one, and it now says so when you switch results on, and on the window's
  status line while it is true
- the channel is not available (not in that party, not in that raid)
- the preset is still announcing to preview only

## 1.7.0 - 2026-08-03

**Roll effects: a window for the complicated version of the loot table.** Same
host, next request. The table on the Loot tab answers "what did that roll
catch"; an effect answers "what happens on that roll", and it can do three
things the table cannot.

- **Fire on a result, not just a number.** An effect triggers on a roll, a
  range, a success, a failure, a critical either way, or every roll.
- **Several can answer the same roll.** "On a natural 1 your line snaps" and
  "every cast makes a splash" are both true of a 1, so both are said. The loot
  table still stops at its first match, which is what makes it the quick one.
- **Each carries its own chance, delay and destination.** A 25% chance of the
  big one getting away; two seconds before the crowd reacts; a line only you
  see while the rest goes to the room.

`{name}`, `{roll}` and `{result}` are filled in, and `{item}` reaches across to
whatever the loot table gave that same roll -- so the catch and what happens
next can be two lines rather than one crowded one.

Open it with **Roll effects...** on the Loot tab or `/reh effects`. **Try it**
in the window (or `/reh effects test 1`) shows what a roll would set off without
waiting for someone to roll it and without sending anything. `/reh effects list`
reads the whole set back in plain English.

Effects are per preset, travel in export strings, and an event with none behaves
exactly as it did before they existed. The same delayed-message limitation as
the loot table applies: /say, /yell, /emote, whispers and custom channels cannot
receive a line sent seconds after a roll, and the addon says so once. An effect
set to *to me only* is never affected by that, which makes it a way to run the
whole thing in a `/say` event with the host reading the results out.

## 1.6.0 - 2026-08-03

**A loot table, read off the roll.** Asked for by a host running a fishing
night: someone rolls a 3, and a few seconds later the room hears that they
caught an anchovy.

- A new **Loot** tab holds the table, written the same way as the rest of the
  addon's lists -- one per line, `1-3 an anchovy`, `4-10 an old boot`,
  `100 the legendary whale`. A bare number is a band of one, and the first line
  covering the roll wins, so a narrow band can sit above a wide one.
- The result line is yours: `{name}`, `{item}` and `{roll}` are filled in.
  Rolls no band covers say nothing at all unless you give them something to say.
- It waits a few seconds by default, so the roll lands first and the catch reads
  as its outcome rather than as part of the same breath.
- It has its own switch, separate from the watcher's verdicts. A fishing night
  can put the catch in the room without `Rennek rolled 3 -> FAILURE` going with
  it -- set the watcher to *verdicts to me* and leave the loot on.
- Off by default, and it follows the same filter as everything else: whoever the
  watcher ignores is not handed a fish either.
- The table can be announced with your rules like any other section, or left off
  the announcement to keep the catches a surprise.
- `/reh loot` lists it, `/reh loot on|off` switches it, and `/reh loot test 3`
  shows what a roll would give without waiting for one or sending anything.

One limitation worth knowing before the event: because the result is sent a few
seconds after the roll rather than from a click, the client will not let it
reach **/say, /yell, /emote, whispers or custom channels** -- the same
restriction the rule announcement runs into. Party, raid, guild, officer and
instance chat are delivered every time. The addon says so once when you set it
up that way rather than leaving you watching an empty channel.

The editor tab strip now wraps onto a second row, since ten tabs no longer fit
across one.

## 1.5.1 - 2026-08-02

Fixes the minimap button sitting inside the minimap's border, on top of the map.

- The orbit radius was a fixed 80 pixels, which is only correct for a 140-pixel
  minimap. The retail minimap is larger than that, so the icon was drawn well
  inside the ring. The radius is now measured from the minimap itself -- half its
  width and height plus a few pixels -- so the button rides the edge at any
  minimap size or UI scale.
- The button follows the minimap when it is resized afterwards, by an interface
  option, a patch or a UI pack, instead of keeping the position it was given at
  login.
- Square minimaps (SexyMap and several UI packs) put the button on the square's
  edge rather than on the circle it does not have.

## 1.5.0 - 2026-08-01

**Each custom rule and etiquette line is announced as its own message.**

Message packing was running consecutive rules together whenever they fit inside
one chat message, so two rules written on separate lines arrived as a single
run-on instruction. Rules and etiquette lines are no longer packed; the
descriptive sections still are, since "Rolls: ... One roll per turn." reads
perfectly well as one message.

This also puts the host in charge of it: rules on separate lines arrive
separately, and two thoughts that belong together can be typed on one line.

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
