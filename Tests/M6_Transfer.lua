-- M6: export and import strings.
--
-- Import is the only place the addon consumes data written by someone else, so
-- most of this is about what happens when the string is wrong: truncated,
-- mangled by a chat client, from a future version, or crafted to be awkward.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "Tests"
local H = dofile(here .. "/Harness.lua")

H.installStubs()
H.snapshotGlobals()
H.wipeSavedVariables()

local REH = H.login()
local DB = REH.Database
local Transfer = REH.Transfer

--------------------------------------------------------------------------------
H.section("The libraries loaded")
--------------------------------------------------------------------------------

H.check("LibStub is present", LibStub ~= nil)
local serialize, deflate = Transfer.GetLibraries()
H.check("LibSerialize is registered", serialize ~= nil)
H.check("LibDeflate is registered", deflate ~= nil)
H.check("so sharing is available", Transfer:IsAvailable())

--------------------------------------------------------------------------------
H.section("Round trip")
--------------------------------------------------------------------------------

local source = REH.CreateDefaultPreset("Gurubashi Arena")
source.header.description = "Free-for-all, last one standing wins the pot."
source.rolls.successThreshold = 25
source.rolls.dieMax = 50
source.rolls.successText = "HIT"
source.health.rows = { { label = "Cloth", hp = 8 }, { label = "Plate", hp = 14 } }
source.health.modifiers = { { label = "Shield equipped", bonus = 2 } }
source.custom = { "No mounts inside the ring.", "No consumables between rounds." }
source.etiquette = { "OOC in double parentheses." }
source.turns.turnTimeSeconds = 45
source.moduleEnabled.damage = false
source.rollFilter.mode = "subgroup"
source.rollFilter.subgroups = { 1, 2 }
source.channel.type = "CHANNEL"
source.channel.target = "MoonGuardRP"
DB:ValidatePreset(source)

local text, exportError = Transfer:Export(source, "Gurubashi Arena")
H.check("a preset exports", text ~= nil, exportError)
H.check("the string is tagged with the format version",
	tostring(text):sub(1, 5) == "REH1:", tostring(text):sub(1, 12))
