-- M2: byte-safe chat splitting and preset-to-chat formatting.
--
-- The splitter gets the heaviest coverage here. It is the piece most likely to
-- be subtly wrong and the most tedious to test in-game: a break inside a colour
-- escape leaks colour into the rest of the chat frame, a break inside a link
-- kills the link, and a break inside a UTF-8 character shows a replacement box
-- to every player watching.

local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "Tests"
local H = dofile(here .. "/Harness.lua")

H.installStubs()
H.snapshotGlobals()
H.wipeSavedVariables()

local REH = H.login()
local DB = REH.Database
local Formatter = REH.Formatter

--------------------------------------------------------------------------------
-- Test helpers
--------------------------------------------------------------------------------

local function isValidUtf8(text)
	local index, length = 1, #text
	while index <= length do
		local byte = text:byte(index)
		local size

		if byte < 0x80 then
			size = 1
		elseif byte >= 0xC2 and byte <= 0xDF then
			size = 2
		elseif byte >= 0xE0 and byte <= 0xEF then
			size = 3
		elseif byte >= 0xF0 and byte <= 0xF4 then
			size = 4
		else
			return false
		end

		for offset = 1, size - 1 do
			local continuation = text:byte(index + offset)
			if not continuation or continuation < 0x80 or continuation > 0xBF then
				return false
			end
		end

		index = index + size
	end
	return true
end

local function countOccurrences(text, needle)
	local count, position = 0, 1
	while true do
		local found = text:find(needle, position, true)
		if not found then
			return count
		end
		count = count + 1
		position = found + #needle
	end
end

