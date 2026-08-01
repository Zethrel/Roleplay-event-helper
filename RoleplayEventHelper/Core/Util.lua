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

function REH.ToBoolean(value, fallback)
	if value == nil then
		return fallback
	end
	return value and true or false
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
