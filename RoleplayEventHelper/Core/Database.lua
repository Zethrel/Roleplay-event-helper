local ADDON_NAME, REH = ...

local L = REH.L

local Database = {}
REH.Database = Database

--------------------------------------------------------------------------------
-- Migrations
--------------------------------------------------------------------------------

-- migrations[n] upgrades a database at version n-1 to version n. They run in
-- order, so a player returning after several releases is walked forward one
-- step at a time. Never delete an entry: someone's saved variables are always
-- older than you expect.
Database.migrations = {
	-- [2] = function(db) ... end,
}

local function RunMigrations(db)
	local from = tonumber(db.dbVersion) or REH.DB_VERSION

	-- A database claiming a version newer than this build is from a downgrade.
	-- Leave it alone rather than mangling it with migrations that do not apply.
	if from > REH.DB_VERSION then
		return false, from
	end

	for version = from + 1, REH.DB_VERSION do
		local migrate = Database.migrations[version]
		if migrate then
			migrate(db)
		end
		db.dbVersion = version
	end

	return true, from
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

-- Saved variables are a plain Lua file the user can edit, and presets also
-- arrive from import strings written by strangers (M6). Everything below
-- assumes the incoming table is arbitrary and coerces it into shape rather than
-- trusting it. A malformed preset is repaired, never allowed to error later in
-- the formatter or the roll watcher.

local function ValidateLabelledList(list, valueKey, minimum, maximum, fallback, maxEntries)
	if type(list) ~= "table" then
		return {}
	end

	local cleaned = {}
	for _, entry in ipairs(list) do
		if type(entry) == "table" then
			local label = REH.CleanString(entry.label, REH.MAX_PRESET_NAME_LENGTH)
			if label ~= "" then
				cleaned[#cleaned + 1] = {
					label = label,
					[valueKey] = REH.ClampInteger(entry[valueKey], minimum, maximum, fallback),
				}
			end
		end
		if maxEntries and #cleaned >= maxEntries then
			break
		end
	end

	return cleaned
end

