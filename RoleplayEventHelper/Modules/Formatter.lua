local ADDON_NAME, REH = ...

local Formatter = {}
REH.Formatter = Formatter

-- Turns a preset into the exact lines that will be sent to chat.
--
-- Three stages, deliberately separate:
--
--   BuildLines     one rule per line, however long it needs to be
--   BuildMessages  those lines packed into chat-sized messages
--   Preview        the messages printed locally, sending nothing
--
-- Keeping them apart means the wording can be reviewed without thinking about
-- byte limits, and the byte limits can be tested without thinking about
-- wording.

local COLOR_HEADING = "|cffffd100"
local COLOR_LABEL = "|cff8fd3ff"
local COLOR_END = "|r"

local SEPARATOR = "---"

local SUMMARY_MODULES = { header = true, rolls = true, health = true }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Colorize(text, color, enabled)
	if not enabled then
		return text
	end
	return color .. text .. COLOR_END
end

--- "Rolls: " with the label coloured, the value left plain.
local function Labelled(label, body, useColors)
	return Colorize(label .. ":", COLOR_LABEL, useColors) .. " " .. body
end

local function JoinSentences(parts)
	return table.concat(parts, " ")
end

local function Capitalize(text)
	return text:sub(1, 1):upper() .. text:sub(2)
end

--------------------------------------------------------------------------------
-- Module builders
--------------------------------------------------------------------------------

-- Each builder is handed an `emit(text, standalone)` function and calls it once
-- per logical line. A module that has nothing to say emits nothing at all -- an
-- empty custom-rules list should not produce a heading, a separator, or a
-- lonely "none".
--
-- `standalone` marks a line that must never share a chat message with another.

local builders = {}

builders.header = function(preset, emit, options)
	local header = preset.header
	local title = header.eventName

	if header.hostName ~= "" then
		title = ("%s - hosted by %s"):format(title, header.hostName)
	end

	-- The title gets its own message: it is what people scrolling back look
	-- for, and burying it inside a merged block defeats the point of it.
	emit(Colorize(("=== %s ==="):format(title), COLOR_HEADING, options.useColors), true)

	if header.description ~= "" then
		emit(header.description)
	end

	if header.showTimestamp and date then
		emit(("(rules posted at %s)"):format(date("%H:%M")))
	end
end

