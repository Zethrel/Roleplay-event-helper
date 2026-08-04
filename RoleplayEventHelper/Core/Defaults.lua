local ADDON_NAME, REH = ...

-- Bump when the saved layout changes in a way that needs a migration step, and
-- add the matching entry to REH.Database.migrations.
REH.DB_VERSION = 1

REH.MAX_PRESET_NAME_LENGTH = 32
REH.MAX_PRESETS = 50
REH.MAX_RULE_LINE_LENGTH = 200
REH.MAX_CUSTOM_RULES = 30
REH.MAX_LOOT_ENTRIES = 60
REH.MAX_ROLL_EFFECTS = 25

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
REH.RANGE_MODES = { "atMost", "exact", "any" }
REH.ANNOUNCE_STYLES = { "full", "summary" }

-- Roll effects: what sets one off, what it is judged against, and where the
-- line it produces goes.
REH.EFFECT_TRIGGERS = { "band", "verdict", "any" }
REH.EFFECT_VERDICTS = { "critsuccess", "success", "fail", "critfail" }
-- Where a line the addon produces after a roll ends up. The same three for a
-- roll effect and for the results table: they are the same question, and a host
-- who learns them in one place should not have to learn them again in the other.
REH.RESULT_TARGETS = { "channel", "self", "whisper" }
REH.EFFECT_TARGETS = REH.RESULT_TARGETS
REH.CHANNEL_TYPES = {
	"PREVIEW", "SAY", "YELL", "EMOTE", "PARTY", "RAID", "RAID_WARNING",
	"INSTANCE_CHAT", "GUILD", "OFFICER", "CHANNEL", "WHISPER",
}

REH.MODULE_KEYS = { "header", "rolls", "health", "damage", "turns", "loot", "custom", "etiquette" }

-- Human-readable text for the stored enumeration keys. Kept here so the
-- announcement, the /reh show summary and the UI all describe a rule the same
-- way, and so a translator has one place to change.
REH.DISPLAY = {
	tieBreak = {
		reroll = "ties are rerolled",
		armor = "on a tie the heavier armor wins",
		attacker = "the attacker wins ties",
		defender = "the defender wins ties",
		host = "the host settles ties",
	},
	tieBreakShort = {
		reroll = "reroll",
		armor = "higher armor wins",
		attacker = "attacker wins",
		defender = "defender wins",
		host = "host decides",
	},
	deathRule = {
		out = "You are out at 0 HP.",
		downed = "At 0 HP you are downed but can be revived.",
		host = "The host decides what happens at 0 HP.",
	},
	initiative = {
		initiative = "roll for initiative, highest goes first",
		host = "the host calls each turn",
		roundrobin = "round-robin in join order",
		freeform = "free-form, no fixed order",
	},
	initiativeShort = {
		initiative = "roll for initiative",
		host = "host calls turns",
		roundrobin = "round-robin",
		freeform = "free-form",
	},
	channel = {
		PREVIEW = "preview only (nothing is sent)",
		SAY = "/say",
		YELL = "/yell",
		EMOTE = "/emote",
		PARTY = "party chat",
		RAID = "raid chat",
		RAID_WARNING = "raid warning",
		INSTANCE_CHAT = "instance chat",
		GUILD = "guild chat",
		OFFICER = "officer chat",
		CHANNEL = "a custom channel",
		WHISPER = "a whisper",
	},
	rangeMode = {
		atMost = "that die or a smaller one",
		exact = "only that exact die",
		any = "any die at all",
	},
	effectTrigger = {
		band = "a roll of",
		verdict = "a result of",
		any = "any roll",
	},
	effectVerdict = {
		critsuccess = "critical success",
		success = "success",
		fail = "failure",
		critfail = "critical failure",
	},
	resultTarget = {
		channel = "to my channel",
		self = "to me only",
		whisper = "to the roller",
	},
	rollFilter = {
		group = "party/raid members",
		subgroup = "chosen raid subgroups",
		roster = "a saved roster",
		everyone = "everyone in range",
	},
}

