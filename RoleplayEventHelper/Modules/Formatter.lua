local ADDON_NAME, REH = ...

local Formatter = {}
REH.Formatter = Formatter

-- Turns a preset into the exact lines that will be sent to chat.
--
-- Two stages, deliberately separate. BuildLines produces logical lines -- one
-- rule, one line, however long it needs to be. BuildMessages then packs those
-- into chat-sized messages. Keeping them apart means the wording can be
-- reviewed without thinking about byte limits, and the byte limits can be
-- tested without thinking about wording.

local COLOR_HEADING = "|cffffd100"
local COLOR_LABEL = "|cff8fd3ff"
local COLOR_END = "|r"

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

--------------------------------------------------------------------------------
-- Module builders
--------------------------------------------------------------------------------

-- Each builder appends zero or more logical lines. A module that has nothing
-- to say adds nothing at all -- an empty custom-rules list should not produce a
-- heading, a separator, or a lonely "none".

local builders = {}

builders.header = function(preset, lines, options)
	local header = preset.header
	local title = header.eventName

	if header.hostName ~= "" then
		title = ("%s - hosted by %s"):format(title, header.hostName)
	end

	lines[#lines + 1] = Colorize(("=== %s ==="):format(title), COLOR_HEADING, options.useColors)

	if header.description ~= "" then
		lines[#lines + 1] = header.description
	end

	if header.showTimestamp and date then
		lines[#lines + 1] = ("(rules posted at %s)"):format(date("%H:%M"))
	end
end

builders.rolls = function(preset, lines, options)
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

	lines[#lines + 1] = Labelled("Rolls", ("use /roll %d. %s."):format(
		rolls.dieMax, table.concat(bands, ". ")), options.useColors)

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

		lines[#lines + 1] = table.concat(crits, ", ") .. "."
	end

	local closers = {}
	if rolls.rollsPerTurn == 1 then
		closers[#closers + 1] = "One roll per turn."
	else
		closers[#closers + 1] = ("%d rolls per turn."):format(rolls.rollsPerTurn)
	end

	local tieText = REH.DISPLAY.tieBreak[rolls.tieBreak]
	if tieText then
		closers[#closers + 1] = tieText:sub(1, 1):upper() .. tieText:sub(2) .. "."
	end

	lines[#lines + 1] = JoinSentences(closers)
end

builders.health = function(preset, lines, options)
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

	lines[#lines + 1] = Labelled("Health", JoinSentences(sentences), options.useColors)

	if health.note ~= "" then
		lines[#lines + 1] = health.note
	end
end

builders.damage = function(preset, lines, options)
	local damage = preset.damage
	local sentences = {}

	sentences[#sentences + 1] = ("%d per successful hit, %d on a critical."):format(
		damage.perHit, damage.onCrit)

	local deathText = REH.DISPLAY.deathRule[damage.deathRule]
	if deathText then
		sentences[#sentences + 1] = deathText
	end

	lines[#lines + 1] = Labelled("Damage", JoinSentences(sentences), options.useColors)

	if damage.healingAllowed then
		local healing = ("%d restored per successful heal."):format(damage.healPerSuccess)
		if damage.healsPerEvent > 0 then
			healing = healing .. (" %d heals each per event."):format(damage.healsPerEvent)
		end
		lines[#lines + 1] = Labelled("Healing", healing, options.useColors)
	end
end

builders.turns = function(preset, lines, options)
	local turns = preset.turns
	local sentences = {}

	local modeText = REH.DISPLAY.initiative[turns.mode]
	if modeText then
		sentences[#sentences + 1] = modeText:sub(1, 1):upper() .. modeText:sub(2) .. "."
	end

	if turns.turnTimeSeconds > 0 then
		sentences[#sentences + 1] = ("%d seconds per turn."):format(turns.turnTimeSeconds)
	end

	if #sentences > 0 then
		lines[#lines + 1] = Labelled("Turn order", JoinSentences(sentences), options.useColors)
	end

	if turns.note ~= "" then
		lines[#lines + 1] = turns.note
	end
end

builders.custom = function(preset, lines, options)
	for index, rule in ipairs(preset.custom) do
		if options.numberCustomRules then
			lines[#lines + 1] = ("%d. %s"):format(index, rule)
		else
			lines[#lines + 1] = rule
		end
	end
end

builders.etiquette = function(preset, lines, options)
	for _, rule in ipairs(preset.etiquette) do
		lines[#lines + 1] = rule
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
		linePrefix = preset.formatting.linePrefix,
		numberCustomRules = preset.formatting.numberCustomRules,
		style = preset.announceStyle,
		maxBytes = REH.MAX_CHAT_BYTES,
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
function Formatter:BuildLines(preset, overrides)
	local options = self:ResolveOptions(preset, overrides)
	local lines = {}

	for _, moduleKey in ipairs(preset.moduleOrder) do
		local include = preset.moduleEnabled[moduleKey]
		if include and options.style == "summary" then
			include = SUMMARY_MODULES[moduleKey]
		end

		if include and builders[moduleKey] then
			local before = #lines
			builders[moduleKey](preset, lines, options)

			-- Only separate modules that actually produced something, so a
			-- disabled or empty module never leaves a dangling rule line.
			if options.useSeparators and #lines > before and before > 0 then
				table.insert(lines, before + 1, "---")
			end
		end
	end

	-- The prefix is applied last so it lands on the separator lines too, and so
	-- module builders never have to think about it.
	if options.linePrefix ~= "" then
		for index, line in ipairs(lines) do
			lines[index] = options.linePrefix .. " " .. line
		end
	end

	return lines, options
end

--- Chat-ready messages: logical lines packed to the byte limit.
--- Returns the messages, plus the logical lines they came from.
function Formatter:BuildMessages(preset, overrides)
	local lines, options = self:BuildLines(preset, overrides)
	local messages = {}

	for _, line in ipairs(lines) do
		local pieces = REH.SplitMessage(line, options.maxBytes, options.continuationPrefix or "")
		for _, piece in ipairs(pieces) do
			messages[#messages + 1] = piece
		end
	end

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
