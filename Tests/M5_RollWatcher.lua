-- M5: the roll watcher.
--
-- The two things most likely to be quietly wrong in the game are covered
-- hardest here: parsing roll results without assuming English, and matching
-- cross-realm names. Both look fine on your own realm in your own locale and
-- fail for half the room at a real event.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "Tests"
local H = dofile(here .. "/Harness.lua")

H.installStubs()
H.snapshotGlobals()
H.wipeSavedVariables()

local REH = H.login()
local DB = REH.Database
local Watcher = REH.RollWatcher

local function reset()
	H.clearSent()
	H.clearOutput()
	H.clearTimers()
	H.resetGroup()
	Watcher:SetMode("off")
	Watcher:ClearLog()
	Watcher:Unmute("Testchar")
end

--- Deliver a roll result the way the client would.
local function roll(name, value, minRoll, maxRoll)
	local message = ("%s rolls %d (%d-%d)"):format(name, value, minRoll or 1, maxRoll or 100)
	return Watcher:HandleSystemMessage(message)
end

--------------------------------------------------------------------------------
H.section("Parsing roll results")
--------------------------------------------------------------------------------

local name, value, minRoll, maxRoll = Watcher:ParseRoll("Zethrel rolls 74 (1-100)")
H.checkEqual("the name is read", name, "Zethrel")
H.checkEqual("the roll is read", value, 74)
H.checkEqual("the minimum is read", minRoll, 1)
H.checkEqual("the maximum is read", maxRoll, 100)

name = Watcher:ParseRoll("Zethrel-Argent Dawn rolls 12 (1-100)")
H.checkEqual("a cross-realm name is read whole", name, "Zethrel-Argent Dawn")

H.check("an unrelated system message is not a roll",
	Watcher:ParseRoll("You have joined the channel.") == nil)
H.check("a near-miss is not a roll",
	Watcher:ParseRoll("Zethrel rolls the dice") == nil)
H.check("nil is handled", Watcher:ParseRoll(nil) == nil)

-- The parser is built from the client's format string, so a translated client
-- must work without any change to the addon.
local germanPattern, germanOrder =
	Watcher:BuildRollPattern("%s w\195\188rfelt. Ergebnis: %d (%d-%d)")
local gName, gRoll = ("R\195\182gnvald w\195\188rfelt. Ergebnis: 88 (1-100)"):match(germanPattern)
H.checkEqual("a translated format string still parses the name", gName, "R\195\182gnvald")
H.checkEqual("and the roll", tonumber(gRoll), 88)

-- Some locales reorder the arguments with positional specifiers.
local positional, order = Watcher:BuildRollPattern("(%3$d-%4$d) %2$d :%1$s")
H.checkEqual("positional specifiers are tracked", order[1], 3)
H.checkEqual("in the order they appear", order[4], 1)

--------------------------------------------------------------------------------
H.section("Cross-realm name normalization")
--------------------------------------------------------------------------------

H.checkEqual("a bare name gains the home realm",
	Watcher:NormalizeName("Zethrel"), "Zethrel-ArgentDawn")
H.checkEqual("a suffixed name keeps its realm",
	Watcher:NormalizeName("Bob-Moon Guard"), "Bob-MoonGuard")
H.checkEqual("realm spaces are removed so both spellings match",
	Watcher:NormalizeName("Bob-MoonGuard"), Watcher:NormalizeName("Bob-Moon Guard"))
H.checkEqual("a name and realm given separately match the suffixed form",
	Watcher:NormalizeName("Bob", "Moon Guard"), Watcher:NormalizeName("Bob-Moon Guard"))
H.check("an empty name is rejected", Watcher:NormalizeName("") == nil)

H.checkEqual("same-realm names display bare",
	Watcher:DisplayName("Zethrel-ArgentDawn"), "Zethrel")
H.checkEqual("cross-realm names keep the realm",
	Watcher:DisplayName("Bob-MoonGuard"), "Bob-MoonGuard")

--------------------------------------------------------------------------------
H.section("Building the roster")
--------------------------------------------------------------------------------

