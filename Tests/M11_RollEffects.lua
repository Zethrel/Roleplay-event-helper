-- M11: roll effects -- the customizable half of the loot feature.
--
-- Where the loot table answers "what did that roll catch", an effect answers
-- "what happens on that roll": it can fire on a result rather than a number,
-- several can answer the same roll, and each carries its own chance, delay and
-- destination. The window that edits them is built here too, against the widget
-- mock, so the layout code is known to call only API that exists.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "Tests"
local H = dofile(here .. "/Harness.lua")

H.installStubs()
H.snapshotGlobals()
H.wipeSavedVariables()

local REH = H.login()
local DB = REH.Database
local Watcher = REH.RollWatcher
local Effects = REH.UI.EffectsFrame

local function reset()
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

--- An effect with the given fields laid over the default.
local function effect(overrides)
	local record = REH.CreateRollEffect()
	for key, value in pairs(overrides or {}) do
		record[key] = value
	end
	return record
end

local function withEffects(list)
	local preset = DB:GetActivePreset()
	preset.rollEffects = list

	-- The loot table is the other thing that speaks after a roll. Off unless a
	-- check turns it on, so a stray fish cannot be mistaken for an effect.
	preset.loot.enabled = false

	DB:ValidatePreset(preset)
	return preset
end

--------------------------------------------------------------------------------
H.section("What sets an effect off")
--------------------------------------------------------------------------------

local band = effect({ trigger = "band", min = 1, max = 1 })
H.check("a band fires on its number", Watcher:EffectMatches(band, 1, "critfail"))
H.check("and not on another", Watcher:EffectMatches(band, 2, "fail") == false)

local wide = effect({ trigger = "band", min = 90, max = 100 })
H.check("a range fires at its bottom", Watcher:EffectMatches(wide, 90, "success"))
H.check("and at its top", Watcher:EffectMatches(wide, 100, "critsuccess"))
H.check("but not below it", Watcher:EffectMatches(wide, 89, "success") == false)

local onCrit = effect({ trigger = "verdict", verdict = "critfail" })
H.check("a verdict effect fires on that verdict", Watcher:EffectMatches(onCrit, 1, "critfail"))
H.check("and not on another", Watcher:EffectMatches(onCrit, 50, "success") == false)

local always = effect({ trigger = "any" })
H.check("an 'any' effect fires on anything", Watcher:EffectMatches(always, 47, "success"))

local off = effect({ trigger = "any", enabled = false })
H.check("a disabled effect never fires", Watcher:EffectMatches(off, 47, "success") == false)

--------------------------------------------------------------------------------
H.section("Several answer the same roll")
--------------------------------------------------------------------------------

-- This is the difference from the loot table, which stops at the first match.
-- "On a natural 1 your line snaps" and "every cast makes a splash" are both
-- true of a 1, and a host who wanted only one would not have written the other.
local preset = withEffects({
	effect({ trigger = "band", min = 1, max = 1, message = "{name}'s line snaps." }),
	effect({ trigger = "verdict", verdict = "critfail", message = "The crowd winces." }),
	effect({ trigger = "any", message = "A splash." }),
	effect({ trigger = "band", min = 100, max = 100, message = "Never on a 1." }),
})

