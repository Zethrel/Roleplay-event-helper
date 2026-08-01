local ADDON_NAME, REH = ...

local Fields = {}
REH.Fields = Fields

-- The editor described as data rather than as widgets.
--
-- Every editable rule appears here once, with how to read it, how to write it,
-- and what its legal values are. The UI walks this table to build itself, which
-- keeps the layout code free of rule-specific knowledge and means the editing
-- behaviour can be tested without creating a single frame.

--------------------------------------------------------------------------------
-- List parsing
--------------------------------------------------------------------------------

-- List-shaped rules are edited as plain text, one entry per line. It is far
-- less code than a grid of dynamic row widgets, and it matches how a host
-- thinks about the rules: a list you can paste in and out.

--- "Cloth 10" or "Cloth = 10" -> { label = "Cloth", hp = 10 }
local function ParseValueLines(text, valueKey)
	local entries = {}

	for line in tostring(text or ""):gmatch("[^\r\n]+") do
		local label, value = line:match("^%s*(.-)%s*=?%s*([+-]?%d+)%s*$")

		if label and label ~= "" then
			entries[#entries + 1] = { label = label, [valueKey] = tonumber(value) }
		else
			-- A line with no number is still a label the host typed; keep it at
			-- zero rather than silently discarding their work.
			local bare = REH.Trim(line)
			if bare ~= "" then
				entries[#entries + 1] = { label = bare, [valueKey] = 0 }
			end
		end
	end

	return entries
end

local function SerializeValueLines(entries, valueKey, signed)
	local lines = {}

	for _, entry in ipairs(entries or {}) do
		if signed then
			lines[#lines + 1] = ("%s %+d"):format(entry.label, entry[valueKey] or 0)
		else
			lines[#lines + 1] = ("%s %d"):format(entry.label, entry[valueKey] or 0)
		end
	end

	return table.concat(lines, "\n")
end

local function ParseStringLines(text)
	local lines = {}

	for line in tostring(text or ""):gmatch("[^\r\n]+") do
		local trimmed = REH.Trim(line)
		if trimmed ~= "" then
			lines[#lines + 1] = trimmed
		end
	end

	return lines
end

local function SerializeStringLines(lines)
	return table.concat(lines or {}, "\n")
end

Fields.ParseValueLines = ParseValueLines
Fields.SerializeValueLines = SerializeValueLines
Fields.ParseStringLines = ParseStringLines
Fields.SerializeStringLines = SerializeStringLines

--------------------------------------------------------------------------------
-- Option lists
--------------------------------------------------------------------------------

local function OptionsFrom(keys, labels)
	local options = {}
	for _, key in ipairs(keys) do
		options[#options + 1] = { value = key, label = labels[key] or key }
	end
	return options
end

Fields.OptionsFrom = OptionsFrom

--------------------------------------------------------------------------------
-- The schema
--------------------------------------------------------------------------------

Fields.TABS = {
	{
		module = "header",
		title = "Event",
		fields = {
			{
				key = "eventName", label = "Event name", type = "text", maxLength = 60,
				tooltip = "The name announced at the top of your rules.",
				get = function(p) return p.header.eventName end,
				set = function(p, v) p.header.eventName = v end,
			},
			{
				key = "hostName", label = "Host name", type = "text", maxLength = 60,
				tooltip = "Shown as 'hosted by'. Leave empty to omit it.",
				get = function(p) return p.header.hostName end,
				set = function(p, v) p.header.hostName = v end,
			},
			{
				key = "description", label = "Description", type = "text", maxLength = 200,
				tooltip = "One line describing the event.",
				get = function(p) return p.header.description end,
				set = function(p, v) p.header.description = v end,
			},
			{
				key = "showTimestamp", label = "Include the time posted", type = "toggle",
				get = function(p) return p.header.showTimestamp end,
				set = function(p, v) p.header.showTimestamp = v end,
			},
		},
	},

	{
		module = "rolls",
		title = "Rolls",
		fields = {
			{
				key = "dieMax", label = "Roll up to", type = "number", min = 2, max = 1000000,
				tooltip = "Participants use /roll with this number.",
				get = function(p) return p.rolls.dieMax end,
				set = function(p, v) p.rolls.dieMax = v end,
			},
			{
				key = "successThreshold", label = "Success at or above", type = "number",
				min = 1, max = 1000000,
				tooltip = "Rolls at or above this succeed. Anything below fails.",
				get = function(p) return p.rolls.successThreshold end,
				set = function(p, v) p.rolls.successThreshold = v end,
			},
			{
				key = "successText", label = "Success word", type = "text", maxLength = 24,
				get = function(p) return p.rolls.successText end,
				set = function(p, v) p.rolls.successText = v end,
			},
			{
				key = "failText", label = "Failure word", type = "text", maxLength = 24,
				get = function(p) return p.rolls.failText end,
				set = function(p, v) p.rolls.failText = v end,
			},
			{
				key = "useCritical", label = "Use critical rolls", type = "toggle",
				get = function(p) return p.rolls.useCritical end,
				set = function(p, v) p.rolls.useCritical = v end,
			},
			{
				key = "critSuccessAt", label = "Critical success at", type = "number",
				min = 1, max = 1000000,
				get = function(p) return p.rolls.critSuccessAt end,
				set = function(p, v) p.rolls.critSuccessAt = v end,
			},
			{
				key = "critFailAt", label = "Critical failure at or below", type = "number",
				min = 1, max = 1000000,
				get = function(p) return p.rolls.critFailAt end,
				set = function(p, v) p.rolls.critFailAt = v end,
			},
			{
				key = "rollsPerTurn", label = "Rolls per turn", type = "number", min = 1, max = 20,
				get = function(p) return p.rolls.rollsPerTurn end,
				set = function(p, v) p.rolls.rollsPerTurn = v end,
			},
			{
				key = "tieBreak", label = "Ties", type = "select",
				options = function() return OptionsFrom(REH.TIE_BREAKS, REH.DISPLAY.tieBreakShort) end,
				get = function(p) return p.rolls.tieBreak end,
				set = function(p, v) p.rolls.tieBreak = v end,
			},
		},
	},

	{
		module = "health",
		title = "Health",
		fields = {
			{
				key = "rows", label = "Health by armor", type = "lines", height = 110,
				tooltip = "One per line, e.g. 'Cloth 10'. These are examples -- use whatever numbers your event runs on.",
				get = function(p) return SerializeValueLines(p.health.rows, "hp", false) end,
				set = function(p, v) p.health.rows = ParseValueLines(v, "hp") end,
			},
			{
				key = "modifiers", label = "Modifiers", type = "lines", height = 60,
				tooltip = "One per line, e.g. 'Shield equipped +1'.",
				get = function(p) return SerializeValueLines(p.health.modifiers, "bonus", true) end,
				set = function(p, v) p.health.modifiers = ParseValueLines(v, "bonus") end,
			},
			{
				key = "note", label = "Note", type = "text", maxLength = 200,
				get = function(p) return p.health.note end,
				set = function(p, v) p.health.note = v end,
			},
			{
				key = "autoDetectArmor", label = "Show my own armor type in this window",
				type = "toggle",
				tooltip = "Reads your own equipped armor only. Never inspects other players.",
				get = function(p) return p.health.autoDetectArmor end,
				set = function(p, v) p.health.autoDetectArmor = v end,
			},
		},
	},

	{
		module = "damage",
		title = "Damage",
		fields = {
			{
				key = "perHit", label = "Damage per hit", type = "number", min = 0, max = 10000,
				get = function(p) return p.damage.perHit end,
				set = function(p, v) p.damage.perHit = v end,
			},
			{
				key = "onCrit", label = "Damage on a critical", type = "number", min = 0, max = 10000,
				get = function(p) return p.damage.onCrit end,
				set = function(p, v) p.damage.onCrit = v end,
			},
			{
				key = "deathRule", label = "At 0 HP", type = "select",
				options = function() return OptionsFrom(REH.DEATH_RULES, REH.DISPLAY.deathRule) end,
				get = function(p) return p.damage.deathRule end,
				set = function(p, v) p.damage.deathRule = v end,
			},
			{
				key = "healingAllowed", label = "Allow healing", type = "toggle",
				get = function(p) return p.damage.healingAllowed end,
				set = function(p, v) p.damage.healingAllowed = v end,
			},
			{
				key = "healPerSuccess", label = "Healing per success", type = "number",
				min = 0, max = 10000,
				get = function(p) return p.damage.healPerSuccess end,
				set = function(p, v) p.damage.healPerSuccess = v end,
			},
			{
				key = "healsPerEvent", label = "Heals per event (0 = unlimited)", type = "number",
				min = 0, max = 1000,
				get = function(p) return p.damage.healsPerEvent end,
				set = function(p, v) p.damage.healsPerEvent = v end,
			},
		},
	},

	{
		module = "turns",
		title = "Turns",
		fields = {
			{
				key = "mode", label = "Turn order", type = "select",
				options = function() return OptionsFrom(REH.INITIATIVE_MODES, REH.DISPLAY.initiativeShort) end,
				get = function(p) return p.turns.mode end,
				set = function(p, v) p.turns.mode = v end,
			},
			{
				key = "turnTimeSeconds", label = "Seconds per turn (0 = no limit)",
				type = "number", min = 0, max = 3600,
				get = function(p) return p.turns.turnTimeSeconds end,
				set = function(p, v) p.turns.turnTimeSeconds = v end,
			},
			{
				key = "note", label = "Note", type = "text", maxLength = 200,
				get = function(p) return p.turns.note end,
				set = function(p, v) p.turns.note = v end,
			},
		},
	},

	{
		module = "custom",
		title = "Rules",
		fields = {
			{
				key = "custom", label = "Custom rules", type = "lines", height = 180,
				tooltip = "One rule per line. Announced as a numbered list.",
				get = function(p) return SerializeStringLines(p.custom) end,
				set = function(p, v) p.custom = ParseStringLines(v) end,
			},
			{
				key = "numberCustomRules", label = "Number them when announcing", type = "toggle",
				get = function(p) return p.formatting.numberCustomRules end,
				set = function(p, v) p.formatting.numberCustomRules = v end,
			},
		},
	},

	{
		module = "etiquette",
		title = "Etiquette",
		fields = {
			{
				key = "etiquette", label = "Etiquette and OOC", type = "lines", height = 180,
				tooltip = "One line each. Announced as written.",
				get = function(p) return SerializeStringLines(p.etiquette) end,
				set = function(p, v) p.etiquette = ParseStringLines(v) end,
			},
			{
				key = "linePrefix", label = "Prefix every line with", type = "text", maxLength = 20,
				tooltip = "Optional, e.g. [Event]. Makes the rules stand out in a busy channel.",
				get = function(p) return p.formatting.linePrefix end,
				set = function(p, v) p.formatting.linePrefix = v end,
			},
		},
	},
}

-- The watcher tab edits the preset's filter, not the armed state. Arming lives
-- on the main window's bottom bar, because it is a per-event action rather than
-- part of the rules.
Fields.TABS[#Fields.TABS + 1] = {
	module = "watcher",
	title = "Watcher",
	fields = {
		{
			key = "mode", label = "Track rolls from", type = "select",
			options = function() return OptionsFrom(REH.ROLL_FILTER_MODES, REH.DISPLAY.rollFilter) end,
			tooltip = "Group: everyone in your party or raid. Subgroups: only the raid subgroups you choose, so combatants can be separated from the audience.",
			get = function(p) return p.rollFilter.mode end,
			set = function(p, v) p.rollFilter.mode = v end,
		},
		{
			key = "subgroups", label = "Combatant subgroups", type = "text", maxLength = 40,
			tooltip = "Raid subgroup numbers, e.g. '1 2'. Put combatants in those groups and the audience elsewhere. Empty means the whole raid.",
			get = function(p) return table.concat(p.rollFilter.subgroups, " ") end,
			set = function(p, v)
				local chosen = {}
				for number in tostring(v or ""):gmatch("%d+") do
					chosen[#chosen + 1] = tonumber(number)
				end
				p.rollFilter.subgroups = chosen
			end,
		},
		{
			key = "matchRangeOnly", label = "Only count rolls matching the die size",
			type = "toggle",
			tooltip = "Ignores a /roll 20 for loot while your event runs on /roll 100.",
			get = function(p) return p.rollFilter.matchRangeOnly end,
			set = function(p, v) p.rollFilter.matchRangeOnly = v end,
		},
		{
			key = "announceRounds", label = "Announce each new round", type = "toggle",
			tooltip = "Sends a short line to your channel when you start a round, so everyone knows the next exchange has begun.",
			get = function(p) return p.rounds.announce end,
			set = function(p, v) p.rounds.announce = v end,
		},
		{
			key = "roundMessage", label = "Round message", type = "text", maxLength = 120,
			tooltip = "{round} is replaced with the round number.",
			get = function(p) return p.rounds.message end,
			set = function(p, v) p.rounds.message = v end,
		},
		{
			key = "roster", label = "Saved roster", type = "lines", height = 120,
			tooltip = "One name per line, used when tracking a saved roster. Seed it from your group with /reh roster import.",
			get = function(p) return SerializeStringLines(p.rollFilter.roster) end,
			set = function(p, v) p.rollFilter.roster = ParseStringLines(v) end,
		},
	},
}

-- Account-wide settings rather than per-preset rules. Marked with a scope so
-- the editor writes them to the settings table instead of the active preset.
Fields.TABS[#Fields.TABS + 1] = {
	module = "settings",
	title = "Options",
	scope = "settings",
	fields = {
		{
			key = "mergeLines", label = "Pack rules into fewer messages", type = "toggle",
			tooltip = "Combines adjacent rules from the same section into one message. Off sends one message per rule, which takes longer.",
			get = function(s) return s.mergeLines end,
			set = function(s, v) s.mergeLines = v end,
		},
		{
			key = "useSeparators", label = "Separator line between sections", type = "toggle",
			tooltip = "Each separator costs a whole chat message and a send delay.",
			get = function(s) return s.useSeparators end,
			set = function(s, v) s.useSeparators = v end,
		},
		{
			key = "sendDelay", label = "Seconds between messages", type = "decimal",
			min = 0.3, max = 5.0,
			tooltip = "Too low and the client drops messages; too high and you hold the channel for a long time. 0.7 is a good default.",
			get = function(s) return s.sendDelay end,
			set = function(s, v) s.sendDelay = v end,
		},
		{
			key = "minimapHide", label = "Hide the minimap button", type = "toggle",
			get = function(s) return s.minimapButton and s.minimapButton.hide end,
			set = function(s, v)
				s.minimapButton = s.minimapButton or {}
				s.minimapButton.hide = v
			end,
		},
	},
}

-- Every section that can be announced gets an include toggle as the first
-- thing on its tab. Plenty of events run without rolls or combat at all, and
-- the rules for those sections should be switched off rather than deleted, so
-- the same preset can be turned back on for the next duelling night.
--
-- Added in a loop rather than written into each tab so a new module cannot be
-- given an editor and quietly miss its toggle.
for _, tab in ipairs(Fields.TABS) do
	if REH.IsValidEnum(REH.MODULE_KEYS, tab.module) then
		local moduleKey = tab.module

		table.insert(tab.fields, 1, {
			key = "include",
			label = "Announce this section",
			type = "toggle",
			tooltip = "Off keeps the rules here but leaves them out of the announcement. Useful for events with no rolls or combat.",
			get = function(p) return p.moduleEnabled[moduleKey] end,
			set = function(p, v) p.moduleEnabled[moduleKey] = v end,
		})
	end
end

--- Suggested etiquette lines offered as one-click inserts.
Fields.ETIQUETTE_SUGGESTIONS = {
	"Keep emotes to two sentences so the round moves.",
	"OOC chat in double parentheses (( like this )).",
	"Disputes are settled by the host; please do not argue in character.",
	"If anything makes you uncomfortable, whisper the host.",
}

--------------------------------------------------------------------------------
-- Reading and writing
--------------------------------------------------------------------------------

function Fields:Get(preset, field)
	return field.get(preset)
end

--- Write a raw value from a widget into the preset.
---
--- Returns true on success, or false plus a reason. The preset is revalidated
--- after every write so cross-field rules hold immediately -- lowering the die
--- max below the success threshold pulls the threshold down with it rather than
--- leaving an impossible rule on screen.
--- What a tab edits: the account settings, or the active preset.
function Fields:GetTarget(tab)
	if tab and tab.scope == "settings" then
		return REH.Database:GetSettings()
	end
	return REH.Database:GetActivePreset()
end

function Fields:Set(target, field, rawValue, scope)
	local preset = target

	if field.type == "decimal" then
		local number = tonumber(rawValue)
		if not number then
			return false, ("'%s' needs a number."):format(field.label)
		end

		number = REH.ClampNumber(number, field.min, field.max, number)
		field.set(preset, number)

	elseif field.type == "number" then
		local number = tonumber(rawValue)
		if not number then
			return false, ("'%s' needs a number."):format(field.label)
		end

		number = math.floor(number + 0.5)

		if field.min and number < field.min then
			number = field.min
		end
		if field.max and number > field.max then
			number = field.max
		end

		field.set(preset, number)

	elseif field.type == "toggle" then
		field.set(preset, rawValue and true or false)

	elseif field.type == "select" then
		local allowed = false
		for _, option in ipairs(field.options()) do
			if option.value == rawValue then
				allowed = true
				break
			end
		end

		if not allowed then
			return false, ("'%s' is not a valid choice."):format(tostring(rawValue))
		end

		field.set(preset, rawValue)

	elseif field.type == "lines" then
		field.set(preset, rawValue)

	else
		field.set(preset, REH.CleanString(rawValue, field.maxLength))
	end

	-- Revalidate whatever was written, so cross-field rules hold immediately.
	if scope == "settings" then
		REH.Database:ValidateSettings(preset)
	else
		REH.Database:ValidatePreset(preset)
	end

	return true
end

--- All tabs, or only those whose module is enabled.
function Fields:GetTabs()
	return self.TABS
end

function Fields:FindTab(moduleKey)
	for _, tab in ipairs(self.TABS) do
		if tab.module == moduleKey then
			return tab
		end
	end
	return nil
end

function Fields:FindField(moduleKey, fieldKey)
	local tab = self:FindTab(moduleKey)
	if not tab then
		return nil
	end

	for _, field in ipairs(tab.fields) do
		if field.key == fieldKey then
			return field
		end
	end

	return nil
end