local function ValidateStringList(list, maxEntries)
	if type(list) ~= "table" then
		return {}
	end

	local cleaned = {}
	for _, entry in ipairs(list) do
		local text = REH.CleanString(entry, REH.MAX_RULE_LINE_LENGTH)
		if text ~= "" then
			cleaned[#cleaned + 1] = text
			if maxEntries and #cleaned >= maxEntries then
				break
			end
		end
	end

	return cleaned
end

--- Coerce account settings into a valid shape in place.
function Database:ValidateSettings(settings)
	-- The send delay paces the announcement queue. Too low and the client
	-- drops messages; too high and the host holds the channel for a minute.
	settings.sendDelay = REH.ClampNumber(settings.sendDelay, 0.3, 5.0, 0.7)

	if settings.sendMode ~= "paced" and settings.sendMode ~= "burst"
		and settings.sendMode ~= "auto" then
		settings.sendMode = "auto"
	end
	settings.useSeparators = REH.ToBoolean(settings.useSeparators, false)
	settings.mergeLines = REH.ToBoolean(settings.mergeLines, true)
	settings.debug = REH.ToBoolean(settings.debug, false)

	return settings
end

--- Coerce a preset into a valid shape in place. Returns the preset.
function Database:ValidatePreset(preset)
	preset = REH.ApplyDefaults(preset, REH.PRESET_TEMPLATE)

	-- Header
	local header = preset.header
	header.eventName = REH.CleanString(header.eventName, 60, "My Roleplay Event")
	header.hostName = REH.CleanString(header.hostName, 60)
	header.description = REH.CleanString(header.description, REH.MAX_RULE_LINE_LENGTH)
	header.showTimestamp = REH.ToBoolean(header.showTimestamp, false)

	-- Rolls. dieMax is settled first because the thresholds are clamped to it.
	local rolls = preset.rolls
	rolls.dieMax = REH.ClampInteger(rolls.dieMax, 2, 1000000, 100)
	rolls.successThreshold = REH.ClampInteger(rolls.successThreshold, 1, rolls.dieMax, 10)
	rolls.rollsPerTurn = REH.ClampInteger(rolls.rollsPerTurn, 1, 20, 1)
	rolls.successText = REH.CleanString(rolls.successText, 24, "SUCCESS")
	rolls.failText = REH.CleanString(rolls.failText, 24, "FAILURE")
	rolls.useCritical = REH.ToBoolean(rolls.useCritical, true)
	rolls.critSuccessAt = REH.ClampInteger(rolls.critSuccessAt, 1, rolls.dieMax, rolls.dieMax)
	rolls.critFailAt = REH.ClampInteger(rolls.critFailAt, 1, rolls.dieMax, 1)

	if not REH.IsValidEnum(REH.TIE_BREAKS, rolls.tieBreak) then
		rolls.tieBreak = "reroll"
	end

	-- A critical-failure band at or above the critical-success band would make
	-- every roll ambiguous. Rather than guess which the host meant, disable
	-- criticals and let them set it again deliberately.
	if rolls.useCritical and rolls.critFailAt >= rolls.critSuccessAt then
		rolls.useCritical = false
	end

	-- Health
	local health = preset.health
	health.rows = ValidateLabelledList(health.rows, "hp", 0, 10000, 10, 20)
	health.modifiers = ValidateLabelledList(health.modifiers, "bonus", -10000, 10000, 0, 20)
	health.note = REH.CleanString(health.note, REH.MAX_RULE_LINE_LENGTH)
	health.autoDetectArmor = REH.ToBoolean(health.autoDetectArmor, true)

	-- Damage
	local damage = preset.damage
	damage.perHit = REH.ClampInteger(damage.perHit, 0, 10000, 1)
	damage.onCrit = REH.ClampInteger(damage.onCrit, 0, 10000, 2)
	damage.healingAllowed = REH.ToBoolean(damage.healingAllowed, false)
	damage.healPerSuccess = REH.ClampInteger(damage.healPerSuccess, 0, 10000, 1)
	damage.healsPerEvent = REH.ClampInteger(damage.healsPerEvent, 0, 1000, 2)

	if not REH.IsValidEnum(REH.DEATH_RULES, damage.deathRule) then
		damage.deathRule = "out"
	end

	-- Turns
	local turns = preset.turns
	turns.turnTimeSeconds = REH.ClampInteger(turns.turnTimeSeconds, 0, 3600, 60)
	turns.note = REH.CleanString(turns.note, REH.MAX_RULE_LINE_LENGTH)

	if not REH.IsValidEnum(REH.INITIATIVE_MODES, turns.mode) then
		turns.mode = "initiative"
	end

	-- Free-text rule lists
	preset.custom = ValidateStringList(preset.custom, REH.MAX_CUSTOM_RULES)
	preset.etiquette = ValidateStringList(preset.etiquette, REH.MAX_CUSTOM_RULES)

	-- Roll filter
	local filter = preset.rollFilter
	if not REH.IsValidEnum(REH.ROLL_FILTER_MODES, filter.mode) then
		filter.mode = "group"
	end
	filter.matchRangeOnly = REH.ToBoolean(filter.matchRangeOnly, true)

	-- Subgroup numbers are dropped when out of range rather than clamped.
	-- Clamping 99 to 8 would silently add a subgroup the host never selected,
	-- and the watcher would then adjudicate spectators they meant to exclude.
	-- Erring toward tracking fewer people is the safe direction here.
	local subgroups, seenSubgroup = {}, {}
	if type(filter.subgroups) == "table" then
		for _, value in ipairs(filter.subgroups) do
			local number = tonumber(value)
			if number then
				number = math.floor(number + 0.5)
				if number >= 1 and number <= 8 and not seenSubgroup[number] then
					seenSubgroup[number] = true
					subgroups[#subgroups + 1] = number
				end
			end
		end
		table.sort(subgroups)
	end
	filter.subgroups = subgroups
	filter.roster = ValidateStringList(filter.roster, 200)

	-- Modules. Rebuild the order so it always contains every known module
	-- exactly once, preserving whatever order the host arranged.
	local order, seen = {}, {}
	if type(preset.moduleOrder) == "table" then
		for _, key in ipairs(preset.moduleOrder) do
			if REH.IsValidEnum(REH.MODULE_KEYS, key) and not seen[key] then
				seen[key] = true
				order[#order + 1] = key
			end
		end
	end
	for _, key in ipairs(REH.MODULE_KEYS) do
		if not seen[key] then
			order[#order + 1] = key
		end
	end
	preset.moduleOrder = order

	local enabled = {}
	for _, key in ipairs(REH.MODULE_KEYS) do
		enabled[key] = REH.ToBoolean(preset.moduleEnabled and preset.moduleEnabled[key], true)
	end
	preset.moduleEnabled = enabled

	if not REH.IsValidEnum(REH.ANNOUNCE_STYLES, preset.announceStyle) then
		preset.announceStyle = "full"
	end

	-- Formatting. The prefix is capped short and stripped of pipes: it is
	-- repeated on every line, and a stray colour escape there would bleed
	-- through the whole announcement.
	local formatting = preset.formatting
	formatting.linePrefix = REH.CleanString(formatting.linePrefix, 20):gsub("|", "")
	formatting.numberCustomRules = REH.ToBoolean(formatting.numberCustomRules, true)

	-- Channel. An unrecognised type falls back to PREVIEW, which cannot speak.
	local channel = preset.channel
	if not REH.IsValidEnum(REH.CHANNEL_TYPES, channel.type) then
		channel.type = "PREVIEW"
	end
	channel.target = REH.CleanString(channel.target, 64)

	return preset
end

--------------------------------------------------------------------------------
-- Preset names
--------------------------------------------------------------------------------

--- Returns cleanedName, or nil plus a reason.
function Database:ValidateName(name)
	local cleaned = REH.CleanString(name, REH.MAX_PRESET_NAME_LENGTH)

	if cleaned == "" then
		return nil, L["A preset name cannot be empty."]
	end

	-- Colour escapes and hyperlinks in a name would corrupt every list and
	-- announcement the name appears in.
	if cleaned:find("|", 1, true) then
		return nil, L["A preset name cannot contain the | character."]
	end

	return cleaned
end

--- Existing preset name matching case-insensitively, or nil.
function Database:FindName(name)
	local cleaned = REH.CleanString(name, REH.MAX_PRESET_NAME_LENGTH)
	if cleaned == "" then
		return nil
	end

	local presets = self:GetPresets()
	if presets[cleaned] then
		return cleaned
	end

	local lowered = cleaned:lower()
	for existing in pairs(presets) do
		if existing:lower() == lowered then
			return existing
		end
	end

	return nil
end

--------------------------------------------------------------------------------
-- Accessors
--------------------------------------------------------------------------------

function Database:GetDB()
	return RoleplayEventHelperDB
end

function Database:GetSettings()
	return RoleplayEventHelperDB.settings
end

function Database:GetPresets()
	return RoleplayEventHelperDB.presets
end

function Database:GetPresetNames()
	return REH.SortedKeys(RoleplayEventHelperDB.presets)
end

function Database:CountPresets()
	return REH.CountKeys(RoleplayEventHelperDB.presets)
end

function Database:GetPreset(name)
	local existing = self:FindName(name)
	if not existing then
		return nil
	end
	return RoleplayEventHelperDB.presets[existing], existing
end

--- The active preset, guaranteed non-nil once the database is initialised.
function Database:GetActivePreset()
	local db = RoleplayEventHelperDB
	local preset = db.activePreset and db.presets[db.activePreset]

	if not preset then
		-- The active pointer went stale (hand-edited file, or a preset deleted
		-- by an older build). Fall back to any preset rather than returning nil
		-- to every caller downstream.
		local names = self:GetPresetNames()
		if names[1] then
			db.activePreset = names[1]
			preset = db.presets[db.activePreset]
		else
			db.activePreset = REH.DEFAULT_PRESET_NAME
			preset = REH.CreateDefaultPreset(REH.DEFAULT_PRESET_NAME)
			db.presets[db.activePreset] = preset
		end
	end

	return preset, db.activePreset
end

function Database:SetActivePreset(name)
	local existing = self:FindName(name)
	if not existing then
		return false, L["No preset named '%s'."]:format(tostring(name))
	end

	RoleplayEventHelperDB.activePreset = existing
	return true, existing
end

--------------------------------------------------------------------------------
-- Mutations
--------------------------------------------------------------------------------

function Database:CreatePreset(name)
	local cleaned, reason = self:ValidateName(name)
	if not cleaned then
		return nil, reason
	end

	if self:FindName(cleaned) then
		return nil, L["A preset named '%s' already exists."]:format(cleaned)
	end

	if self:CountPresets() >= REH.MAX_PRESETS then
		return nil, L["You already have the maximum of %d presets."]:format(REH.MAX_PRESETS)
	end

	local preset = REH.CreateDefaultPreset(cleaned)
	RoleplayEventHelperDB.presets[cleaned] = preset

	return preset, cleaned
end

function Database:CopyPreset(sourceName, newName)
	local source, resolvedSource = self:GetPreset(sourceName)
	if not source then
		return nil, L["No preset named '%s'."]:format(tostring(sourceName))
	end

	local cleaned, reason = self:ValidateName(newName)
	if not cleaned then
		return nil, reason
	end

	if self:FindName(cleaned) then
		return nil, L["A preset named '%s' already exists."]:format(cleaned)
	end

	if self:CountPresets() >= REH.MAX_PRESETS then
		return nil, L["You already have the maximum of %d presets."]:format(REH.MAX_PRESETS)
	end

	local copy = REH.DeepCopy(source)
	copy.header.eventName = cleaned
	RoleplayEventHelperDB.presets[cleaned] = copy

	return copy, cleaned, resolvedSource
end

function Database:RenamePreset(oldName, newName)
	local preset, resolvedOld = self:GetPreset(oldName)
	if not preset then
		return false, L["No preset named '%s'."]:format(tostring(oldName))
	end

	local cleaned, reason = self:ValidateName(newName)
	if not cleaned then
		return false, reason
	end

	local collision = self:FindName(cleaned)
	if collision and collision ~= resolvedOld then
		return false, L["A preset named '%s' already exists."]:format(cleaned)
	end

	local db = RoleplayEventHelperDB
	db.presets[resolvedOld] = nil
	db.presets[cleaned] = preset

	if db.activePreset == resolvedOld then
		db.activePreset = cleaned
	end

	return true, cleaned, resolvedOld
end

function Database:DeletePreset(name)
	local preset, resolved = self:GetPreset(name)
	if not preset then
		return false, L["No preset named '%s'."]:format(tostring(name))
	end

	local db = RoleplayEventHelperDB
	db.presets[resolved] = nil

	-- There is always at least one preset. Deleting the last one recreates the
	-- default rather than leaving the addon in a state with nothing to edit.
	if self:CountPresets() == 0 then
		db.presets[REH.DEFAULT_PRESET_NAME] = REH.CreateDefaultPreset(REH.DEFAULT_PRESET_NAME)
		db.activePreset = REH.DEFAULT_PRESET_NAME
	elseif db.activePreset == resolved then
		db.activePreset = self:GetPresetNames()[1]
	end

	return true, resolved
end

--- Restore a preset's contents to the defaults, keeping its name.
function Database:ResetPreset(name)
	local preset, resolved = self:GetPreset(name)
	if not preset then
		return false, L["No preset named '%s'."]:format(tostring(name))
	end

	RoleplayEventHelperDB.presets[resolved] = REH.CreateDefaultPreset(resolved)
	return true, resolved
end

--------------------------------------------------------------------------------
-- Initialisation
--------------------------------------------------------------------------------

function Database:Initialize()
	RoleplayEventHelperDB = RoleplayEventHelperDB or {}
	local db = RoleplayEventHelperDB

	local isFreshInstall = (db.dbVersion == nil)
	if isFreshInstall then
		db.dbVersion = REH.DB_VERSION
		db.firstInstalledVersion = REH.version
	end

	local migrated, fromVersion = RunMigrations(db)

	db.settings = REH.ApplyDefaults(db.settings, REH.DEFAULT_SETTINGS)
	self:ValidateSettings(db.settings)
	db.presets = type(db.presets) == "table" and db.presets or {}

	-- Repair every preset on load. Cheap at this scale, and it means nothing
	-- downstream has to defend against a malformed preset.
	for presetName, preset in pairs(db.presets) do
		if type(preset) ~= "table" then
			db.presets[presetName] = REH.CreateDefaultPreset(presetName)
		else
			db.presets[presetName] = self:ValidatePreset(preset)
		end
	end

	if REH.CountKeys(db.presets) == 0 then
		db.presets[REH.DEFAULT_PRESET_NAME] = REH.CreateDefaultPreset(REH.DEFAULT_PRESET_NAME)
		db.activePreset = REH.DEFAULT_PRESET_NAME
	end

	self:GetActivePreset() -- repairs a stale active pointer

	db.loadCount = (db.loadCount or 0) + 1
	db.lastVersion = REH.version

	REH.db = db
	REH.isFreshInstall = isFreshInstall

	if not migrated then
		REH.downgradedFrom = fromVersion
	end

	return db
end
