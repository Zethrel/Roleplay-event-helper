local ADDON_NAME, REH = ...

local CHAT_PREFIX = "|cff8fd3ff[REH]|r "

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

-- All output here is local to the host's own chat frame. Nothing in this file
-- ever reaches other players; sending to a channel is the Announcer's job (M3)
-- and always requires an explicit host action.

local function Format(message, ...)
	if select("#", ...) > 0 then
		return tostring(message):format(...)
	end
	return tostring(message)
end

function REH:Print(message, ...)
	DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. Format(message, ...))
end

function REH:PrintWarning(message, ...)
	DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "|cffffd100" .. Format(message, ...) .. "|r")
end

function REH:PrintError(message, ...)
	DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "|cffff6060" .. Format(message, ...) .. "|r")
end

--------------------------------------------------------------------------------
-- Tables
--------------------------------------------------------------------------------

--- Recursive copy. Used to stamp out a fresh preset from the template so the
--- template itself can never be mutated by editing a preset.
function REH.DeepCopy(source)
	if type(source) ~= "table" then
		return source
	end

	local copy = {}
	for key, value in pairs(source) do
		copy[key] = REH.DeepCopy(value)
	end
	return copy
end

--- True for tables that behave as ordered lists rather than keyed records.
local function IsList(tbl)
	return type(tbl) == "table" and tbl[1] ~= nil
end

--- Fill in missing keys from `defaults` without disturbing values the user has
--- already set. Repairs a saved table after a version adds new fields.
---
--- Lists are treated as single values, not merged element by element. That is
--- deliberate: if a host deletes the "Cloth" row from their health table, an
--- element-wise merge would helpfully put it back on every reload. A list is
--- only filled in when it is missing entirely, so an intentionally emptied list
--- stays empty.
function REH.ApplyDefaults(target, defaults)
	if type(defaults) ~= "table" then
		return target
	end

	if type(target) ~= "table" then
		target = {}
	end

	if IsList(defaults) then
		return target
	end

	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if target[key] == nil then
				target[key] = REH.DeepCopy(value)
			else
				target[key] = REH.ApplyDefaults(target[key], value)
			end
		elseif target[key] == nil then
			target[key] = value
		end
	end

	return target
end

function REH.CountKeys(tbl)
	local count = 0
	if type(tbl) == "table" then
		for _ in pairs(tbl) do
			count = count + 1
		end
	end
	return count
end