local matched = Watcher:MatchEffects(preset, 1, "critfail")
H.checkEqual("all three matching effects are returned", #matched, 3)
H.checkEqual("in the host's own order", matched[1].message, "{name}'s line snaps.")
H.checkEqual("and only the matching ones", matched[3].message, "A splash.")

H.checkEqual("a roll matching one effect returns one",
	#Watcher:MatchEffects(preset, 50, "success"), 1)

--------------------------------------------------------------------------------
H.section("One of these at random")
--------------------------------------------------------------------------------

-- The same idea as repeating a band in the loot table, on the effects side:
-- effects sharing a trigger normally all fire, and ticking "one of these" on a
-- group makes them alternatives instead.
reset()
preset = withEffects({
	effect({ trigger = "band", min = 4, max = 7, random = true, message = "A salmon." }),
	effect({ trigger = "band", min = 4, max = 7, random = true, message = "A trout." }),
	effect({ trigger = "band", min = 4, max = 7, random = true, message = "A carp." }),
	effect({ trigger = "any", message = "A splash." }),
})

local resolved = Watcher:ResolveEffects(Watcher:MatchEffects(preset, 5, "fail"))
H.checkEqual("a random group collapses to one, and the others stay", #resolved, 2)
H.checkEqual("with the non-random effect kept as it was",
	resolved[2].message, "A splash.")

local picked = {}
for _ = 1, 200 do
	local one = Watcher:ResolveEffects(Watcher:MatchEffects(preset, 5, "fail"))
	picked[one[1].message] = true
end
H.check("every alternative can be the one chosen",
	picked["A salmon."] and picked["A trout."] and picked["A carp."])
H.checkEqual("and nothing else ever is", REH.CountKeys(picked), 3)

-- Grouping is by trigger, so two random effects that fire on different things
-- are not alternatives to each other.
preset = withEffects({
	effect({ trigger = "band", min = 1, max = 1, random = true, message = "Snap." }),
	effect({ trigger = "verdict", verdict = "critfail", random = true, message = "Ouch." }),
})
H.checkEqual("different triggers are not alternatives",
	#Watcher:ResolveEffects(Watcher:MatchEffects(preset, 1, "critfail")), 2)

-- Without the flag, nothing changes: this is what 1.7.0 already did.
preset = withEffects({
	effect({ trigger = "band", min = 4, max = 7, message = "A salmon." }),
	effect({ trigger = "band", min = 4, max = 7, message = "A trout." }),
})
H.checkEqual("effects that are not marked random all still fire",
	#Watcher:ResolveEffects(Watcher:MatchEffects(preset, 5, "fail")), 2)

--------------------------------------------------------------------------------
H.section("The line it produces")
--------------------------------------------------------------------------------

preset = withEffects({
	effect({ trigger = "any", message = "{name} rolled {roll}: {result}." }),
})

H.checkEqual("the placeholders are filled in",
	Watcher:FormatEffect(preset, preset.rollEffects[1], "Rennek-Argent Dawn", 74, "success"),
	"Rennek-Argent Dawn rolled 74: SUCCESS.")

-- An effect can talk about what the loot table gave the same roll, so the catch
-- and what happens next can be two lines rather than one crowded one.
preset.loot.enabled = true
preset.loot.entries = { { min = 1, max = 3, text = "an anchovy" } }
preset.rollEffects[1].message = "{name} holds up {item} to no applause."
H.checkEqual("an effect can name the loot for that roll",
	Watcher:FormatEffect(preset, preset.rollEffects[1], "Rennek-Argent Dawn", 2, "fail"),
	"Rennek-Argent Dawn holds up an anchovy to no applause.")

-- Host-editable text: a stray % must print rather than error, and a colour
-- escape must never reach chat, because the client silently drops a message
-- containing one.
preset.rollEffects[1].message = "{name} is 100% soaked"
H.checkEqual("a percent sign survives",
	Watcher:FormatEffect(preset, preset.rollEffects[1], "Rennek-Argent Dawn", 2, "fail"),
	"Rennek-Argent Dawn is 100% soaked")

preset.rollEffects[1].message = "|cffff0000{name}|r slips."
H.check("colour escapes are stripped",
	Watcher:FormatEffect(preset, preset.rollEffects[1], "Rennek-Argent Dawn", 2, "fail")
		:find("|", 1, true) == nil)

--------------------------------------------------------------------------------
H.section("At the event")
--------------------------------------------------------------------------------

reset()
preset = withEffects({
	effect({ trigger = "band", min = 1, max = 1, delaySeconds = 3,
		message = "{name}'s line snaps." }),
	effect({ trigger = "any", delaySeconds = 0, message = "A splash." }),
})
preset.channel.type = "PARTY"
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })
Watcher:SetMode("local")

roll("Rennek", 1)
H.checkEqual("an effect with no delay is sent at once", #H.sentMessages(), 1)
H.checkEqual("and it is the right one", H.sentMessages()[1], "A splash.")

H.advance(4)
H.checkEqual("the delayed one follows", #H.sentMessages(), 2)
H.checkEqual("with its own text", H.sentMessages()[2], "Rennek's line snaps.")

reset()
preset = withEffects({
	effect({ trigger = "any", delaySeconds = 0, target = "self",
		message = "Only I see this." }),
})
preset.channel.type = "PARTY"
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })
Watcher:SetMode("local")

roll("Rennek", 50)
H.checkEqual("a 'to me only' effect sends nothing", #H.sentMessages(), 0)
H.check("but is shown to the host",
	H.outputText():find("Only I see this", 1, true) ~= nil)

reset()
preset = withEffects({
	effect({ trigger = "any", delaySeconds = 0, chance = 0, message = "Never." }),
})
preset.channel.type = "PARTY"
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })
Watcher:SetMode("local")

roll("Rennek", 50)
H.checkEqual("a chance of zero never fires", #H.sentMessages(), 0)

-- The watcher's own switches still govern everything: nothing fires while it is
-- disarmed, and nothing fires for a roll the filter drops.
reset()
preset = withEffects({
	effect({ trigger = "any", delaySeconds = 0, message = "A splash." }),
})
preset.channel.type = "PARTY"
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })

roll("Rennek", 50)
H.checkEqual("a disarmed watcher fires nothing", #H.sentMessages(), 0)

Watcher:SetMode("local")
preset.rollFilter.mode = "roster"
preset.rollFilter.roster = { "Rennek" }
roll("Passerby", 50)
H.checkEqual("nor does a roll the filter drops", #H.sentMessages(), 0)

roll("Rennek", 50)
H.checkEqual("a roll it keeps still fires", #H.sentMessages(), 1)

-- Same wall as the loot table: a line sent from a timer has no click behind it.
reset()
preset = withEffects({
	effect({ trigger = "any", delaySeconds = 2, message = "A splash." }),
})
preset.channel.type = "SAY"
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })
Watcher:SetMode("local")

roll("Rennek", 50)
H.check("a restricted channel is explained",
	H.outputText():find("right after you click something", 1, true) ~= nil)

--------------------------------------------------------------------------------
H.section("Whispering the roller")
--------------------------------------------------------------------------------

-- Asked for because not everything an effect says belongs in front of the whole
-- room: what one person notices on their own cast is theirs.
reset()
preset = withEffects({
	effect({ trigger = "any", delaySeconds = 0, target = "whisper",
		message = "You feel something tug the line." }),
})
preset.channel.type = "PARTY"

-- An earlier section left a roster filter behind, and a filtered roll never
-- reaches an effect at all.
preset.rollFilter.mode = "group"

H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })
Watcher:SetMode("local")

