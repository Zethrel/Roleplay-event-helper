-- M1: defaults, preset CRUD, validation of untrusted saved data, the migration
-- scaffold, and the preset slash commands.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "Tests"
local H = dofile(here .. "/Harness.lua")

H.installStubs()
H.snapshotGlobals()

H.wipeSavedVariables()
local REH = H.login()
local DB = REH.Database

local function freshLogin()
	H.wipeSavedVariables()
	REH = H.login()
	DB = REH.Database
	return REH
end

--------------------------------------------------------------------------------
H.section("Default preset")
--------------------------------------------------------------------------------

local preset, name = DB:GetActivePreset()
H.check("a default preset exists", preset ~= nil)
H.checkEqual("named as expected", name, REH.DEFAULT_PRESET_NAME)
H.checkEqual("exactly one preset on a fresh install", DB:CountPresets(), 1)

H.checkEqual("die max is 100", preset.rolls.dieMax, 100)
H.checkEqual("success threshold is 10", preset.rolls.successThreshold, 10)
H.checkEqual("cloth health", preset.health.rows[1].hp, 10)
H.checkEqual("leather health", preset.health.rows[2].hp, 11)
H.checkEqual("mail health", preset.health.rows[3].hp, 12)
H.checkEqual("plate health", preset.health.rows[4].hp, 13)
H.checkEqual("shield bonus", preset.health.modifiers[1].bonus, 1)
H.checkEqual("host name taken from the player", preset.header.hostName, H.playerName)
H.checkEqual("announce target defaults to PREVIEW", preset.channel.type, "PREVIEW")
H.checkEqual("roll filter defaults to group", preset.rollFilter.mode, "group")
H.checkEqual("every module is listed in the order", #preset.moduleOrder, #REH.MODULE_KEYS)

--------------------------------------------------------------------------------
H.section("Creating presets")
--------------------------------------------------------------------------------

local created, createdName = DB:CreatePreset("Duel Ring")
H.check("created", created ~= nil)
H.checkEqual("name preserved", createdName, "Duel Ring")
H.checkEqual("preset count", DB:CountPresets(), 2)
H.checkEqual("event name seeded from the preset name", created.header.eventName, "Duel Ring")

local dupe, reason = DB:CreatePreset("duel ring")
H.check("rejects a case-insensitive duplicate", dupe == nil)
H.check("explains why", (reason or ""):find("already exists", 1, true) ~= nil, reason)

local trimmed, trimmedName = DB:CreatePreset("   Tavern Brawl   ")
H.check("accepts a name needing trimming", trimmed ~= nil)
H.checkEqual("name is trimmed", trimmedName, "Tavern Brawl")

local empty, emptyReason = DB:CreatePreset("    ")
H.check("rejects an empty name", empty == nil)
H.check("explains why", (emptyReason or ""):find("empty", 1, true) ~= nil, emptyReason)

local piped, pipeReason = DB:CreatePreset("Bad|cff00ff00Name")
H.check("rejects a name containing a colour escape", piped == nil)
H.check("explains why", (pipeReason or ""):find("|", 1, true) ~= nil, pipeReason)

local longName = string.rep("A", REH.MAX_PRESET_NAME_LENGTH + 20)
local _, longResult = DB:CreatePreset(longName)
H.checkEqual("an over-long name is truncated, not rejected",
	#longResult, REH.MAX_PRESET_NAME_LENGTH)
DB:DeletePreset(longResult)

--------------------------------------------------------------------------------
H.section("Copying is a deep copy")
--------------------------------------------------------------------------------

DB:SetActivePreset("Duel Ring")
local source = DB:GetPreset("Duel Ring")
source.rolls.successThreshold = 55
source.custom[1] = "No mounts in the ring."

local copy, copyName = DB:CopyPreset("Duel Ring", "Duel Ring Nights")
H.check("copy created", copy ~= nil)
H.checkEqual("copied the edited threshold", copy.rolls.successThreshold, 55)
H.checkEqual("copied the custom rule", copy.custom[1], "No mounts in the ring.")

copy.rolls.successThreshold = 90
copy.custom[1] = "Changed."
copy.health.rows[1].hp = 99
H.checkEqual("editing the copy leaves the source threshold alone",
	source.rolls.successThreshold, 55)
H.checkEqual("editing the copy leaves the source rule alone",
	source.custom[1], "No mounts in the ring.")
H.checkEqual("nested tables are independent too", source.health.rows[1].hp, 10)

H.check("cannot copy onto an existing name", (DB:CopyPreset("Duel Ring", "Tavern Brawl")) == nil)
DB:DeletePreset(copyName)

--------------------------------------------------------------------------------
H.section("Renaming and deleting")
--------------------------------------------------------------------------------

DB:SetActivePreset("Tavern Brawl")
local renamed = DB:RenamePreset("Tavern Brawl", "Tavern Night")
H.check("renamed", renamed == true)
H.check("old name is gone", DB:GetPreset("Tavern Brawl") == nil)
H.check("new name resolves", DB:GetPreset("Tavern Night") ~= nil)
local _, activeName = DB:GetActivePreset()
H.checkEqual("active pointer followed the rename", activeName, "Tavern Night")

H.check("renaming to an existing name is refused",
	(DB:RenamePreset("Tavern Night", "Duel Ring")) == false)
H.check("renaming to its own name in different case is allowed",
	(DB:RenamePreset("Tavern Night", "tavern night")) == true)
DB:RenamePreset("tavern night", "Tavern Night")

DB:DeletePreset("Tavern Night")
H.check("deleted", DB:GetPreset("Tavern Night") == nil)
local _, afterDelete = DB:GetActivePreset()
H.check("active moved to a surviving preset", DB:GetPreset(afterDelete) ~= nil)

freshLogin()
DB:DeletePreset(REH.DEFAULT_PRESET_NAME)
H.checkEqual("deleting the last preset recreates a default", DB:CountPresets(), 1)
local _, recreated = DB:GetActivePreset()
H.check("and leaves a valid active preset", DB:GetPreset(recreated) ~= nil)

--------------------------------------------------------------------------------
H.section("Resetting")
--------------------------------------------------------------------------------

freshLogin()
local target = DB:GetActivePreset()
target.rolls.successThreshold = 77
target.custom[1] = "Temporary rule."
DB:ResetPreset(REH.DEFAULT_PRESET_NAME)
local afterReset = DB:GetActivePreset()
H.checkEqual("threshold restored", afterReset.rolls.successThreshold, 10)
H.checkEqual("custom rules cleared", #afterReset.custom, 0)

--------------------------------------------------------------------------------
H.section("Validation of hand-edited saved data")
--------------------------------------------------------------------------------

freshLogin()

-- Everything below is what a corrupted SavedVariables file, or a preset from a
-- stranger's import string, could plausibly contain.
RoleplayEventHelperDB.presets["Broken"] = {
	header = { eventName = 12345, description = string.rep("x", 500) },
	rolls = {
		dieMax = "not a number",
		successThreshold = 9999,
		tieBreak = "nonsense",
		rollsPerTurn = -4,
		critSuccessAt = 5,
		critFailAt = 50,
		useCritical = true,
	},
	health = {
		rows = { { label = "Cloth", hp = "ten" }, { label = "", hp = 5 }, "garbage" },
		modifiers = "not a table",
	},
	damage = { perHit = -3, deathRule = "explode" },
	turns = { mode = "teleport", turnTimeSeconds = 99999 },
	custom = { "  Spaced rule.  ", "", 42, "Valid." },
	rollFilter = { mode = "invalid", subgroups = { 1, 99, "x", 3 } },
	moduleOrder = { "rolls", "rolls", "unknown", "header" },
	moduleEnabled = { header = "yes" },
	channel = { type = "NOT_A_CHANNEL", target = 99 },
}

H.reload()
local broken = DB:GetPreset("Broken")

H.checkEqual("non-string event name replaced", type(broken.header.eventName), "string")
H.check("over-long description truncated", #broken.header.description <= REH.MAX_RULE_LINE_LENGTH)
H.checkEqual("bad die max falls back to 100", broken.rolls.dieMax, 100)
H.checkEqual("threshold clamped to the die max", broken.rolls.successThreshold, 100)
H.checkEqual("rolls per turn clamped to at least 1", broken.rolls.rollsPerTurn, 1)
H.checkEqual("unknown tie-break replaced", broken.rolls.tieBreak, "reroll")
H.check("criticals disabled when the bands overlap", broken.rolls.useCritical == false)
H.checkEqual("non-numeric hp coerced", type(broken.health.rows[1].hp), "number")
H.checkEqual("unlabelled and malformed health rows dropped", #broken.health.rows, 1)
H.checkEqual("non-table modifiers replaced with a list", type(broken.health.modifiers), "table")
H.checkEqual("negative damage clamped", broken.damage.perHit, 0)
H.checkEqual("unknown death rule replaced", broken.damage.deathRule, "out")
H.checkEqual("unknown initiative mode replaced", broken.turns.mode, "initiative")
H.check("turn time clamped", broken.turns.turnTimeSeconds <= 3600)
H.checkEqual("custom rules keep only valid strings", #broken.custom, 2)
H.checkEqual("custom rules are trimmed", broken.custom[1], "Spaced rule.")
H.checkEqual("unknown filter mode replaced", broken.rollFilter.mode, "group")
H.checkEqual("out-of-range subgroups dropped", #broken.rollFilter.subgroups, 2)
H.checkEqual("module order deduplicated and completed",
	#broken.moduleOrder, #REH.MODULE_KEYS)
H.checkEqual("module order keeps the host's arrangement first", broken.moduleOrder[1], "rolls")
H.checkEqual("module enabled flags coerced to booleans",
	type(broken.moduleEnabled.header), "boolean")
H.checkEqual("unknown channel type falls back to PREVIEW", broken.channel.type, "PREVIEW")

RoleplayEventHelperDB.presets["Broken"] = "this is not a preset at all"
H.reload()
H.checkEqual("a non-table preset is rebuilt", type(DB:GetPreset("Broken")), "table")

--------------------------------------------------------------------------------
H.section("Deleted list entries stay deleted")
--------------------------------------------------------------------------------

-- The defaults merge fills in missing keys, which must not mean "helpfully put
-- back the health rows the host deliberately removed".
freshLogin()
local editable = DB:GetActivePreset()
editable.health.rows = {}
editable.health.modifiers = {}
H.reload()
local afterReloadPreset = DB:GetActivePreset()
H.checkEqual("emptied health rows stay empty", #afterReloadPreset.health.rows, 0)
H.checkEqual("emptied modifiers stay empty", #afterReloadPreset.health.modifiers, 0)

freshLogin()
local partial = DB:GetActivePreset()
partial.health.rows = { { label = "Cloth", hp = 10 } }
H.reload()
H.checkEqual("a shortened list is not topped back up",
	#DB:GetActivePreset().health.rows, 1)

freshLogin()
DB:GetActivePreset().health.rows = nil
H.reload()
H.checkEqual("a missing list is restored from defaults",
	#DB:GetActivePreset().health.rows, 4)

--------------------------------------------------------------------------------
H.section("Stale and future saved data")
--------------------------------------------------------------------------------

freshLogin()
RoleplayEventHelperDB.activePreset = "A Preset That Was Deleted"
H.reload()
local repaired, repairedName = DB:GetActivePreset()
H.check("a stale active pointer is repaired", repaired ~= nil)
H.check("and points at a real preset", DB:GetPreset(repairedName) ~= nil)

freshLogin()
RoleplayEventHelperDB.dbVersion = REH.DB_VERSION + 5
RoleplayEventHelperDB.presets["From The Future"] = REH.CreateDefaultPreset("From The Future")
H.clearOutput()
H.reload()
H.checkEqual("a newer database version is left alone",
	RoleplayEventHelperDB.dbVersion, REH.DB_VERSION + 5)
H.check("the future preset is not discarded", DB:GetPreset("From The Future") ~= nil)
H.check("and the host is told", H.outputText():find("newer version", 1, true) ~= nil,
	H.outputText())

--------------------------------------------------------------------------------
H.section("Preset persistence")
--------------------------------------------------------------------------------

freshLogin()
DB:CreatePreset("Arena Night")
local arena = DB:GetPreset("Arena Night")
arena.rolls.successThreshold = 42
arena.custom[1] = "No consumables between rounds."
DB:SetActivePreset("Arena Night")

H.reload()
local survived, survivedName = DB:GetActivePreset()
H.checkEqual("active preset survived the reload", survivedName, "Arena Night")
H.checkEqual("edited threshold survived", survived.rolls.successThreshold, 42)
H.checkEqual("custom rule survived", survived.custom[1], "No consumables between rounds.")
H.checkEqual("preset count survived", DB:CountPresets(), 2)

--------------------------------------------------------------------------------
H.section("Slash commands")
--------------------------------------------------------------------------------

freshLogin()

local out = H.runSlash("list")
H.check("/reh list shows the active preset", out:find("active", 1, true) ~= nil, out)

out = H.runSlash("new Gurubashi Arena")
H.check("/reh new creates a preset with spaces in the name",
	DB:GetPreset("Gurubashi Arena") ~= nil, out)
local _, nowActive = DB:GetActivePreset()
H.checkEqual("and makes it active", nowActive, "Gurubashi Arena")

out = H.runSlash("new Gurubashi Arena")
H.check("/reh new reports a duplicate", out:find("already exists", 1, true) ~= nil, out)

out = H.runSlash("show")
H.check("/reh show describes the rules", out:find("Health:", 1, true) ~= nil, out)
H.check("/reh show includes the roll rule", out:find("/roll 100", 1, true) ~= nil, out)

out = H.runSlash("use " .. REH.DEFAULT_PRESET_NAME)
H.check("/reh use switches preset", out:find("now", 1, true) ~= nil, out)

out = H.runSlash("use Nonexistent")
H.check("/reh use reports an unknown preset", out:find("No preset named", 1, true) ~= nil, out)

H.section("Destructive commands need confirming")

out = H.runSlash("delete Gurubashi Arena")
H.check("/reh delete asks first", out:find("confirm", 1, true) ~= nil, out)
H.check("and does not delete yet", DB:GetPreset("Gurubashi Arena") ~= nil)

out = H.runSlash("confirm")
H.check("/reh confirm carries it out", DB:GetPreset("Gurubashi Arena") == nil, out)

out = H.runSlash("confirm")
H.check("a second confirm does nothing", out:find("Nothing is waiting", 1, true) ~= nil, out)

DB:CreatePreset("Expiring")
H.runSlash("delete Expiring")
H.now = H.now + 120
out = H.runSlash("confirm")
H.check("an expired confirmation is refused", out:find("expired", 1, true) ~= nil, out)
H.check("and the preset survives", DB:GetPreset("Expiring") ~= nil)

H.runSlash("delete Expiring")
H.runSlash("list")
out = H.runSlash("confirm")
H.check("an unrelated command cancels the pending delete",
	out:find("Nothing is waiting", 1, true) ~= nil, out)
H.check("and the preset survives", DB:GetPreset("Expiring") ~= nil)

H.runSlash("use Expiring")
H.runSlash("reset")
H.check("/reh reset asks first too", DB:GetPreset("Expiring") ~= nil)

H.checkNoLeakedGlobals(H.ALLOWED_GLOBALS)

H.finish()