--- Keys of a table, sorted case-insensitively for stable, human-friendly lists.
function REH.SortedKeys(tbl)
	local keys = {}
	if type(tbl) == "table" then
		for key in pairs(tbl) do
			keys[#keys + 1] = key
		end
	end
	table.sort(keys, function(a, b)
		local la, lb = tostring(a):lower(), tostring(b):lower()
		if la == lb then
			return tostring(a) < tostring(b)
		end
		return la < lb
	end)
	return keys
end

--------------------------------------------------------------------------------
-- Scalars
--------------------------------------------------------------------------------

function REH.Trim(text)
	if type(text) ~= "string" then
		return ""
	end
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Coerce to a whole number inside [minimum, maximum], falling back to
--- `fallback` when the value is missing or not numeric. Saved variables are a
--- plain Lua file a user can hand-edit, so nothing loaded from disk is trusted
--- to be the type or range it was written as.
function REH.ClampInteger(value, minimum, maximum, fallback)
	local number = tonumber(value)
	if not number then
		return fallback
	end

	number = math.floor(number + 0.5)

	if minimum and number < minimum then
		number = minimum
	end
	if maximum and number > maximum then
		number = maximum
	end

	return number
end

--- As ClampInteger, but keeps fractional values (send delays, positions).
function REH.ClampNumber(value, minimum, maximum, fallback)
	local number = tonumber(value)
	if not number then
		return fallback
	end

	if minimum and number < minimum then
		number = minimum
	end
	if maximum and number > maximum then
		number = maximum
	end

	return number
end

function REH.ToBoolean(value, fallback)
	if value == nil then
		return fallback
	end
	return value and true or false
end

--------------------------------------------------------------------------------
-- Chat message splitting
--------------------------------------------------------------------------------

-- A chat message is capped at 255. The client counts characters, but the
-- transport is UTF-8, so we budget in bytes -- the conservative reading. Being
-- wrong in this direction costs a slightly early line break; being wrong the
-- other way costs a silently truncated rule.
REH.MAX_CHAT_BYTES = 255

--- Break a string into tokens the splitter may reorder or break between.
---
--- The interesting cases are WoW's inline escapes. A colour run is
--- |cAARRGGBB ... |r, and breaking between those two halves leaks the colour
--- into everything after it in the chat frame. A hyperlink |Hitem:...|h[Name]|h
--- breaks entirely if split anywhere inside. Both are recognised here so the
--- packer can treat them as indivisible.
local function Tokenize(text)
	local tokens = {}
	local index, length = 1, #text

	local function push(kind, value)
		tokens[#tokens + 1] = { kind = kind, text = value }
	end

	while index <= length do
		local char = text:sub(index, index)

		if char == "|" then
			local next_ = text:sub(index + 1, index + 1)

			if next_ == "|" then
				-- An escaped pipe renders as a literal "|"; it is ordinary text.
				push("word", "||")
				index = index + 2

			elseif next_ == "c" or next_ == "C" then
				local code = text:sub(index, index + 9)
				if #code == 10 then
					push("colorStart", code)
					index = index + 10
				else
					push("word", text:sub(index))
					index = length + 1
				end

			elseif next_ == "r" or next_ == "R" then
				push("colorEnd", text:sub(index, index + 1))
				index = index + 2

			elseif next_ == "H" then
				-- |Hlink|h[display]|h -- atomic, including the display text.
				local firstClose = text:find("|h", index + 2, true)
				local secondClose = firstClose and text:find("|h", firstClose + 2, true)
				if secondClose then
					push("atomic", text:sub(index, secondClose + 1))
					index = secondClose + 2
				else
					push("word", text:sub(index))
					index = length + 1
				end

			elseif next_ == "T" or next_ == "A" then
				-- Inline texture |T...|t or atlas |A...|a -- also atomic.
				local terminator = (next_ == "T") and "|t" or "|a"
				local close = text:find(terminator, index + 2, true)
				if close then
					push("atomic", text:sub(index, close + 1))
					index = close + 2
				else
					push("word", text:sub(index))
					index = length + 1
				end

			else
				push("word", char)
				index = index + 1
			end

		elseif char == " " or char == "\t" then
			local stop = index
			while stop <= length and text:sub(stop, stop):match("[ \t]") do
				stop = stop + 1
			end
			push("space", text:sub(index, stop - 1))
			index = stop

		else
			local stop = index
			while stop <= length do
				local scan = text:sub(stop, stop)
				if scan == "|" or scan == " " or scan == "\t" then
					break
				end
				stop = stop + 1
			end
			push("word", text:sub(index, stop - 1))
			index = stop
		end
	end

	return tokens
end

--- Cut `text` at no more than `budget` bytes without splitting a UTF-8
--- character. Continuation bytes are 0x80-0xBF, so back up off any of them.
local function CutBytes(text, budget)
	if #text <= budget then
		return text, ""
	end

	local cut = budget
	while cut > 0 do
		local byte = text:byte(cut + 1)
		if byte and byte >= 128 and byte < 192 then
			cut = cut - 1
		else
			break
		end
	end

	if cut <= 0 then
		return "", text
	end

	return text:sub(1, cut), text:sub(cut + 1)
end

--- Split `text` into chat-sized messages.
---
--- Breaks at word boundaries, never inside a colour escape, hyperlink, texture
--- or UTF-8 character. A colour left open at a break is closed with |r and
--- reopened on the next message, so each message stands alone in the chat
--- frame. Continuation messages are prefixed with `continuationPrefix`, which
--- is charged against their budget.
function REH.SplitMessage(text, maxBytes, continuationPrefix)
	text = tostring(text or "")
	maxBytes = maxBytes or REH.MAX_CHAT_BYTES
	continuationPrefix = continuationPrefix or ""

	if #text <= maxBytes then
		return { text }
	end

	local tokens = Tokenize(text)
	local lines = {}
	local colorStack = {}
	local pieces, used, hasContent = {}, 0, false

	local function flush()
		if not hasContent then
			pieces, used = {}, 0
			return
		end

		local line = table.concat(pieces):gsub("%s+$", "")
		lines[#lines + 1] = line .. string.rep("|r", #colorStack)
		pieces, used, hasContent = {}, 0, false
	end

	local function beginContinuation()
		local head = continuationPrefix .. table.concat(colorStack)
		if head ~= "" then
			pieces[1] = head
			used = #head
		end
	end

	for _, token in ipairs(tokens) do
		local value = token.text

		-- Reserve room for the |r characters needed to close whatever colours
		-- would be open once this token is placed.
		local depthAfter = #colorStack
		if token.kind == "colorStart" then
			depthAfter = depthAfter + 1
		elseif token.kind == "colorEnd" and depthAfter > 0 then
			depthAfter = depthAfter - 1
		end

		if used + #value + depthAfter * 2 > maxBytes then
			flush()
			beginContinuation()

			-- The break itself stands in for the whitespace.
			if token.kind == "space" then
				value = nil
			end
		end

		if value then
			-- A single word longer than a whole message still has to go
			-- somewhere. Links and textures are never cut: a broken link is
			-- worse than an over-long message.
			if token.kind == "word" then
				while used + #value + depthAfter * 2 > maxBytes do
					local budget = maxBytes - used - depthAfter * 2
					local head, tail = CutBytes(value, budget)
					if head == "" then
						break
					end

					pieces[#pieces + 1] = head
					used = used + #head
					hasContent = true

					flush()
					beginContinuation()
					value = tail
				end
			end

			if value ~= "" then
				pieces[#pieces + 1] = value
				used = used + #value

				if token.kind == "word" or token.kind == "atomic" then
					hasContent = true
				end

				if token.kind == "colorStart" then
					colorStack[#colorStack + 1] = value
				elseif token.kind == "colorEnd" then
					table.remove(colorStack)
				end
			end
		end
	end

	flush()

	return lines
end

--- Constrain a string: trimmed, and truncated to `maxLength` if given.
function REH.CleanString(value, maxLength, fallback)
	if type(value) ~= "string" then
		return fallback or ""
	end

	local text = REH.Trim(value)
	if text == "" then
		return fallback or ""
	end

	if maxLength and #text > maxLength then
		text = text:sub(1, maxLength)
	end

	return text
end
