local ADDON_NAME, REH = ...

local L = REH.L
local Transfer = {}
REH.Transfer = Transfer

-- Export and import presets as copyable text strings.
--
-- A string is "REH<version>:" followed by the preset serialized, compressed and
-- encoded for printing. Hosts paste them into Discord; attendees who have the
-- addon can paste them back. Attendees who do not still get the rules through
-- the chat announcement, which is why this is a convenience rather than the
-- distribution mechanism.
--
-- Everything arriving here was written by someone else, so it is treated as
-- hostile input at every stage: the size is capped before decompression, the
-- decode and deserialize steps are allowed to fail, and the resulting table
-- goes through the same validation as a hand-edited saved-variables file.

local FORMAT_VERSION = 1
local PREFIX = "REH"

-- A pasted string longer than this is not a preset. The cap exists so a
-- deliberately crafted string cannot be handed to the decompressor to expand
-- into something enormous.
local MAX_ENCODED_LENGTH = 40000
local MAX_DECOMPRESSED_LENGTH = 400000

--------------------------------------------------------------------------------
-- Libraries
--------------------------------------------------------------------------------

local serializer, deflater

local function GetLibraries()
	if serializer and deflater then
		return serializer, deflater
	end

	if LibStub then
		serializer = LibStub:GetLibrary("LibSerialize", true)
		deflater = LibStub:GetLibrary("LibDeflate", true)
	end

	serializer = serializer or _G.LibSerialize
	deflater = deflater or _G.LibDeflate

	return serializer, deflater
end

Transfer.GetLibraries = GetLibraries

function Transfer:IsAvailable()
	local a, b = GetLibraries()
	return a ~= nil and b ~= nil
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

--- Returns the string, or nil plus a reason.
function Transfer:Export(preset, presetName)
	local serialize, deflate = GetLibraries()
	if not serialize or not deflate then
		return nil, L["The export libraries did not load, so presets cannot be shared."]
	end

	local payload = {
		v = FORMAT_VERSION,
		name = presetName,
		preset = REH.DeepCopy(preset),
	}

	local ok, serialized = pcall(serialize.Serialize, serialize, payload)
	if not ok or type(serialized) ~= "string" then
		return nil, L["That preset could not be packed into a string."]
	end

	local compressed = deflate:CompressDeflate(serialized, { level = 9 })
	if not compressed then
		return nil, L["That preset could not be packed into a string."]
	end

	local encoded = deflate:EncodeForPrint(compressed)
	if not encoded then
		return nil, L["That preset could not be packed into a string."]
	end

	return PREFIX .. FORMAT_VERSION .. ":" .. encoded
end

--------------------------------------------------------------------------------
-- Import
--------------------------------------------------------------------------------

local CORRUPT = "That string is damaged or incomplete. Copy it again, making sure you have the whole thing."

--- Parse a string into a preset. Returns preset, name, or nil plus a reason.
--- Nothing is saved: the caller decides what to do about name collisions.
function Transfer:Import(text)
	local serialize, deflate = GetLibraries()
	if not serialize or not deflate then
		return nil, L["The export libraries did not load, so presets cannot be shared."]
	end

	-- Strings get wrapped and indented on their way through Discord and
	-- pastebins, so all whitespace is stripped rather than only the ends.
	local cleaned = tostring(text or ""):gsub("%s+", "")

	if cleaned == "" then
		return nil, L["Paste an export string first."]
	end

	if #cleaned > MAX_ENCODED_LENGTH then
		return nil, L["That string is too long to be a preset."]
	end

	local version, body = cleaned:match("^" .. PREFIX .. "(%d+):(.+)$")
	if not version then
		return nil, L["That does not look like a Roleplay Event Helper preset string. They start with 'REH1:'."]
	end

	version = tonumber(version)
	if version > FORMAT_VERSION then
		return nil, L["That string was made by a newer version of the addon. Update to import it."]
	end

	local decoded = deflate:DecodeForPrint(body)
	if not decoded then
		return nil, L[CORRUPT]
	end

	local decompressed = deflate:DecompressDeflate(decoded)
	if not decompressed then
		return nil, L[CORRUPT]
	end

	if #decompressed > MAX_DECOMPRESSED_LENGTH then
		return nil, L["That string is too long to be a preset."]
	end

	-- Deserialize returns (success, value), so through pcall the value arrives
	-- as the third result: pcall-ok, then the library's own success flag.
	local called, succeeded, payload = pcall(serialize.Deserialize, serialize, decompressed)
	if not called or not succeeded or type(payload) ~= "table" then
		return nil, L[CORRUPT]
	end

	if type(payload.preset) ~= "table" then
		return nil, L[CORRUPT]
	end

	-- The same validation a hand-edited saved-variables file gets. A stranger's
	-- preset is not trusted to have sane numbers, types or list contents.
	local preset = REH.Database:ValidatePreset(payload.preset)
	local name = REH.CleanString(payload.name, REH.MAX_PRESET_NAME_LENGTH, "Imported Event")

	return preset, name
end

--- A one-line description of what a parsed string contains, for the confirm
--- step. Importing without seeing what you are about to get is how someone
--- loses the preset they spent an evening on.
function Transfer:Describe(preset, name)
	local enabled = 0
	for _, key in ipairs(REH.MODULE_KEYS) do
		if preset.moduleEnabled[key] then
			enabled = enabled + 1
		end
	end

	return ("'%s': /roll %d, %d+ succeeds, %d health rows, %d custom rules, %d modules on")
		:format(name, preset.rolls.dieMax, preset.rolls.successThreshold,
			#preset.health.rows, #preset.custom, enabled)
end

--------------------------------------------------------------------------------
-- Saving an import
--------------------------------------------------------------------------------

--- A name that is not taken, derived from `name`.
function Transfer:FreeName(name)
	if not REH.Database:FindName(name) then
		return name
	end

	for suffix = 2, 99 do
		local candidate = ("%s (%d)"):format(name, suffix)
		if #candidate > REH.MAX_PRESET_NAME_LENGTH then
			candidate = candidate:sub(1, REH.MAX_PRESET_NAME_LENGTH)
		end
		if not REH.Database:FindName(candidate) then
			return candidate
		end
	end

	return nil
end

--- Save an imported preset. `mode` is "new" (keep both) or "overwrite".
--- Returns the stored name, or nil plus a reason.
function Transfer:Commit(preset, name, mode)
	local existing = REH.Database:FindName(name)

	if mode == "overwrite" and existing then
		RoleplayEventHelperDB.presets[existing] = preset
		REH.Database:SetActivePreset(existing)
		return existing
	end

	local target = existing and self:FreeName(name) or name
	if not target then
		return nil, L["Too many presets with that name already."]
	end

	if REH.Database:CountPresets() >= REH.MAX_PRESETS then
		return nil, L["You already have the maximum of %d presets."]:format(REH.MAX_PRESETS)
	end

	local cleaned, reason = REH.Database:ValidateName(target)
	if not cleaned then
		return nil, reason
	end

	RoleplayEventHelperDB.presets[cleaned] = preset
	REH.Database:SetActivePreset(cleaned)

	return cleaned
end