H.check("and is short enough to paste into Discord", #text < 2000, #text)

local imported, name = Transfer:Import(text)
H.check("it imports back", imported ~= nil, name)
H.checkEqual("the name survives", name, "Gurubashi Arena")

H.checkEqual("the die max survives", imported.rolls.dieMax, 50)
H.checkEqual("the threshold survives", imported.rolls.successThreshold, 25)
H.checkEqual("custom success wording survives", imported.rolls.successText, "HIT")
H.checkEqual("health rows survive", #imported.health.rows, 2)
H.checkEqual("with their values", imported.health.rows[2].hp, 14)
H.checkEqual("modifiers survive", imported.health.modifiers[1].bonus, 2)
H.checkEqual("custom rules survive", #imported.custom, 2)
H.checkEqual("and their text", imported.custom[1], "No mounts inside the ring.")
H.checkEqual("etiquette survives", #imported.etiquette, 1)
H.checkEqual("turn timer survives", imported.turns.turnTimeSeconds, 45)
H.checkEqual("a disabled module stays disabled", imported.moduleEnabled.damage, false)
H.checkEqual("the roll filter survives", imported.rollFilter.mode, "subgroup")
H.checkEqual("with its subgroups", table.concat(imported.rollFilter.subgroups, ","), "1,2")
H.checkEqual("the channel survives", imported.channel.type, "CHANNEL")
H.checkEqual("with its target", imported.channel.target, "MoonGuardRP")
H.checkEqual("the description survives",
	imported.header.description, "Free-for-all, last one standing wins the pot.")

-- The whole point is that the other host sees the same rules.
local sourceMessages = REH.Formatter:BuildMessages(source)
local importedMessages = REH.Formatter:BuildMessages(imported)
H.checkEqual("the imported preset announces identically",
	table.concat(importedMessages, "\n"), table.concat(sourceMessages, "\n"))

--------------------------------------------------------------------------------
H.section("Strings survive being pasted around")
--------------------------------------------------------------------------------

-- Chat clients and pastebins wrap long strings and add indentation.
local wrapped = text:sub(1, 40) .. "\n" .. text:sub(41, 90) .. "\n   " .. text:sub(91)
local fromWrapped = Transfer:Import(wrapped)
H.check("a string broken across lines still imports", fromWrapped ~= nil)

local padded = "   " .. text .. "  \n"
H.check("leading and trailing whitespace is tolerated", Transfer:Import(padded) ~= nil)

local spaced = text:gsub("(....)", "%1 ")
H.check("even spaces inside the string are tolerated", Transfer:Import(spaced) ~= nil)

--------------------------------------------------------------------------------
H.section("Bad strings are refused, with an explanation")
--------------------------------------------------------------------------------

local function refuses(label, input, expectedWord)
	local preset, reason = Transfer:Import(input)
	local refused = (preset == nil)
	H.check(label, refused, "was accepted")

	if refused and expectedWord then
		H.check("  ...and explains why",
			tostring(reason):lower():find(expectedWord, 1, true) ~= nil, reason)
	end
end

refuses("an empty string is refused", "", "paste")
refuses("plain prose is refused", "hello, here are my event rules", "reh1")
refuses("a string with no prefix is refused", text:sub(6), "reh1")
refuses("a wrong prefix is refused", "XYZ1:" .. text:sub(6), "reh1")
refuses("a future format version is refused", "REH9:" .. text:sub(6), "newer version")
refuses("a truncated string is refused", text:sub(1, #text - 20), "damaged")
refuses("a corrupted body is refused", text:sub(1, 20) .. "!!!!!" .. text:sub(26), "damaged")
refuses("an over-long string is refused", "REH1:" .. string.rep("a", 50000), "too long")

local preset = Transfer:Import(nil)
H.check("nil is handled", preset == nil)

--------------------------------------------------------------------------------
H.section("An imported preset is not trusted")
--------------------------------------------------------------------------------

-- A preset arriving from a stranger goes through the same validation as a
-- hand-edited saved-variables file. This builds a deliberately awkward payload
-- and packs it the same way an export would.
local hostile = {
	v = 1,
	name = "Hostile|cffff0000Name",
	preset = {
		header = { eventName = string.rep("x", 5000) },
		rolls = {
			dieMax = -50,
			successThreshold = 99999,
			tieBreak = "explode",
			critSuccessAt = 2,
			critFailAt = 90,
			useCritical = true,
		},
		health = { rows = "not a table" },
		damage = { deathRule = "vaporise", perHit = -20 },
		turns = { mode = "teleport" },
		custom = { "fine", 12345, string.rep("y", 900) },
		rollFilter = { mode = "wat", subgroups = { 77 } },
		moduleEnabled = { header = "yes" },
		channel = { type = "SPY_CHANNEL", target = "x" },
		formatting = { linePrefix = "|cff00ff00[x]" },
	},
}

local packed = "REH1:" .. deflate:EncodeForPrint(
	deflate:CompressDeflate(serialize:Serialize(hostile), { level = 9 }))

local cleaned, cleanedName = Transfer:Import(packed)
H.check("the hostile payload still imports", cleaned ~= nil, cleanedName)
H.check("a pipe in the name is not carried into preset names",
	not tostring(cleanedName):find("|", 1, true) or
		DB:ValidateName(cleanedName) == nil, cleanedName)
H.check("an absurd event name is truncated", #cleaned.header.eventName <= 60)
-- Clamped to the smallest legal die rather than reset to the default: for a
-- numeric field, pulling a nonsense value to the nearest legal one cannot
-- broaden anything, and the host sees an obviously odd number to correct.
H.checkEqual("a negative die max is clamped to the smallest legal die",
	cleaned.rolls.dieMax, 2)
H.check("the threshold is inside the die range",
	cleaned.rolls.successThreshold <= cleaned.rolls.dieMax)
H.checkEqual("an unknown tie-break is replaced", cleaned.rolls.tieBreak, "reroll")
H.checkEqual("overlapping critical bands disable criticals", cleaned.rolls.useCritical, false)
H.checkEqual("a non-table health list becomes a list", type(cleaned.health.rows), "table")
H.checkEqual("an unknown death rule is replaced", cleaned.damage.deathRule, "out")
H.checkEqual("negative damage is clamped", cleaned.damage.perHit, 0)
H.checkEqual("an unknown turn mode is replaced", cleaned.turns.mode, "initiative")
H.checkEqual("non-string rules are dropped", #cleaned.custom, 2)
H.check("over-long rules are truncated", #cleaned.custom[2] <= REH.MAX_RULE_LINE_LENGTH)
H.checkEqual("an unknown filter mode is replaced", cleaned.rollFilter.mode, "group")
H.checkEqual("an out-of-range subgroup is dropped", #cleaned.rollFilter.subgroups, 0)
H.checkEqual("module flags become booleans", type(cleaned.moduleEnabled.header), "boolean")
H.checkEqual("an unknown channel falls back to preview", cleaned.channel.type, "PREVIEW")
H.check("a colour escape in the prefix is stripped",
	cleaned.formatting.linePrefix:find("|", 1, true) == nil)

-- The real proof: a hostile preset must still format and announce safely.
local hostileMessages = REH.Formatter:BuildMessages(cleaned)
local allWithinLimit = true
for _, message in ipairs(hostileMessages) do
	if #message > REH.MAX_CHAT_BYTES then
		allWithinLimit = false
	end
end
H.check("and it still produces sendable messages", allWithinLimit)

--------------------------------------------------------------------------------
H.section("Saving an import")
--------------------------------------------------------------------------------

H.wipeSavedVariables()
REH = H.login()
DB = REH.Database
Transfer = REH.Transfer

local before = DB:CountPresets()
local fresh, freshName = Transfer:Import(text)
local stored = Transfer:Commit(fresh, freshName, "new")
H.checkEqual("importing adds a preset", DB:CountPresets(), before + 1)
H.checkEqual("under its own name", stored, "Gurubashi Arena")
local _, activeName = DB:GetActivePreset()
H.checkEqual("and makes it active", activeName, "Gurubashi Arena")

-- A collision must never silently replace the preset someone spent an evening
-- building, so "keep both" is a real option rather than the only choice being
-- overwrite.
local second, secondName = Transfer:Import(text)
local kept = Transfer:Commit(second, secondName, "new")
H.check("importing the same name again keeps both", kept ~= "Gurubashi Arena", kept)
H.check("with a distinguishable name", tostring(kept):find("(2)", 1, true) ~= nil, kept)
H.checkEqual("so nothing was lost", DB:CountPresets(), before + 2)

DB:GetPreset("Gurubashi Arena").rolls.dieMax = 7
local third, thirdName = Transfer:Import(text)
local overwritten = Transfer:Commit(third, thirdName, "overwrite")
H.checkEqual("overwriting replaces in place", overwritten, "Gurubashi Arena")
H.checkEqual("with the imported rules", DB:GetPreset("Gurubashi Arena").rolls.dieMax, 50)
H.checkEqual("and adds no preset", DB:CountPresets(), before + 2)

H.check("the description names what will be imported",
	Transfer:Describe(third, thirdName):find("Gurubashi Arena", 1, true) ~= nil)
H.check("including the roll rule",
	Transfer:Describe(third, thirdName):find("/roll 50", 1, true) ~= nil)

--------------------------------------------------------------------------------
H.section("Presets survive a reload after import")
--------------------------------------------------------------------------------

REH = H.reload()
DB = REH.Database
Transfer = REH.Transfer
H.check("an imported preset is still there", DB:GetPreset("Gurubashi Arena") ~= nil)
H.checkEqual("with its rules intact",
	DB:GetPreset("Gurubashi Arena").rolls.dieMax, 50)

--------------------------------------------------------------------------------
H.section("The transfer window")
--------------------------------------------------------------------------------

local Window = REH.UI.TransferFrame
local preset2, name2 = DB:GetActivePreset()

local shown = Window:ShowExport(preset2, name2)
H.check("the export window opens", Window:IsShown())
H.check("with the string in the box",
	Window:GetFrame().box.editBox:GetText():sub(1, 5) == "REH1:")
H.checkEqual("and the string matches the module's output",
	shown, Transfer:Export(preset2, name2))

Window:ShowImport()
H.check("the import window opens", Window:IsShown())
H.checkEqual("with an empty box", Window:GetFrame().box.editBox:GetText(), "")

Window:GetFrame().box.editBox:SetText("this is not a preset")
Window:GetFrame().importButton:Click()
H.check("a bad paste is reported in the window",
	Window:GetFrame().statusText:GetText():find("REH1", 1, true) ~= nil,
	Window:GetFrame().statusText:GetText())
H.check("and nothing is imported", Window:GetPending() == nil)
H.check("the window stays open to try again", Window:IsShown())

local countBefore = DB:CountPresets()
Window:ShowImport()
Window:GetFrame().box.editBox:SetText(text)
Window:GetFrame().importButton:Click()
H.check("a colliding import offers to overwrite",
	Window:GetFrame().overwriteButton:IsShown())
H.check("or to keep both", Window:GetFrame().keepBothButton:IsShown())
H.checkEqual("and imports nothing until you choose", DB:CountPresets(), countBefore)

Window:GetFrame().keepBothButton:Click()
H.checkEqual("choosing keep both imports it", DB:CountPresets(), countBefore + 1)
H.check("and closes the window", Window:IsShown() == false)

DB:DeletePreset("Gurubashi Arena")
countBefore = DB:CountPresets()
Window:ShowImport()
Window:GetFrame().box.editBox:SetText(text)
Window:GetFrame().importButton:Click()
H.checkEqual("a non-colliding import goes straight through",
	DB:CountPresets(), countBefore + 1)
H.check("closing the window behind it", Window:IsShown() == false)

--------------------------------------------------------------------------------
H.section("Commands")
--------------------------------------------------------------------------------

local out = H.runSlash("export")
H.check("/reh export opens the window", Window:IsShown())
Window:Hide()

out = H.runSlash("export Nonexistent")
H.check("/reh export names an unknown preset",
	out:find("No preset named", 1, true) ~= nil, out)

out = H.runSlash("import")
H.check("/reh import with no argument opens the window", Window:IsShown())
Window:Hide()

out = H.runSlash("import garbage-not-a-preset")
H.check("/reh import reports a bad string", out:find("REH1", 1, true) ~= nil, out)

countBefore = DB:CountPresets()
H.runSlash("import " .. text)
H.checkEqual("/reh import with a valid string imports it",
	DB:CountPresets(), countBefore + 1)

H.checkNoLeakedGlobals(H.ALLOWED_GLOBALS)

H.finish()