roll("Rennek", 50)

local sent = H.sent[1]
H.check("the effect is sent", sent ~= nil)
H.checkEqual("as a whisper", sent and sent.chatType, "WHISPER")
H.checkEqual("to the person who rolled", sent and sent.target, "Rennek-ArgentDawn")
H.checkEqual("with the effect's own text", sent and sent.message,
	"You feel something tug the line.")

-- The host is running the event and needs to know what each person was told.
H.check("and the host sees it too",
	H.outputText():find("tug the line", 1, true) ~= nil, H.outputText())
H.check("with who it went to",
	H.outputText():find("(to Rennek)", 1, true) ~= nil, H.outputText())

-- Nobody can whisper themselves, so a host testing their own effects gets it
-- in their frame rather than an error.
reset()
H.setGroup({ { name = "Testchar", subgroup = 1 } })
Watcher:SetMode("local")
roll("Testchar", 50)
H.checkEqual("whispering yourself sends nothing", #H.sentMessages(), 0)
H.check("but still shows you the line",
	H.outputText():find("tug the line", 1, true) ~= nil, H.outputText())

-- The exception, asked for after a party test: the preset's channel says where
-- rules and results are announced, and a line meant for one person is not an
-- announcement. A host running an evening in preview -- reading the rules out
-- by hand, broadcasting nothing -- can still have each person told privately
-- what only they noticed.
reset()
preset.channel.type = "PREVIEW"
preset.rollFilter.mode = "group"
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })
Watcher:SetMode("local")
roll("Rennek", 50)