builders.rolls = function(preset, emit, options)
	local rolls = preset.rolls
	local bands = {}

	-- A threshold of 1 leaves no failure band at all. Saying "1-0 = FAILURE"
	-- would be nonsense, so the sentence adapts instead.
	if rolls.successThreshold > 1 then
		bands[#bands + 1] = ("1-%d = %s"):format(rolls.successThreshold - 1, rolls.failText)
	end

	if rolls.successThreshold >= rolls.dieMax then
		bands[#bands + 1] = ("%d = %s"):format(rolls.dieMax, rolls.successText)
	else
		bands[#bands + 1] = ("%d-%d = %s"):format(rolls.successThreshold, rolls.dieMax, rolls.successText)
	end

	emit(Labelled("Rolls", ("use /roll %d. %s."):format(
		rolls.dieMax, table.concat(bands, ". ")), options.useColors))

	if rolls.useCritical then
		local crits = {}

		if rolls.critSuccessAt >= rolls.dieMax then
			crits[#crits + 1] = ("A natural %d is a critical success"):format(rolls.dieMax)
		else
			crits[#crits + 1] = ("%d or higher is a critical success"):format(rolls.critSuccessAt)
		end

		if rolls.critFailAt <= 1 then
			crits[#crits + 1] = "a natural 1 is a critical failure"
		else
			crits[#crits + 1] = ("%d or lower is a critical failure"):format(rolls.critFailAt)
		end

		emit(table.concat(crits, ", ") .. ".")
	end

	local closers = {}
	if rolls.rollsPerTurn == 1 then
		closers[#closers + 1] = "One roll per turn."
	else
		closers[#closers + 1] = ("%d rolls per turn."):format(rolls.rollsPerTurn)
	end

	local tieText = REH.DISPLAY.tieBreak[rolls.tieBreak]
	if tieText then
		closers[#closers + 1] = Capitalize(tieText) .. "."
	end

	emit(JoinSentences(closers))
end

builders.health = function(preset, emit, options)
	local health = preset.health

	if #health.rows == 0 and #health.modifiers == 0 then
		return
	end

	local sentences = {}

	if #health.rows > 0 then
		local parts = {}
		for _, row in ipairs(health.rows) do
			parts[#parts + 1] = ("%s %d"):format(row.label, row.hp)
		end
		sentences[#sentences + 1] = table.concat(parts, ", ") .. "."
	end

	if #health.modifiers > 0 then
		local parts = {}
		for _, modifier in ipairs(health.modifiers) do
			parts[#parts + 1] = ("%s %+d"):format(modifier.label, modifier.bonus)
		end
		sentences[#sentences + 1] = table.concat(parts, ", ") .. "."
	end

	emit(Labelled("Health", JoinSentences(sentences), options.useColors))

	if health.note ~= "" then
		emit(health.note)
	end
end

builders.damage = function(preset, emit, options)
	local damage = preset.damage
	local sentences = {}

	sentences[#sentences + 1] = ("%d per successful hit, %d on a critical."):format(
		damage.perHit, damage.onCrit)

	local deathText = REH.DISPLAY.deathRule[damage.deathRule]
	if deathText then
		sentences[#sentences + 1] = deathText
	end

	emit(Labelled("Damage", JoinSentences(sentences), options.useColors))

	if damage.healingAllowed then
		local healing = ("%d restored per successful heal."):format(damage.healPerSuccess)
		if damage.healsPerEvent > 0 then
			healing = healing .. (" %d heals each per event."):format(damage.healsPerEvent)
		end
		emit(Labelled("Healing", healing, options.useColors))
	end
end

builders.turns = function(preset, emit, options)
	local turns = preset.turns
	local sentences = {}

	local modeText = REH.DISPLAY.initiative[turns.mode]
	if modeText then
		sentences[#sentences + 1] = Capitalize(modeText) .. "."
	end

	if turns.turnTimeSeconds > 0 then
		sentences[#sentences + 1] = ("%d seconds per turn."):format(turns.turnTimeSeconds)
	end

	if #sentences > 0 then
		emit(Labelled("Turn order", JoinSentences(sentences), options.useColors))
	end

	if turns.note ~= "" then
		emit(turns.note)
	end
end

builders.custom = function(preset, emit, options)
	for index, rule in ipairs(preset.custom) do
		if options.numberCustomRules then
			emit(("%d. %s"):format(index, rule))
		else
			emit(rule)
		end
	end
end

builders.etiquette = function(preset, emit, options)
	for _, rule in ipairs(preset.etiquette) do
		emit(rule)
	end
end

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

function Formatter:ResolveOptions(preset, overrides)
	local settings = REH.Database:GetSettings()

	local options = {
		useColors = settings.useColors,
		useSeparators = settings.useSeparators,
		mergeLines = settings.mergeLines,
		linePrefix = preset.formatting.linePrefix,
		numberCustomRules = preset.formatting.numberCustomRules,
		style = preset.announceStyle,
		maxBytes = REH.MAX_CHAT_BYTES,
		continuationPrefix = "",
	}

	if overrides then
		for key, value in pairs(overrides) do
			options[key] = value
		end
	end

	return options
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

--- The logical lines for a preset: one rule per line, any length.
---
--- Returns the lines as display strings (prefix applied), plus an info table
--- carrying the resolved options and per-line metadata. BuildMessages needs the
--- metadata; callers that only want to read the rules can ignore it.
function Formatter:BuildLines(preset, overrides)
	local options = self:ResolveOptions(preset, overrides)
	local records = {}

	for _, moduleKey in ipairs(preset.moduleOrder) do
		local include = preset.moduleEnabled[moduleKey]
		if include and options.style == "summary" then
			include = SUMMARY_MODULES[moduleKey]
		end

		if include and builders[moduleKey] then
			local before = #records

			builders[moduleKey](preset, function(text, standalone)
				records[#records + 1] = {
					text = text,
					module = moduleKey,
					standalone = standalone and true or false,
				}
			end, options)

			-- Only separate modules that actually produced something, so a
			-- disabled or empty module never leaves a dangling rule line.
			if options.useSeparators and #records > before and before > 0 then
				table.insert(records, before + 1, {
					text = SEPARATOR,
					module = "separator",
					standalone = true,
				})
			end
		end
	end

	local prefix = options.linePrefix ~= "" and (options.linePrefix .. " ") or ""
	local lines = {}
	for index, record in ipairs(records) do
		lines[index] = prefix .. record.text
	end

	return lines, { records = records, options = options, prefix = prefix }
end

--- Chat-ready messages: logical lines merged where they fit, then split where
--- they do not. Returns the messages, the logical lines, and the options used.
function Formatter:BuildMessages(preset, overrides)
	local lines, info = self:BuildLines(preset, overrides)
	local records, options, prefix = info.records, info.options, info.prefix

	-- The prefix is charged against every message's budget, and is applied
	-- after merging so two merged rules do not each carry a copy of it.
	local budget = options.maxBytes - #prefix
	local messages = {}

	local pending, pendingModule = nil, nil

	local function flush()
		if pending then
			messages[#messages + 1] = prefix .. pending
			pending, pendingModule = nil, nil
		end
	end

	local function emitLong(text)
		for _, piece in ipairs(REH.SplitMessage(text, budget, options.continuationPrefix)) do
			messages[#messages + 1] = prefix .. piece
		end
	end

	for _, record in ipairs(records) do
		local text = record.text

		if not options.mergeLines or record.standalone then
			flush()
			if #text > budget then
				emitLong(text)
			else
				messages[#messages + 1] = prefix .. text
			end

		elseif #text > budget then
			-- Too long to merge with anything; it becomes its own run of
			-- messages rather than dragging a neighbour into a split.
			flush()
			emitLong(text)

		elseif pending and pendingModule == record.module
			and #pending + 1 + #text <= budget then
			-- Merging stays within a module so each labelled topic still starts
			-- a fresh message, which is what makes the announcement scannable.
			pending = pending .. " " .. text

		else
			flush()
			pending, pendingModule = text, record.module
		end
	end

	flush()

	return messages, lines, options
end

--- Print the announcement to the host's own chat frame. Sends nothing.
function Formatter:Preview(preset, presetName, overrides)
	local messages = self:BuildMessages(preset, overrides)

	REH:Print("Preview of |cffffd100%s|r - %d message(s), nothing sent:",
		presetName, #messages)

	for index, message in ipairs(messages) do
		DEFAULT_CHAT_FRAME:AddMessage(("|cff808080%2d.|r %s |cff808080(%d bytes)|r")
			:format(index, message, #message))
	end

	return messages
end
