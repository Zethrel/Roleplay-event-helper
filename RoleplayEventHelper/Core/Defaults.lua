local ADDON_NAME, REH = ...

-- Bump when the saved layout changes in a way that needs a migration step, and
-- add the matching entry to REH.Database.migrations.
REH.DB_VERSION = 1

REH.MAX_PRESET_NAME_LENGTH = 32
REH.MAX_PRESETS = 50
REH.MAX_RULE_LINE_LENGTH = 200
REH.MAX_CUSTOM_RULES = 30

REH.DEFAULT_PRESET_NAME = "Default Event"

--------------------------------------------------------------------------------
-- Enumerations
--------------------------------------------------------------------------------

-- Stored values are these lowercase keys; the display strings are looked up
-- separately so a saved preset never depends on the player's language.

REH.TIE_BREAKS = { "reroll", "armor", "attacker", "defender", "host" }
REH.DEATH_RULES = { "out", "downed", "host" }
REH.INITIATIVE_MODES = { "initiative", "host", "roundrobin", "freeform" }
REH.ROLL_FILTER_MODES = { "group", "subgroup", "roster", "everyone" }
REH.ANNOUNCE_STYLES = { "full", "summary" }
REH.CHANNEL_TYPES = {
	"PREVIEW", "SAY", "YELL", "EMOTE", "PARTY", "RAID", "RAID_WARNING",
	"INSTANCE_CHAT", "GUILD", "OFFICER", "CHANNEL", "WHISPER",
}

REH.MODULE_KEYS = { "header", "rolls", "health", "damage", "turns", "custom", "etiquette" }

--- Membership test for the enumerations above.
function REH.IsValidEnum(list, value)
	if type(value) ~= "string" then
		return false
	end
	for _, candidate in ipairs(list) do
		if candidate == value then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Account settings
--------------------------------------------------------------------------------

REH.DEFAULT_SETTINGS = {
	minimapButton = { hide = false, minimapPos = 220 },
	framePoint = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
	sendDelay = 0.7,
	useColors = true,
	useSeparators = true,
	debug = false,
}

--------------------------------------------------------------------------------
-- The default preset
--------------------------------------------------------------------------------

-- These numbers are a worked example, not a rule set. Every one of them is
-- meant to be edited; they exist so a new host has something coherent to
-- announce and adjust rather than an empty form.

local PRESET_TEMPLATE = {
	header = {
		eventName = "My Roleplay Event",
		hostName = "",           -- filled with the player's name on creation
		description = "",
		showTimestamp = false,
	},

	rolls = {
		dieMax = 100,
		successThreshold = 10,   -- 1-9 fails, 10-100 succeeds
		successText = "SUCCESS",
		failText = "FAILURE",
		useCritical = true,
		critSuccessAt = 100,
		critFailAt = 1,
		tieBreak = "reroll",
		rollsPerTurn = 1,
	},

	health = {
		rows = {
			{ label = "Cloth",   hp = 10 },
			{ label = "Leather", hp = 11 },
			{ label = "Mail",    hp = 12 },
			{ label = "Plate",   hp = 13 },
		},
		modifiers = {
			{ label = "Shield equipped", bonus = 1 },
		},
		note = "",
		autoDetectArmor = true,
	},

	damage = {
		perHit = 1,
		onCrit = 2,
		healingAllowed = false,
		healPerSuccess = 1,
		healsPerEvent = 2,       -- 0 means unlimited
		deathRule = "out",
	},

	turns = {
		mode = "initiative",
		turnTimeSeconds = 60,    -- 0 means no limit
		note = "",
	},

	custom = {},
	etiquette = {},

	rollFilter = {
		mode = "group",
		subgroups = {},          -- raid subgroup numbers when mode == "subgroup"
		roster = {},             -- explicit names when mode == "roster"
		matchRangeOnly = true,   -- ignore rolls whose range is not 1..dieMax
	},

	moduleOrder = { "header", "rolls", "health", "damage", "turns", "custom", "etiquette" },
	moduleEnabled = {
		header = true,
		rolls = true,
		health = true,
		damage = true,
		turns = true,
		custom = true,
		etiquette = true,
	},

	announceStyle = "full",

	-- Deliberately PREVIEW on a fresh preset: the first press of Announce can
	-- never spam a channel by accident. The host chooses a real target once,
	-- and it is then remembered per preset.
	channel = { type = "PREVIEW", target = "" },
}

--- A fresh, independent copy of the default preset.
function REH.CreateDefaultPreset(eventName)
	local preset = REH.DeepCopy(PRESET_TEMPLATE)

	if eventName and eventName ~= "" then
		preset.header.eventName = eventName
	end

	preset.header.hostName = (UnitName and UnitName("player")) or ""

	return preset
end

--- Exposed read-only for validation; callers must not mutate it.
REH.PRESET_TEMPLATE = PRESET_TEMPLATE