H.checkEqual("a preview preset still whispers the roller", #H.sentMessages(), 1)
H.checkEqual("as a whisper", H.sent[1].chatType, "WHISPER")
H.checkEqual("to them", H.sent[1].target, "Rennek-ArgentDawn")

-- Everything else about preview is untouched: an effect aimed at the channel
-- still says nothing to the room.
reset()
preset = withEffects({
	effect({ trigger = "any", delaySeconds = 0, target = "channel",
		message = "Heard by everyone." }),
})
preset.channel.type = "PREVIEW"
preset.rollFilter.mode = "group"
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })
Watcher:SetMode("local")
roll("Rennek", 50)
H.checkEqual("while an effect aimed at the channel still sends nothing",
	#H.sentMessages(), 0)
H.check("and says the preset is on preview",
	H.outputText():find("preview only", 1, true) ~= nil, H.outputText())

preset = withEffects({
	effect({ trigger = "any", delaySeconds = 0, target = "whisper",
		message = "You feel something tug the line." }),
})
preset.rollFilter.mode = "group"

-- The refusal that matters, and the one 1.16.0 got wrong: the client does not
-- raise a Lua error when it refuses a send. It fires ADDON_ACTION_BLOCKED and
-- returns normally, so pcall reports success for a whisper that never left and
-- the host is told a line arrived when nobody received it.
reset()
preset.channel.type = "PARTY"
preset.rollFilter.mode = "group"
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })
Watcher:SetMode("local")
REH.Diagnostics:Clear()
H.blockAfter = 0

roll("Rennek", 50)
H.blockAfter = nil

