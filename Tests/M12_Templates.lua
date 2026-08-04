-- M12: the starter presets.
--
-- A template is hand-written data, and hand-written data is data that can be
-- wrong. The checks that matter are the ones a host would otherwise discover at
-- an event: that every template survives validation unchanged, that each one
-- actually announces something, and that the features each was written to
-- demonstrate are still switched on.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "Tests"
local H = dofile(here .. "/Harness.lua")

H.installStubs()
H.snapshotGlobals()
H.wipeSavedVariables()

local REH = H.login()
local DB = REH.Database
local Templates = REH.Templates

--------------------------------------------------------------------------------
H.section("Every template is a usable preset")
--------------------------------------------------------------------------------

H.check("there are starters to choose from", #Templates.LIST >= 4, #Templates.LIST)

local seenKeys, seenNames = {}, {}
local uniqueKeys, uniqueNames = true, true

for _, template in ipairs(Templates.LIST) do
	if seenKeys[template.key] then
		uniqueKeys = false
	end
	if seenNames[template.name] then
		uniqueNames = false
	end
	seenKeys[template.key] = true
	seenNames[template.name] = true
end

H.check("their keys are unique", uniqueKeys)
H.check("and so are their names", uniqueNames)

for _, template in ipairs(Templates.LIST) do
	local label = template.key

	H.check(label .. ": has a name a host can read", (template.name or "") ~= "")
	H.check(label .. ": explains itself in one line",
		#(template.summary or "") > 20 and #(template.summary or "") < 120,
		template.summary)

	local preset = Templates:Build(template.key)
	H.check(label .. ": builds a preset", preset ~= nil)

	-- Validation repairs anything wrong with a preset. A template that comes
	-- out of it changed is a template with a bug -- a band past its die, a
	-- threshold above the maximum roll -- and the host would never be told.
	local before = REH.DeepCopy(preset)
	DB:ValidatePreset(preset)
	H.check(label .. ": survives validation unchanged",
		H.deepEqual(before, preset), H.firstDifference(before, preset))

	-- An announcement with nothing in it is the one outcome a starter must
	-- never produce.
	local messages = REH.Formatter:BuildMessages(preset)
	H.check(label .. ": announces something", #messages > 3, #messages)

	-- Nothing may be sent until the host has chosen where.
	H.checkEqual(label .. ": announces to preview only", preset.channel.type, "PREVIEW")

	-- Rules and etiquette are what turn a set of numbers into an event.
	H.check(label .. ": comes with rules", #preset.custom > 0)
	H.check(label .. ": and with etiquette", #preset.etiquette > 0)

	-- Every section left switched on must actually produce a line. A section
	-- that is announced and says nothing is one the host meant to switch off.
	local _, info = REH.Formatter:BuildLines(preset)
	local spoke = {}
	for _, record in ipairs(info.records) do
		spoke[record.module] = true
	end

	local silentSection = nil
	for _, key in ipairs(REH.MODULE_KEYS) do
		if preset.moduleEnabled[key] and not spoke[key] then
			silentSection = key
		end
	end
	H.check(label .. ": every announced section has something to say",
		silentSection == nil, silentSection)
end

--------------------------------------------------------------------------------
H.section("Each one demonstrates what it was written for")
--------------------------------------------------------------------------------

local fishing = Templates:Build("fishing")
DB:ValidatePreset(fishing)

-- The reason this switch exists: a 7 is a fat carp, and calling it a FAILURE
-- in the same breath contradicts the catch.
H.check("the fishing night does not call rolls a success or failure",
	fishing.rolls.useVerdicts == false)

local fishingRolls
for _, message in ipairs(REH.Formatter:BuildMessages(fishing)) do
	if message:find("Rolls:", 1, true) then
		fishingRolls = message
	end
end
H.check("so its rules announce no success band",
	(fishingRolls or ""):find("SUCCESS", 1, true) == nil, fishingRolls)

H.check("the fishing night has its results table on", fishing.loot.enabled)
H.check("with a full table of bands", #fishing.loot.entries >= 8, #fishing.loot.entries)
H.check("every band inside its die", (function()
	for _, entry in ipairs(fishing.loot.entries) do
		if entry.max > fishing.rolls.dieMax or entry.min < 1 then
			return false
		end
	end
	return true
end)())

-- The whole point of the fishing template: a band written more than once is
-- several fish, one chosen at random.
local alternatives = REH.RollWatcher:LootAlternatives(fishing, 5)
H.check("and several fish for the same roll", #alternatives > 1, #alternatives)

local caught = {}
for _ = 1, 200 do
	caught[REH.RollWatcher:LootFor(fishing, 5).text] = true
end
H.checkEqual("all of which come up", REH.CountKeys(caught), #alternatives)

H.check("it also ships roll effects", #fishing.rollEffects > 0)

-- The effects fire on the result rather than on a number, which is what shows
-- that silencing verdicts does not stop them being used.
local verdictTriggered = 0
for _, effect in ipairs(fishing.rollEffects) do
	if effect.trigger == "verdict" then
		verdictTriggered = verdictTriggered + 1
	end
end
H.checkEqual("all of which fire on a result", verdictTriggered, #fishing.rollEffects)

-- End to end: a great cast still sets off the reaction, with nothing announced
-- as a success anywhere.
local greatCast = REH.RollWatcher:Judge(fishing, 18, fishing.rolls.dieMax)
H.checkEqual("18 is a great cast at this event", greatCast, "critsuccess")

local reactions = REH.RollWatcher:MatchEffects(fishing, 18, greatCast)
H.checkEqual("which sets off the pair of reactions", #reactions, 2)
H.checkEqual("one of which is chosen",
	#REH.RollWatcher:ResolveEffects(reactions), 1)

H.checkEqual("a snapped line is its own reaction",
	#REH.RollWatcher:MatchEffects(fishing, 1,
		REH.RollWatcher:Judge(fishing, 1, fishing.rolls.dieMax)), 1)

H.checkEqual("and an ordinary cast sets off none",
	#REH.RollWatcher:MatchEffects(fishing, 7,
		REH.RollWatcher:Judge(fishing, 7, fishing.rolls.dieMax)), 0)

-- Moving the band moves the reaction with it, which is the reason to trigger
-- on the result rather than on the numbers.
fishing.rolls.critSuccessAt = 20
DB:ValidatePreset(fishing)
H.checkEqual("narrowing the critical band narrows what reacts",
	#REH.RollWatcher:MatchEffects(fishing, 18,
		REH.RollWatcher:Judge(fishing, 18, fishing.rolls.dieMax)), 0)
H.checkEqual("while the top of the die still does",
	#REH.RollWatcher:MatchEffects(fishing, 20,
		REH.RollWatcher:Judge(fishing, 20, fishing.rolls.dieMax)), 2)

fishing = Templates:Build("fishing")
DB:ValidatePreset(fishing)

local randomEffects = 0
for _, effect in ipairs(fishing.rollEffects) do
	if effect.random then
		randomEffects = randomEffects + 1
	end
end
H.check("including a pair marked as alternatives", randomEffects >= 2, randomEffects)

-- Every roll from 1 to the die must produce a catch, or a host finds the hole
-- when somebody rolls into it.
local uncovered = nil
for roll = 1, fishing.rolls.dieMax do
	if #REH.RollWatcher:LootAlternatives(fishing, roll) == 0 then
		uncovered = roll
	end
end
H.check("and the table covers every roll on the die", uncovered == nil, uncovered)

local arena = Templates:Build("arena")
DB:ValidatePreset(arena)
H.checkEqual("the arena brawl filters to subgroups", arena.rollFilter.mode, "subgroup")
H.check("with subgroups actually chosen", #arena.rollFilter.subgroups > 0)
H.check("and announces its rounds", arena.rounds.announce)

local tavern = Templates:Build("tavern")
DB:ValidatePreset(tavern)
H.check("the tavern night has no combat sections",
	tavern.moduleEnabled.damage == false and tavern.moduleEnabled.health == false)
-- A tavern night runs in /say, where the client will not deliver a line sent
-- seconds after a roll. The drinks go to the host to read out instead.
H.check("its drinks come to the host rather than the channel",
	tavern.loot.enabled and tavern.loot.target == "self")
H.check("and you cannot fail at being handed a drink",
	tavern.rolls.useVerdicts == false)

-- The two that are about winning and losing keep their verdicts.
H.check("the arena still calls rolls a success or failure", arena.rolls.useVerdicts)

local duel = Templates:Build("duel")
DB:ValidatePreset(duel)
H.checkEqual("the duel ring rolls for initiative", duel.turns.mode, "initiative")
H.check("and has a turn timer", duel.turns.turnTimeSeconds > 0)
H.check("with health to lose", #duel.health.rows > 0)

--------------------------------------------------------------------------------
H.section("Creating one")
--------------------------------------------------------------------------------

local created, name, template = DB:CreateFromTemplate("fishing")
H.check("a template can be created", created ~= nil, name)
H.checkEqual("named after itself", name, "Fishing Night")
H.checkEqual("and reports which template it was", template.key, "fishing")
H.check("it is saved", DB:GetPreset("Fishing Night") ~= nil)
H.checkEqual("with the loot table intact", #DB:GetPreset("Fishing Night").loot.entries,
	#created.loot.entries)

-- Making the same one twice is a thing hosts do -- one for Tuesday, one for the
-- guild night -- and it must not fail on a name clash.
local second, secondName = DB:CreateFromTemplate("fishing")
H.check("a second copy is created", second ~= nil, secondName)
H.checkEqual("with a numbered name", secondName, "Fishing Night 2")

local third, thirdName = DB:CreateFromTemplate("fishing")
H.checkEqual("and a third", thirdName, "Fishing Night 3")

local named, namedResult = DB:CreateFromTemplate("duel", "Friday Duels")
H.check("a template can be given a name", named ~= nil, namedResult)
H.checkEqual("which is used", namedResult, "Friday Duels")
H.checkEqual("and the event announces itself by that name too",
	named.header.eventName, "Friday Duels")

local missing, reason = DB:CreateFromTemplate("nonsense")
H.check("an unknown template is refused", missing == nil)
H.check("with a reason naming the command",
	(reason or ""):find("/reh templates", 1, true) ~= nil, reason)

H.checkEqual("the host's own name is filled in", named.header.hostName, H.playerName)

--------------------------------------------------------------------------------
H.section("Finding one by name")
--------------------------------------------------------------------------------

H.checkEqual("a template is found by key", Templates:Find("tavern").key, "tavern")
H.checkEqual("case does not matter", Templates:Find("TAVERN").key, "tavern")
H.checkEqual("and the shown name works too",
	Templates:Find("Fishing Night").key, "fishing")
H.check("an unknown name finds nothing", Templates:Find("bingo") == nil)
H.check("and so does a non-string", Templates:Find(nil) == nil)

--------------------------------------------------------------------------------
H.section("The commands")
--------------------------------------------------------------------------------

H.clearOutput()
REH.Commands:Handle("templates")
local listing = H.outputText()
H.check("/reh templates lists them", listing:find("fishing", 1, true) ~= nil, listing)
H.check("with what each one is for",
	listing:find("picked at random", 1, true) ~= nil)

H.clearOutput()
REH.Commands:Handle("template arena")
H.check("/reh template creates one", DB:GetPreset("Arena Brawl") ~= nil)
local _, activeName = DB:GetActivePreset()
H.checkEqual("and makes it active", activeName, "Arena Brawl")
H.check("saying it will not send anything yet",
	H.outputText():find("preview only", 1, true) ~= nil, H.outputText())

H.clearOutput()
REH.Commands:Handle("template duel Saturday Duels")
H.check("a name with spaces is kept whole", DB:GetPreset("Saturday Duels") ~= nil)

H.clearOutput()
REH.Commands:Handle("template bingo")
H.check("an unknown one is refused rather than guessed at",
	DB:GetPreset("bingo") == nil)
H.check("and says so", H.outputText():find("No starter preset", 1, true) ~= nil)

H.clearOutput()
REH.Commands:Handle("template")
H.check("with no argument it lists them instead",
	H.outputText():find("Starter presets", 1, true) ~= nil, H.outputText())

--------------------------------------------------------------------------------
H.section("They survive a reload and travel")
--------------------------------------------------------------------------------

REH = H.reload()
DB = REH.Database

local reloaded = DB:GetPreset("Fishing Night")
H.check("a preset made from a template is still there", reloaded ~= nil)
H.check("with its loot table", #reloaded.loot.entries >= 8)
H.check("and its effects", #reloaded.rollEffects > 0)

local exported = REH.Transfer:Export(reloaded, "Fishing Night")
local imported = REH.Transfer:Import(exported)
H.checkEqual("and it can be shared with another host",
	#imported.loot.entries, #reloaded.loot.entries)

H.checkNoLeakedGlobals(H.ALLOWED_GLOBALS)
H.finish()
