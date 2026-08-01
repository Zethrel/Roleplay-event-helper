-- Rounds in the roll log, and choosing which sections are announced.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "Tests"
local H = dofile(here .. "/Harness.lua")

H.installStubs()
H.snapshotGlobals()
H.wipeSavedVariables()

local REH = H.login()
local DB = REH.Database
local Watcher = REH.RollWatcher
local Log = REH.UI.RollLog

local function roll(name, value)
	return Watcher:HandleSystemMessage(("%s rolls %d (1-100)"):format(name, value))
end

H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Bob", subgroup = 1 } }, true)
Watcher:SetMode("local")
DB:GetActivePreset().rollFilter.mode = "group"
Watcher:ClearLog()

--------------------------------------------------------------------------------
H.section("Rounds")
--------------------------------------------------------------------------------

H.checkEqual("an event starts on round one", Watcher:GetCurrentRound(), 1)
H.checkEqual("with one round in it", Watcher:GetRoundCount(), 1)

roll("Bob", 74)
roll("Testchar", 20)
H.checkEqual("rolls land in the current round", #select(1, Watcher:GetRound(1)), 2)

local number, created = Watcher:NewRound()
H.checkEqual("starting a round moves to it", number, 2)
H.check("and reports that it made one", created)
H.checkEqual("there are now two rounds", Watcher:GetRoundCount(), 2)
H.checkEqual("the new one is empty", #select(1, Watcher:GetRound(2)), 0)

-- Pressing it twice should not pile up empty rounds mid-event.
local again, createdAgain = Watcher:NewRound()
H.checkEqual("starting a round again on an empty round stays put", again, 2)
H.check("and says nothing was created", createdAgain == false)
H.checkEqual("still two rounds", Watcher:GetRoundCount(), 2)

roll("Bob", 5)
H.checkEqual("new rolls land in the new round", #select(1, Watcher:GetRound(2)), 1)
H.checkEqual("the earlier round is untouched", #select(1, Watcher:GetRound(1)), 2)

local allEntries, allTallies = Watcher:GetRound(0)
H.checkEqual("round zero is every round together", #allEntries, 3)
H.checkEqual("with combined per-name totals",
	allTallies[Watcher:NormalizeName("Bob")].total, 2)
H.checkEqual("counting successes across rounds",
	allTallies[Watcher:NormalizeName("Bob")].successes, 1)
H.checkEqual("and failures", allTallies[Watcher:NormalizeName("Bob")].failures, 1)

H.checkEqual("the plain log is still the current round",
	#select(1, Watcher:GetLog()), 1)

H.check("an entry remembers its round", select(1, Watcher:GetRound(1))[1].round == 1)

--------------------------------------------------------------------------------
H.section("Reading back through rounds")
--------------------------------------------------------------------------------

Log:Show()
local frame = Log:GetFrame()

H.checkEqual("the window follows the current round", Log:GetViewedRound(), 2)
H.check("and says which one", frame.roundLabel:GetText():find("Round 2 of 2", 1, true) ~= nil,
	frame.roundLabel:GetText())

frame.previousButton:Click()
H.checkEqual("the arrow steps back a round", Log:GetViewedRound(), 1)
H.check("showing that round's rolls",
	frame.bodyText:GetText():find("74", 1, true) ~= nil, frame.bodyText:GetText())
H.check("and not the later one's",
	frame.bodyText:GetText():find("rolled 5", 1, true) == nil, frame.bodyText:GetText())

-- A host reading round one must not be dragged forward by a live roll.
roll("Bob", 99)
H.checkEqual("a new roll does not yank the view forward", Log:GetViewedRound(), 1)
H.check("and the pinned round still shows its own rolls",
	frame.bodyText:GetText():find("99", 1, true) == nil, frame.bodyText:GetText())

frame.previousButton:Click()
H.checkEqual("stepping back past round one shows all rounds", Log:GetViewedRound(), 0)
H.check("labelled as such",
	frame.roundLabel:GetText():find("All rounds", 1, true) ~= nil, frame.roundLabel:GetText())
H.check("with rolls from both rounds",
	frame.bodyText:GetText():find("74", 1, true) ~= nil
		and frame.bodyText:GetText():find("99", 1, true) ~= nil, frame.bodyText:GetText())
H.check("and each roll marked with its round",
	frame.bodyText:GetText():find("R1", 1, true) ~= nil, frame.bodyText:GetText())

H.check("there is nothing before all rounds", frame.previousButton:IsEnabled() == false)
frame.previousButton:Click()
H.checkEqual("so it stays there", Log:GetViewedRound(), 0)

frame.nextButton:Click()
H.checkEqual("forward goes to round one", Log:GetViewedRound(), 1)
frame.nextButton:Click()
H.checkEqual("and on to round two", Log:GetViewedRound(), 2)
H.check("there is nothing past the newest round", frame.nextButton:IsEnabled() == false)

-- Back on the newest round, the window resumes following live rolls.
roll("Bob", 42)
H.check("following resumes on the current round",
	frame.bodyText:GetText():find("42", 1, true) ~= nil, frame.bodyText:GetText())

frame.previousButton:Click()
frame.newRoundButton:Click()
H.checkEqual("the new round button starts one", Watcher:GetRoundCount(), 3)
H.checkEqual("and brings the view with it", Log:GetViewedRound(), 3)

Watcher:ClearLog()
H.checkEqual("clearing goes back to a single round", Watcher:GetRoundCount(), 1)
H.checkEqual("and to round one", Watcher:GetCurrentRound(), 1)
H.checkEqual("with the window following", Log:GetViewedRound(), 1)
Log:Hide()

local out = H.runSlash("round")
H.check("/reh round reports the round", out:find("Round 1 of 1", 1, true) ~= nil, out)
roll("Bob", 10)
out = H.runSlash("round new")
H.check("/reh round new starts one", out:find("Round 2", 1, true) ~= nil, out)
out = H.runSlash("round new")
H.check("and refuses to stack empty rounds",
	out:find("nothing has been rolled", 1, true) ~= nil, out)

--------------------------------------------------------------------------------
H.section("Choosing which sections are announced")
--------------------------------------------------------------------------------

local preset = DB:GetActivePreset()
preset.custom = { "Stay in character in the tavern." }
DB:ValidatePreset(preset)

-- Plenty of events have no combat at all, and the rules for it should be
-- switched off rather than deleted.
for _, key in ipairs({ "rolls", "health", "damage", "turns" }) do
	local field = REH.Fields:FindField(key, "include")
	H.check(key .. " has an include toggle on its tab", field ~= nil)
	if field then
		REH.Fields:Set(preset, field, false)
	end
end

local text = table.concat(REH.Formatter:BuildMessages(preset), "\n")
H.check("a no-combat event announces no roll rules",
	text:find("/roll", 1, true) == nil, text)
H.check("no health table", text:find("Health:", 1, true) == nil, text)
H.check("no damage rules", text:find("Damage:", 1, true) == nil, text)
H.check("no turn order", text:find("Turn order:", 1, true) == nil, text)
H.check("but keeps the event name", text:find(preset.header.eventName, 1, true) ~= nil, text)
H.check("and the custom rules",
	text:find("Stay in character in the tavern.", 1, true) ~= nil, text)

local rollsInclude = REH.Fields:FindField("rolls", "include")
REH.Fields:Set(preset, rollsInclude, true)
H.check("turning a section back on restores it",
	table.concat(REH.Formatter:BuildMessages(preset), "\n"):find("/roll", 1, true) ~= nil)
H.checkEqual("and the rules inside it were never lost", preset.rolls.dieMax, 100)

out = H.runSlash("include")
H.check("/reh include lists the sections", out:find("Rolls", 1, true) ~= nil, out)
H.check("marking which are on", out:find("on", 1, true) ~= nil, out)
H.check("and which are off", out:find("off", 1, true) ~= nil, out)

H.runSlash("include rolls off")
H.checkEqual("/reh include can turn one off", preset.moduleEnabled.rolls, false)
H.runSlash("include Rolls on")
H.checkEqual("and back on, matching the name shown in the window",
	preset.moduleEnabled.rolls, true)
H.runSlash("include health")
H.checkEqual("with no state given it toggles", preset.moduleEnabled.health, true)

out = H.runSlash("include nonsense")
H.check("an unknown section is refused",
	out:find("No section called", 1, true) ~= nil, out)

H.checkNoLeakedGlobals(H.ALLOWED_GLOBALS)

H.finish()