H.checkEqual("a silently refused whisper sends nothing", #H.sentMessages(), 0)
H.check("and is not reported as delivered",
	H.outputText():find("(to Rennek)", 1, true) == nil, H.outputText())
H.check("it says the line did not go",
	H.outputText():find("NOT sent to Rennek", 1, true) ~= nil, H.outputText())
H.check("and explains why once",
	H.outputText():find("refused a whispered effect", 1, true) ~= nil, H.outputText())
H.check("with the refusal recorded for /reh blocked",
	#REH.Diagnostics:GetBlocked() > 0)

Watcher.whisperWarned = false

-- The same again, this time as an outright Lua error rather than a block.
reset()
preset.channel.type = "PARTY"
H.setGroup({ { name = "Testchar", subgroup = 1 }, { name = "Rennek", subgroup = 1 } })
Watcher:SetMode("local")
H.sendError = "blocked by the client"

roll("Rennek", 50)
H.sendError = nil

H.checkEqual("a refused whisper sends nothing", #H.sentMessages(), 0)
H.check("the line still reaches the host",
	H.outputText():find("tug the line", 1, true) ~= nil, H.outputText())
H.check("and the refusal is explained once",
	H.outputText():find("refused a whispered effect", 1, true) ~= nil, H.outputText())
H.check("pointing at where the details are",
	H.outputText():find("/reh blocked", 1, true) ~= nil)

H.clearOutput()
H.sendError = "blocked by the client"
roll("Rennek", 50)
H.sendError = nil
H.check("and not repeated on every roll after it",
	H.outputText():find("refused a whispered effect", 1, true) == nil, H.outputText())

reset()

--------------------------------------------------------------------------------
H.section("Trying a roll before the event")
--------------------------------------------------------------------------------

reset()
preset = withEffects({
	effect({ trigger = "band", min = 1, max = 1, message = "{name}'s line snaps." }),
	effect({ trigger = "any", chance = 25, message = "A splash." }),
})
preset.channel.type = "PARTY"

local lines = Watcher:PreviewEffects(preset, 1, "Rennek-Argent Dawn")
H.checkEqual("a preview lists every effect that matches", #lines, 2)
H.checkEqual("with the placeholders filled in",
	lines[1].text, "Rennek-Argent Dawn's line snaps.")
H.checkEqual("and the chance carried through so it can be shown",
	lines[2].chance, 25)

H.clearOutput()
H.clearSent()
local count = Effects:Test(1)
H.checkEqual("the window's test reports both", count, 2)
H.checkEqual("and sends nothing at all", #H.sentMessages(), 0)
H.check("showing the line in the host's frame",
	H.outputText():find("line snaps", 1, true) ~= nil)
H.check("and saying which one is a gamble",
	H.outputText():find("25%", 1, true) ~= nil, H.outputText())

H.clearOutput()
H.checkEqual("a roll nothing answers reports nothing", Effects:Test(50), 1)

H.clearOutput()
Effects:Test(nil)
H.check("and a missing number is explained rather than ignored",
	H.outputText():find("number", 1, true) ~= nil, H.outputText())

--------------------------------------------------------------------------------
H.section("Describing one in words")
--------------------------------------------------------------------------------

H.checkEqual("a single-number band reads as one number",
	Effects:Describe(effect({ trigger = "band", min = 1, max = 1, delaySeconds = 0,
		message = "Snap." })),
	"On a roll of 1, to my channel: Snap.")

H.checkEqual("a range reads as a range",
	Effects:Describe(effect({ trigger = "band", min = 90, max = 100, delaySeconds = 0,
		message = "Big one." })),
	"On a roll of 90-100, to my channel: Big one.")

H.checkEqual("a verdict reads as a verdict",
	Effects:Describe(effect({ trigger = "verdict", verdict = "critfail", delaySeconds = 0,
		message = "Ouch." })),
	"On a critical failure, to my channel: Ouch.")

H.checkEqual("a chance and a delay are both mentioned",
	Effects:Describe(effect({ trigger = "any", chance = 25, delaySeconds = 2,
		target = "self", message = "Maybe." })),
	"On any roll, 25% of the time after 2s, to me only: Maybe.")

--------------------------------------------------------------------------------
H.section("The window builds")
--------------------------------------------------------------------------------

-- The widget mock raises on any method the client does not have, so reaching
-- the end of this proves the layout code calls nothing imaginary.
reset()
withEffects({
	effect({ trigger = "band", min = 1, max = 1, message = "{name}'s line snaps." }),
	effect({ trigger = "verdict", verdict = "critsuccess", message = "A monster!" }),
	effect({ trigger = "any", message = "A splash." }),
})

Effects:Show()
H.check("the window builds and shows", Effects:IsShown())

local frame = Effects:GetFrame()
H.check("the scroll child is tall enough to reach every row",
	frame.content:GetHeight() >= 3 * 56, frame.content:GetHeight())

-- Frames cannot be released in WoW, so a list that rebuilt itself on every edit
-- would leak a row per keystroke. Rows are pooled: refreshing with fewer
-- effects must reuse them, not make more.
local before = frame.content:GetHeight()
local list = DB:GetActivePreset().rollEffects
table.remove(list, 3)
Effects:Refresh()
H.check("removing an effect shortens the list", frame.content:GetHeight() < before)

Effects:Refresh()
Effects:Refresh()
H.check("and refreshing repeatedly does not grow it",
	frame.content:GetHeight() < before)

Effects:Hide()
H.check("it closes", Effects:IsShown() == false)

Effects:Toggle()
H.check("and toggles back open", Effects:IsShown())

--------------------------------------------------------------------------------
H.section("It opens where it can be seen")
--------------------------------------------------------------------------------

-- Reported from use: the window opened at the centre of the screen, which is
-- exactly where the main window is, so it arrived underneath it and the host
-- had to drag the main window aside to find it.
local Main = REH.UI.MainFrame
Main:Show()
Effects:Hide()
Effects:Show()

local window = Effects:GetFrame()
local point, relativeTo = window:GetPoint()

H.checkEqual("it opens beside the main window, not on top of it", point, "TOPLEFT")
H.checkEqual("anchored to the main window itself", relativeTo, Main:GetFrame())
H.check("and comes to the front", (window._raises or 0) > 0, window._raises)

-- Where the host drags it is where it belongs from then on.
window:ClearAllPoints()
window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -120)
H.fireScript(window, "OnDragStop")

local saved = DB:GetSettings().windowPoints.effects
H.check("dropping it remembers the position", saved ~= nil)
H.checkEqual("with the corner it was dropped by", saved.point, "TOPLEFT")
H.checkEqual("and the offset", saved.x, 40)

Effects:Hide()
Effects:Show()
local reopened, reopenedTo = window:GetPoint()
H.checkEqual("reopening puts it back there", reopened, "TOPLEFT")
H.check("free of the main window", reopenedTo ~= Main:GetFrame())

-- A point that survived a hand edit must not crash the restore.
DB:GetSettings().windowPoints.effects = { point = 42 }
DB:ValidateSettings(DB:GetSettings())
H.check("a nonsense saved point is dropped",
	DB:GetSettings().windowPoints.effects == nil)

Effects:Hide()
Effects:Show()
H.checkEqual("and it falls back to opening beside the main window",
	window:GetPoint(), "TOPLEFT")

-- With the main window closed there is nothing to sit beside.
Main:Hide()
DB:GetSettings().windowPoints.effects = nil
Effects:Hide()
Effects:Show()
H.checkEqual("with the main window closed it opens centred",
	window:GetPoint(), "CENTER")
Main:Show()

--------------------------------------------------------------------------------
H.section("The effects window can be dragged out")
--------------------------------------------------------------------------------

local effectsFrame = Effects:GetFrame()
Effects:Refresh()

local beforeWidth = effectsFrame:GetWidth()

effectsFrame:SetSize(1200, 800)
H.checkEqual("the window takes a dragged size", effectsFrame:GetWidth(), 1200)
H.check("which is wider than it was", effectsFrame:GetWidth() > beforeWidth)

Effects:SaveSize()
local savedEffects = DB:GetSettings().effectsSize
H.checkEqual("and remembers it", savedEffects.width, 1200)
H.checkEqual("in both directions", savedEffects.height, 800)

-- Adding an effect after a resize must build the new row at the window's
-- current width, not the width it was created at.
local list = DB:GetActivePreset().rollEffects
list[#list + 1] = REH.CreateRollEffect()
Effects:Refresh()
H.check("a row added after the drag is as wide as the window",
	effectsFrame:GetWidth() >= 1200)

effectsFrame:SetSize(640, 480)
H.check("and it goes back down again", effectsFrame:GetWidth() == 640)

Effects:Hide()

--------------------------------------------------------------------------------
H.section("Bad and hostile effects")
--------------------------------------------------------------------------------

local scratch = REH.CreateDefaultPreset("Scratch")
scratch.rolls.dieMax = 20
scratch.rollEffects = {
	{ trigger = "nonsense", verdict = "explode", target = "everywhere",
		min = 500, max = -3, chance = 900, delaySeconds = 9999, message = "Repaired." },
	{ trigger = "any", message = "" },
	{ trigger = "any" },
	"not a table",
	{ trigger = "any", message = "Kept.", enabled = "yes" },
}
DB:ValidatePreset(scratch)

H.checkEqual("only the usable effects survive", #scratch.rollEffects, 2)

local repaired = scratch.rollEffects[1]
H.checkEqual("an unknown trigger falls back to a band", repaired.trigger, "band")
H.checkEqual("an unknown verdict falls back", repaired.verdict, "critfail")
H.checkEqual("an unknown destination falls back", repaired.target, "channel")
H.checkEqual("a band past the die is clamped", repaired.max, 20)
H.checkEqual("and one below 1 is clamped up", repaired.min, 1)
H.checkEqual("an impossible chance is clamped", repaired.chance, 100)
H.checkEqual("an absurd delay is clamped", repaired.delaySeconds, 30)
H.checkEqual("a string enabled is coerced", scratch.rollEffects[2].enabled, true)

scratch.rolls.dieMax = 6
DB:ValidatePreset(scratch)
local past = false
for _, record in ipairs(scratch.rollEffects) do
	if record.min > 6 or record.max > 6 then
		past = true
	end
end
H.check("shrinking the die pulls the bands in with it", past == false)

local many = {}
for index = 1, REH.MAX_ROLL_EFFECTS + 10 do
	many[index] = { trigger = "any", message = "Effect " .. index }
end
scratch.rollEffects = many
DB:ValidatePreset(scratch)
H.check("the list is capped", #scratch.rollEffects <= REH.MAX_ROLL_EFFECTS,
	#scratch.rollEffects)

--------------------------------------------------------------------------------
H.section("They survive a reload and an export")
--------------------------------------------------------------------------------

reset()
withEffects({
	effect({ trigger = "band", min = 1, max = 1, message = "{name}'s line snaps." }),
	effect({ trigger = "verdict", verdict = "critsuccess", chance = 50,
		message = "A monster!" }),
})

REH = H.reload()
DB = REH.Database
Watcher = REH.RollWatcher
Effects = REH.UI.EffectsFrame

local reloaded = DB:GetActivePreset()
H.checkEqual("both effects are still there", #reloaded.rollEffects, 2)
H.checkEqual("with their triggers", reloaded.rollEffects[2].trigger, "verdict")
H.checkEqual("and their chances", reloaded.rollEffects[2].chance, 50)

local exported = REH.Transfer:Export(reloaded, "Fishing Night")
local imported = REH.Transfer:Import(exported)
H.checkEqual("they travel in an export string", #imported.rollEffects, 2)
H.checkEqual("with the text intact", imported.rollEffects[1].message, "{name}'s line snaps.")

--------------------------------------------------------------------------------
H.section("The command")
--------------------------------------------------------------------------------

H.clearOutput()
REH.Commands:Handle("effects list")
H.check("/reh effects list describes each one",
	H.outputText():find("line snaps", 1, true) ~= nil, H.outputText())
H.check("in plain English",
	H.outputText():find("On a roll of 1", 1, true) ~= nil)

H.clearOutput()
REH.Commands:Handle("effects test 1")
H.check("/reh effects test tries a roll",
	H.outputText():find("line snaps", 1, true) ~= nil, H.outputText())
H.checkEqual("without sending anything", #H.sentMessages(), 0)

REH.Commands:Handle("effects")
H.check("/reh effects opens the window", REH.UI.EffectsFrame:IsShown())
REH.Commands:Handle("effects")
H.check("and closes it again", REH.UI.EffectsFrame:IsShown() == false)

DB:GetActivePreset().rollEffects = {}
H.clearOutput()
REH.Commands:Handle("effects list")
H.check("an empty list says how to make one",
	H.outputText():find("/reh effects", 1, true) ~= nil, H.outputText())

H.checkNoLeakedGlobals(H.ALLOWED_GLOBALS)
H.finish()