local function allWithin(pieces, maxBytes)
	for _, piece in ipairs(pieces) do
		if #piece > maxBytes then
			return false, ("%d bytes: %s"):format(#piece, piece)
		end
	end
	return true
end

--- Text with all escapes and whitespace removed, for comparing before/after.
local function visibleText(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", "")
		:gsub("|r", "")
		:gsub("|H.-|h", "")
		:gsub("|h", "")
		:gsub("%s+", ""))
end

--------------------------------------------------------------------------------
H.section("Splitting: the easy cases")
--------------------------------------------------------------------------------

local pieces = REH.SplitMessage("A short line.", 255)
H.checkEqual("short text is one message", #pieces, 1)
H.checkEqual("and is unchanged", pieces[1], "A short line.")

local sentence = "The quick brown fox jumps over the lazy dog. "
local long = sentence:rep(10)
pieces = REH.SplitMessage(long, 255)
H.check("long text splits into several messages", #pieces > 1)
H.check("every message is within the limit", allWithin(pieces, 255))
H.checkEqual("no visible text is lost", visibleText(table.concat(pieces)), visibleText(long))

for _, piece in ipairs(pieces) do
	if piece:sub(1, 1) == " " or piece:sub(-1) == " " then
		H.check("messages are not padded with stray spaces", false, "'" .. piece .. "'")
		break
	end
end
H.check("messages are not padded with stray spaces", true)

-- Words must survive intact: a rule that reads "no mou nts" is worse than one
-- that wraps a little early.
pieces = REH.SplitMessage(long, 40)
local rejoined = table.concat(pieces, " ")
H.check("no word is broken when a break point exists",
	rejoined:find("quic k") == nil and rejoined:find("jump s") == nil)
H.check("every message is within a tight limit", allWithin(pieces, 40))

--------------------------------------------------------------------------------
H.section("Splitting: colour escapes")
--------------------------------------------------------------------------------

local colored = "|cffffd100" .. sentence:rep(3) .. "|r"
pieces = REH.SplitMessage(colored, 60)
H.check("splits a coloured run", #pieces > 1)
H.check("every message is within the limit", allWithin(pieces, 60))

local balanced = true
local reopened = true
for index, piece in ipairs(pieces) do
	if countOccurrences(piece, "|c") ~= countOccurrences(piece, "|r") then
		balanced = false
	end
	if index > 1 and piece:sub(1, 10) ~= "|cffffd100" then
		reopened = false
	end
end
H.check("each message closes every colour it opens", balanced)
H.check("continuation messages reopen the colour", reopened)

-- The failure this guards against: a message ending mid-escape, which would
-- print raw escape characters and colour everything after it.
local noSplitEscape = true
for _, piece in ipairs(pieces) do
	for position in piece:gmatch("()|c") do
		if #piece - position + 1 < 10 then
			noSplitEscape = false
		end
	end
end
H.check("no message ends part-way through a colour code", noSplitEscape)

local nested = "|cffffd100Outer " .. "|cff8fd3ffinner text here |r" .. sentence:rep(2) .. "|r"
pieces = REH.SplitMessage(nested, 50)
balanced = true
for _, piece in ipairs(pieces) do
	if countOccurrences(piece, "|c") ~= countOccurrences(piece, "|r") then
		balanced = false
	end
end
H.check("nested colours stay balanced across messages", balanced)

--------------------------------------------------------------------------------
H.section("Splitting: links, textures and escaped pipes")
--------------------------------------------------------------------------------

local link = "|Hitem:6948:0:0:0:0:0:0:0:0|h[Hearthstone]|h"
local withLink = sentence:rep(2) .. link .. " " .. sentence:rep(2)
pieces = REH.SplitMessage(withLink, 60)

local linkIntact = false
for _, piece in ipairs(pieces) do
	if piece:find(link, 1, true) then
		linkIntact = true
	end
end
H.check("a hyperlink survives intact in one message", linkIntact)
H.checkEqual("the link appears exactly once",
	countOccurrences(table.concat(pieces), "[Hearthstone]"), 1)

local texture = "|TInterface\\Icons\\INV_Misc_Dice_01:16|t"
pieces = REH.SplitMessage(sentence:rep(2) .. texture .. sentence:rep(2), 60)
local textureIntact = false
for _, piece in ipairs(pieces) do
	if piece:find(texture, 1, true) then
		textureIntact = true
	end
end
H.check("an inline texture survives intact", textureIntact)

local piped = ("Roll || or pass. "):rep(20)
pieces = REH.SplitMessage(piped, 50)
H.checkEqual("escaped pipes are preserved",
	countOccurrences(table.concat(pieces), "||"), 20)

--------------------------------------------------------------------------------
H.section("Splitting: UTF-8")
--------------------------------------------------------------------------------

-- Accented and CJK characters cost 2-3 bytes each, so a byte-budgeted split
-- lands mid-character unless it is guarded.
local accented = "Rögnvald würfelt für die Verteidigung des Ratshauses. "
pieces = REH.SplitMessage(accented:rep(6), 60)
local validUtf8 = true
for _, piece in ipairs(pieces) do
	if not isValidUtf8(piece) then
		validUtf8 = false
	end
end
H.check("accented text is never cut mid-character", validUtf8)
H.check("every message is within the limit", allWithin(pieces, 60))

local cjk = "角色扮演活动规则说明 "
pieces = REH.SplitMessage(cjk:rep(12), 60)
validUtf8 = true
for _, piece in ipairs(pieces) do
	if not isValidUtf8(piece) then
		validUtf8 = false
	end
end
H.check("three-byte characters are never cut mid-character", validUtf8)
H.check("every message is within the limit", allWithin(pieces, 60))

-- A single word longer than one whole message has to be cut somewhere; the cut
-- still must not land inside a character.
local hugeWord = ("ü"):rep(200)
pieces = REH.SplitMessage(hugeWord, 60)
H.check("an over-long word is split", #pieces > 1)
H.check("every message is within the limit", allWithin(pieces, 60))
validUtf8 = true
for _, piece in ipairs(pieces) do
	if not isValidUtf8(piece) then
		validUtf8 = false
	end
end
H.check("a hard split still respects character boundaries", validUtf8)
H.checkEqual("no bytes are lost in a hard split", #table.concat(pieces), #hugeWord)

--------------------------------------------------------------------------------
H.section("Splitting: continuation prefix")
--------------------------------------------------------------------------------

pieces = REH.SplitMessage(sentence:rep(6), 60, "  ...")
H.check("more than one message", #pieces > 1)
H.check("every message is within the limit including the prefix", allWithin(pieces, 60))

local prefixed = true
for index = 2, #pieces do
	if pieces[index]:sub(1, 5) ~= "  ..." then
		prefixed = false
	end
end
H.check("continuation messages carry the prefix", prefixed)
H.check("the first message does not", pieces[1]:sub(1, 5) ~= "  ...")

--------------------------------------------------------------------------------
H.section("Formatting the default preset")
--------------------------------------------------------------------------------

local preset, presetName = DB:GetActivePreset()
local lines = Formatter:BuildLines(preset, { useColors = false, useSeparators = false })
local text = table.concat(lines, "\n")

H.check("announces the roll command", text:find("/roll 100", 1, true) ~= nil, text)
H.check("states the failure band", text:find("1-9 = FAILURE", 1, true) ~= nil, text)
H.check("states the success band", text:find("10-100 = SUCCESS", 1, true) ~= nil, text)
H.check("states the critical success", text:find("natural 100", 1, true) ~= nil, text)
H.check("lists cloth health", text:find("Cloth 10", 1, true) ~= nil, text)
H.check("lists leather health", text:find("Leather 11", 1, true) ~= nil, text)
H.check("lists mail health", text:find("Mail 12", 1, true) ~= nil, text)
H.check("lists plate health", text:find("Plate 13", 1, true) ~= nil, text)
H.check("states the shield bonus", text:find("Shield equipped +1", 1, true) ~= nil, text)
H.check("states the damage rule", text:find("1 per successful hit", 1, true) ~= nil, text)
H.check("states the death rule", text:find("out at 0 HP", 1, true) ~= nil, text)
H.check("states the turn order", text:find("Roll for initiative", 1, true) ~= nil, text)
H.check("names the event", text:find(preset.header.eventName, 1, true) ~= nil, text)
H.check("names the host", text:find(H.playerName, 1, true) ~= nil, text)

--------------------------------------------------------------------------------
H.section("Wording adapts to the numbers")
--------------------------------------------------------------------------------

local function linesFor(mutate)
	local scratch = REH.CreateDefaultPreset("Scratch")
	mutate(scratch)
	DB:ValidatePreset(scratch)
	return table.concat(Formatter:BuildLines(scratch, { useColors = false, useSeparators = false }), "\n")
end

local everySucceeds = linesFor(function(p) p.rolls.successThreshold = 1 end)
H.check("a threshold of 1 does not print an impossible '1-0' band",
	everySucceeds:find("1-0", 1, true) == nil, everySucceeds)
H.check("and still states the success band",
	everySucceeds:find("1-100 = SUCCESS", 1, true) ~= nil, everySucceeds)

local onlyMax = linesFor(function(p) p.rolls.successThreshold = 100 end)
H.check("a threshold equal to the die max reads as a single value",
	onlyMax:find("100 = SUCCESS", 1, true) ~= nil, onlyMax)
H.check("with the matching failure band",
	onlyMax:find("1-99 = FAILURE", 1, true) ~= nil, onlyMax)

-- "2 on a critical" lives in the damage line, so this checks for the critical
-- band sentence specifically rather than the word.
local noCrits = linesFor(function(p) p.rolls.useCritical = false end)
H.check("the critical band is omitted when criticals are disabled",
	noCrits:find("critical success", 1, true) == nil, noCrits)

local lowCrit = linesFor(function(p)
	p.rolls.critSuccessAt = 95
	p.rolls.critFailAt = 5
end)
H.check("a critical band below the die max reads as a range",
	lowCrit:find("95 or higher", 1, true) ~= nil, lowCrit)
H.check("and so does the low end",
	lowCrit:find("5 or lower", 1, true) ~= nil, lowCrit)

local plural = linesFor(function(p) p.rolls.rollsPerTurn = 3 end)
H.check("plural rolls per turn", plural:find("3 rolls per turn", 1, true) ~= nil, plural)

local noTimer = linesFor(function(p) p.turns.turnTimeSeconds = 0 end)
H.check("no turn timer means no timer sentence",
	noTimer:find("seconds per turn", 1, true) == nil, noTimer)

local healing = linesFor(function(p)
	p.damage.healingAllowed = true
	p.damage.healPerSuccess = 2
	p.damage.healsPerEvent = 3
end)
H.check("healing appears when allowed", healing:find("Healing:", 1, true) ~= nil, healing)
H.check("with the per-event cap", healing:find("3 heals each", 1, true) ~= nil, healing)

local unlimitedHeals = linesFor(function(p)
	p.damage.healingAllowed = true
	p.damage.healsPerEvent = 0
end)
H.check("an unlimited heal count is not printed as '0 heals'",
	unlimitedHeals:find("0 heals", 1, true) == nil, unlimitedHeals)

--------------------------------------------------------------------------------
H.section("Empty and disabled modules")
--------------------------------------------------------------------------------

local emptyHealth = linesFor(function(p)
	p.health.rows = {}
	p.health.modifiers = {}
end)
H.check("an empty health table produces no health line",
	emptyHealth:find("Health:", 1, true) == nil, emptyHealth)

local withCustom = linesFor(function(p)
	p.custom = { "No mounts inside the ring.", "No consumables between rounds." }
end)
H.check("custom rules are numbered",
	withCustom:find("1. No mounts inside the ring.", 1, true) ~= nil, withCustom)
H.check("and keep counting", withCustom:find("2. No consumables", 1, true) ~= nil, withCustom)

local unnumbered = linesFor(function(p)
	p.custom = { "No mounts inside the ring." }
	p.formatting.numberCustomRules = false
end)
H.check("numbering can be turned off",
	unnumbered:find("1. No mounts", 1, true) == nil, unnumbered)

local disabled = linesFor(function(p)
	p.moduleEnabled.damage = false
	p.moduleEnabled.turns = false
end)
H.check("a disabled module is omitted", disabled:find("Damage:", 1, true) == nil, disabled)
H.check("and so is the other one", disabled:find("Turn order:", 1, true) == nil, disabled)

--------------------------------------------------------------------------------
H.section("Separators")
--------------------------------------------------------------------------------

local scratch = REH.CreateDefaultPreset("Separators")
scratch.custom = {}
scratch.etiquette = {}
DB:ValidatePreset(scratch)
local separated = Formatter:BuildLines(scratch, { useColors = false, useSeparators = true })

H.check("the announcement does not start with a separator", separated[1] ~= "---")
H.check("nor end with one", separated[#separated] ~= "---")

local emptyModulesLeaveNoSeparator = true
for index = 2, #separated do
	if separated[index] == "---" and separated[index - 1] == "---" then
		emptyModulesLeaveNoSeparator = false
	end
end
H.check("empty modules never leave a doubled separator", emptyModulesLeaveNoSeparator)

--------------------------------------------------------------------------------
H.section("Module order, style and prefix")
--------------------------------------------------------------------------------

local reordered = REH.CreateDefaultPreset("Reordered")
reordered.moduleOrder = { "health", "rolls", "header", "damage", "turns", "custom", "etiquette" }
DB:ValidatePreset(reordered)
local orderedLines = Formatter:BuildLines(reordered, { useColors = false, useSeparators = false })
H.check("the host's module order is honoured",
	orderedLines[1]:find("Health:", 1, true) ~= nil, orderedLines[1])

local summary = REH.CreateDefaultPreset("Summary")
summary.announceStyle = "summary"
summary.custom = { "No mounts." }
DB:ValidatePreset(summary)
local summaryText = table.concat(
	Formatter:BuildLines(summary, { useColors = false, useSeparators = false }), "\n")
H.check("summary style keeps the roll rules",
	summaryText:find("/roll 100", 1, true) ~= nil, summaryText)
H.check("summary style keeps the health table",
	summaryText:find("Cloth 10", 1, true) ~= nil, summaryText)
H.check("summary style drops the damage module",
	summaryText:find("Damage:", 1, true) == nil, summaryText)
H.check("summary style drops custom rules",
	summaryText:find("No mounts.", 1, true) == nil, summaryText)

local prefixed2 = REH.CreateDefaultPreset("Prefixed")
prefixed2.formatting.linePrefix = "[Event]"
DB:ValidatePreset(prefixed2)
local prefixedLines = Formatter:BuildLines(prefixed2, { useColors = false, useSeparators = true })
local allPrefixed = true
for _, line in ipairs(prefixedLines) do
	if line:sub(1, 7) ~= "[Event]" then
		allPrefixed = false
	end
end
H.check("the line prefix is applied to every line, separators included", allPrefixed)

local pipedPrefix = REH.CreateDefaultPreset("PipedPrefix")
pipedPrefix.formatting.linePrefix = "|cffff0000[Evil]"
DB:ValidatePreset(pipedPrefix)
H.check("a colour escape in the prefix is stripped",
	pipedPrefix.formatting.linePrefix:find("|", 1, true) == nil,
	pipedPrefix.formatting.linePrefix)

--------------------------------------------------------------------------------
H.section("Colours")
--------------------------------------------------------------------------------

local plainText = table.concat(
	Formatter:BuildLines(preset, { useColors = false, useSeparators = false }), "\n")
H.check("colours are absent when disabled", plainText:find("|c", 1, true) == nil)

local colorText = table.concat(
	Formatter:BuildLines(preset, { useColors = true, useSeparators = false }), "\n")
H.check("colours are present when enabled", colorText:find("|c", 1, true) ~= nil)
H.checkEqual("and every colour is closed",
	countOccurrences(colorText, "|c"), countOccurrences(colorText, "|r"))

--------------------------------------------------------------------------------
H.section("Messages fit the chat limit")
--------------------------------------------------------------------------------

local wordy = REH.CreateDefaultPreset("Wordy")
wordy.header.description = ("A very long description of this event. "):rep(12)
wordy.custom = {
	("Combatants must describe their action in full before rolling. "):rep(6),
	"Short rule.",
}
wordy.health.note = ("Announce your starting health in say before round one. "):rep(5)
DB:ValidatePreset(wordy)

local messages = Formatter:BuildMessages(wordy, { useColors = true, useSeparators = true })
H.check("a wordy preset produces several messages", #messages > 1)
H.check("every message fits the chat limit", allWithin(messages, REH.MAX_CHAT_BYTES))

local allBalanced = true
for _, message in ipairs(messages) do
	if countOccurrences(message, "|c") ~= countOccurrences(message, "|r") then
		allBalanced = false
	end
end
H.check("every message is colour-balanced on its own", allBalanced)

--------------------------------------------------------------------------------
H.section("Merge-packing")
--------------------------------------------------------------------------------

-- Holding a busy channel for twenty messages is worse than one dense message
-- per topic, so adjacent rules from the same module are packed together.

local packable = REH.CreateDefaultPreset("Packable")
packable.header.description = "Free-for-all, last one standing wins the pot."
packable.custom = { "No mounts inside the ring.", "No consumables between rounds." }
packable.etiquette = { "OOC in double parentheses.", "Disputes are settled by the host." }
DB:ValidatePreset(packable)

local unmerged = Formatter:BuildMessages(packable,
	{ useColors = false, useSeparators = false, mergeLines = false })
local merged = Formatter:BuildMessages(packable,
	{ useColors = false, useSeparators = false, mergeLines = true })

H.check("merging reduces the message count", #merged < #unmerged,
	("%d merged vs %d unmerged"):format(#merged, #unmerged))
H.check("every merged message still fits", allWithin(merged, REH.MAX_CHAT_BYTES))
H.checkEqual("no visible text is lost by merging",
	visibleText(table.concat(merged, " ")), visibleText(table.concat(unmerged, " ")))

local mergedText = table.concat(merged, "\n")
H.check("the roll bands and criticals share a message",
	mergedText:find("10%-100 = SUCCESS%. A natural 100") ~= nil, mergedText)
H.check("the health table and its note share a message",
	mergedText:find("Plate 13%. Shield equipped %+1%.") ~= nil, mergedText)
H.check("both custom rules share a message",
	mergedText:find("1%. No mounts inside the ring%. 2%. No consumables") ~= nil, mergedText)

-- Merging across modules would run "Health: ..." into the end of the damage
-- rules, and the announcement stops being scannable.
local labelStartsMessage = true
for _, message in ipairs(merged) do
	local _, occurrences = message:gsub("Health:", "")
	if occurrences > 0 and message:sub(1, 7) ~= "Health:" then
		labelStartsMessage = false
	end
end
H.check("a module label always starts its own message", labelStartsMessage)

H.checkEqual("the title is never merged into another rule", merged[1],
	"=== " .. packable.header.eventName .. " - hosted by " .. H.playerName .. " ===")

-- The prefix is charged to each message once, not once per merged rule.
local prefixedMerged = Formatter:BuildMessages(packable, {
	useColors = false, useSeparators = false, mergeLines = true, linePrefix = "[Event]",
})
local singlePrefix = true
for _, message in ipairs(prefixedMerged) do
	local _, occurrences = message:gsub("%[Event%]", "")
	if occurrences ~= 1 then
		singlePrefix = false
	end
end
H.check("a merged message carries the prefix exactly once", singlePrefix)
H.check("prefixed messages still fit", allWithin(prefixedMerged, REH.MAX_CHAT_BYTES))

-- A rule too long to merge must not drag a neighbour into its split.
local longRule = REH.CreateDefaultPreset("LongRule")
longRule.custom = {
	("Combatants must describe their action in full before rolling. "):rep(6),
	"Short rule.",
}
DB:ValidatePreset(longRule)
local longMessages = Formatter:BuildMessages(longRule,
	{ useColors = false, useSeparators = false, mergeLines = true })
H.check("every message fits when one rule is over-long",
	allWithin(longMessages, REH.MAX_CHAT_BYTES))
H.check("the short rule survives intact",
	table.concat(longMessages, "\n"):find("2. Short rule.", 1, true) ~= nil)

local separated2 = Formatter:BuildMessages(packable,
	{ useColors = false, useSeparators = true, mergeLines = true })
local separatorStandalone = true
for _, message in ipairs(separated2) do
	if message:find("---", 1, true) and message ~= "---" then
		separatorStandalone = false
	end
end
H.check("separators are never merged into a rule", separatorStandalone)
H.check("separators cost messages, so they are off by default",
	REH.DEFAULT_SETTINGS.useSeparators == false)

--------------------------------------------------------------------------------
H.section("/reh preview")
--------------------------------------------------------------------------------

local out = H.runSlash("preview")
H.check("preview reports the message count", out:find("message(s)", 1, true) ~= nil, out)
H.check("preview shows the rules", out:find("/roll 100", 1, true) ~= nil, out)
H.check("preview shows byte counts", out:find("bytes", 1, true) ~= nil, out)
H.check("preview says nothing was sent", out:find("nothing sent", 1, true) ~= nil, out)

out = H.runSlash("preview Nonexistent")
H.check("preview reports an unknown preset", out:find("No preset named", 1, true) ~= nil, out)

H.check("preview broadcast nothing to other players", #H.sent == 0)
H.checkNoLeakedGlobals(H.ALLOWED_GLOBALS)

H.finish()
