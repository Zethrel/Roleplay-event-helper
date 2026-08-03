-- M10: the loot table -- a result read off the roll itself.
--
-- Asked for by a host running a fishing night: someone rolls a 3 and, a few
-- seconds later, the room hears that they caught an anchovy. The parts worth
-- pinning down are which band a roll falls into, that the delay is real, and
-- that the result follows its own switch rather than the watcher's verdicts.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "Tests"
local H = dofile(here .. "/Harness.lua")

H.installStubs()
H.snapshotGlobals()
H.wipeSavedVariables()

local REH = H.login()
local DB = REH.Database
local Fields = REH.Fields
local Watcher = REH.RollWatcher

local function reset()
	-- Let time pass before wiping the timers, the way it does between two
	-- events. The send queue paces itself with a timer, and pulling that timer
	-- out from under it mid-drain would leave the queue holding a message that
	-- the next section then blames on its own code.
	H.advance(5)

	H.clearSent()
	H.clearOutput()
	H.clearTimers()
	H.resetGroup()
	Watcher:SetMode("off")
	Watcher:ClearLog()
end

local function roll(name, value, maxRoll)
	return Watcher:HandleSystemMessage(
		("%s rolls %d (1-%d)"):format(name, value, maxRoll or 100))
end

--- The fishing night, set up the way the host would.
local function fishingPreset()
	local preset = DB:GetActivePreset()

	preset.loot.enabled = true
	preset.loot.announce = true
	preset.loot.delaySeconds = 3
	preset.loot.message = "{name} has caught {item}."
	preset.loot.nothingText = ""
	preset.loot.entries = Fields.ParseLootLines(table.concat({
		"1-3 an anchovy",
		"4-10 an old boot",
		"11-89 a river trout",
		"90-99 a gleaming salmon",
		"100 the legendary whale",
	}, "\n"))

	DB:ValidatePreset(preset)
	return preset
end

--------------------------------------------------------------------------------
H.section("Writing the table")
--------------------------------------------------------------------------------