REH.DISPLAY.effectTarget = REH.DISPLAY.resultTarget

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

	-- The window is resizable, and the size it was left at is remembered the
	-- same way its position is. Clamped on load: a size saved by a future
	-- version, or edited by hand, must not produce a window that cannot be
	-- reached or read.
	frameSize = { width = 820, height = 600 },
	logSize = { width = 420, height = 400 },

	-- Where the roll log and the effects editor were last dropped, keyed by
	-- window. Empty until the host drags one.
	windowPoints = {},
	effectsSize = { width = 640, height = 480 },
	sendDelay = 0.7,

	-- "auto" picks per channel: burst where the client needs a hardware event
	-- behind each send, paced everywhere else. "paced" and "burst" force one.
	sendMode = "auto",

	-- Off by default. Each separator costs a whole chat message and a send
	-- delay, and the module labels ("Rolls:", "Health:") already give the
	-- announcement its structure. Hosts who want the visual break can switch
	-- it on and pay the extra seconds.
	useSeparators = false,

	-- Pack adjacent rules from the same module into one message where they
	-- fit. Holding a busy channel for twenty messages is worse than one dense
	-- message per topic.
	mergeLines = true,

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

		-- Whether a roll is called a success or a failure at all. Off suits an
		-- event where the roll decides what happens rather than whether it
		-- worked: at a fishing night, "rolled 7 -> FAILURE" followed by "reels
		-- in a fat carp" contradicts itself, and the catch is the result.
		--
		-- It governs the saying, not the judging. The verdict is still worked
		-- out, so the log, the tallies and effects that fire on a result all
		-- keep working; it is simply not announced.
		useVerdicts = true,

		critSuccessAt = 100,
		critFailAt = 1,
		tieBreak = "reroll",
		rollsPerTurn = 1,

		-- Whether the success threshold moves with a smaller die. Off means a
		-- wounded character rolling d15 still needs the event's number, so the
		-- smaller die is the penalty. On keeps their odds the same and makes
		-- the smaller die cosmetic.
		scaleToDie = false,
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
		-- No limit by default. Not everyone types quickly, and a countdown on
		-- someone composing an emote is pressure the host did not ask for.
		turnTimeSeconds = 0,
		note = "",
	},

	-- A result table read off the roll itself: roll a 3 at a fishing night and
	-- the addon says what you caught. Off by default, because most events do not
	-- want an extra line in chat after every roll.
	loot = {
		enabled = false,

		-- Where the result goes. Separate from the watcher's own verdicts on
		-- purpose: a fishing night wants "Rennek has caught an anchovy" without
		-- "Rennek rolled 3 -> FAILURE" going with it.
		--
		-- "whisper" is the one worth understanding. Telling the room what
		-- somebody caught hands them the outcome and leaves them nothing to
		-- play; telling only them lets them announce it in their own words, or
		-- struggle with it, or lie about it. The addon knows what was caught,
		-- and the person who caught it decides what that means.
		target = "channel",

		-- A pause before the result, so the roll lands first and the catch reads
		-- as a consequence of it rather than as part of the same line.
		delaySeconds = 3,

		-- {name}, {item} and {roll} are replaced. Placeholders rather than
		-- printf tokens because this text is host-editable and a stray % in a
		-- format string errors instead of printing.
		message = "{name} has caught {item}.",

		-- Empty means silence when nothing matches, which is the right default:
		-- a table covering 1-20 at an event on /roll 100 should not announce
		-- eighty non-events.
		nothingText = "",

		-- Bands, in order. The first band containing the roll wins, so a host can
		-- put "100 the legendary whale" above "90-100 a big fish" and have it
		-- take precedence.
		entries = {},
	},

	-- Roll effects go further than the loot table: they fire on a result as well
	-- as on a number, several can answer the same roll, and each one carries its
	-- own chance, delay and destination. The loot table stays because it is the
	-- two-minute version of this -- a fishing night should not have to open a
	-- second window to say what a 3 catches.
	--
	-- Empty by default. An event with no effects behaves exactly as it did
	-- before they existed.
	rollEffects = {},

	custom = {},
	etiquette = {},

	rounds = {
		announce = true,
		-- {round} is replaced with the number. A placeholder rather than a
		-- printf token on purpose: this text is host-editable, and a stray %
		-- in a format string would error rather than print.
		message = "Round {round} begins.",
	},

	rollFilter = {
		mode = "group",
		subgroups = {},          -- raid subgroup numbers when mode == "subgroup"
		roster = {},             -- explicit names when mode == "roster"
		-- "atMost" counts /roll 100 and anything smaller, because a wounded
		-- character rolling a reduced die is the usual reason to roll low.
		-- "exact" wants the die in the rules and nothing else; "any" takes
		-- everything.
		rangeMode = "atMost",
	},

	moduleOrder = { "header", "rolls", "health", "damage", "turns", "loot", "custom", "etiquette" },
	moduleEnabled = {
		header = true,
		rolls = true,
		health = true,
		damage = true,
		turns = true,
		loot = true,
		custom = true,
		etiquette = true,
	},

	announceStyle = "full",

	formatting = {
		linePrefix = "",         -- e.g. "[Event]" to stand out in a busy channel
		numberCustomRules = true,
	},

	-- Deliberately PREVIEW on a fresh preset: the first press of Announce can
	-- never spam a channel by accident. The host chooses a real target once,
	-- and it is then remembered per preset.
	channel = { type = "PREVIEW", target = "" },
}

--- One roll effect, with every field present. Used by the editor's Add button
--- and by validation, so a hand-written effect and a clicked one are the same
--- shape.
function REH.CreateRollEffect()
	return {
		enabled = true,
		trigger = "band",
		min = 1,
		max = 1,
		verdict = "critfail",
		chance = 100,
		delaySeconds = 3,

		-- Effects sharing a trigger normally all fire. Ticking this on each of
		-- them makes that group one choice instead: three fish written against
		-- 4-7 become one fish, picked at random.
		random = false,

		target = "channel",
		message = "{name} rolled {roll}.",
	}
end

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