reset()
H.setGroup({}, false)
Watcher:RebuildRoster()
local roster, count = Watcher:GetRoster()
H.checkEqual("solo, the roster is just you", count, 1)
H.check("and it is you", roster[Watcher:NormalizeName("Testchar")] ~= nil)

-- Party unit tokens exclude the player, which is the classic way to end up
-- adjudicating everyone except the host.
H.setGroup({
	{ name = "Testchar", subgroup = 1 },
	{ name = "Bob", subgroup = 1 },
	{ name = "Carla", subgroup = 1 },
}, false)
Watcher:RebuildRoster()
roster, count = Watcher:GetRoster()
H.checkEqual("a party of three has three members", count, 3)
H.check("including the player", roster[Watcher:NormalizeName("Testchar")] ~= nil)
H.check("and the others", roster[Watcher:NormalizeName("Bob")] ~= nil)

H.setGroup({
	{ name = "Testchar", subgroup = 1 },
	{ name = "Bob", subgroup = 1 },
	{ name = "Faraway", realm = "Moon Guard", subgroup = 3 },
}, true)
Watcher:RebuildRoster()
roster, count = Watcher:GetRoster()
H.checkEqual("a raid roster is built", count, 3)
H.check("a cross-realm raider is in the roster",
	roster[Watcher:NormalizeName("Faraway-Moon Guard")] ~= nil)
H.checkEqual("with their subgroup",
	roster[Watcher:NormalizeName("Faraway-Moon Guard")].subgroup, 3)

--------------------------------------------------------------------------------
H.section("Adjudication")
--------------------------------------------------------------------------------

local preset = DB:GetActivePreset()
H.checkEqual("below the threshold fails", Watcher:Judge(preset, 9), "fail")
H.checkEqual("at the threshold succeeds", Watcher:Judge(preset, 10), "success")
H.checkEqual("above the threshold succeeds", Watcher:Judge(preset, 74), "success")
H.checkEqual("the top roll is a critical success", Watcher:Judge(preset, 100), "critsuccess")
H.checkEqual("a natural one is a critical failure", Watcher:Judge(preset, 1), "critfail")

preset.rolls.useCritical = false
H.checkEqual("without criticals the top roll is a plain success",
	Watcher:Judge(preset, 100), "success")
H.checkEqual("and a one is a plain failure", Watcher:Judge(preset, 1), "fail")
preset.rolls.useCritical = true

H.check("the verdict uses the preset's own wording",
	Watcher:FormatVerdict(preset, "Bob-ArgentDawn", 74, "success", false)
		:find(preset.rolls.successText, 1, true) ~= nil)
H.check("and names a critical as one",
	Watcher:FormatVerdict(preset, "Bob-ArgentDawn", 100, "critsuccess", false)
		:find("critical", 1, true) ~= nil)

preset.rolls.successText = "HIT"
preset.rolls.failText = "MISS"
H.check("custom wording is honoured",
	Watcher:FormatVerdict(preset, "Bob-ArgentDawn", 74, "success", false)
		:find("HIT", 1, true) ~= nil)
preset.rolls.successText = "SUCCESS"
preset.rolls.failText = "FAILURE"

--------------------------------------------------------------------------------
H.section("Scaling the threshold to a smaller die")
--------------------------------------------------------------------------------

-- Both readings are defensible, which is why it is a choice: unscaled makes
-- the reduced die the wound penalty, scaled keeps the odds and makes it
-- flavour.
local scaling = REH.CreateDefaultPreset("Scaling")
DB:ValidatePreset(scaling)
H.checkEqual("scaling is off unless asked for", scaling.rolls.scaleToDie, false)

H.checkEqual("unscaled, a d15 still needs the event's number",
	Watcher:Judge(scaling, 9, 15), "fail")
H.checkEqual("and clears it at the same number",
	Watcher:Judge(scaling, 10, 15), "success")

scaling.rolls.scaleToDie = true
local success, critSuccess, critFail = Watcher:ThresholdsFor(scaling, 15)
H.checkEqual("scaled, 10 of 100 becomes 2 of 15", success, 2)
H.checkEqual("the critical success follows the top of the die", critSuccess, 15)
H.checkEqual("and a natural 1 is still a critical failure", critFail, 1)