local entries = Fields.ParseLootLines("1-3 an anchovy\n4 an old boot\n100 = a golden carp")
H.checkEqual("three lines parsed", #entries, 3)
H.checkEqual("a range keeps its start", entries[1].min, 1)
H.checkEqual("and its end", entries[1].max, 3)
H.checkEqual("and its text", entries[1].text, "an anchovy")

H.checkEqual("a bare number is a band of one", entries[2].min, entries[2].max)
H.checkEqual("with the number read", entries[2].min, 4)
H.checkEqual("an equals sign is accepted", entries[3].text, "a golden carp")

H.checkEqual("and they serialize back unchanged",
	Fields.SerializeLootLines(entries), "1-3 an anchovy\n4 an old boot\n100 a golden carp")

-- A line the host is halfway through typing must not take a chunk of the table
-- with it.
local partial = Fields.ParseLootLines("1-3 an anchovy\n7\n\n12 a trout")
H.checkEqual("a number with no text is skipped", #partial, 2)
H.checkEqual("without disturbing the lines around it", partial[2].text, "a trout")

--------------------------------------------------------------------------------
H.section("Reading a roll off it")
--------------------------------------------------------------------------------

reset()
local preset = fishingPreset()

H.checkEqual("the bottom of a band matches", Watcher:LootFor(preset, 1).text, "an anchovy")
H.checkEqual("the top of a band matches", Watcher:LootFor(preset, 3).text, "an anchovy")
H.checkEqual("the next band starts where it should",
	Watcher:LootFor(preset, 4).text, "an old boot")
H.checkEqual("a single-number band matches",
	Watcher:LootFor(preset, 100).text, "the legendary whale")

preset.loot.entries = Fields.ParseLootLines("50 the one that got away\n1-100 a river trout")
H.checkEqual("the first line covering the roll wins",
	Watcher:LootFor(preset, 50).text, "the one that got away")
H.checkEqual("and the wide band still catches everything else",
	Watcher:LootFor(preset, 51).text, "a river trout")

preset = fishingPreset()
preset.loot.entries = Fields.ParseLootLines("1-3 an anchovy")
H.check("a roll no band covers has no loot", Watcher:LootFor(preset, 40) == nil)
H.check("and says nothing when there is no fallback text",
	Watcher:FormatLoot(preset, "Rennek-Argent Dawn", 40) == nil)

preset.loot.nothingText = "nothing at all"
H.checkEqual("a fallback line is used when one is set",
	Watcher:FormatLoot(preset, "Rennek-Argent Dawn", 40),
	"Rennek-Argent Dawn has caught nothing at all.")

preset.loot.enabled = false
H.check("nothing matches while the table is switched off",
	Watcher:LootFor(preset, 2) == nil)

--------------------------------------------------------------------------------
H.section("The line itself")
--------------------------------------------------------------------------------

preset = fishingPreset()
H.checkEqual("the placeholders are filled in",
	Watcher:FormatLoot(preset, "Rennek-Argent Dawn", 2),
	"Rennek-Argent Dawn has caught an anchovy.")

preset.loot.message = "{name} reels in {item} on a {roll}!"
H.checkEqual("the roll can be shown too",
	Watcher:FormatLoot(preset, "Rennek-Argent Dawn", 2),
	"Rennek-Argent Dawn reels in an anchovy on a 2!")

-- Every one of these strings is host-editable, so a stray % must print rather
-- than error, and a colour escape must never reach chat -- the client drops the
-- whole message when it finds one.
preset.loot.message = "{name} caught {item} (100% certain)"
H.checkEqual("a percent sign in the template survives",
	Watcher:FormatLoot(preset, "Rennek-Argent Dawn", 2),
	"Rennek-Argent Dawn caught an anchovy (100% certain)")

preset.loot.message = "|cffff0000{name}|r has caught {item}."
H.check("colour escapes are stripped out of the line",
	Watcher:FormatLoot(preset, "Rennek-Argent Dawn", 2):find("|", 1, true) == nil)

--------------------------------------------------------------------------------
H.section("At the event")
--------------------------------------------------------------------------------

reset()
preset = fishingPreset()
preset.channel.type = "PARTY"
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })

Watcher:SetMode("local")
roll("Rennek", 2)

H.checkEqual("nothing is said the instant the roll lands", #H.sentMessages(), 0)

H.advance(2)
H.checkEqual("nor before the delay is up", #H.sentMessages(), 0)

H.advance(2)
H.checkEqual("the result reaches the channel after it", #H.sentMessages(), 1)
H.checkEqual("with the caught item in it",
	H.sentMessages()[1], "Rennek has caught an anchovy.")

-- The host sees it in their own frame either way, so a table set up wrong is
-- visible without waiting to read it back out of the channel.
H.check("and the host is shown it locally",
	H.outputText():find("has caught an anchovy", 1, true) ~= nil)

-- The watcher is on "local": the verdicts are the host's own business and only
-- the catch was meant for the room.
H.checkEqual("the verdict did not go with it", #H.sentMessages(), 1)

reset()
preset = fishingPreset()
preset.channel.type = "PARTY"
preset.loot.announce = false
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })

Watcher:SetMode("local")
roll("Rennek", 2)
H.advance(5)

H.checkEqual("with sending switched off nothing reaches the channel", #H.sentMessages(), 0)
H.check("but the host still sees the result",
	H.outputText():find("has caught an anchovy", 1, true) ~= nil)

reset()
preset = fishingPreset()
preset.channel.type = "PARTY"
preset.loot.delaySeconds = 0
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })

Watcher:SetMode("local")
roll("Rennek", 100)
H.checkEqual("a delay of zero sends immediately", #H.sentMessages(), 1)
H.checkEqual("with the right band",
	H.sentMessages()[1], "Rennek has caught the legendary whale.")

--------------------------------------------------------------------------------
H.section("It respects the rest of the watcher")
--------------------------------------------------------------------------------

reset()
preset = fishingPreset()
preset.channel.type = "PARTY"
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })

-- Off means off: a loot table left enabled in a preset must not start
-- announcing because somebody in the room happened to roll.
roll("Rennek", 2)
H.advance(5)
H.checkEqual("a disarmed watcher announces nothing", #H.sentMessages(), 0)

Watcher:SetMode("local")
H.clearSent()

-- Whoever the filter excludes gets no loot either, or a stranger rolling in the
-- middle of the event would be handed a fish.
preset.rollFilter.mode = "roster"
preset.rollFilter.roster = { "Rennek" }
roll("Passerby", 2)
H.advance(5)
H.checkEqual("a roll the filter drops produces no result", #H.sentMessages(), 0)

roll("Rennek", 2)
H.advance(5)
H.checkEqual("a roll it keeps still does", #H.sentMessages(), 1)

reset()
preset = fishingPreset()
preset.channel.type = "PREVIEW"
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })
Watcher:SetMode("local")

roll("Rennek", 2)
H.advance(5)
H.checkEqual("a preview channel sends nothing", #H.sentMessages(), 0)
H.check("and still shows the host what would have been said",
	H.outputText():find("has caught an anchovy", 1, true) ~= nil)

--------------------------------------------------------------------------------
H.section("The channel the results can actually reach")
--------------------------------------------------------------------------------

-- A result is sent from a timer, seconds after the roll, with no click behind
-- it -- and /say, /yell, /emote, whispers and custom channels are exactly the
-- ones the client will not let an addon reach that way. This is the same wall
-- the rule announcement hit in 1.1.0, and the host is told about it once rather
-- than left watching an empty channel.
reset()
preset = fishingPreset()
preset.channel.type = "SAY"
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })
Watcher:SetMode("local")

roll("Rennek", 2)
H.check("a restricted channel is explained before the event goes wrong",
	H.outputText():find("right after you click something", 1, true) ~= nil, H.outputText())
H.check("and the channel it applies to is named",
	H.outputText():find("/say", 1, true) ~= nil)

H.clearOutput()
roll("Rennek", 3)
H.check("but only once, not on every roll",
	H.outputText():find("right after you click", 1, true) == nil)

reset()
preset = fishingPreset()
preset.channel.type = "PARTY"
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })
Watcher:SetMode("local")

roll("Rennek", 2)
H.check("party chat draws no such warning",
	H.outputText():find("right after you click", 1, true) == nil)

--------------------------------------------------------------------------------
H.section("Announcing the table with the rules")
--------------------------------------------------------------------------------

reset()
preset = fishingPreset()

local messages = REH.Formatter:BuildMessages(preset)
local joined = table.concat(messages, "\n")
H.check("the table can be announced with the rules",
	joined:find("1-3 = an anchovy", 1, true) ~= nil, joined)
H.check("a single-number band reads as one number",
	joined:find("100 = the legendary whale", 1, true) ~= nil)

preset.moduleEnabled.loot = false
joined = table.concat(REH.Formatter:BuildMessages(preset), "\n")
H.check("and left out when the section is switched off",
	joined:find("an anchovy", 1, true) == nil)

-- A host who wants the catches to be a surprise turns the section off; a host
-- with no table at all should never see an empty heading either way.
preset.moduleEnabled.loot = true
preset.loot.entries = {}
joined = table.concat(REH.Formatter:BuildMessages(preset), "\n")
H.check("an empty table announces nothing", joined:find("Results:", 1, true) == nil)

preset = fishingPreset()
preset.loot.enabled = false
joined = table.concat(REH.Formatter:BuildMessages(preset), "\n")
H.check("nor does a table that is switched off", joined:find("Results:", 1, true) == nil)

--------------------------------------------------------------------------------
H.section("Bad and hostile tables")
--------------------------------------------------------------------------------

local scratch = REH.CreateDefaultPreset("Scratch")
scratch.rolls.dieMax = 20
scratch.loot = {
	enabled = "yes",
	announce = 1,
	delaySeconds = 9999,
	message = 42,
	entries = {
		{ min = 10, max = 3, text = "back to front" },
		{ min = -5, max = 500, text = "out of range" },
		{ min = 1, max = 2, text = "" },
		{ min = 2, max = 3 },
		"not a table",
		{ min = 4, max = 5, text = "|cffff0000red|r" },
	},
}
DB:ValidatePreset(scratch)