H.checkEqual("so a 2 on a d15 succeeds", Watcher:Judge(scaling, 2, 15), "success")
H.checkEqual("and a 1 is a critical failure", Watcher:Judge(scaling, 1, 15), "critfail")
H.checkEqual("the top of the die is a critical success",
	Watcher:Judge(scaling, 15, 15), "critsuccess")

H.checkEqual("the event's own die is unaffected either way",
	select(1, Watcher:ThresholdsFor(scaling, 100)), 10)

-- Nothing may scale to zero, or to a number the die cannot roll.
local harsh = REH.CreateDefaultPreset("Harsh")
harsh.rolls.scaleToDie = true
harsh.rolls.successThreshold = 1
DB:ValidatePreset(harsh)
H.check("a threshold can never scale below 1",
	select(1, Watcher:ThresholdsFor(harsh, 3)) >= 1)

local steep = REH.CreateDefaultPreset("Steep")
steep.rolls.scaleToDie = true
steep.rolls.successThreshold = 100
DB:ValidatePreset(steep)
H.check("nor above what the die can roll",
	select(1, Watcher:ThresholdsFor(steep, 6)) <= 6)

H.check("a scaled verdict shows the number they needed",
	Watcher:FormatVerdict(scaling, "Bob-ArgentDawn", 2, "success", false, 15)
		:find("(1-15, 2+)", 1, true) ~= nil,
	Watcher:FormatVerdict(scaling, "Bob-ArgentDawn", 2, "success", false, 15))
scaling.rolls.scaleToDie = false
H.check("and an unscaled one just names the die",
	Watcher:FormatVerdict(scaling, "Bob-ArgentDawn", 2, "fail", false, 15)
		:find("(1-15)", 1, true) ~= nil)

--------------------------------------------------------------------------------
H.section("The watcher starts disarmed")
--------------------------------------------------------------------------------

reset()
H.checkEqual("mode is off after a fresh login", Watcher:GetMode(), "off")
H.check("and it is not watching", Watcher:IsWatching() == false)

H.clearOutput()
roll("Bob", 74)
H.checkEqual("a roll while disarmed is ignored", #select(1, Watcher:GetLog()), 0)
H.checkEqual("and nothing is printed", H.outputText(), "")

-- Arming is not remembered: the addon must never wake up talking. The reloaded
-- namespace has to be re-bound, or this would test the old module's state.
Watcher:SetMode("announce")
local reloaded = H.login()
H.checkEqual("a reload disarms the watcher", reloaded.RollWatcher:GetMode(), "off")
REH = reloaded
DB = REH.Database
Watcher = REH.RollWatcher

--------------------------------------------------------------------------------
H.section("Watching a group")
--------------------------------------------------------------------------------

reset()
H.setGroup({
	{ name = "Testchar", subgroup = 1 },
	{ name = "Bob", subgroup = 1 },
	{ name = "Faraway", realm = "Moon Guard", subgroup = 2 },
}, true)
Watcher:SetMode("local")
preset = DB:GetActivePreset()
preset.rollFilter.mode = "group"

H.clearOutput()
local entry = roll("Bob", 74)
H.check("a group member's roll is adjudicated", entry ~= nil)
H.checkEqual("with the right verdict", entry.verdict, "success")
H.check("and shown to the host",
	H.outputText():find("SUCCESS", 1, true) ~= nil, H.outputText())

entry = roll("Faraway-Moon Guard", 1)
H.check("a cross-realm group member is adjudicated too", entry ~= nil,
	"cross-realm matching failed")
H.checkEqual("and judged", entry.verdict, "critfail")

H.check("a stranger's roll is ignored", roll("Randomer", 50) == nil)
H.checkEqual("nothing is broadcast in local mode", #H.sent, 0)

--------------------------------------------------------------------------------
H.section("Combatants and audience by subgroup")
--------------------------------------------------------------------------------

reset()
H.setGroup({
	{ name = "Testchar", subgroup = 1 },
	{ name = "Fighter", subgroup = 1 },
	{ name = "Second", subgroup = 2 },
	{ name = "Watcher1", subgroup = 5 },
	{ name = "Watcher2", subgroup = 6 },
}, true)
Watcher:SetMode("local")

preset = DB:GetActivePreset()
preset.rollFilter.mode = "subgroup"
preset.rollFilter.subgroups = { 1, 2 }

H.check("a combatant in subgroup 1 is adjudicated", roll("Fighter", 50) ~= nil)
H.check("a combatant in subgroup 2 is adjudicated", roll("Second", 50) ~= nil)
H.check("a spectator in subgroup 5 is ignored", roll("Watcher1", 50) == nil)
H.check("a spectator in subgroup 6 is ignored", roll("Watcher2", 50) == nil)

-- An empty selection must mean "the whole raid", not "nobody" -- the reading
-- that cannot silently drop a participant.
preset.rollFilter.subgroups = {}
H.check("no subgroups chosen means everyone in the raid counts",
	roll("Watcher1", 50) ~= nil)
preset.rollFilter.subgroups = { 1, 2 }

--------------------------------------------------------------------------------
H.section("Which dice sizes count")
--------------------------------------------------------------------------------

reset()
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Bob", subgroup = 1 } }, true)
Watcher:SetMode("local")
preset = DB:GetActivePreset()
preset.rollFilter.mode = "group"

-- A wounded character rolling a reduced die is the usual reason to roll on
-- something smaller than the event's, so those must count.
preset.rollFilter.rangeMode = "atMost"
H.check("a roll on the event's die counts", roll("Bob", 50, 1, 100) ~= nil)
H.check("a roll on a smaller die counts too", roll("Bob", 12, 1, 15) ~= nil)
H.check("and one right at the edge", roll("Bob", 2, 1, 2) ~= nil)
H.check("but a roll on a bigger die does not", roll("Bob", 500, 1, 1000) == nil)
H.check("nor one that does not start at 1", roll("Bob", 12, 5, 15) == nil)

H.checkEqual("counting rolls on smaller dice is the default",
	REH.PRESET_TEMPLATE.rollFilter.rangeMode, "atMost")

-- The die matters when reading the verdict back: "rolled 12" looks like a near
-- miss until you know it was out of 15.
local entry = roll("Bob", 12, 1, 15)
H.checkEqual("the entry remembers the die used", entry.maxRoll, 15)
H.check("and the verdict shows it",
	Watcher:FormatVerdict(preset, "Bob-ArgentDawn", 12, "success", false, 15)
		:find("(1-15)", 1, true) ~= nil)
H.check("while the event's own die is not worth repeating",
	Watcher:FormatVerdict(preset, "Bob-ArgentDawn", 12, "success", false, 100)
		:find("(1-100)", 1, true) == nil)

preset.rollFilter.rangeMode = "exact"
H.check("exact still takes the event's die", roll("Bob", 50, 1, 100) ~= nil)
H.check("but refuses a smaller one", roll("Bob", 12, 1, 15) == nil)

preset.rollFilter.rangeMode = "any"
H.check("any takes a smaller die", roll("Bob", 12, 1, 15) ~= nil)
H.check("and a bigger one", roll("Bob", 500, 1, 1000) ~= nil)
H.check("and an odd range", roll("Bob", 12, 5, 15) ~= nil)

-- A roll dropped for its die should say so, since that is exactly the case
-- that looks like the watcher has stopped working.
reset()
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Bob", subgroup = 1 } }, true)
Watcher:SetMode("local")
preset = DB:GetActivePreset()
preset.rollFilter.mode = "group"
preset.rollFilter.rangeMode = "atMost"
H.clearOutput()
roll("Bob", 500, 1, 1000)
H.check("an ignored die is explained",
	H.outputText():find("Ignored a /roll 1000", 1, true) ~= nil, H.outputText())
H.check("naming the die the rules use",
	H.outputText():find("/roll 100", 1, true) ~= nil, H.outputText())

H.clearOutput()
roll("Bob", 400, 1, 1000)
H.checkEqual("and it is not repeated for every roll", H.outputText(), "")

--------------------------------------------------------------------------------
H.section("Saved roster and muting")
--------------------------------------------------------------------------------

reset()
H.setGroup({}, false)
Watcher:SetMode("local")
preset = DB:GetActivePreset()
preset.rollFilter.mode = "roster"
preset.rollFilter.roster = { "Bob", "Faraway-Moon Guard" }

H.check("a roster name is adjudicated even with no group", roll("Bob", 50) ~= nil)
H.check("a cross-realm roster name matches", roll("Faraway-Moon Guard", 50) ~= nil)
H.check("someone not on the roster is ignored", roll("Stranger", 50) == nil)

preset.rollFilter.mode = "everyone"
H.check("everyone mode adjudicates a stranger", roll("Stranger", 50) ~= nil)

Watcher:Mute("Stranger")
H.check("a muted name is ignored even in everyone mode", roll("Stranger", 50) == nil)
H.check("and reports as muted", Watcher:IsMuted("Stranger"))
Watcher:Unmute("Stranger")
H.check("unmuting restores them", roll("Stranger", 50) ~= nil)

--------------------------------------------------------------------------------
H.section("Ignored rolls are surfaced, not swallowed")
--------------------------------------------------------------------------------

reset()
H.setGroup({ { name = "Testchar", subgroup = 1 } }, true)
Watcher:SetMode("local")
preset = DB:GetActivePreset()
preset.rollFilter.mode = "group"

H.clearOutput()
for index = 1, 6 do
	roll("Outsider" .. index, 50)
end

H.check("ignored rolls are counted", Watcher:GetIgnoredCount() >= 5)
H.check("and the host is told once, with the fix",
	H.outputText():find("rolls ignored", 1, true) ~= nil, H.outputText())

local hintCount = select(2, H.outputText():gsub("rolls ignored", ""))
H.checkEqual("the hint does not repeat for every roll", hintCount, 1)

--------------------------------------------------------------------------------
H.section("The log")
--------------------------------------------------------------------------------

reset()
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Bob", subgroup = 1 } }, true)
Watcher:SetMode("local")
preset = DB:GetActivePreset()
preset.rollFilter.mode = "group"

roll("Bob", 74)
roll("Bob", 1)
roll("Bob", 100)
roll("Testchar", 50)

local entries, tallies = Watcher:GetLog()
H.checkEqual("every adjudicated roll is logged", #entries, 4)

local bobTally = tallies[Watcher:NormalizeName("Bob")]
H.checkEqual("per-name totals are kept", bobTally.total, 3)
H.checkEqual("successes counted", bobTally.successes, 2)
H.checkEqual("failures counted", bobTally.failures, 1)
H.checkEqual("criticals counted", bobTally.criticals, 2)

local logText = REH.UI.RollLog:BuildText()
H.check("the log window lists the rolls", logText:find("74", 1, true) ~= nil)
H.check("and shows totals", logText:find("Totals", 1, true) ~= nil)

Watcher:ClearLog()
H.checkEqual("clearing empties it", #select(1, Watcher:GetLog()), 0)
H.check("and the window says so",
	REH.UI.RollLog:BuildText():find("No rolls recorded", 1, true) ~= nil)

--------------------------------------------------------------------------------
H.section("Announcing verdicts")
--------------------------------------------------------------------------------

reset()
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Bob", subgroup = 1 } }, true)
H.group.inGroup = true
preset = DB:GetActivePreset()
preset.rollFilter.mode = "group"
REH.Announcer:SetChannel(preset, "party")

Watcher:SetMode("announce")
roll("Bob", 74)
H.advance(5)
H.checkEqual("a verdict is broadcast", #H.sent, 1)
H.check("with the roll and the verdict",
	H.sent[1].message:find("74", 1, true) ~= nil
		and H.sent[1].message:find("SUCCESS", 1, true) ~= nil, H.sent[1].message)
H.checkEqual("to the preset's channel", H.sent[1].chatType, "PARTY")
H.check("and carries no colour escapes into chat",
	H.sent[1].message:find("|c", 1, true) == nil)

H.clearSent()
REH.Announcer:SetChannel(preset, "preview")
roll("Bob", 74)
H.advance(5)
H.checkEqual("a preview-only preset broadcasts nothing", #H.sent, 0)
H.check("but still shows the verdict locally",
	H.outputText():find("rolled 74", 1, true) ~= nil)

-- A twenty-person free-for-all can produce a burst. Flooding the channel is
-- worse than the host reading a few out.
reset()
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Bob", subgroup = 1 } }, true)
H.group.inGroup = true
preset = DB:GetActivePreset()
preset.rollFilter.mode = "everyone"
REH.Announcer:SetChannel(preset, "party")
Watcher:SetMode("announce")

for index = 1, 40 do
	roll("Roller" .. index, 50)
end
H.advance(120)

H.check("the announced verdicts are capped", #H.sent <= 20,
	("%d messages sent"):format(#H.sent))
H.check("every roll is still logged locally", #select(1, Watcher:GetLog()) == 40)
H.check("and the host is told why the channel went quiet",
	H.outputText():find("Too many rolls", 1, true) ~= nil, H.outputText())

--------------------------------------------------------------------------------
H.section("Commands")
--------------------------------------------------------------------------------

reset()
local out = H.runSlash("watch")
H.check("/reh watch reports the mode", out:find("off", 1, true) ~= nil, out)

out = H.runSlash("watch on")
H.checkEqual("/reh watch on arms it locally", Watcher:GetMode(), "local")

out = H.runSlash("watch announce")
H.checkEqual("/reh watch announce arms announcing", Watcher:GetMode(), "announce")

out = H.runSlash("watch off")
H.checkEqual("/reh watch off disarms", Watcher:GetMode(), "off")

out = H.runSlash("watch sideways")
H.check("an unknown mode is refused", out:find("must be off", 1, true) ~= nil, out)

out = H.runSlash("filter everyone")
H.checkEqual("/reh filter sets the mode",
	DB:GetActivePreset().rollFilter.mode, "everyone")

out = H.runSlash("filter nonsense")
H.check("an unknown filter is refused", out:find("must be group", 1, true) ~= nil, out)

out = H.runSlash("subgroups 1 2 3")
H.checkEqual("/reh subgroups stores them",
	table.concat(DB:GetActivePreset().rollFilter.subgroups, ","), "1,2,3")
H.checkEqual("and switches the filter to subgroup",
	DB:GetActivePreset().rollFilter.mode, "subgroup")

out = H.runSlash("subgroups 99")
H.check("an out-of-range subgroup is refused",
	out:find("1 to 8", 1, true) ~= nil, out)

H.setGroup({
	{ name = "Testchar", subgroup = 1 },
	{ name = "Bob", subgroup = 1 },
	{ name = "Faraway", realm = "Moon Guard", subgroup = 2 },
}, true)
out = H.runSlash("roster import")
H.checkEqual("/reh roster import snapshots the group",
	#DB:GetActivePreset().rollFilter.roster, 3)
H.checkEqual("and switches to roster mode",
	DB:GetActivePreset().rollFilter.mode, "roster")

H.runSlash("roster clear")
H.checkEqual("/reh roster clear empties it",
	#DB:GetActivePreset().rollFilter.roster, 0)

H.runSlash("roster add Bob")
H.checkEqual("/reh roster add adds a name",
	#DB:GetActivePreset().rollFilter.roster, 1)
H.runSlash("roster remove Bob")
H.checkEqual("/reh roster remove takes it away",
	#DB:GetActivePreset().rollFilter.roster, 0)

Watcher:SetMode("local")
DB:GetActivePreset().rollFilter.mode = "everyone"
roll("Bob", 74)
out = H.runSlash("log")
H.check("/reh log lists the rolls", out:find("74", 1, true) ~= nil, out)
out = H.runSlash("log clear")
H.check("/reh log clear empties it", out:find("cleared", 1, true) ~= nil, out)

out = H.runSlash("mute Bob")
H.check("/reh mute works", Watcher:IsMuted("Bob"))
out = H.runSlash("unmute Bob")
H.check("/reh unmute works", Watcher:IsMuted("Bob") == false)

--------------------------------------------------------------------------------
H.section("The window")
--------------------------------------------------------------------------------

reset()
REH.UI.MainFrame:Show()
local frame = REH.UI.MainFrame:GetFrame()

H.check("the bottom bar has a watcher control", frame.watchButton ~= nil)
H.check("and a log button", frame.logButton ~= nil)

Watcher:SetMode("local")
REH.UI.MainFrame:RefreshPreview()
H.check("the control reflects the current mode",
	frame.watchButton:GetText():find("verdicts to me", 1, true) ~= nil,
	frame.watchButton:GetText())

frame.watchButton:Click()
H.check("clicking it changes the mode", Watcher:GetMode() ~= "local")

frame.logButton:Click("LeftButton")
H.check("the round button opens the log", REH.UI.RollLog:IsShown())
frame.logButton:Click("RightButton")
H.check("and right-click closes it again", REH.UI.RollLog:IsShown() == false)

--------------------------------------------------------------------------------
H.section("The log window keeps up with the event")
--------------------------------------------------------------------------------

-- The window does not poll, so a roll arriving while it is open has to push an
-- update. Without that the log looks like it stopped recording the moment you
-- opened it -- which is exactly when a host is watching it.
reset()
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Bob", subgroup = 1 } }, true)
Watcher:SetMode("local")
DB:GetActivePreset().rollFilter.mode = "group"

REH.UI.RollLog:Show()
local logFrame = REH.UI.RollLog:GetFrame()
H.check("the log opens empty",
	logFrame.bodyText:GetText():find("No rolls recorded", 1, true) ~= nil,
	logFrame.bodyText:GetText())

roll("Bob", 74)
H.check("a roll made while the window is open appears in it",
	logFrame.bodyText:GetText():find("74", 1, true) ~= nil,
	logFrame.bodyText:GetText())
H.check("with its verdict",
	logFrame.bodyText:GetText():find("SUCCESS", 1, true) ~= nil,
	logFrame.bodyText:GetText())

roll("Bob", 3)
H.check("and so does the next one",
	logFrame.bodyText:GetText():find(" 3 ", 1, true) ~= nil
		or logFrame.bodyText:GetText():find("rolled 3", 1, true) ~= nil,
	logFrame.bodyText:GetText())

-- The scroll child has to grow, or everything past the first screenful is
-- unreachable and the log appears to stop.
local heightBefore = logFrame.content:GetHeight()
for index = 1, 40 do
	roll("Bob", index)
end
H.check("the scroll area grows with the log",
	logFrame.content:GetHeight() > heightBefore,
	("%s -> %s"):format(tostring(heightBefore), tostring(logFrame.content:GetHeight())))

Watcher:ClearLog()
H.check("clearing empties the window too",
	logFrame.bodyText:GetText():find("No rolls recorded", 1, true) ~= nil,
	logFrame.bodyText:GetText())

REH.UI.RollLog:Hide()
roll("Bob", 50)
H.check("a roll with the window closed is still recorded",
	#select(1, Watcher:GetLog()) == 1)
REH.UI.RollLog:Show()
H.check("and is there when it is reopened",
	logFrame.bodyText:GetText():find("50", 1, true) ~= nil,
	logFrame.bodyText:GetText())
REH.UI.RollLog:Hide()

local watcherTab = REH.Fields:FindTab("watcher")
H.check("there is a watcher tab in the editor", watcherTab ~= nil)
H.check("with a subgroup field",
	REH.Fields:FindField("watcher", "subgroups") ~= nil)

local subgroupField = REH.Fields:FindField("watcher", "subgroups")
REH.Fields:Set(DB:GetActivePreset(), subgroupField, "1 2")
H.checkEqual("typing subgroups into the editor works",
	table.concat(DB:GetActivePreset().rollFilter.subgroups, ","), "1,2")

H.checkNoLeakedGlobals(H.ALLOWED_GLOBALS)

H.finish()