H.checkEqual("a string enable is coerced to a boolean", scratch.loot.enabled, true)
H.checkEqual("and a number announce", scratch.loot.announce, true)
H.checkEqual("an absurd delay is clamped", scratch.loot.delaySeconds, 30)
H.checkEqual("a non-string message falls back to the default",
	scratch.loot.message, "{name} has caught {item}.")

H.checkEqual("only the usable bands survive", #scratch.loot.entries, 3)
H.checkEqual("a back-to-front band is turned around", scratch.loot.entries[1].min, 3)
H.checkEqual("and kept", scratch.loot.entries[1].max, 10)
H.checkEqual("a band below 1 is clamped up", scratch.loot.entries[2].min, 1)
H.checkEqual("and one past the die is clamped down", scratch.loot.entries[2].max, 20)

H.check("a colour escape in an entry cannot reach chat",
	(Watcher:FormatLoot(scratch, "Rennek-Argent Dawn", 4) or ""):find("|", 1, true) == nil)

-- Lowering the die must not leave bands nobody can roll into.
scratch.rolls.dieMax = 6
DB:ValidatePreset(scratch)
local past = false
for _, entry in ipairs(scratch.loot.entries) do
	if entry.min > 6 or entry.max > 6 then
		past = true
	end
end
H.check("shrinking the die pulls the bands in with it", past == false)

local huge = {}
for index = 1, REH.MAX_LOOT_ENTRIES + 20 do
	huge[index] = { min = 1, max = 1, text = "fish " .. index }
end
scratch.loot.entries = huge
DB:ValidatePreset(scratch)
H.check("the table is capped", #scratch.loot.entries <= REH.MAX_LOOT_ENTRIES,
	#scratch.loot.entries)

--------------------------------------------------------------------------------
H.section("It survives a reload and an export")
--------------------------------------------------------------------------------

reset()
preset = fishingPreset()
preset.loot.message = "{name} has landed {item}!"

REH = H.reload()
DB = REH.Database
Fields = REH.Fields
Watcher = REH.RollWatcher

local reloaded = DB:GetActivePreset()
H.checkEqual("the table is still there", #reloaded.loot.entries, 5)
H.checkEqual("with the host's own line",
	reloaded.loot.message, "{name} has landed {item}!")
H.checkEqual("and still reads a roll",
	Watcher:LootFor(reloaded, 95).text, "a gleaming salmon")

local exported = REH.Transfer:Export(reloaded, "Fishing Night")
H.check("a preset with a table exports", type(exported) == "string" and #exported > 0)

local decoded = REH.Transfer:Import(exported)
H.checkEqual("and the table comes back with it", #decoded.loot.entries, 5)
H.checkEqual("with its text intact", decoded.loot.entries[1].text, "an anchovy")

--------------------------------------------------------------------------------
H.section("The command")
--------------------------------------------------------------------------------

reset()
preset = fishingPreset()

REH.Commands:Handle("loot off")
H.checkEqual("/reh loot off switches it off", DB:GetActivePreset().loot.enabled, false)

REH.Commands:Handle("loot on")
H.checkEqual("/reh loot on switches it back", DB:GetActivePreset().loot.enabled, true)

H.clearOutput()
REH.Commands:Handle("loot")
H.check("/reh loot lists the table",
	H.outputText():find("an anchovy", 1, true) ~= nil, H.outputText())

H.clearOutput()
REH.Commands:Handle("loot test 95")
H.check("/reh loot test shows what a roll would give",
	H.outputText():find("a gleaming salmon", 1, true) ~= nil, H.outputText())
H.checkEqual("and sends nothing while doing it", #H.sentMessages(), 0)

H.clearOutput()
REH.Commands:Handle("loot test")
H.check("a test with no number explains itself",
	H.outputText():find("loot test", 1, true) ~= nil, H.outputText())

H.checkNoLeakedGlobals(H.ALLOWED_GLOBALS)
H.finish()
